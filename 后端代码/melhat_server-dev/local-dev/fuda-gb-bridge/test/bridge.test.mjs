import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import dgram from 'node:dgram';
import {createHmac,createHash} from 'node:crypto';
import {GbBridge} from '../bridge.mjs';
import {MediaAdapter,SessionJournal} from '../media.mjs';
import {parseMessage,serialize,response,token,frameLength,negotiateSdp,digest,queryXml} from '../sip.mjs';
import {configuration} from '../config.mjs';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn,timeout=4000){const limit=Date.now()+timeout;while(!fn()){if(Date.now()>limit)throw Error('condition timeout');await sleep(10);}return fn();}
const upperId='34020000002000000001',localId='34020000002000000002',channelId='34020000001320000001';
const sdp=(ip='127.0.0.1',transport='RTP/AVP',extra='')=>`v=0\r\no=${upperId} 0 0 IN IP4 127.0.0.1\r\ns=Play\r\nc=IN IP4 ${ip}\r\nt=0 0\r\nm=video 31000 ${transport} 96\r\na=rtpmap:96 PS/90000\r\na=recvonly\r\n${extra}y=0100000001\r\n`;
async function fixture(t,transport='UDP',options={}){
  const state={requests:[],zlm:[],leases:new Map(),released:[],online:true,busy:false,publishing:true,auth:0,delayed:0,rtpFail:false};
  const secret='test-only-shared-secret-000000000000',nonces=new Set();
  const control=http.createServer(async(req,res)=>{
    const parts=[];for await(const part of req)parts.push(part);const raw=Buffer.concat(parts).toString();
    const send=(status,b)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(b));};
    if(req.url.startsWith('/index/api/')){
      const input=Object.fromEntries(new URLSearchParams(raw));state.zlm.push({api:req.url.split('/').at(-1),input});
      if(input.secret!=='test-zlm-secret-0000000000')return send(401,{});
      if(req.url.endsWith('/startSendRtp')&&state.rtpFail)return send(200,{code:-1});
      if(req.url.endsWith('/addStreamProxy'))return send(200,{code:0,data:{key:'__defaultVhost__/fuda_gb/'+input.stream}});
      if(req.url.endsWith('/startSendRtp'))return send(200,{code:0,local_port:Number(input.src_port)});
      if(req.url.endsWith('/getMediaInfo'))return send(200,{code:0,tracks:[{codec_type:0,codec_id_name:'H264',ready:true},{codec_type:1,codec_id_name:'AAC',ready:true}]});
      return send(200,{code:0});
    }
    const time=req.headers['x-gb-time'],nonce=req.headers['x-gb-nonce'],sig=req.headers['x-gb-signature'];
    const expected=createHmac('sha256',secret).update(`${time}\n${nonce}\n${req.method}\n${req.url}\n${createHash('sha256').update(raw).digest('hex')}`).digest('hex');
    if(sig!==expected||nonces.has(nonce)||Math.abs(Date.now()/1000-Number(time))>60)return send(401,{error:'GB_UNAUTHORIZED'});nonces.add(nonce);state.auth++;
    if(req.url.includes('/devices/'))return send(200,{code:200,data:{online:state.online,busy:state.busy,mediaAvailable:true}});
    const lease=req.url.split('/').at(-1);
    if(req.method==='DELETE'){state.leases.delete(lease);state.released.push(lease);return send(200,{code:200,data:{released:true}});}
    if(!state.online)return send(503,{error:'GB_DEVICE_OFFLINE'});if(state.busy)return send(409,{error:'GB_DEVICE_BUSY'});
    if(req.method==='PUT')state.leases.set(lease,JSON.parse(raw));
    if(state.delayed)await sleep(state.delayed);
    return send(200,{code:200,data:{streamId:'real-source-id',playToken:'test.playback-ticket-only-0000',online:true,busy:false,publishing:state.publishing,statusVerified:true}});
  });
  await new Promise(r=>control.listen(0,'127.0.0.1',r));
  const replies=[],received=[];let sendUpper,upperPort,upperSocket;
  const process=bytes=>{const m=parseMessage(bytes);received.push(m);
    if(m.method==='REGISTER'){
      if(!m.headers.authorization){sendUpper(response(m,401,{'WWW-Authenticate':'Digest realm="3402000000", nonce="testnonce", algorithm=MD5, qop="auth"'},'','up'));}
      else{assert.match(m.headers.authorization,/response="[a-f0-9]{32}"/);sendUpper(response(m,200,{Expires:'60'},'','up'));}
    }else if(m.method){sendUpper(response(m,200,{},'','up'));}
    else replies.push(m);
  };
  let upper;
  if(transport==='UDP'){
    upper=dgram.createSocket('udp4');upper.on('message',(b,p)=>{sendUpper=data=>upper.send(data,p.port,p.address);process(b);});await new Promise(r=>upper.bind(0,'127.0.0.1',r));upperPort=upper.address().port;
  }else{
    upper=net.createServer(socket=>{upperSocket=socket;sendUpper=data=>socket.write(data);let buf=Buffer.alloc(0);socket.on('data',b=>{buf=Buffer.concat([buf,b]);while(true){const n=frameLength(buf);if(!n)break;process(buf.subarray(0,n));buf=buf.subarray(n);}});});await new Promise(r=>upper.listen(0,'127.0.0.1',r));upperPort=upper.address().port;
  }
  const config={enabled:true,transport,upperIp:'127.0.0.1',upperPort,upperId,localId,localIp:'127.0.0.1',bindIp:'127.0.0.1',localPort:0,realm:'3402000000',username:localId,password:'testpassword',registerSeconds:60,heartbeatSeconds:600,heartbeatFailures:3,channels:[{channelId,deviceId:'helmet-test',deviceType:'HELMET',name:'Test helmet'}],mediaPeers:['127.0.0.1'],mediaMinPort:30000,mediaMaxPort:32000,mediaIp:'127.0.0.1',rtpSourcePort:30020,sourceTimeoutMs:800,ackTimeoutMs:800,maxSessionMs:60000,maxSessions:8,t1:50,transactionMs:1000,leaseRenewMs:20000,javaOrigin:`http://127.0.0.1:${control.address().port}`,javaSecret:secret,zlmOrigin:`http://127.0.0.1:${control.address().port}`,zlmSecret:'test-zlm-secret-0000000000',srsOrigin:'rtmp://127.0.0.1:1935',requireAudio:true,...options};
  const events=[];
  const media=new MediaAdapter(config,{journal:new SessionJournal(null)}),bridge=new GbBridge(config,media,{log:x=>events.push(x)});
  t.after(async()=>{await bridge.close();upperSocket?.destroy();await new Promise(r=>upper.close(r));await new Promise(r=>control.close(r));});
  await bridge.start();try{await until(()=>bridge.registered);}catch(e){throw Error(JSON.stringify({events,received:received.map(x=>({method:x.method,status:x.status,auth:!!x.headers.authorization}))}));}
  function request(method,{id='call-'+token(),seq=1,body='',toTag,branchId='z9hG4bK'+token(),target=channelId,fromTag='fuda-from'}={}){
    const fields={Via:`SIP/2.0/${transport} 127.0.0.1:${upperPort};branch=${branchId}`,From:`<sip:${upperId}@3402000000>;tag=${fromTag}`,To:`<sip:${target}@3402000000>${toTag?`;tag=${toTag}`:''}`,'Call-ID':id,CSeq:`${seq} ${method}`,Contact:`<sip:${upperId}@127.0.0.1:${upperPort}>`,...(body?{'Content-Type':method==='MESSAGE'?'Application/MANSCDP+xml':'application/sdp'}:{})};
    const bytes=serialize(`${method} sip:${target}@3402000000 SIP/2.0`,fields,body);sendUpper(bytes);return {id,seq,bytes,branchId};
  }
  function final(id,method='INVITE'){return replies.find(m=>m.headers['call-id']===id&&m.headers.cseq.endsWith(method)&&m.status>=200);}
  return {bridge,config,state,events,request,final,replies,received,send:bytes=>sendUpper(bytes)};
}
for(const transport of ['UDP','TCP'])test(`${transport}: digest registration, catalog, INVITE/ACK -> PS/RTP and BYE cleanup`,async t=>{
  const f=await fixture(t,transport);
  assert.equal(f.received.filter(x=>x.method==='REGISTER').length,2);
  for(const register of f.received.filter(x=>x.method==='REGISTER'))assert.equal(register.headers.to,`<sip:${localId}@3402000000>`,'REGISTER To identifies the local registered AOR');
  f.request('MESSAGE',{target:localId,body:`<Query><CmdType>Catalog</CmdType><SN>8</SN><DeviceID>${localId}</DeviceID></Query>`});
  await until(()=>f.received.some(x=>x.method==='MESSAGE'&&x.body.includes(Buffer.from('<DeviceList'))));
  const inv=f.request('INVITE',{body:sdp()});await until(()=>f.final(inv.id));assert.equal(f.final(inv.id).status,200);
  assert.equal(f.state.zlm.filter(x=>x.api==='startSendRtp').length,0,'No RTP before ACK');
  f.send(inv.bytes);await sleep(30);assert.equal(f.state.zlm.filter(x=>x.api==='addStreamProxy').length,1,'Retransmission reuses acquisition');
  const localTag=/;tag=([^;]+)/.exec(f.final(inv.id).headers.to)[1];f.request('ACK',{id:inv.id,toTag:localTag});
  await until(()=>f.state.zlm.some(x=>x.api==='startSendRtp'));
  const rtp=f.state.zlm.find(x=>x.api==='startSendRtp').input;assert.equal(rtp.use_ps,'1');assert.equal(rtp.dst_url,'127.0.0.1');assert.equal(rtp.ssrc,'100000001');
  assert.equal(f.state.zlm.find(x=>x.api==='addStreamProxy').input.add_mute_audio,'0');
  f.request('ACK',{id:inv.id,toTag:localTag});await sleep(20);assert.equal(f.state.zlm.filter(x=>x.api==='startSendRtp').length,1);
  f.request('BYE',{id:inv.id,seq:2,toTag:localTag});await until(()=>f.state.released.length&&f.bridge.sessions.size===0);assert.ok(f.state.auth>0);
  assert.ok(f.events.includes('GB_CATALOG_SENT'));assert.ok(f.events.includes('GB_RTP_STARTED'));assert.ok(f.events.includes('GB_SESSION_RELEASED'));
});
test('media SSRF and unlisted channel are rejected before any acquisition',async t=>{
  const f=await fixture(t);const a=f.request('INVITE',{body:sdp('169.254.169.254')});await until(()=>f.final(a.id));assert.equal(f.final(a.id).status,488);
  const b=f.request('INVITE',{target:'34020000001320000999',body:sdp()});await until(()=>f.final(b.id));assert.equal(f.final(b.id).status,404);assert.equal(f.state.zlm.length,0);assert.equal(f.state.leases.size,0);
});
test('offline and busy helmets explicitly fail',async t=>{
  const f=await fixture(t);f.state.online=false;const a=f.request('INVITE',{body:sdp()});await until(()=>f.final(a.id));assert.equal(f.final(a.id).status,480);
  f.state.online=true;f.state.busy=true;const b=f.request('INVITE',{body:sdp()});await until(()=>f.final(b.id));assert.equal(f.final(b.id).status,486);
});
test('CANCEL during delayed acquire releases the eventual lease and cannot start RTP',async t=>{
  const f=await fixture(t);f.state.delayed=200;f.state.publishing=false;
  const a=f.request('INVITE',{body:sdp()});await until(()=>f.state.leases.size===1);f.request('CANCEL',{id:a.id,branchId:a.branchId});
  await until(()=>f.final(a.id));assert.equal(f.final(a.id).status,487);await until(()=>f.state.released.length&&f.bridge.sessions.size===0);assert.equal(f.state.leases.size,0);assert.ok(!f.state.zlm.some(x=>x.api==='startSendRtp'));
});
test('missing ACK expires and releases media',async t=>{const f=await fixture(t,'UDP',{ackTimeoutMs:150});const a=f.request('INVITE',{body:sdp()});await until(()=>f.final(a.id));await until(()=>f.state.released.length&&f.bridge.sessions.size===0);assert.ok(f.events.includes('GB_INVITE_ACK_TIMEOUT'));});
test('wrong dialog tag cannot tear down a valid session',async t=>{const f=await fixture(t);const a=f.request('INVITE',{body:sdp()});await until(()=>f.final(a.id));f.request('BYE',{id:a.id,seq:2,toTag:'wrong'});await until(()=>f.final(a.id,'BYE'));assert.equal(f.final(a.id,'BYE').status,481);assert.equal(f.bridge.sessions.size,1);});
test('TCP media offer selects an active sender; receiver-active is explicitly rejected',()=>{
  const c={mediaPeers:['127.0.0.1'],mediaMinPort:30000,mediaMaxPort:32000};assert.equal(negotiateSdp(Buffer.from(sdp('127.0.0.1','TCP/RTP/AVP','a=setup:passive\r\n')),c).tcp,true);
  assert.throws(()=>negotiateSdp(Buffer.from(sdp('127.0.0.1','TCP/RTP/AVP','a=setup:active\r\n')),c));
});
test('unsafe XML, SIP framing and digest realms fail closed',()=>{
  assert.throws(()=>parseMessage(Buffer.from('INVITE sip:x SIP/2.0\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n')));
  assert.throws(()=>digest('Digest realm="other", nonce="n"',{username:'u',password:'p',uri:'sip:x',expectedRealm:'expected'}));
  assert.throws(()=>queryXml(Buffer.from('<!DOCTYPE Query [<!ENTITY x SYSTEM "file:///etc/passwd">]><Query><CmdType>Catalog</CmdType><SN>1</SN><DeviceID>34020000002000000002</DeviceID></Query>')));
  assert.deepEqual(configuration({}),{enabled:false});
});
test('source timeout cannot answer success and cleans pending lease',async t=>{const f=await fixture(t,'UDP',{sourceTimeoutMs:100});f.state.publishing=false;const a=f.request('INVITE',{body:sdp()});await until(()=>f.final(a.id));assert.equal(f.final(a.id).status,503);await until(()=>f.state.released.length&&f.bridge.sessions.size===0);});
test('RTP start failure sends BYE and cleans the session',async t=>{const f=await fixture(t);f.state.rtpFail=true;const a=f.request('INVITE',{body:sdp()});await until(()=>f.final(a.id));const tag=/;tag=([^;]+)/.exec(f.final(a.id).headers.to)[1];f.request('ACK',{id:a.id,toTag:tag});await until(()=>f.received.some(x=>x.method==='BYE')&&f.bridge.sessions.size===0);assert.equal(f.state.leases.size,0);});
test('lost source on lease renewal terminates established dialog',async t=>{const f=await fixture(t,'UDP',{leaseRenewMs:30});const a=f.request('INVITE',{body:sdp()});await until(()=>f.final(a.id));const tag=/;tag=([^;]+)/.exec(f.final(a.id).headers.to)[1];f.request('ACK',{id:a.id,toTag:tag});await until(()=>f.bridge.sessions.get(a.id)?.state==='streaming');f.state.online=false;await until(()=>f.received.some(x=>x.method==='BYE')&&f.bridge.sessions.size===0);});
test('digest result follows the RFC auth formula',()=>{const hash=s=>createHash('md5').update(s).digest('hex');const v=digest('Digest realm="r", nonce="n", qop="auth", algorithm=MD5',{username:'u',password:'p',uri:'sip:x',expectedRealm:'r'});const cnonce=/cnonce="([^"]+)"/.exec(v)[1],actual=/response="([^"]+)"/.exec(v)[1];assert.equal(actual,hash(`${hash('u:r:p')}:n:00000001:${cnonce}:auth:${hash('REGISTER:sip:x')}`));});
test('renew registration retains Call-ID and keepalive is a real MESSAGE transaction',async t=>{
  const f=await fixture(t);await f.bridge.register();const registrations=f.received.filter(x=>x.method==='REGISTER');assert.equal(registrations.length,4);assert.equal(new Set(registrations.map(x=>x.headers['call-id'])).size,1);
  assert.ok(Number(registrations[3].headers.cseq.split(' ')[0])>Number(registrations[0].headers.cseq.split(' ')[0]));await f.bridge.heartbeat();assert.ok(f.received.some(x=>x.method==='MESSAGE'&&x.body.includes(Buffer.from('<CmdType>Keepalive</CmdType>'))));
});
test('TCP media negotiated via UDP signaling invokes active TCP PS sender',async t=>{
  const f=await fixture(t);const a=f.request('INVITE',{body:sdp('127.0.0.1','TCP/RTP/AVP','a=setup:passive\r\n')});await until(()=>f.final(a.id));assert.equal(f.final(a.id).status,200);assert.match(f.final(a.id).body.toString(),/a=setup:active/);
  const tag=/;tag=([^;]+)/.exec(f.final(a.id).headers.to)[1];f.request('ACK',{id:a.id,toTag:tag});await until(()=>f.state.zlm.some(x=>x.api==='startSendRtp'));assert.equal(f.state.zlm.find(x=>x.api==='startSendRtp').input.is_udp,'0');
});

