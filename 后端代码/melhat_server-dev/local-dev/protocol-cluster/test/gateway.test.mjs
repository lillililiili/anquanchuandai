import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {randomBytes} from 'node:crypto';
import {once} from 'node:events';
import {setTimeout as delay} from 'node:timers/promises';
import {WebSocket,WebSocketServer} from 'ws';
import {createClusterGateway,validateClusterConfig} from '../gateway.mjs';
import {createDeviceGateway} from '../../device-gateway/gateway.mjs';

async function until(check) {
  for(let i=0;i<100;i++){if(await check())return;await delay(15);}
  throw new Error('Isolated condition did not become true');
}
async function fixture(t,kind='helmet',overrides={}) {
  const state={ready:true,messages:[],posts:0,invalidHealth:false};
  const upstream=http.createServer(async(req,res)=>{
    if(req.url==='/internal/cluster/ready'){res.writeHead(state.ready?200:503);res.end(state.invalidHealth?'<html>login</html>':JSON.stringify({ready:state.ready}));return;}
    if(req.method==='POST'){state.posts++;for await(const _ of req){}res.writeHead(503);res.end('{}');return;}
    const config={api_url:'http://private.invalid/api/',ws_url:'ws://private.invalid/wsHat'};
    res.setHeader('Content-Type','application/json');res.end(JSON.stringify({status:true,data:{config:JSON.stringify(config)}}));
  });
  const wss=new WebSocketServer({noServer:true});
  upstream.on('upgrade',(req,socket,head)=>wss.handleUpgrade(req,socket,head,ws=>{
    ws.on('message',raw=>{const msg=JSON.parse(raw);state.messages.push(msg);ws.send(JSON.stringify({cmd:msg.act,status:true}));});
    ws.on('error',()=>{});
  }));
  upstream.listen(0,'127.0.0.1');await once(upstream,'listening');
  const config={listenHost:'127.0.0.1',listenPort:0,upstreamOrigin:`http://127.0.0.1:${upstream.address().port}`,
    publicOrigin:'https://wearable.example.com',nodeId:'lab-a',adminToken:randomBytes(32).toString('base64url'),
    healthPollMillis:20,healthTimeoutMillis:300,drainTimeoutMillis:40,
    devices:[1,2].map(n=>({deviceId:`90000000000000${n}`,pathToken:randomBytes(32).toString('base64url')})),
    limits:{maxConnections:8,upgradesPerMinute:100,requestsPerMinute:200},...overrides};
  const gateway=createClusterGateway(kind,config,{testOnly:true});const address=await gateway.listen();
  const origin=`http://127.0.0.1:${address.port}`;
  t.after(async()=>{await gateway.close();for(const ws of wss.clients)ws.terminate();await new Promise(r=>wss.close(r));upstream.closeAllConnections();await new Promise(r=>upstream.close(r));});
  await until(async()=>(await fetch(origin+'/internal/gateway/ready')).status===200);
  return {state,config,gateway,origin,async connect(index,idOverride){
    const d=config.devices[index],suffix=kind==='belt'?'wsBelt':'wsHat';
    const ws=new WebSocket(origin.replace('http:','ws:')+`/${d.pathToken}/${suffix}`);ws.on('error',()=>{});await once(ws,'open');
    const response=once(ws,idOverride?'close':'message');ws.send(JSON.stringify({act:'ca_login',device_id:idOverride??d.deviceId}));await response;return ws;
  }};
}

