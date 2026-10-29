import dgram from 'node:dgram';
import net from 'node:net';
import {createHash} from 'node:crypto';
import {parseMessage,frameLength,serialize,response,transactionKey,token,branch,tag,user,digest,queryXml,xml,negotiateSdp,answerSdp} from './sip.mjs';
const norm=ip=>ip?.replace(/^::ffff:/,'');
export class GbBridge{
  constructor(config,media,{log=()=>{}}={}){this.config=config;this.media=media;this.log=log;this.sessions=new Map();this.transactions=new Map();this.responses=new Map();this.sockets=new Set();this.timers=new Set();this.cseq=0;this.sn=0;this.registered=false;this.closed=false;this.failures=0;this.registrationId=token();this.registrationTag=token();}
  later(fn,ms){const t=setTimeout(()=>{this.timers.delete(t);Promise.resolve().then(fn).catch(()=>this.log('GB_TIMER_FAILED'));},ms);this.timers.add(t);return t;}
  clear(t){clearTimeout(t);this.timers.delete(t);}
  async start(){
    await this.media.recover();
    if(this.config.transport==='UDP'){
      this.udp=dgram.createSocket('udp4');this.udp.on('message',(b,p)=>{if(p.address===this.config.upperIp&&p.port===this.config.upperPort)this.receive(b,{send:data=>this.udp.send(data,p.port,p.address)});});
      this.udp.on('error',()=>this.log('GB_UDP_ERROR'));
      await new Promise((resolve,reject)=>{this.udp.once('error',reject);this.udp.bind(this.config.localPort,this.config.bindIp,resolve);});
    }else{
      this.tcp=net.createServer(socket=>{if(norm(socket.remoteAddress)!==this.config.upperIp||this.sockets.size>=16)return socket.destroy();this.attachSocket(socket);});
      this.tcp.on('error',()=>this.log('GB_TCP_ERROR'));
      await new Promise((resolve,reject)=>{this.tcp.once('error',reject);this.tcp.listen(this.config.localPort,this.config.bindIp,resolve);});
    }
    this.maintenance();this.register();return this;
  }
  attachSocket(socket){
    this.sockets.add(socket);socket.setNoDelay(true);socket.setTimeout(180000);let buffer=Buffer.alloc(0);
    socket.on('timeout',()=>socket.destroy());socket.on('error',()=>this.log('GB_TCP_PEER_ERROR'));
    socket.on('close',()=>{this.sockets.delete(socket);if(this.outbound===socket)this.outbound=null;});
    socket.on('data',bytes=>{try{buffer=Buffer.concat([buffer,bytes]);while(buffer.length){if(buffer.subarray(0,4).toString()==='\r\n\r\n'){buffer=buffer.subarray(4);continue;}const n=frameLength(buffer);if(!n)break;this.receive(buffer.subarray(0,n),{send:data=>socket.write(data)});buffer=buffer.subarray(n);}}catch{socket.destroy();this.log('GB_INVALID_TCP_FRAME');}});
    return socket;
  }
  async send(data){
    if(this.closed)throw Error('Bridge closed');
    if(this.config.transport==='UDP')return new Promise((resolve,reject)=>this.udp.send(data,this.config.upperPort,this.config.upperIp,e=>e?reject(e):resolve()));
    if(this.outbound&&!this.outbound.destroyed)return this.outbound.write(data);
    if(!this.connecting)this.connecting=new Promise((resolve,reject)=>{
      const socket=this.attachSocket(net.createConnection({host:this.config.upperIp,port:this.config.upperPort}));
      const timer=setTimeout(()=>socket.destroy(),5000);
      socket.once('connect',()=>{clearTimeout(timer);this.outbound=socket;resolve(socket);});
      socket.once('error',()=>{clearTimeout(timer);reject(Error('SIP connect failed'));});socket.once('close',()=>{clearTimeout(timer);if(!this.outbound)reject(Error('SIP disconnected'));});
    }).finally(()=>{this.connecting=null;});
    const socket=await this.connecting;socket.write(data);
  }
  request(method,body='',extra={},dialog){
    if(this.closed)return Promise.reject(Error('Closed'));
    const c=this.config,id=dialog?.callId??token(),seq=dialog?.cseq??++this.cseq,uri=dialog?.uri??`sip:${c.upperId}@${c.realm}`,b='z9hG4bK'+token();
    const fields={Via:`SIP/2.0/${c.transport} ${c.localIp}:${c.localPort};rport;branch=${b}`,From:dialog?.from??`<sip:${c.localId}@${c.realm}>;tag=${token()}`,To:dialog?.to??`<sip:${c.upperId}@${c.realm}>`,'Call-ID':id,CSeq:`${seq} ${method}`,'Max-Forwards':'70',Contact:`<sip:${c.localId}@${c.localIp}:${c.localPort};transport=${c.transport.toLowerCase()}>`,...extra};
    const data=serialize(`${method} ${uri} SIP/2.0`,fields,body),key=`${id}|${seq} ${method}|${b}`;
    return new Promise((resolve,reject)=>{
      const tx={resolve,reject,method,started:Date.now(),interval:c.t1??500,data,fields};this.transactions.set(key,tx);
      const transmit=async()=>{if(this.transactions.get(key)!==tx)return;
        if(Date.now()-tx.started>(c.transactionMs??32000)){this.transactions.delete(key);return reject(Error('SIP transaction timeout'));}
        try{await this.send(data);}catch{this.transactions.delete(key);return reject(Error('SIP send failed'));}
        if(c.transport==='UDP'){tx.timer=this.later(transmit,tx.interval);tx.interval=Math.min(4000,tx.interval*2);}
      };
      tx.deadline=this.later(()=>{if(this.transactions.delete(key)){this.clear(tx.timer);reject(Error('SIP transaction timeout'));}},c.transactionMs??32000);
      transmit();
    });
  }
  async register(){
    if(this.closed||this.registering)return;this.registering=true;
    try{
      const c=this.config,uri=`sip:${c.upperId}@${c.realm}`;let auth={},r,wanted=c.registerSeconds;
      for(let attempt=0;attempt<3;attempt++){
        r=await this.request('REGISTER','',{Expires:String(wanted),...auth},{callId:this.registrationId,from:`<sip:${c.localId}@${c.realm}>;tag=${this.registrationTag}`});
        if(r.status===423){const minimum=Number(r.headers['min-expires']);if(!Number.isInteger(minimum)||minimum<10||minimum>86400)throw Error('Invalid minimum expiry');wanted=minimum;continue;}
        if(![401,407].includes(r.status))break;
        const proxy=r.status===407;auth={[proxy?'Proxy-Authorization':'Authorization']:digest(r.headers[proxy?'proxy-authenticate':'www-authenticate'],{username:c.username,password:c.password,uri,expectedRealm:c.realm})};
      }
      if(r.status!==200)throw Error('Registration rejected');
      const contactExpires=/;expires=(\d+)/i.exec(r.headers.contact??'')?.[1],expires=Number(contactExpires??r.headers.expires??wanted);
      if(!Number.isInteger(expires)||expires<10||expires>86400)throw Error('Invalid registration expiry');
      this.registered=true;this.failures=0;this.log('GB_REGISTERED');
      this.clear(this.registrationTimer);this.registrationTimer=this.later(()=>this.register(),expires*800);
      if(!this.heartbeatTimer)this.heartbeatTimer=this.later(()=>this.heartbeat(),c.heartbeatSeconds*1000);
    }catch{this.registered=false;this.log('GB_REGISTRATION_FAILED');this.registrationTimer=this.later(()=>this.register(),5000);}
    finally{this.registering=false;}
  }
  async heartbeat(){
    this.heartbeatTimer=null;if(this.closed)return;
    if(this.registered)try{const body=`<?xml version="1.0" encoding="UTF-8"?><Notify><CmdType>Keepalive</CmdType><SN>${++this.sn}</SN><DeviceID>${this.config.localId}</DeviceID><Status>OK</Status></Notify>`;
      const r=await this.request('MESSAGE',body,{'Content-Type':'Application/MANSCDP+xml'});if(r.status!==200)throw Error();this.failures=0;
    }catch{if(++this.failures>=this.config.heartbeatFailures){this.registered=false;await Promise.allSettled([...this.sessions.values()].map(s=>this.finish(s,true)));this.register();}}
    this.heartbeatTimer=this.later(()=>this.heartbeat(),this.config.heartbeatSeconds*1000);
  }
  receive(bytes,peer){
    let m;try{m=parseMessage(bytes);}catch{this.log('GB_INVALID_SIP');return;}
    if(!branch(m)||!/^z9hG4bK/.test(branch(m)))return;
    if(m.status){const key=transactionKey(m),tx=this.transactions.get(key);if(!tx||m.status<200)return;
      if(m.headers.from!==tx.fields.From||tag(m.headers.to)===undefined&&tx.method!=='REGISTER')return;
      this.transactions.delete(key);this.clear(tx.timer);this.clear(tx.deadline);tx.resolve(m);return;
    }
    if(m.headers.cseq.split(' ')[1]!==m.method||user(m.headers.from)!==this.config.upperId||!tag(m.headers.from)){peer.send(response(m,403));return;}
    const key=transactionKey(m),cached=this.responses.get(key);if(cached&&m.method!=='ACK'){peer.send(cached.data);return;}
    const reply=(status,extra={},body='',localTag)=>{const data=response(m,status,extra,body,localTag);if(m.method!=='ACK')this.responses.set(key,{data,at:Date.now()});peer.send(data);return data;};
    if(!this.registered&&!['BYE','CANCEL','ACK'].includes(m.method)){reply(503);return;}
    (async()=>{
      if(m.method==='MESSAGE')return this.message(m,reply);
      if(m.method==='INVITE')return this.invite(m,reply,peer);
      if(m.method==='ACK')return this.ack(m);
      if(m.method==='BYE')return this.bye(m,reply);
      if(m.method==='CANCEL')return this.cancel(m,reply);
      if(m.method==='OPTIONS'){reply(200,{Allow:'REGISTER, MESSAGE, INVITE, ACK, BYE, CANCEL, OPTIONS'});return;}
      reply(405,{Allow:'REGISTER, MESSAGE, INVITE, ACK, BYE, CANCEL, OPTIONS'});
    })().catch(()=>{this.log('GB_REQUEST_FAILED');if(!this.responses.has(key))reply(500);});
  }
  async message(m,reply){
    if(!/^application\/manscdp\+xml(?:\s*;|$)/i.test(m.headers['content-type']??''))return reply(415);
    let q;try{q=queryXml(m.body);}catch{return reply(400);}
    const c=this.config,channel=c.channels.find(x=>x.channelId===q.deviceId);
    if(q.deviceId!==c.localId&&!channel)return reply(404);
    if(!['Catalog','DeviceStatus','DeviceInfo'].includes(q.cmd))return reply(501);
    reply(200);let inner='';
    if(q.cmd==='Catalog'){
      const channels=channel?[channel]:c.channels;const states=await Promise.all(channels.map(ch=>this.media.device(ch).catch(()=>({online:false}))));
      inner=`<SumNum>${channels.length}</SumNum><DeviceList Num="${channels.length}">`+channels.map((ch,i)=>`<Item><DeviceID>${ch.channelId}</DeviceID><Name>${xml(ch.name)}</Name><Manufacturer>Wearable</Manufacturer><Model>HELMET</Model><Owner>WearablePlatform</Owner><CivilCode>${ch.channelId.slice(0,6)}</CivilCode><Address></Address><Parental>0</Parental><ParentID>${c.localId}</ParentID><SafetyWay>0</SafetyWay><RegisterWay>1</RegisterWay><Secrecy>0</Secrecy><Status>${states[i].online?'ON':'OFF'}</Status></Item>`).join('')+'</DeviceList>';
    }else if(q.cmd==='DeviceStatus'){
      const status=channel?await this.media.device(channel).catch(()=>({online:false})):{online:true};inner=`<Result>OK</Result><Online>${status.online?'ONLINE':'OFFLINE'}</Online><Status>${status.online?'OK':'ERROR'}</Status><DeviceTime>${new Date().toISOString().replace(/\.\d{3}Z$/,'')}</DeviceTime>`;
    }else inner=`<Result>OK</Result><DeviceName>${xml(channel?.name??'Wearable GB Gateway')}</DeviceName><Manufacturer>Wearable</Manufacturer><Model>GBBridge</Model><Firmware>0.1.0</Firmware><Channel>${channel?1:c.channels.length}</Channel>`;
    const body=`<?xml version="1.0" encoding="UTF-8"?><Response><CmdType>${q.cmd}</CmdType><SN>${q.sn}</SN><DeviceID>${q.deviceId}</DeviceID>${inner}</Response>`;
    await this.request('MESSAGE',body,{'Content-Type':'Application/MANSCDP+xml'});
  }
  async invite(m,reply,peer){
    const c=this.config,channel=c.channels.find(x=>x.channelId===user(m.uri)),callId=m.headers['call-id'];
    if(!channel)return reply(404);if(this.sessions.has(callId))return reply(488);
    if(this.sessions.size>=c.maxSessions)return reply(486);
    if(!/^application\/sdp(?:\s*;|$)/i.test(m.headers['content-type']??''))return reply(415);
    let media;try{media=negotiateSdp(m.body,c);}catch{return reply(488);}
    const used=new Set([...this.sessions.values()].map(s=>s.localPort));let localPort=c.rtpSourcePort||30000;while(used.has(localPort))localPort+=2;if(localPort>65534)return reply(503);
    const row={callId,channel,media,localPort,request:m,reply,peer,tag:token(),state:'preparing',started:Date.now(),leaseId:'GB_'+createHash('sha256').update(callId+'|'+m.headers.from+'|'+token()).digest('hex').slice(0,48),abort:new AbortController(),remoteSeq:Number(m.headers.cseq.split(' ')[0]),localSeq:0};
    this.sessions.set(callId,row);reply(100,{},'',row.tag);
    row.preparation=(async()=>{
      try{
        await this.media.prepare(row,row.abort.signal);if(row.abort.signal.aborted)return;
        row.state='awaiting-ack';row.answer=reply(200,{Contact:`<sip:${c.localId}@${c.localIp}:${c.localPort}>`,'Content-Type':'application/sdp'},answerSdp({...c,rtpSourcePort:localPort},media),row.tag);
        row.ackDeadline=this.later(()=>this.finish(row,false),c.ackTimeoutMs);let interval=c.t1??500;
        const resend=()=>{if(row.state!=='awaiting-ack')return;peer.send(row.answer);interval=Math.min(interval*2,4000);row.answerTimer=this.later(resend,interval);};
        if(c.transport==='UDP')row.answerTimer=this.later(resend,interval);
      }catch(e){if(!row.abort.signal.aborted)reply(e.code==='GB_DEVICE_BUSY'||e.status===409?486:e.code==='GB_DEVICE_OFFLINE'?480:503,{},'',row.tag);}
      finally{if(row.state==='preparing'||row.abort.signal.aborted)await this.finish(row,false,true);}
    })();
    await row.preparation;
  }
  dialogMatches(row,m){return row&&tag(m.headers.from)===tag(row.request.headers.from)&&tag(m.headers.to)===row.tag;}
  async ack(m){
    const row=this.sessions.get(m.headers['call-id']);if(!this.dialogMatches(row,m)||m.headers.cseq.split(' ')[0]!==row.request.headers.cseq.split(' ')[0]||row.state!=='awaiting-ack')return;
    row.state='starting';this.clear(row.ackDeadline);this.clear(row.answerTimer);
    row.starting=(async()=>{try{await this.media.start(row);if(row.abort.signal.aborted)return;row.state='streaming';row.renewAt=Date.now()+this.config.leaseRenewMs;}
      catch{this.log('GB_RTP_START_FAILED');await this.finish(row,true,true);}})();await row.starting;
  }
  async bye(m,reply){const row=this.sessions.get(m.headers['call-id']);if(!this.dialogMatches(row,m))return reply(481);
    const seq=Number(m.headers.cseq.split(' ')[0]);if(seq<=row.remoteSeq)return reply(500);row.remoteSeq=seq;reply(200,{},'',row.tag);await this.finish(row,false);}
  async cancel(m,reply){const row=this.sessions.get(m.headers['call-id']);
    if(!row||tag(m.headers.from)!==tag(row.request.headers.from)||branch(m)!==branch(row.request)||m.headers.cseq.split(' ')[0]!==row.request.headers.cseq.split(' ')[0])return reply(481);
    reply(200,{},'',row.tag);if(row.state==='preparing'){row.reply(487,{},'',row.tag);await this.finish(row,false);}
  }
  async finish(row,notify,inside=false){
    if(row.finishing)return inside?undefined:row.finishing;
    row.abort.abort();this.clear(row.ackDeadline);this.clear(row.answerTimer);const wasEstablished=['starting','streaming'].includes(row.state);row.state='closing';
    if(notify&&wasEstablished){const req=row.request;this.request('BYE','',req.headers['record-route']?{Route:req.headers['record-route']}:{},{callId:row.callId,cseq:++row.localSeq,from:req.headers.to+(/;tag=/.test(req.headers.to)?'':`;tag=${row.tag}`),to:req.headers.from,uri:/<([^>]+)>/.exec(req.headers.contact??'')?.[1]??`sip:${this.config.upperId}@${this.config.realm}`}).catch(()=>{});}
    row.finishing=(async()=>{
      // Wait for in-flight acquisition/start so cleanup cannot race with a late successful resource creation.
      if(!inside){if(row.preparation)await row.preparation.catch(()=>{});if(row.starting)await row.starting.catch(()=>{});}
      await this.media.release(row);this.sessions.delete(row.callId);
    })();return row.finishing;
  }
  maintenance(){
    if(this.closed)return;
    this.later(async()=>{
      for(const [key,r]of this.responses)if(Date.now()-r.at>120000)this.responses.delete(key);
      if(this.responses.size>10000){this.log('GB_RESPONSE_LIMIT');for(const key of [...this.responses.keys()].slice(0,1000))this.responses.delete(key);}
      for(const row of this.sessions.values()){
        if(Date.now()-row.started>this.config.maxSessionMs){this.finish(row,true);continue;}
        if(row.state==='streaming'&&!row.renewing&&Date.now()>=row.renewAt){row.renewing=true;
          this.media.renew(row).catch(()=>this.finish(row,true)).finally(()=>{row.renewing=false;row.renewAt=Date.now()+this.config.leaseRenewMs;});}
      }
      if(!this.recovering&&Date.now()>=(this.cleanupAt??0)){
        this.recovering=true;this.cleanupAt=Date.now()+30000;
        this.media.cleanupOrphans(new Set([...this.sessions.values()].map(s=>s.leaseId))).catch(()=>this.log('GB_CLEANUP_RETRY_PENDING')).finally(()=>{this.recovering=false;});
      }
      this.maintenance();
    },500);
  }
  async close(){
    this.closed=true;for(const timer of this.timers)clearTimeout(timer);this.timers.clear();
    for(const tx of this.transactions.values())tx.reject(Error('Bridge closed'));this.transactions.clear();
    await Promise.allSettled([...this.sessions.values()].map(row=>this.finish(row,false)));
    this.udp?.close();for(const socket of this.sockets)socket.destroy();if(this.tcp)await new Promise(resolve=>this.tcp.close(resolve));
  }
}