test('GB2312 catalog and keepalive use matching charset and byte length',async t=>{
  const f=await fixture(t,'UDP',{charset:'GB2312',channels:[{channelId,deviceId:'helmet-test',deviceType:'HELMET',name:'安全帽一号'}]});
  f.request('MESSAGE',{target:localId,body:`<?xml version="1.0" encoding="GB2312"?><Query><CmdType>Catalog</CmdType><SN>88</SN><DeviceID>${localId}</DeviceID></Query>`});
  await until(()=>f.received.some(m=>m.method==='MESSAGE'&&m.body.includes(Buffer.from('<DeviceList'))));
  await f.bridge.heartbeat();
  for(const message of f.received.filter(m=>m.method==='MESSAGE')){
    assert.equal(message.headers['content-type'],'Application/MANSCDP+xml; charset=GB2312');
    assert.equal(Number(message.headers['content-length']),message.body.length);
    assert.ok(message.body.every(value=>value<128),'ASCII XML references are valid GB2312 bytes');
    assert.match(message.body.toString('ascii'),/^<\?xml version="1.0" encoding="GB2312"\?>/);
  }
  const catalog=f.received.find(m=>m.body.includes(Buffer.from('<DeviceList')));
  assert.match(catalog.body.toString('ascii'),/<Name>&#23433;&#20840;&#24125;&#19968;&#21495;<\/Name>/);
});

test('CANCEL with a different request target cannot release a preparing session',async t=>{
  const f=await fixture(t);f.state.delayed=250;f.state.publishing=false;
  const a=f.request('INVITE',{body:sdp()});await until(()=>f.state.leases.size===1);
  f.request('CANCEL',{id:a.id,branchId:a.branchId,target:localId});await until(()=>f.final(a.id,'CANCEL'));
  assert.equal(f.final(a.id,'CANCEL').status,481);assert.equal(f.bridge.sessions.size,1);
});

test('BYE waits for in-flight lease renewal before deleting its lease',async t=>{
  const f=await fixture(t,'UDP',{leaseRenewMs:50});const a=f.request('INVITE',{body:sdp()});await until(()=>f.final(a.id));
  const localTag=/;tag=([^;]+)/.exec(f.final(a.id).headers.to)[1];f.request('ACK',{id:a.id,toTag:localTag});await until(()=>f.bridge.sessions.get(a.id)?.state==='streaming');
  const originalRenew=f.bridge.media.renew.bind(f.bridge.media);let entered=false,resume;
  const gate=new Promise(resolve=>{resume=resolve;});
  f.bridge.media.renew=async row=>{entered=true;await gate;return originalRenew(row);};
  try{
    await until(()=>entered);f.request('BYE',{id:a.id,seq:2,toTag:localTag});await until(()=>f.final(a.id,'BYE'));
    await sleep(30);assert.equal(f.state.released.length,0,'DELETE must wait until the pending PUT settles');
    resume();await until(()=>f.bridge.sessions.size===0);assert.equal(f.state.leases.size,0);
  }finally{resume();}
});

test('registration logs distinguish rejected status, send failure and transaction timeout safely',async()=>{
  for(const outcome of ['reject','send','timeout']){
    const events=[],config={transport:'UDP',localId,upperId,realm:'3402000000',registerSeconds:60,transactionMs:20,t1:10};
    const bridge=new GbBridge(config,{}, {log:x=>events.push(x)});
    if(outcome==='reject')bridge.request=async()=>({status:403,headers:{}});
    else bridge.send=async()=>{if(outcome==='send')throw Error('private endpoint and authentication details');};
    try{await bridge.register();assert.deepEqual(events,[`GB_REGISTRATION_FAILED ${outcome==='reject'?'SIP_403':outcome==='send'?'GB_SIP_SEND_FAILED':'GB_SIP_TIMEOUT'}`]);}
    finally{await bridge.close();}
  }
});

test('media diagnostics allow known error codes and never arbitrary error values',async t=>{
  const f=await fixture(t);f.state.online=false;const a=f.request('INVITE',{body:sdp()});await until(()=>f.final(a.id));
  assert.ok(f.events.includes('GB_PREPARATION_FAILED GB_DEVICE_OFFLINE'));
  f.bridge.media.prepare=async()=>{throw Object.assign(Error('private playback URL'),{code:'GB_PRIVATE_AUTHENTICATION_DATA'});};
  const b=f.request('INVITE',{body:sdp()});await until(()=>f.final(b.id));assert.equal(f.final(b.id).status,503);
  assert.ok(f.events.includes('GB_PREPARATION_FAILED GB_UNKNOWN_FAILURE'));assert.ok(!f.events.some(x=>/private|AUTHENTICATION/i.test(x)));
});

test('TCP passive offer outside the authorized RTP range records its fixed rejection reason',async t=>{
  const f=await fixture(t,'UDP',{mediaMinPort:30010,mediaMaxPort:30050});
  const body=sdp('127.0.0.1','TCP/RTP/AVP','a=setup:passive\r\n').replace('31000','30003').replace('TCP/RTP/AVP 96','TCP/RTP/AVP 96 97 98 99');
  const a=f.request('INVITE',{body});await until(()=>f.final(a.id));
  assert.equal(f.final(a.id).status,488);assert.equal(f.state.leases.size,0);assert.equal(f.state.zlm.length,0);
  assert.ok(f.events.includes('GB_INVITE_RECEIVED'));
  assert.ok(f.events.includes('GB_INVITE_REJECTED SIP_488 GB_SDP_DESTINATION_DENIED'));
});

test('explicit TCP 30003 exception accepts the captured offer shape and starts only the negotiated PS sender',async t=>{
  const f=await fixture(t,'UDP',{mediaMinPort:30010,mediaMaxPort:30050,mediaExtraTcpPorts:[30003]});
  const body=sdp('127.0.0.1','TCP/RTP/AVP','a=setup:passive\r\n').replace('31000','30003').replace('TCP/RTP/AVP 96','TCP/RTP/AVP 96 97 98 99');
  const a=f.request('INVITE',{body});await until(()=>f.final(a.id));assert.equal(f.final(a.id).status,200);
  const localTag=/;tag=([^;]+)/.exec(f.final(a.id).headers.to)[1];f.request('ACK',{id:a.id,toTag:localTag});
  await until(()=>f.bridge.sessions.get(a.id)?.state==='streaming');
  const sent=f.state.zlm.find(x=>x.api==='startSendRtp').input;
  assert.equal(sent.is_udp,'0');assert.equal(sent.dst_port,'30003');assert.equal(sent.dst_url,'127.0.0.1');assert.equal(sent.pt,'96');assert.equal(sent.use_ps,'1');
  f.request('BYE',{id:a.id,seq:2,toTag:localTag});await until(()=>f.bridge.sessions.size===0);assert.equal(f.state.leases.size,0);
});

test('unapproved UDP source ports remain ignored and diagnostics are rate limited without peer data',async t=>{
  const f=await fixture(t);const marker='private-untrusted-payload';
  const peer={address:f.config.upperIp,port:f.config.upperPort===65535?1:f.config.upperPort+1};
  for(let i=0;i<5;i++)f.bridge.udp.emit('message',Buffer.from(marker),peer);
  assert.equal(f.events.filter(x=>x==='GB_UPPER_UDP_SOURCE_PORT_MISMATCH').length,1);
  f.bridge.udp.emit('message',Buffer.from(marker),{...peer,address:'192.0.2.20'});
  assert.equal(f.events.filter(x=>x==='GB_UPPER_UDP_SOURCE_PORT_MISMATCH').length,1);
  f.bridge.udpPortLogAt=Date.now()-1;f.bridge.udp.emit('message',Buffer.from(marker),peer);
  assert.equal(f.events.filter(x=>x==='GB_UPPER_UDP_SOURCE_PORT_MISMATCH').length,2);
  assert.equal(f.state.leases.size,0);assert.ok(!f.events.some(x=>x.includes(marker)||x.includes(peer.address)));
});

test('INVITE rejection diagnostics preserve status rules and never expose request or exception text',async()=>{
  const events=[],marker='private-authorization-and-playback-ticket';
  const config={upperId,localId,channels:[{channelId}],maxSessions:8,mediaPeers:['127.0.0.1'],mediaMinPort:30000,mediaMaxPort:32000,rtpSourcePort:30020};
  const bridge=new GbBridge(config,{}, {log:x=>events.push(x)});bridge.registered=true;let seq=0;
  async function check(status,reason,{target=channelId,headers={},body=sdp(),id=marker+'-'+(++seq)}={}){
    const fields={Via:'SIP/2.0/UDP 127.0.0.1;branch=z9hG4bK'+seq,From:`<sip:${upperId}@example>;tag=fuda`,To:`<sip:${target}@example>`,'Call-ID':id,CSeq:'1 INVITE','Content-Type':'application/sdp',Authorization:marker,...headers};
    const replies=[];bridge.receive(serialize(`INVITE sip:${target}@example SIP/2.0`,fields,body),{send:b=>replies.push(parseMessage(b))});
    await until(()=>replies.length);assert.equal(replies[0].status,status);assert.ok(events.includes(`GB_INVITE_REJECTED SIP_${status} ${reason}`));
  }
  await check(403,'GB_INVALID_REQUEST_IDENTITY',{headers:{From:`<sip:${localId}@example>;tag=${marker}`}});
  await check(404,'GB_CHANNEL_NOT_AUTHORIZED',{target:localId});
  await check(415,'GB_SDP_CONTENT_TYPE_REQUIRED',{headers:{'Content-Type':marker}});
  await check(488,'GB_SDP_PS_REQUIRED',{body:sdp().replace('PS/90000',marker)});
  bridge.registered=false;await check(503,'GB_NOT_REGISTERED');bridge.registered=true;
  config.maxSessions=0;await check(486,'GB_SESSION_LIMIT');config.maxSessions=8;
  config.rtpSourcePort=65535;await check(503,'GB_LOCAL_RTP_PORT_EXHAUSTED');config.rtpSourcePort=30020;
  const duplicate=marker+'-duplicate';bridge.sessions.set(duplicate,{});await check(488,'GB_CALL_ALREADY_EXISTS',{id:duplicate});bridge.sessions.delete(duplicate);
  config.mediaPeers={includes(){throw Error(marker);}};await check(488,'GB_SDP_INVALID');config.mediaPeers=['127.0.0.1'];
  config.channels={find(){throw Error(marker);}};await check(500,'GB_INTERNAL_FAILURE');config.channels=[{channelId}];
  assert.ok(events.includes('GB_INVITE_RECEIVED'));
  assert.ok(events.every(value=>/^GB_[A-Z_]+(?: SIP_[0-9]{3})?(?: GB_[A-Z_]+)?$/.test(value)), 'Only fixed diagnostics reach the logger');
  assert.ok(!events.some(value=>value.includes(marker)||value.includes(channelId)||value.includes('sip:')));
  await bridge.close();
});
