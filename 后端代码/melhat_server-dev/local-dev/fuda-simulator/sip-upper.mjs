import dgram from 'node:dgram';
import net from 'node:net';
import {createHash, randomInt, timingSafeEqual} from 'node:crypto';
import {parseMessage, frameLength, serialize, response, transactionKey, token, branch, tag, user} from '../fuda-gb-bridge/sip.mjs';

const loopback='127.0.0.1';
const defaultCapture=async options=>(await import('./rtp-receiver.mjs')).createCapture(options);
const md5=text=>createHash('md5').update(text).digest('hex');
const idPattern=/^\d{20}$/;
const peerEqual=(a,b)=>a&&b&&a.transport===b.transport&&a.address===b.address&&(a.transport==='TCP'?a.socket===b.socket:a.port===b.port);
const numericSequence=m=>Number(m.headers.cseq.split(' ')[0]);

// This parser accepts the bounded GB28181 XML subset, never DTDs or entities.
function readXml(bytes){
  if(bytes.length>49152)throw Error('XML too large');
  const encoding=/encoding=["'](?:GB2312|GBK|GB18030)["']/i.test(bytes.subarray(0,120).toString())?'gb18030':'utf-8';
  const text=new TextDecoder(encoding,{fatal:true}).decode(bytes);
  if(/<!|<\?xml-stylesheet|[\x00-\x08\x0b\x0c\x0e-\x1f]/i.test(text))throw Error('Unsafe XML');
  const clean=text.replace(/^\s*<\?xml\s+[^?]*\?>\s*/,'').trim();
  if(!/^<(Notify|Response)>[\s\S]*<\/\1>$/.test(clean))throw Error('Unsupported XML root');
  // A tiny stack ensures malformed/nested structure cannot smuggle duplicate fields.
  const stack=[];let offset=0;
  for(const match of clean.matchAll(/<\/?([A-Za-z][A-Za-z0-9]*)(?:\s+[A-Za-z]+="[^"<>]*")*\s*>/g)){
    if(clean.slice(offset,match.index).includes('<'))throw Error('Malformed XML');
    if(match[0].startsWith('</')){if(stack.pop()!==match[1])throw Error('Malformed XML');}
    else{stack.push(match[1]);if(stack.length>6)throw Error('XML depth');}offset=match.index+match[0].length;
  }
  if(stack.length||clean.slice(offset).trim())throw Error('Malformed XML');
  const get=(name,source=clean)=>{const values=[...source.matchAll(new RegExp(`<${name}>([^<>]*)</${name}>`,'g'))];if(values.length!==1)throw Error('Missing or duplicate XML field');return decodeXml(values[0][1]);};
  const deviceId=get('DeviceID',clean.replace(/<DeviceList\b[^>]*>[\s\S]*<\/DeviceList>/,'')),cmd=get('CmdType'),sn=get('SN');
  if(!idPattern.test(deviceId)||!/^\d{1,10}$/.test(sn))throw Error('Invalid XML identity');
  if(clean.startsWith('<Notify>')&&cmd==='Keepalive'){if(get('Status')!=='OK')throw Error('Bad keepalive');return {cmd,sn,deviceId};}
  if(!clean.startsWith('<Response>')||cmd!=='Catalog')throw Error('Unsupported XML');
  const totalText=get('SumNum');if(!/^\d{1,3}$/.test(totalText)||Number(totalText)>512)throw Error('Catalog too large');
  const lists=[...clean.matchAll(/<DeviceList(?:\s+Num="(\d{1,3})")?>([\s\S]*?)<\/DeviceList>/g)];if(lists.length!==1)throw Error('Missing catalog');
  const items=[...lists[0][2].matchAll(/<Item>([\s\S]*?)<\/Item>/g)];
  if(lists[0][2].replace(/<Item>[\s\S]*?<\/Item>/g,'').trim()||items.length>512||(lists[0][1]!==undefined&&Number(lists[0][1])!==items.length))throw Error('Invalid catalog count');
  const channels=items.map(item=>{const channelId=get('DeviceID',item[1]),name=get('Name',item[1]),status=get('Status',item[1]);if(!idPattern.test(channelId)||name.length>256||!['ON','OFF'].includes(status))throw Error('Invalid channel');return {channelId,name,status};});
  if(new Set(channels.map(ch=>ch.channelId)).size!==channels.length||channels.length>Number(totalText))throw Error('Duplicate catalog channel');
  return {cmd,sn,deviceId,total:Number(totalText),channels};
}
function decodeXml(value){if(/&(?!(?:amp|lt|gt|quot|apos);)/.test(value))throw Error('Unsupported XML entity');return value.replace(/&(amp|lt|gt|quot|apos);/g,(_,key)=>({amp:'&',lt:'<',gt:'>',quot:'"',apos:"'"})[key]);}
function authFields(value){
  if(!/^Digest /i.test(value??''))throw Error('Missing digest');
  const fields={};let remaining=value.slice(7);
  while(remaining.length){const match=/^\s*([a-zA-Z]+)\s*=\s*(?:"([^"\\\r\n]*)"|([^,\s]+))\s*(?:,\s*|$)/.exec(remaining);if(!match)throw Error('Invalid digest');const key=match[1].toLowerCase();if(Object.hasOwn(fields,key))throw Error('Duplicate digest');fields[key]=match[2]??match[3];remaining=remaining.slice(match[0].length);}
  return fields;
}

export class UpperPlatform{
  constructor({id='34020000002000000001',realm='3402000000',username='34020000002000000002',password,port=0,directory,ffmpegPath,captureFactory=defaultCapture,transactionMs=8000,nonceTtlMs=60000}={}){
    if(!idPattern.test(id)||!idPattern.test(username)||!/^\d{10}$/.test(realm)||typeof password!=='string'||password.length<8||password.length>256)throw Error('Valid synthetic SIP IDs and password are required');
    if(!Number.isInteger(port)||port<0||port>65535)throw Error('Invalid SIP port');
    if(!Number.isFinite(transactionMs)||transactionMs<100||transactionMs>32000||!Number.isFinite(nonceTtlMs)||nonceTtlMs<10||nonceTtlMs>300000)throw Error('Invalid SIP timeout');
    Object.assign(this,{id,realm,username,password,port,directory,ffmpegPath,captureFactory,transactionMs,nonceTtlMs});
    this.peer=null;this.channels=[];this.active=null;this.history=[];this.logs=[];this.nonces=new Map();this.transactions=new Map();this.responses=new Map();this.answered=new Map();this.retiredInvites=new Map();this.sockets=new Set();this.timers=new Set();this.cseq=0;this.sn=0;this.closed=false;this.closing=false;
  }
  log(message){this.logs.push({at:new Date().toISOString(),message});if(this.logs.length>100)this.logs.shift();}
  later(fn,ms){const timer=setTimeout(()=>{this.timers.delete(timer);Promise.resolve().then(fn).catch(()=>this.log('SIP background operation failed'));},ms);this.timers.add(timer);return timer;}
  clear(timer){clearTimeout(timer);this.timers.delete(timer);}
  async start(){
    if(this.udp||this.closed)throw Error('SIP simulator already started or closed');
    const requestedPort=this.port;
    // Windows has different reserved ranges for UDP and TCP. Test the pair,
    // rather than trusting either protocol's ephemeral allocator for the other.
    for(let attempt=0;attempt<24;attempt++){
      const candidate=requestedPort||randomInt(20000,49000);
      this.udp=dgram.createSocket('udp4');this.udp.on('error',()=>this.log('UDP socket error'));
      this.udp.on('message',(bytes,remote)=>{if(remote.address!==loopback)return;this.receive(bytes,{address:loopback,port:remote.port,transport:'UDP',send:data=>this.udp.send(data,remote.port,loopback)});});
      this.tcp=net.createServer(socket=>this.attachSocket(socket));this.tcp.on('error',()=>this.log('TCP listener error'));
      try{
        await new Promise((resolve,reject)=>{const fail=error=>reject(error);this.tcp.once('error',fail);this.tcp.listen(candidate,loopback,()=>{this.tcp.off('error',fail);resolve();});});
        await new Promise((resolve,reject)=>{const fail=error=>reject(error);this.udp.once('error',fail);this.udp.bind(candidate,loopback,()=>{this.udp.off('error',fail);resolve();});});
        this.port=candidate;this.log('SIP UDP and TCP listening on loopback');return this;
      }catch(error){
        await Promise.all([new Promise(resolve=>{try{this.udp.close(resolve);}catch{resolve();}}),new Promise(resolve=>{try{this.tcp.close(resolve);}catch{resolve();}})]);this.udp=null;this.tcp=null;
        if(requestedPort||attempt===23||!['EACCES','EADDRINUSE'].includes(error.code))throw error;
      }
    }
  }
  attachSocket(socket){
    if(socket.remoteAddress?.replace(/^::ffff:/,'')!==loopback||this.sockets.size>=16||this.closing)return socket.destroy();
    this.sockets.add(socket);socket.setNoDelay(true);socket.setTimeout(180000);let buffer=Buffer.alloc(0);
    const peer={address:loopback,port:socket.remotePort,transport:'TCP',socket,send:data=>{if(socket.destroyed)throw Error('SIP peer disconnected');socket.write(data);}};
    socket.on('error',()=>this.log('TCP peer error'));socket.on('timeout',()=>socket.destroy());
    socket.on('close',()=>{this.sockets.delete(socket);if(peerEqual(peer,this.peer)){this.peer=null;this.channels=[];this.stop().catch(()=>{});}});
    socket.on('data',bytes=>{try{buffer=Buffer.concat([buffer,bytes]);if(buffer.length>131072)throw Error('TCP buffer too large');while(buffer.length){if(buffer.subarray(0,4).toString()==='\r\n\r\n'){buffer=buffer.subarray(4);continue;}const length=frameLength(buffer.subarray(0,65536));if(!length){if(buffer.length>=65536)throw Error('TCP frame too large');break;}this.receive(buffer.subarray(0,length),peer);buffer=buffer.subarray(length);}}catch{this.log('Rejected invalid SIP TCP frame');socket.destroy();}});
  }
  snapshot(){
    const peer=this.peer&&this.peer.expiresAt>Date.now()?this.peer:null;
    return {id:this.id,realm:this.realm,port:this.port,registered:!!peer,peer:peer?{id:peer.id,address:peer.address,port:peer.port,transport:peer.transport,expiresAt:peer.expiresAt}:null,channels:this.channels.map(x=>({...x})),active:this.active?this.captureSnapshot(this.active):null,history:this.history.map(x=>({...x})),logs:this.logs.map(x=>({...x}))};
  }
  captureSnapshot(row){const capture=row.capture?.snapshot()??{};return {...capture,captureState:capture.state??null,id:row.id,channelId:row.channelId,state:row.state,transport:row.transport,startedAt:row.startedAt,...(row.reason?{reason:row.reason}:{})};}
  requirePeer(){if(this.closed||this.closing)throw Error('SIP simulator closed');if(!this.peer||this.peer.expiresAt<=Date.now())throw Error('No registered lower platform');return this.peer;}
  receive(bytes,peer){
    let m;try{m=parseMessage(bytes);}catch{this.log('Rejected invalid SIP message');return;}
    if(!branch(m)?.startsWith('z9hG4bK'))return;
    if(m.status)return this.receiveResponse(m,peer);
    if(m.headers.cseq.split(' ')[1]!==m.method||!tag(m.headers.from))return peer.send(response(m,400));
    const key=transactionKey(m),cached=this.responses.get(key);
    if(cached&&cached.expiresAt>Date.now()&&peerEqual(cached.peer,peer)&&cached.fingerprint===md5(bytes)){peer.send(cached.data);return;}
    const reply=(status,extra={},body='',localTag=token())=>{const data=response(m,status,extra,body,localTag);this.responses.set(key,{data,peer,expiresAt:Date.now()+32000,fingerprint:md5(bytes)});if(this.responses.size>1024)this.responses.delete(this.responses.keys().next().value);peer.send(data);};
    if(m.method==='REGISTER'){this.register(m,peer,reply);return;}
    if(!this.peer||this.peer.expiresAt<=Date.now()||!peerEqual(this.peer,peer)){reply(403);return;}
    if(m.method==='BYE'){this.peerBye(m,reply);return;}
    if(user(m.headers.from)!==this.username||user(m.headers.to)!==this.id||user(m.uri)!==this.id){reply(403);return;}
    if(m.method==='MESSAGE'){this.message(m,reply);return;}
    if(m.method==='OPTIONS'){reply(200,{Allow:'REGISTER, MESSAGE, INVITE, ACK, BYE, CANCEL, OPTIONS'});return;}
    if(m.method!=='ACK')reply(405);
  }
  register(m,peer,reply){
    if(user(m.headers.from)!==this.username||user(m.headers.to)!==this.id||m.uri!==`sip:${this.id}@${this.realm}`){reply(403);return;}
    const expiresText=/;expires=([^;,\s>]+)/i.exec(m.headers.contact??'')?.[1]??m.headers.expires??'3600';
    if(!/^\d{1,5}$/.test(expiresText)||Number(expiresText)>86400){reply(400);return;}
    const challenge=()=>{for(const [key,row] of this.nonces)if(row.expiresAt<Date.now())this.nonces.delete(key);const nonce=token();this.nonces.set(nonce,{peer,expiresAt:Date.now()+this.nonceTtlMs,counts:new Map()});if(this.nonces.size>256)this.nonces.delete(this.nonces.keys().next().value);reply(401,{'WWW-Authenticate':`Digest realm="${this.realm}", nonce="${nonce}", algorithm=MD5, qop="auth"`});};
    if(!m.headers.authorization){challenge();return;}
    let auth;try{auth=authFields(m.headers.authorization);}catch{reply(403);return;}
    const nonce=this.nonces.get(auth.nonce);
    if(!nonce||nonce.expiresAt<Date.now()){challenge();return;}
    if(!peerEqual(nonce.peer,peer)||auth.username!==this.username||auth.realm!==this.realm||auth.uri!==m.uri||auth.qop!=='auth'||(auth.algorithm??'MD5').toUpperCase()!=='MD5'||!/^\w{1,128}$/.test(auth.cnonce??'')||!/^\d[a-fA-F0-9]{7}$/.test(auth.nc??'')||!/^\w{32}$/.test(auth.response??'')){reply(403);return;}
    const nc=Number.parseInt(auth.nc,16),last=nonce.counts.get(auth.cnonce)??0;
    const expected=md5(`${md5(`${this.username}:${this.realm}:${this.password}`)}:${auth.nonce}:${auth.nc}:${auth.cnonce}:auth:${md5(`REGISTER:${m.uri}`)}`);
    if(nc<=last||!timingSafeEqual(Buffer.from(expected),Buffer.from(auth.response.toLowerCase()))){reply(403);return;}
    if(this.peer&&this.peer.expiresAt>Date.now()&&!peerEqual(this.peer,peer)){reply(486);return;}
    nonce.counts.set(auth.cnonce,nc);this.clear(this.expiryTimer);
    const expires=Number(expiresText);
    if(expires===0){this.peer=null;this.channels=[];reply(200,{Expires:'0'});this.stop().catch(()=>{});this.log('Lower platform unregistered');return;}
    this.peer={...peer,id:this.username,expiresAt:Date.now()+expires*1000};const registered=this.peer;
    this.expiryTimer=this.later(()=>{if(this.peer===registered){this.peer=null;this.channels=[];this.log('Lower platform registration expired');return this.stop();}},expires*1000);
    reply(200,{Expires:String(expires)});this.log('Lower platform authenticated and registered');
  }
  message(m,reply){
    if(!/^application\/manscdp\+xml(?:\s*;|$)/i.test(m.headers['content-type']??'')){reply(415);return;}
    let value;try{value=readXml(m.body);}catch{reply(400);return;}
    if(value.deviceId!==this.username){reply(403);return;}
    if(value.cmd==='Keepalive'){reply(200);this.log('Keepalive acknowledged');return;}
    const pending=this.catalogPending;
    if(!pending||value.sn!==pending.sn){reply(481);return;}
    if(pending.total!==undefined&&pending.total!==value.total){reply(400);return;}
    for(const channel of value.channels){const old=pending.channels.get(channel.channelId);if(old&&JSON.stringify(old)!==JSON.stringify(channel)){reply(400);return;}}
    pending.total=value.total;for(const channel of value.channels)pending.channels.set(channel.channelId,channel);
    if(pending.channels.size>value.total){reply(400);return;}reply(200);
    if(pending.channels.size===value.total){this.channels=[...pending.channels.values()];this.clear(pending.timer);this.catalogPending=null;pending.resolve(this.channels.map(x=>({...x})));this.log(`Catalog received: ${this.channels.length} channels`);}
  }
  request(method,{body='',headers={},peer=this.requirePeer(),id=token(),seq=++this.cseq,uri=`sip:${this.username}@${this.realm}`,from=`<sip:${this.id}@${this.realm}>;tag=${token()}`,to=`<sip:${this.username}@${this.realm}>`,branchId='z9hG4bK'+token()}={}){
    const fields={Via:`SIP/2.0/${peer.transport} ${loopback}:${this.port};rport;branch=${branchId}`,From:from,To:to,'Call-ID':id,CSeq:`${seq} ${method}`,'Max-Forwards':'70',Contact:`<sip:${this.id}@${loopback}:${this.port};transport=${peer.transport.toLowerCase()}>`,...headers};
    const data=serialize(`${method} ${uri} SIP/2.0`,fields,body),key=`${id}|${seq} ${method}|${branchId}`;
    const tx={method,fields,data,peer,uri,seq,id,branchId,key,interval:100};
    tx.promise=new Promise((resolve,reject)=>{Object.assign(tx,{resolve,reject});this.transactions.set(key,tx);const transmit=()=>{if(this.transactions.get(key)!==tx)return;try{peer.send(data);}catch{this.settle(tx,Error('SIP send failed'));return;}if(peer.transport==='UDP'){tx.timer=this.later(transmit,tx.interval);tx.interval=Math.min(tx.interval*2,1000);}};tx.deadline=this.later(()=>this.settle(tx,Error(`${method} transaction timeout`)),this.transactionMs);transmit();});
    return tx;
  }
  settle(tx,error,message){if(this.transactions.get(tx.key)!==tx)return;this.transactions.delete(tx.key);this.clear(tx.timer);this.clear(tx.deadline);if(error)tx.reject(error);else tx.resolve(message);}
  receiveResponse(m,peer){
    const key=transactionKey(m),tx=this.transactions.get(key);
    if(!tx){
      const saved=this.answered.get(key);if(saved&&saved.expiresAt>Date.now()&&peerEqual(saved.peer,peer)&&m.status===200&&m.headers.from===saved.from&&m.headers.to===saved.to){peer.send(saved.ack);return;}
      const retired=this.retiredInvites.get(key),row=retired?.row;
      if(row&&retired.expiresAt>Date.now()&&peerEqual(row.peer,peer)&&m.status>=200&&m.headers.from===row.invite.fields.From&&user(m.headers.to)===row.channelId&&tag(m.headers.to)){
        this.retiredInvites.delete(key);row.answer=m;this.ack(row,m);
        if(m.status===200){row.established=true;this.sendBye(row).catch(()=>this.log('Late media response cleanup timed out'));}
      }return;
    }
    if(!peerEqual(tx.peer,peer)||m.headers.from!==tx.fields.From||user(m.headers.to)!==user(tx.fields.To)||(tx.method==='INVITE'&&m.status===200&&!tag(m.headers.to))||(tag(tx.fields.To)&&tag(m.headers.to)!==tag(tx.fields.To)))return;
    if(m.status<200){if(tx.method==='INVITE')this.clear(tx.timer);return;}
    this.settle(tx,null,m);
  }
  async catalog(){
    const peer=this.requirePeer();if(this.catalogPending)throw Error('Catalog query already pending');const sn=String(++this.sn);
    const pending={sn,channels:new Map()};pending.promise=new Promise((resolve,reject)=>Object.assign(pending,{resolve,reject}));
    // Attach immediately: the peer can return its Catalog before the MESSAGE 200.
    pending.promise.catch(()=>{});this.catalogPending=pending;
    pending.timer=this.later(()=>{if(this.catalogPending===pending)this.catalogPending=null;pending.reject(Error('Catalog response timeout'));},this.transactionMs);
    try{const tx=this.request('MESSAGE',{peer,body:`<?xml version="1.0" encoding="UTF-8"?><Query><CmdType>Catalog</CmdType><SN>${sn}</SN><DeviceID>${this.username}</DeviceID></Query>`,headers:{'Content-Type':'Application/MANSCDP+xml'}});const result=await tx.promise;if(result.status!==200)throw Error(`Catalog query rejected (${result.status})`);return await pending.promise;}
    catch(error){this.clear(pending.timer);if(this.catalogPending===pending)this.catalogPending=null;pending.reject(error);throw error;}
  }
  async play(channelId,{transport='UDP'}={}){
    const peer=this.requirePeer();if(this.active)throw Error('A media session is already active');
    if(!['UDP','TCP'].includes(transport))throw Error('Unsupported media transport');const channel=this.channels.find(x=>x.channelId===channelId);if(!channel)throw Error('Channel is not in the registered catalog');if(channel.status!=='ON')throw Error('Channel is offline');
    const row={id:token(),channelId,transport,peer,state:'preparing',startedAt:new Date().toISOString(),ssrc:'010'+String(Math.floor(Math.random()*10000000)).padStart(7,'0'),remoteSeq:0};this.active=row;
    row.playPromise=(async()=>{
      try{
        row.capture=await this.captureFactory({directory:this.directory,id:row.id,transport,ssrc:row.ssrc,port:0,ffmpegPath:this.ffmpegPath,onLimit:reason=>{row.reason=String(reason);this.stop().catch(()=>{});}});
        if(row.stopRequested)throw Error('Play cancelled');
        const body=['v=0',`o=${this.id} 0 0 IN IP4 ${loopback}`,'s=Play',`c=IN IP4 ${loopback}`,'t=0 0',`m=video ${row.capture.port} ${transport==='TCP'?'TCP/':''}RTP/AVP 96`,'a=recvonly','a=rtpmap:96 PS/90000',...(transport==='TCP'?['a=setup:passive','a=connection:new']:[]),`y=${row.ssrc}`,''].join('\r\n');
        row.state='inviting';row.invite=this.request('INVITE',{peer,id:row.id,uri:`sip:${channelId}@${this.realm}`,to:`<sip:${channelId}@${this.realm}>`,body,headers:{'Content-Type':'application/sdp',Subject:`${channelId}:${row.ssrc},${this.id}:0`}});
        const answer=await row.invite.promise;row.answer=answer;this.ack(row,answer);
        if(answer.status!==200)throw Error(`INVITE rejected (${answer.status})`);
        row.established=true;row.state='receiving';
        const sdp=answer.body.toString('utf8');
        if(!/^application\/sdp(?:\s*;|$)/i.test(answer.headers['content-type']??'')||!sdp.includes('a=rtpmap:96 PS/90000')||!sdp.split(/\r?\n/).includes(`y=${row.ssrc}`))throw Error('Invalid media answer');
        if(row.stopRequested){await this.sendBye(row);throw Error('Play cancelled');}
        this.log(`Media INVITE accepted for ${channelId}`);return this.captureSnapshot(row);
      }catch(error){
        if(row.invite&&!row.answer){this.retiredInvites.set(row.invite.key,{row,expiresAt:Date.now()+32000});if(this.retiredInvites.size>128)this.retiredInvites.delete(this.retiredInvites.keys().next().value);await this.cancelInvite(row).catch(()=>{});}
        if(row.established&&!row.byeSent)await this.sendBye(row).catch(()=>{});await this.finish(row,row.stopRequested?'stopped':'error',error.message);throw error;
      }
    })();return row.playPromise;
  }
  ack(row,answer){
    const invite=row.invite,fields={...invite.fields,To:answer.headers.to,CSeq:`${invite.seq} ACK`};
    if(answer.status===200)fields.Via=`SIP/2.0/${row.peer.transport} ${loopback}:${this.port};branch=z9hG4bK${token()}`;
    const ack=serialize(`ACK ${invite.uri} SIP/2.0`,fields);row.peer.send(ack);
    if(answer.status===200){this.answered.set(invite.key,{peer:row.peer,from:fields.From,to:fields.To,ack,expiresAt:Date.now()+32000});if(this.answered.size>128)this.answered.delete(this.answered.keys().next().value);}
  }
  async sendBye(row){if(row.byeSent||!row.established)return;row.byeSent=true;const invite=row.invite;const tx=this.request('BYE',{peer:row.peer,id:row.id,seq:invite.seq+1,uri:invite.uri,from:invite.fields.From,to:row.answer.headers.to});const result=await tx.promise;if(result.status!==200&&result.status!==481)throw Error(`BYE rejected (${result.status})`);}
  cancelInvite(row){if(row.cancelPromise)return row.cancelPromise;const tx=row.invite;row.cancelPromise=this.request('CANCEL',{peer:row.peer,id:row.id,seq:tx.seq,uri:tx.uri,from:tx.fields.From,to:tx.fields.To,branchId:tx.branchId}).promise;return row.cancelPromise;}
  peerBye(m,reply){const row=this.active;if(!row?.established||m.headers['call-id']!==row.id||tag(m.headers.from)!==tag(row.answer.headers.to)||tag(m.headers.to)!==tag(row.invite.fields.From)||user(m.headers.from)!==row.channelId||user(m.headers.to)!==this.id||user(m.uri)!==this.id){reply(481);return;}
    const seq=numericSequence(m);if(seq<=row.remoteSeq){reply(500);return;}row.remoteSeq=seq;reply(200,{},'',tag(row.invite.fields.From));row.byeSent=true;this.finish(row,'stopped','Lower platform ended the media session').catch(()=>{});
  }
  async finish(row,state,reason){if(row.finishing)return row.finishing;row.state='closing';row.finishing=(async()=>{try{await row.capture?.close();}catch{state='error';reason='Media capture close failed';}row.state=state;row.reason=reason;this.history.unshift({...this.captureSnapshot(row),endedAt:new Date().toISOString()});if(this.history.length>50)this.history.pop();if(this.active===row)this.active=null;this.log(`Media session ${state}`);})();return row.finishing;}
  async stop(){
    const row=this.active;if(!row)return null;if(row.stopping)return row.stopping;row.stopRequested=true;
    row.stopping=(async()=>{
      if(row.state==='inviting'&&row.invite&&!row.established)try{await this.cancelInvite(row);}catch{}
      if(row.playPromise)await row.playPromise.catch(()=>{});
      let reason=row.reason??'Stopped by simulator';try{await this.sendBye(row);}catch{reason='Stopped locally; lower BYE acknowledgement missing';}
      await this.finish(row,'stopped',reason);return this.history.find(x=>x.id===row.id)??null;
    })();return row.stopping;
  }
  async close(){
    if(this.closePromise)return this.closePromise;this.closing=true;
    this.closePromise=(async()=>{await this.stop();this.closed=true;for(const tx of [...this.transactions.values()])this.settle(tx,Error('SIP simulator closed'));if(this.catalogPending){this.catalogPending.reject(Error('SIP simulator closed'));this.catalogPending=null;}
      for(const timer of this.timers)clearTimeout(timer);this.timers.clear();for(const socket of this.sockets)socket.destroy();
      await Promise.all([this.udp?new Promise(resolve=>{try{this.udp.close(resolve);}catch{resolve();}}):null,this.tcp?new Promise(resolve=>{try{this.tcp.close(resolve);}catch{resolve();}}):null]);this.peer=null;this.nonces.clear();this.responses.clear();this.answered.clear();this.retiredInvites.clear();
    })();return this.closePromise;
  }
}
