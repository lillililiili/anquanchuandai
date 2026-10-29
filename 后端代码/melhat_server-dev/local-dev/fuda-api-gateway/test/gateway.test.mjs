import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {createGateway} from '../gateway.mjs';
const headers = {'Content-Type':'application/json; charset=utf-8','X-App-Id':'test','X-Timestamp':'1793100000','X-Nonce':'test-nonce','X-Signature':'a'.repeat(64)};
const listen = server => new Promise(resolve => server.listen(0,'127.0.0.1',() => resolve(`http://127.0.0.1:${server.address().port}`)));
const close = server => new Promise(resolve => {server.closeAllConnections(); server.close(resolve);});
async function setup(t) {
  let seen=[];
  const backend=http.createServer((req,res)=>{const chunks=[];req.on('data',c=>chunks.push(c));req.on('end',()=>{seen.push({url:req.url,headers:req.headers,body:Buffer.concat(chunks)});res.writeHead(200,{'Content-Type':'application/json'});res.end('{"code":0}');});});
  const upstream=await listen(backend), gateway=createGateway({upstreamOrigin:upstream,testOnly:true}), origin=await listen(gateway);
  t.after(async()=>{await close(gateway);await close(backend);});return {seen,origin};
}
test('preserves signed UTF8 body and only forwards query credentials',async t=>{
  const {seen,origin}=await setup(t), body=' { "设备": "帽", "devices": [] }\n';
  const res=await fetch(origin+'/openapi/wearables/v2/positions/query',{method:'POST',headers:{...headers,'X-Wearable-Token':'must-not-forward','Cookie':'private'},body});
  assert.equal(res.status,200);assert.equal(seen[0].body.toString(),body);assert.equal(seen[0].headers['x-signature'],headers['X-Signature']);assert.equal(seen[0].headers.cookie,undefined);assert.equal(seen[0].headers['x-wearable-token'],undefined);
});
test('only three exact read-only routes are exposed',async t=>{
  const {seen,origin}=await setup(t);
  for(const route of ['/api/admin/v1/query','/api/guardian/v1/snapshot','/internal/fuda/gb/leases','/openapi/wearables/v2/alarms/query?limit=1','/openapi/wearables/v2/alarms/query/']) {
    assert.equal((await fetch(origin+route,{method:'POST',headers,body:'{}'})).status,404);
  }
  assert.equal((await fetch(origin+'/openapi/wearables/v2/alarms/query')).status,404);assert.equal(seen.length,0);
});
test('rejects missing authentication, compressed and oversized bodies before proxying',async t=>{
  const {seen,origin}=await setup(t), url=origin+'/openapi/wearables/v2/statuses/query';
  assert.equal((await fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})).status,401);
  assert.equal((await fetch(url,{method:'POST',headers:{...headers,'Content-Encoding':'gzip'},body:'{}'})).status,415);
  assert.equal((await fetch(url,{method:'POST',headers,body:'x'.repeat(65537)})).status,413);assert.equal(seen.length,0);
});
test('refuses arbitrary origins and the daily upstream in tests',()=>{
  assert.throws(()=>createGateway({upstreamOrigin:'https://example.com'}));
  assert.throws(()=>createGateway({upstreamOrigin:'http://127.0.0.1:18084',testOnly:true}));
  assert.doesNotThrow(()=>createGateway({upstreamOrigin:'http://10.255.1.1:28090'}).close());
  assert.throws(()=>createGateway({upstreamOrigin:'http://10.255.1.2:28090'}));
});
