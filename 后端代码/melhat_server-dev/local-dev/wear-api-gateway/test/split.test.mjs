import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {once} from 'node:events';
import {allowed,createWearGateway} from '../gateway.mjs';

const prefix='/api/guardian/v1/split';
test('split routes have exact methods and cannot expose vendor APIs or callbacks',()=>{
  for(const p of ['/sessions/SPLIT-1/heartbeat','/sessions/SPLIT-1/end','/sessions/SPLIT-1/devices/SN.1/play','/sessions/SPLIT-1/devices/SN.1/talk']) {
    assert.equal(allowed('POST',prefix+p),true);assert.equal(allowed('GET',prefix+p),false);
  }
  assert.equal(allowed('GET',`${prefix}/devices/SN.1/files/${'f'.repeat(64)}`),true);
  assert.equal(allowed('GET','/api/guardian/v1/devices/SN.1/live'),true);
  for(const p of ['/api/auth/token','/api/helmet/notify/sos','/index/api/webrtc',prefix+'/sessions',prefix+'/sessions/s/devices/a/hangup'])assert.equal(allowed('POST',p),false);
});
test('SDP and private ranged files relay only reviewed headers and keep authentication',async t=>{
  const seen=[];
  const backend=http.createServer((req,res)=>{
    const parts=[];req.on('data',b=>parts.push(b));req.on('end',()=>{
      seen.push({url:req.url,headers:req.headers,body:Buffer.concat(parts).toString()});
      if(req.url.endsWith('/play')){res.writeHead(200,{'Content-Type':'application/sdp'});res.end('v=0\r\nanswer');}
      else{res.writeHead(206,{'Content-Type':'video/mp4','Content-Range':'bytes 0-3/8','Accept-Ranges':'bytes','Content-Length':'4'});res.end('test');}
    });
  });
  backend.listen(0,'127.0.0.1');await once(backend,'listening');
  const gateway=createWearGateway({testOnly:true,upstreamOrigin:`http://127.0.0.1:${backend.address().port}`});
  gateway.listen(0,'127.0.0.1');await once(gateway,'listening');
  t.after(async()=>{await new Promise(r=>gateway.close(r));await new Promise(r=>backend.close(r));});
  const origin=`http://127.0.0.1:${gateway.address().port}`;
  const signal=origin+prefix+'/sessions/s1/devices/SN.1/play';
  const file=origin+prefix+`/devices/SN.1/files/${'a'.repeat(64)}`;
  assert.equal((await fetch(file)).status,401);
  const headers={'X-Wearable-Token':'b'.repeat(43),'Content-Type':'application/sdp',Authorization:'Bearer hidden',Cookie:'hidden'};
  const answer=await fetch(signal,{method:'POST',headers,body:'v=0\r\noffer'});
  assert.equal(answer.status,200);assert.equal(await answer.text(),'v=0\r\nanswer');
  assert.equal(seen[0].body,'v=0\r\noffer');assert.equal(seen[0].headers.accept,'application/sdp');
  assert.equal(seen[0].headers.authorization,undefined);assert.equal(seen[0].headers.cookie,undefined);
  const media=await fetch(file,{headers:{...headers,Range:'bytes=0-3'}});
  assert.equal(media.status,206);assert.equal(media.headers.get('content-range'),'bytes 0-3/8');assert.equal(await media.text(),'test');
  assert.equal(seen[1].headers.range,'bytes=0-3');assert.equal(seen[1].headers['x-wearable-token'],'b'.repeat(43));
  assert.equal((await fetch(file+'?url=https://other.example',{headers})).status,400);
  assert.equal((await fetch(file,{headers:{...headers,Range:'bytes=0-3,5-7'}})).status,400);
  assert.equal((await fetch(signal,{method:'POST',headers:{...headers,'Content-Type':'application/json'},body:'{}'})).status,415);
  assert.equal(seen.length,2);
});