for(const kind of ['helmet','belt']) {
  test(`${kind}: bootstrap keeps credentials and public device endpoints scoped`,async t=>{
    const f=await fixture(t,kind);
    for(const d of f.config.devices) {
      const path=kind==='belt'?'api/belt/index.php':'api/index.php';
      const url=f.origin+`/${d.pathToken}/${path}?ctl=config&act=get_config&device_id=${d.deviceId}`;
      const response=await fetch(url);assert.equal(response.status,200);
      const config=JSON.parse((await response.json()).data.config);
      assert.equal(config.ws_url,`wss://wearable.example.com/${kind==='belt'?d.pathToken.slice(0,24):d.pathToken}/wsHat`);
      if(kind==='helmet')assert.equal(config.api_url,`https://wearable.example.com/${d.pathToken}/api/`);
      assert.equal((await fetch(url.replace(d.deviceId,'wrong-device'))).status,400);
    }
  });
  test(`${kind}: device credentials bind each websocket to the matching identity`,async t=>{
    const f=await fixture(t,kind);await f.connect(0);await f.connect(1);
    assert.deepEqual(f.state.messages.map(x=>x.device_id).sort(),f.config.devices.map(x=>x.deviceId));
    await f.connect(0,f.config.devices[1].deviceId);assert.equal(f.state.messages.length,2);
  });
  test(`${kind}: drain denies new work, then closes existing devices`,async t=>{
    const f=await fixture(t,kind);const ws=await f.connect(0);const closed=once(ws,'close');
    assert.equal((await fetch(f.origin+'/internal/gateway/drain',{method:'POST'})).status,403);
    assert.equal((await fetch(f.origin+'/internal/gateway/drain',{method:'POST',headers:{'X-Cluster-Admin-Token':f.config.adminToken}})).status,202);
    assert.equal((await fetch(f.origin+'/internal/gateway/ready')).status,503);
    assert.equal((await fetch(f.origin+'/internal/gateway/live')).status,200);
    await closed;
    const d=f.config.devices[0];assert.equal((await fetch(f.origin+`/${d.pathToken}/api/index.php?ctl=config&act=get_config&device_id=${d.deviceId}`)).status,503);
  });
}
test('gateway becomes unready when its own paired backend fails',async t=>{
  const f=await fixture(t);f.state.ready=false;await until(async()=>(await fetch(f.origin+'/internal/gateway/ready')).status===503);
  assert.equal((await fetch(f.origin+'/internal/gateway/live')).status,200);
});
test('HTTP 200 login/error pages cannot make a paired backend ready',async t=>{
  const f=await fixture(t);f.state.invalidHealth=true;await until(async()=>(await fetch(f.origin+'/internal/gateway/ready')).status===503);
  const d=f.config.devices[0];
  const ws=new WebSocket(f.origin.replace('http:','ws:')+`/${d.pathToken}/wsHat`);
  const response=await new Promise((resolve,reject)=>{ws.on('unexpected-response',(_req,res)=>{resolve(res.statusCode);res.resume();ws.terminate();});ws.on('error',()=>{});ws.on('open',()=>{ws.terminate();reject(new Error('Unready node accepted device'));});});
  assert.equal(response,503);
});
test('helmet advertises explicitly configured device websocket origin',async t=>{
  const f=await fixture(t,'helmet',{deviceWebsocketOrigin:'ws://wearable.example.com:8080'}),d=f.config.devices[0];
  const response=await fetch(f.origin+`/${d.pathToken}/api/index.php?ctl=config&act=get_config&device_id=${d.deviceId}`);
  assert.equal(JSON.parse((await response.json()).data.config).ws_url,`ws://wearable.example.com:8080/${d.pathToken}/wsHat`);
});
test('media admission remains globally bounded across distinct device credentials',async t=>{
  const f=await fixture(t);let calls=0,release;
  const hold=new Promise(resolve=>{release=resolve;});
  const devices=[...f.config.devices,{deviceId:'900000000000003',pathToken:randomBytes(32).toString('base64url')}];
  const config={...f.config,devices,mediaControlOrigin:f.config.publicOrigin,mediaSigningKey:randomBytes(32).toString('base64url')};
  const gateway=createDeviceGateway(config,{testOnly:true,configure:validateClusterConfig,mediaFetch:async()=>{
    calls++;await hold;return new Response(JSON.stringify({code:200,data:{statusVerified:true,publishing:true}}));
  }});
  const address=await gateway.listen();t.after(async()=>{release();await gateway.close();});
  const send=d=>fetch(`http://127.0.0.1:${address.port}/${d.pathToken}/api/index.php?ctl=device&act=check_stream`,{method:'POST'});
  const first=send(devices[0]),second=send(devices[1]);await until(()=>calls===2);
  // A third credential must not multiply the process-wide upload limit.
  const third=send(devices[2]);
  const result=await Promise.race([third.then(r=>r.status),delay(150).then(()=>0)]);
  release();await Promise.all([first,second,third]);assert.equal(result,429);assert.equal(calls,2);
});
test('backup writes are sent only once on an upstream failure',async t=>{
  const f=await fixture(t);const d=f.config.devices[1];
  const reply=await fetch(f.origin+`/${d.pathToken}/api/index.php?ctl=lowcaps&act=ca_backup_data`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({device_id:d.deviceId,data:'1700000000,31.2,121.5'})});
  assert.equal(reply.status,502);assert.equal(f.state.posts,1);
});
test('cluster config rejects ambiguous credentials, external upstreams and unsafe limits',async t=>{
  const f=await fixture(t);
  for(const change of [{devices:[f.config.devices[0],f.config.devices[0]]},{upstreamOrigin:'https://untrusted.example.com'},
    {devices:[f.config.devices[0],{...f.config.devices[1],pathToken:f.config.devices[0].pathToken.slice(0,24)+f.config.devices[1].pathToken.slice(24)}]},
    {limits:{maxConnections:0}},{limits:{maxPayload:1000000}},{adminToken:'short'},{upstreamOrigin:'http://127.0.0.1:18084'}]) {
    assert.throws(()=>validateClusterConfig({...f.config,...change},{testOnly:true}));
  }
});
