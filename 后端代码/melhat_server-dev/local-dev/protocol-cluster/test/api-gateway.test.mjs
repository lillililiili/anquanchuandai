import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {once} from 'node:events';
import {setTimeout as delay} from 'node:timers/promises';
import {createApiGateway} from '../api-gateway.mjs';

async function fixture(t,kind) {
  const state={ready:true,calls:[]};
  const backend=http.createServer(async(req,res)=>{
    if(req.url==='/internal/cluster/ready') {res.writeHead(state.ready?200:503,{'content-type':'application/json'});res.end(JSON.stringify({ready:state.ready}));return;}
    const chunks=[];for await(const c of req)chunks.push(c);
    state.calls.push({url:req.url,headers:req.headers,body:Buffer.concat(chunks).toString()});
    res.writeHead(202,{'content-type':'application/json','retry-after':'2'});res.end('{"code":0,"message":"fixture"}');
  });
  backend.listen(0,'127.0.0.1');await once(backend,'listening');
  const gateway=createApiGateway(kind,{upstreamOrigin:`http://127.0.0.1:${backend.address().port}`,listenHost:'127.0.0.1',listenPort:0,healthPollMillis:20,healthTimeoutMillis:100},{testOnly:true});
  const address=await gateway.listen(),origin=`http://127.0.0.1:${address.port}`;
  t.after(async()=>{await gateway.close();backend.closeAllConnections();await new Promise(r=>backend.close(r));});
  return {state,origin};
}
for(const kind of ['wear','fuda'])test(`${kind}: readiness gates business requests without changing protected forwarding`,async t=>{
  const f=await fixture(t,kind);
  const path=kind==='wear'?'/api/guardian/v1/mobile/login':'/openapi/wearables/v2/positions/query';
  const body='{ "note":"中文 😀", "id":9007199254740993 }';
  const headers={'Content-Type':'application/json','Authorization':'strip','Cookie':'strip','X-App-Id':'fixture','X-Timestamp':'1','X-Nonce':'nonce','X-Signature':'signature'};
  const result=await fetch(f.origin+path,{method:'POST',headers,body});
  assert.equal(result.status,202);assert.equal(f.state.calls.length,1);assert.equal(f.state.calls[0].body,body);
  assert.equal(f.state.calls[0].headers.authorization,undefined);assert.equal(f.state.calls[0].headers.cookie,undefined);
  assert.equal((await fetch(f.origin+'/internal/gateway/ready')).status,200);
  f.state.ready=false;
  for(let i=0;i<40&&(await fetch(f.origin+'/internal/gateway/ready')).status===200;i++)await delay(20);
  assert.equal((await fetch(f.origin+'/internal/gateway/ready')).status,503);
  assert.equal((await fetch(f.origin+'/internal/gateway/live')).status,200);
  assert.equal((await fetch(f.origin+path,{method:'POST',headers,body})).status,503);assert.equal(f.state.calls.length,1);
  assert.equal((await fetch(f.origin+'/internal/gateway/drain',{method:'POST'})).status,404);
});
test('production API gateway accepts only the fixed private router, tests exclude daily backend',()=>{
  for(const url of ['http://127.0.0.1:18084','https://backend:18084','http://example.com','http://backend:18084/','http://user:pass@backend:18084'])
    assert.throws(()=>createApiGateway('wear',{upstreamOrigin:url}));
  assert.throws(()=>createApiGateway('wear',{upstreamOrigin:'http://127.0.0.1:18084'},{testOnly:true}));
});
