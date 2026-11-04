import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {once} from 'node:events';
import {randomBytes} from 'node:crypto';
import {WebSocketServer} from 'ws';
import {benchmark,validateBenchmark} from '../benchmark.mjs';

test('driver counts actual successful and refused reports and excludes secrets from evidence',async t=>{
  const secret=randomBytes(32).toString('base64url');
  const server=http.createServer((req,res)=>{if(req.url==='/.well-known/wearable-lab'){res.end(JSON.stringify({isolated:true,labId:'wearable-lab-contract',proof:secret}));return;}res.writeHead(401);res.end('{}');});
  const wss=new WebSocketServer({server});let received=0;
  wss.on('connection',ws=>ws.on('message',raw=>{const msg=JSON.parse(raw);if(msg.act==='ca_report_location')received++;
    ws.send(JSON.stringify({cmd:msg.act,status:msg.act==='ca_login'||received%2===1}));}));
  server.listen(0,'127.0.0.1');await once(server,'listening');
  t.after(async()=>{for(const ws of wss.clients)ws.terminate();await new Promise(r=>wss.close(r));server.closeAllConnections();await new Promise(r=>server.close(r));});
  const config={origin:`http://127.0.0.1:${server.address().port}`,runId:'wearable-lab-contract',labId:'wearable-lab-contract',isolationProof:secret,scenario:'single',durationSeconds:1,
    reportIntervalMillis:20,timeoutMillis:100,httpConcurrency:1,httpPath:'/api/admin/v1/snapshot',httpSuccess:{field:'revision',type:'number'},sessionToken:secret,
    devices:[{kind:'helmet',deviceId:'900000000000001',pathToken:secret}]};
  const result=await benchmark(config,{testOnly:true});
  assert.equal(result.reports.attempts,received);assert.ok(result.reports.success>0);assert.ok(result.reports.errors>0);
  assert.ok(result.http.attempts>0);assert.equal(result.http.success,0);assert.equal(result.peakConnections,1);
  assert.ok(!JSON.stringify(result).includes(secret));
  assert.throws(()=>validateBenchmark({...config,origin:'http://127.0.0.1:18084'},{testOnly:true}));
  assert.throws(()=>validateBenchmark({...config,devices:[{...config.devices[0],deviceId:'866652021714127'}]},{testOnly:true}));
  const previous=received;
  await assert.rejects(()=>benchmark({...config,isolationProof:randomBytes(32).toString('base64url')},{testOnly:true}));
  assert.equal(received,previous,'wrong laboratory identity must not create any device workload');
});
