import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createBusinessLab } from '../business-lab.mjs';

async function fixture(t) {
  let stored = null, rejectWrites = false, reports = 0;
  const device = {id:'42',sn:'TEST-42',siteId:'1',typeCode:'helmet',currentAssignment:{personId:'7',personName:'测试人员'}};
  const main = http.createServer(async (req,res) => {
    let data;
    const url = new URL(req.url,'http://test');
    if(url.pathname === '/api/v1/me') data={userId:req.headers.authorization==='Bearer duty'?'2':'1',admin:req.headers.authorization!=='Bearer duty',roles:['wear_duty'],authorizedSites:[{id:'1',status:'0'}]};
    else if(url.pathname === '/api/v1/devices/42') data={...device,...stored};
    else if(url.pathname === '/api/v1/devices') data={records:[device],total:1};
    else if(url.pathname.startsWith('/api/v1/people/')) data={id:url.pathname.split('/').pop(),status:'0',siteIds:['1'],name:'测试人员'};
    else if(url.pathname === '/api/v1/simulation/devices/42/state') {
      assert.ok(['Bearer test','Bearer duty'].includes(req.headers.authorization)); assert.equal(req.headers['x-site-id'],'1');
      let raw=''; for await(const c of req)raw+=c;
      if(rejectWrites) {res.writeHead(503,{'Content-Type':'application/json'}).end(JSON.stringify({code:503,msg:'状态写入失败'}));return;}
      const input=JSON.parse(raw); reports++; stored={online:input.online?'1':'0',simulationStatus:input.status,simulationStatusLabel:input.statusLabel}; data=stored;
    } else data={records:[],total:0};
    res.writeHead(200,{'Content-Type':'application/json'}).end(JSON.stringify({code:200,data}));
  });
  await new Promise(r=>main.listen(0,'127.0.0.1',r));
  const handler=createBusinessLab({backendUrl:`http://127.0.0.1:${main.address().port}`});
  const lab=http.createServer((req,res)=>handler(req,res,new URL(req.url,'http://lab')));
  await new Promise(r=>lab.listen(0,'127.0.0.1',r));
  t.after(async()=>{await new Promise(r=>lab.close(r));await new Promise(r=>main.close(r));});
  return {
    async write(body) {const r=await fetch(`http://127.0.0.1:${lab.address().port}/api/v1/lab/presence`,{method:'POST',headers:{Authorization:'Bearer test','X-Site-Id':'1','Content-Type':'application/json'},body:JSON.stringify({deviceId:'42',...body})});return {status:r.status,...await r.json()};},
    async read() {return (await (await fetch(`http://127.0.0.1:${main.address().port}/api/v1/devices/42`)).json()).data;},
    reject(){rejectWrites=true;},
    reports:()=>reports,
    async heartbeat(user='duty',site='1') {return fetch(`http://127.0.0.1:${lab.address().port}/api/v1/lab/state?client=console`,{headers:{Authorization:'Bearer '+user,'X-Site-Id':site}});},
  };
}
test('console online, abnormal and offline changes can be read from main device API',async t=>{
  const f=await fixture(t);
  assert.equal((await f.write({online:true})).status,200);
  assert.equal((await f.read()).online,'1');
  assert.equal((await f.write({online:true,abnormal:true})).status,200);
  assert.equal((await f.read()).simulationStatus,'abnormal');
  assert.equal((await f.write({online:false})).status,200);
  assert.equal((await f.read()).online,'0');
});
test('authorized station console renews devices enabled by another operator',async t=>{
  const f=await fixture(t);
  assert.equal((await f.write({online:true})).status,200);
  const now=Date.now();
  t.mock.method(Date,'now',()=>now+6000);
  assert.equal((await f.heartbeat()).status,200);
  assert.equal(f.reports(),2,'the duty console must renew the administrator-enabled device in main platform');
  assert.equal((await f.heartbeat('duty','2')).status,403);
  assert.equal((await f.write({online:false})).status,200);
  assert.equal((await f.heartbeat()).status,200);
  assert.equal(f.reports(),3,'offline devices must stay offline');
});
test('main write rejection is not reported as successful presence change',async t=>{
  const f=await fixture(t); f.reject();
  const result=await f.write({online:true});
  assert.notEqual(result.status,200); assert.match(result.msg,/状态写入失败/);
  assert.equal((await f.read()).online,undefined);
});
test('console cannot replace a main-platform equipment assignment',async t=>{
  const f=await fixture(t);
  assert.equal((await f.write({online:true,personId:'8'})).status,409);
  assert.equal((await f.read()).currentAssignment.personId,'7');
});
