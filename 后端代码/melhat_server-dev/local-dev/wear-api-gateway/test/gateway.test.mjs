import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {once} from 'node:events';
import {allowed,createWearGateway} from '../gateway.mjs';
test('public API allows reviewed mobile routes only with exact methods',()=>{
  assert.equal(allowed('GET','/api/guardian/v1/mobile/home'),true);
  assert.equal(allowed('POST','/api/guardian/v1/mobile/calls/call-1/end'),true);
  assert.equal(allowed('GET','/api/guardian/v1/devices/d1/media'),true);
  assert.equal(allowed('GET','/api/guardian/v1/devices/d1/live'),true);
  assert.equal(allowed('POST','/api/guardian/v1/devices/d1/live'),false);
  for(const route of ['/api/guardian/v1/snapshot','/api/guardian/v1/admin/accounts','/actuator/env','/api/index.php','/api/guardian/v1/mobile/home/extra']) assert.equal(allowed('GET',route),false);
  assert.equal(allowed('DELETE','/api/guardian/v1/mobile/devices/d1'),false);
});
test('live lease context is forwarded only on the authenticated live route',async t=>{
  let seenUrl;
  const backend=http.createServer((req,res)=>{seenUrl=req.url;res.writeHead(409,{'content-type':'application/json'});res.end('{"error":"ASSIGNMENT_CHANGED"}');});
  backend.listen(0,'127.0.0.1');await once(backend,'listening');
  const gateway=createWearGateway({testOnly:true,upstreamOrigin:`http://127.0.0.1:${backend.address().port}`});
  gateway.listen(0,'127.0.0.1');await once(gateway,'listening');
  t.after(async()=>{await new Promise(r=>gateway.close(r));await new Promise(r=>backend.close(r));});
  const origin=`http://127.0.0.1:${gateway.address().port}`;
  const route='/api/guardian/v1/devices/d1/live?personId=p1&assignmentId=a1&assignmentVersion=2&viewerSessionId=viewer-1';
  assert.equal((await fetch(origin+route)).status,401);
  assert.equal(seenUrl,undefined);
  const headers={'X-Wearable-Token':'a'.repeat(43)};
  assert.equal((await fetch(origin+route,{headers})).status,409);
  assert.equal(seenUrl,route);
  assert.equal((await fetch(origin+route+'&assignmentVersion=3',{headers})).status,400);
  assert.equal((await fetch(origin+'/api/guardian/v1/mobile/home?assignmentId=a1',{headers})).status,400);
  for (const query of ['assignmentVersion=0','assignmentVersion=1.5','assignmentVersion=9007199254740992','viewerSessionId=short','assignmentId=bad%20id']) {
    assert.equal((await fetch(origin+'/api/guardian/v1/devices/d1/live?'+query,{headers})).status,400);
  }
});
test('absolute-form and authority-form request targets cannot change the fixed upstream',async t=>{
  let upstreamHits=0,externalHits=0;
  const backend=http.createServer((_req,res)=>{upstreamHits++;res.end();});
  const other=http.createServer((_req,res)=>{externalHits++;res.end();});
  backend.listen(0,'127.0.0.1');other.listen(0,'127.0.0.1');await Promise.all([once(backend,'listening'),once(other,'listening')]);
  const gateway=createWearGateway({testOnly:true,upstreamOrigin:`http://127.0.0.1:${backend.address().port}`});
  gateway.listen(0,'127.0.0.1');await once(gateway,'listening');
  t.after(async()=>{await Promise.all([gateway,backend,other].map(server=>new Promise(r=>server.close(r))));});
  for(const path of [`http://127.0.0.1:${other.address().port}/api/guardian/v1/mobile/home`,`//127.0.0.1:${other.address().port}/api/guardian/v1/mobile/home`]){
    const status=await new Promise((resolve,reject)=>{
      const request=http.request({host:'127.0.0.1',port:gateway.address().port,path,headers:{'X-Wearable-Token':'a'.repeat(43)}},response=>{response.resume();response.on('end',()=>resolve(response.statusCode));});
      request.on('error',reject);request.end();
    });
    assert.equal(status,400);
  }
  assert.equal(upstreamHits,0);assert.equal(externalHits,0);
});
test('token required, forwarded unchanged; upstream auth and scope remain authoritative',async t=>{
  let seen;
  const backend=http.createServer((req,res)=>{seen=req.headers;res.writeHead(403,{'content-type':'application/json'});res.end('{"error":"scope"}');});
  backend.listen(0,'127.0.0.1');await once(backend,'listening');
  const gateway=createWearGateway({testOnly:true,upstreamOrigin:`http://127.0.0.1:${backend.address().port}`});
  gateway.listen(0,'127.0.0.1');await once(gateway,'listening');
  t.after(async()=>{await new Promise(r=>gateway.close(r));await new Promise(r=>backend.close(r));});
  const origin=`http://127.0.0.1:${gateway.address().port}`;
  assert.equal((await fetch(origin+'/api/guardian/v1/mobile/home')).status,401);
  const result=await fetch(origin+'/api/guardian/v1/mobile/home?siteId=s1',{headers:{'X-Wearable-Token':'a'.repeat(43),Authorization:'Bearer secret',Cookie:'session=secret','X-Forwarded-Host':'evil'}});
  assert.equal(result.status,403);assert.equal(seen['x-wearable-token'],'a'.repeat(43));
  assert.equal(seen.authorization,undefined);assert.equal(seen.cookie,undefined);assert.equal(seen['x-forwarded-host'],undefined);
  assert.equal((await fetch(origin+'/api/guardian/v1/mobile/home?siteId=s1&siteId=s2',{headers:{'X-Wearable-Token':'a'.repeat(43)}})).status,400);
});
