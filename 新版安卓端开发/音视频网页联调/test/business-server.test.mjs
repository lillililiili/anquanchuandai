import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createLab } from '../server.mjs';

async function fixture(t, {ringMs=45000,eventDelay=0,eventFail=false,eventGate=null,assignedPerson='real-person'}={}) {
  const events = [];
  const backend = http.createServer(async (req,res) => {
    const token = req.headers.authorization?.replace('Bearer ',''), site = req.headers['x-site-id'];
    let result, code=200;
    if (!['admin','duty','duty2','other','reader'].includes(token)) code=401;
    else if (req.url === '/api/v1/me') result = {userId:token,admin:token==='admin',roles:['duty','duty2'].includes(token)?['wear_duty']:[],permissions:token==='reader'?[]:['wear:call:start','wear:command:tts'],authorizedSites:[{id:'1',status:'0'},{id:'2',status:'0'}]};
    else if (req.url.startsWith('/api/v1/devices/')) result = {id:req.url.split('/').pop(),siteId: req.url.endsWith('/foreign')?'2':site,sn:'TEST-'+req.url.split('/').pop(),typeCode:req.url.endsWith('/belt')?'belt':'helmet',online:'1',connectionQuality:'ok',capabilities:{actions:['intercom']},currentAssignment:assignedPerson?{personId:assignedPerson}:null};
    else if (req.url.startsWith('/api/v1/people/')) result = {id:req.url.split('/').pop(),status:'0',siteIds:req.url.endsWith('/foreign')?['2']:['1']};
    else if (req.url === '/api/v1/events/simulate') { let raw='';for await(const c of req)raw+=c;events.push(JSON.parse(raw));if(eventGate)await eventGate();if(eventDelay)await new Promise(r=>setTimeout(r,eventDelay));if(eventFail)code=500;else result={id:'e1',demo:true}; }
    else if (req.url.startsWith('/api/v1/work-tasks/')) result={id:'task1',members:[{personId:'p1'}]};
    else result={records:[],total:0};
    res.writeHead(code,{'Content-Type':'application/json'}).end(JSON.stringify({code,data:result,msg:code===401?'未认证':undefined}));
  });
  await new Promise(r=>backend.listen(0,'127.0.0.1',r));
  const lab=createLab({backendUrl:`http://127.0.0.1:${backend.address().port}`,ringMs});
  await new Promise(r=>lab.server.listen(0,'127.0.0.1',r));
  t.after(async()=>{await lab.close();await new Promise(r=>backend.close(r));});
  async function api(path,{user='duty',site='1',method='GET',body}={}) {
    const r=await fetch(`http://127.0.0.1:${lab.server.address().port}/api/v1/lab${path}`,{method,headers:{Authorization:'Bearer '+user,'X-Site-Id':site,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)});
    const j=await r.json();return {status:r.status,...j};
  }
  const online=async(id='h1',extras={})=>api('/presence',{user:'admin',method:'POST',body:{deviceId:id,online:true,...extras}});
  const dial=async(ids=['h1'],extras={})=>api('/calls',{method:'POST',body:{deviceIds:ids,...extras}});
  return {api,online,dial,events};
}
test('outbound voice: both endpoints share ring, acceptance and hangup; no media claim',async t=>{
  const {api,online,dial}=await fixture(t);await online();
  const call=(await dial()).data; assert.equal(call.state,'ringing');assert.equal(call.simulation,true);assert.equal(call.connectedAt,null);
  const connected=(await api(`/calls/${call.id}/accept`,{user:'admin',method:'POST',body:{deviceId:'h1'}})).data;
  assert.equal(connected.state,'connected');assert.ok(connected.connectedAt);
  assert.equal((await api('/state')).data.calls[0].id,call.id);
  assert.equal((await api(`/calls/${call.id}/end`,{method:'POST',body:{}})).data.state,'ended');
});

test('invite appends ringing participants without restarting connected call or video',async t=>{
  const {api,online,dial}=await fixture(t);await online('h1');await online('h2');
  const c=(await dial()).data;
  const connected=(await api(`/calls/${c.id}/accept`,{user:'admin',method:'POST',body:{deviceId:'h1'}})).data;
  await api(`/calls/${c.id}/video`,{method:'POST',body:{enabled:true}});
  const invite=()=>api(`/calls/${c.id}/invite`,{method:'POST',body:{deviceIds:['h2','h2']}});
  const added=await invite();assert.equal(added.status,200);assert.equal(added.data.id,c.id);
  assert.equal(added.data.state,'connected');assert.equal(added.data.connectedAt,connected.connectedAt);assert.equal(added.data.videoEnabled,true);
  assert.deepEqual(added.data.participants.map(p=>p.state),['connected','ringing']);
  assert.equal((await invite()).data.participants.length,2,'Retry must not duplicate participants');
  const accepted=(await api(`/calls/${c.id}/accept`,{user:'admin',method:'POST',body:{deviceId:'h2'}})).data;
  assert.deepEqual(accepted.participants.map(p=>p.state),['connected','connected']);assert.equal(accepted.connectedAt,connected.connectedAt);
  assert.equal((await api('/state')).data.calls.length,1);
});

test('invites require the owning duty user and leave original call intact on rejection',async t=>{
  const {api,online,dial}=await fixture(t);await online('h1');await online('h2');await online('belt');
  const c=(await dial()).data;
  const invite=(ids,extras={})=>api(`/calls/${c.id}/invite`,{method:'POST',body:{deviceIds:ids},...extras});
  assert.equal((await invite(['h2'])).status,409);
  await api(`/calls/${c.id}/accept`,{user:'admin',method:'POST',body:{deviceId:'h1'}});
  assert.equal((await invite(['h2'],{user:'other'})).status,403);
  assert.equal((await invite(['h2'],{site:'2'})).status,404);
  assert.equal((await invite(['h2','off'])).status,409);
  assert.equal((await invite(['h2','belt'])).status,400);
  assert.equal((await invite(['foreign'])).status,403);
  const unchanged=(await api('/state')).data.calls[0];assert.equal(unchanged.participants.length,1);assert.equal(unchanged.state,'connected');
  await api(`/calls/${c.id}/end`,{method:'POST',body:{}});
  assert.equal((await invite(['h2'])).status,409);
});

test('busy devices cannot be invited and concurrent requests cannot duplicate membership',async t=>{
  const {api,online,dial}=await fixture(t);await online('h1');await online('h2');await online('h3');
  const c=(await dial()).data;await api(`/calls/${c.id}/accept`,{user:'admin',method:'POST',body:{deviceId:'h1'}});
  await api('/calls',{user:'other',method:'POST',body:{deviceIds:['h2']}});
  const invite=ids=>api(`/calls/${c.id}/invite`,{method:'POST',body:{deviceIds:ids}});
  assert.equal((await invite(['h2'])).status,409);
  const attempts=await Promise.all([invite(['h3']),invite(['h3'])]);assert.ok(attempts.some(r=>r.status===200));
  const current=(await api('/state')).data.calls[0];assert.deepEqual(current.participants.map(p=>p.deviceId),['h1','h3']);
});

test('late invite gets its own ring timeout and cannot disconnect the existing participant',async t=>{
  const {api,online,dial}=await fixture(t,{ringMs:1000});await online('h1');await online('h2');
  const c=(await dial()).data;await api(`/calls/${c.id}/accept`,{user:'admin',method:'POST',body:{deviceId:'h1'}});
  const actualNow=Date.now;const start=actualNow();
  try {
    Date.now=()=>start+20000;
    assert.equal((await api(`/calls/${c.id}/invite`,{method:'POST',body:{deviceIds:['h2']}})).status,200);
    let current=(await api('/state')).data.calls[0];assert.equal(current.participants[1].state,'ringing');
    Date.now=()=>start+21500;
    current=(await api('/state')).data.calls[0];assert.equal(current.participants[1].state,'timed_out');assert.equal(current.participants[0].state,'connected');assert.equal(current.state,'connected');
  } finally {Date.now=actualNow;}
});
test('legacy video dial becomes unified call and preserves individual participant states',async t=>{
  const {api,online,dial}=await fixture(t);await online('h1');await online('h2');await online('h3');
  const c=(await dial(['h1','h2','h3','h1'],{video:true})).data;assert.equal(c.participants.length,3);assert.equal(c.video,false);assert.equal(c.videoEnabled,false);
  await api(`/calls/${c.id}/reject`,{user:'admin',method:'POST',body:{deviceId:'h3'}});
  await api(`/calls/${c.id}/accept`,{user:'admin',method:'POST',body:{deviceId:'h1'}});
  await api(`/calls/${c.id}/accept`,{user:'admin',method:'POST',body:{deviceId:'h2'}});
  const partial=(await api(`/calls/${c.id}/end`,{user:'admin',method:'POST',body:{deviceId:'h1'}})).data;
  assert.equal(partial.state,'connected');assert.equal(partial.participants[1].state,'connected');
  assert.equal((await api(`/calls/${c.id}/end`,{user:'admin',method:'POST',body:{deviceId:'h2'}})).data.state,'ended');
});

test('duty can view helmet video in the same connected call without a second acceptance',async t=>{
  const {api,online,dial}=await fixture(t);await online('h1');await online('h2');
  const c=(await dial(['h1','h2'])).data;
  const video=enabled=>api(`/calls/${c.id}/video`,{method:'POST',body:{enabled}});
  assert.equal((await video(true)).status,409,'Cannot show ringing equipment as live');
  const accepted=(await api(`/calls/${c.id}/accept`,{user:'admin',method:'POST',body:{deviceId:'h1'}})).data;
  const viewing=await video(true);
  assert.equal(viewing.status,200);assert.equal(viewing.data.id,c.id);assert.equal(viewing.data.videoEnabled,true);
  assert.equal(viewing.data.connectedAt,accepted.connectedAt);assert.equal(viewing.data.state,'connected');
  assert.deepEqual(viewing.data.participants.map(p=>p.state),['connected','ringing']);
  assert.equal((await api('/state')).data.calls.length,1);
  assert.equal((await api(`/calls/${c.id}/video`,{user:'other',method:'POST',body:{enabled:true}})).status,403);
  assert.equal((await api(`/calls/${c.id}/video`,{site:'2',method:'POST',body:{enabled:true}})).status,404);
  assert.equal((await api(`/calls/${c.id}/video`,{method:'POST',body:{enabled:'true'}})).status,400);
  assert.equal((await video(false)).data.videoEnabled,false);
  await video(true);
  const ended=(await api(`/calls/${c.id}/end`,{method:'POST',body:{}})).data;
  assert.equal(ended.videoEnabled,false);
  assert.equal((await video(true)).status,409);
});

test('call permission alone does not grant non-duty account helmet camera viewing',async t=>{
  const {api,online}=await fixture(t);await online();
  const c=(await api('/calls',{user:'other',method:'POST',body:{deviceIds:['h1']}})).data;
  await api(`/calls/${c.id}/accept`,{user:'admin',method:'POST',body:{deviceId:'h1'}});
  assert.equal((await api(`/calls/${c.id}/video`,{user:'other',method:'POST',body:{enabled:true}})).status,403);
});

test('helmet cannot choose another contact and ambiguous duty routing is rejected',async t=>{
  const {api,online}=await fixture(t);await online();await api('/state');
  const c=(await api('/calls',{user:'admin',method:'POST',body:{deviceIds:['h1'],direction:'incoming',targetUserId:'other'}})).data;
  assert.equal(c.userId,'duty');
  await api(`/calls/${c.id}/end`,{user:'admin',method:'POST',body:{deviceId:'h1'}});
  await api('/state',{user:'duty2'});
  const ambiguous=await api('/calls',{user:'admin',method:'POST',body:{deviceIds:['h1'],direction:'incoming',targetUserId:'duty'}});
  assert.equal(ambiguous.status,409);assert.match(ambiguous.msg,/多个在线值班/);
});
test('SOS incoming targets registered duty user, not unrelated account; creates marked event',async t=>{
  const {api,online,events}=await fixture(t);await online();await api('/state');
  const c=(await api('/calls',{user:'admin',method:'POST',body:{deviceIds:['h1'],direction:'incoming',sos:true}})).data;
  assert.equal(c.userId,'duty');assert.equal(c.eventId,'e1');assert.equal(events[0].type,'sos');assert.match(events[0].sourceEventId,/^call-lab:/);
  assert.equal((await api('/state',{user:'other'})).data.calls.length,0);
  assert.equal((await api(`/calls/${c.id}/accept`,{user:'other',method:'POST',body:{}})).status,403);
  assert.equal((await api(`/calls/${c.id}/accept`,{method:'POST',body:{}})).data.state,'connected');
});
test('offline, unsupported device, busy user and absent duty reject honestly',async t=>{
  const {api,online,dial}=await fixture(t);
  assert.equal((await dial()).status,409);await online('belt');assert.equal((await dial(['belt'])).status,400);
  await online();assert.equal((await api('/calls',{user:'admin',method:'POST',body:{deviceIds:['h1'],direction:'incoming'}})).status,409);
  await dial();assert.equal((await dial()).status,409);
});
test('auth, cross-site presence and read-only mutation are rejected',async t=>{
  const {api,online}=await fixture(t);
  assert.equal((await api('/state',{user:'bad'})).status,401);
  assert.equal((await api('/state',{site:'3'})).status,403);
  assert.equal((await online('foreign')).status,403);
  assert.equal((await online('h1',{personId:'foreign'})).status,403);
  assert.equal((await api('/presence',{user:'reader',method:'POST',body:{deviceId:'h1',online:true}})).status,403);
});
test('broadcast reports per-device receipt and explicit simulated acknowledgment',async t=>{
  const {api,online}=await fixture(t);await online();
  const m=(await api('/tts',{method:'POST',body:{deviceIds:['h1','off','h1'],text:'请撤离测试区域'}})).data;
  assert.deepEqual(m.receipts.map(r=>r.state),['sent','offline']);assert.equal(m.simulation,true);
  const ack=(await api('/tts/ack',{user:'admin',method:'POST',body:{id:m.id,deviceId:'h1'}})).data;
  assert.equal(ack.receipts[0].state,'acknowledged');
  assert.equal((await api('/tts',{user:'reader',method:'POST',body:{deviceIds:['h1'],text:'禁止'}})).status,403);
});
test('unanswered calls time out and cannot be accepted afterward',async t=>{
  const {api,online,dial}=await fixture(t,{ringMs:20});await online();const c=(await dial()).data;
  await new Promise(r=>setTimeout(r,35));
  assert.equal((await api('/state')).data.calls[0].state,'timed_out');
  assert.equal((await api(`/calls/${c.id}/accept`,{user:'admin',method:'POST',body:{deviceId:'h1'}})).status,409);
});
test('taking device offline propagates terminal state to Android',async t=>{
  const {api,online,dial}=await fixture(t);await online();const c=(await dial()).data;
  await api('/presence',{user:'admin',method:'POST',body:{deviceId:'h1',online:false}});
  const ended=(await api('/state')).data.calls.find(x=>x.id===c.id);assert.equal(ended.state,'ended');assert.equal(ended.reason,'设备离线');
});

test('empty or omitted test wearer retains the main-platform device assignment',async t=>{
  const {api,online}=await fixture(t);
  assert.equal((await online('h1')).data.personId,'real-person');
  assert.equal((await online('h1',{personId:''})).data.personId,'real-person');
  assert.equal((await api('/state?client=console',{user:'admin'})).data.devices[0].personId,'real-person');
});

test('concurrent SOS reserves dispatcher before event write and admits only one call',async t=>{
  const {api,online,events}=await fixture(t,{eventDelay:60});await online('h1');await online('h2');await api('/state');
  const results=await Promise.all(['h1','h2'].map(id=>api('/calls',{user:'admin',method:'POST',body:{deviceIds:[id],direction:'incoming',sos:true,targetUserId:'duty'}})));
  assert.deepEqual(results.map(r=>r.status).sort(),[200,409]);assert.equal(events.length,1);
  assert.equal((await api('/state')).data.calls.filter(c=>c.state==='ringing').length,1);
});

test('SOS without online duty writes no event; event failure releases call reservation',async t=>{
  const {api,online,dial,events}=await fixture(t,{eventFail:true});await online();
  const body={deviceIds:['h1'],direction:'incoming',sos:true};
  assert.equal((await api('/calls',{user:'admin',method:'POST',body})).status,409);assert.equal(events.length,0);
  await api('/state');assert.notEqual((await api('/calls',{user:'admin',method:'POST',body})).status,200);
  assert.equal((await api('/state')).data.calls.length,0);
  assert.equal((await dial()).status,200,'Failed SOS must not keep dispatcher/device busy');
});

test('dispatcher heartbeat expiry ends active participants as well as call',async t=>{
  const {api,online,dial}=await fixture(t);await online('h1');await online('h2');await api('/state');
  const call=(await dial(['h1','h2'])).data;
  await api(`/calls/${call.id}/accept`,{user:'admin',method:'POST',body:{deviceId:'h1'}});
  const actualNow=Date.now;
  try {
    Date.now=()=>actualNow()+26000;
    const ended=(await api('/state?client=console',{user:'admin'})).data.calls.find(c=>c.id===call.id);
    assert.equal(ended.state,'ended');assert.equal(ended.reason,'值班端离线');
    assert.deepEqual(ended.participants.map(p=>p.state),['ended','ended']);
  } finally {Date.now=actualNow;}
});

test('offline device cannot acknowledge previously sent broadcast',async t=>{
  const {api,online}=await fixture(t);await online();
  const message=(await api('/tts',{method:'POST',body:{deviceIds:['h1'],text:'测试播报'}})).data;
  await api('/presence',{user:'admin',method:'POST',body:{deviceId:'h1',online:false}});
  assert.equal((await api('/tts/ack',{user:'admin',method:'POST',body:{id:message.id,deviceId:'h1'}})).status,409);
  assert.equal((await api('/state')).data.messages[0].receipts[0].state,'sent');
});

test('incoming supports one source device; multi-device calls originate from Android',async t=>{
  const {api,online,events}=await fixture(t);await online('h1');await online('h2');await api('/state');
  assert.equal((await api('/calls',{user:'admin',method:'POST',body:{deviceIds:['h1','h2'],direction:'incoming',sos:true}})).status,400);
  assert.equal(events.length,0);assert.equal((await api('/state')).data.calls.length,0);
});

test('device going offline during SOS persistence returns registered event but creates no ringing call',async t=>{
  let startEvent,releaseEvent;
  const eventStarted=new Promise(resolve=>{startEvent=resolve;});
  const eventRelease=new Promise(resolve=>{releaseEvent=resolve;});
  const {api,online,dial,events}=await fixture(t,{eventGate:async()=>{startEvent();await eventRelease;}});
  await online();await api('/state');
  const pending=api('/calls',{user:'admin',method:'POST',body:{deviceIds:['h1'],direction:'incoming',sos:true}});
  await eventStarted;
  try {assert.equal((await api('/presence',{user:'admin',method:'POST',body:{deviceId:'h1',online:false}})).status,200);}
  finally {releaseEvent();}
  const failed=await pending;
  assert.equal(failed.status,409);assert.match(failed.msg,/SOS事件 e1 已登记/);assert.match(failed.msg,/呼叫未发起/);
  assert.equal(events.length,1);assert.equal((await api('/state')).data.calls.length,0);
  await online();assert.equal((await dial()).status,200,'Aborted SOS must release its reservation');
});

test('SOS rejects simulated wearer mismatch without event write or changing business assignment',async t=>{
  const {api,online,events}=await fixture(t);
  const wrong=await online('h1',{personId:'test-person'});
  assert.equal(wrong.status,409);assert.match(wrong.msg,/不能覆盖领用关系/);
  await api('/state');
  const body={deviceIds:['h1'],direction:'incoming',sos:true};
  const mismatch=await api('/calls',{user:'admin',method:'POST',body});
  assert.equal(mismatch.status,409);
  assert.equal(events.length,0);assert.equal((await api('/state')).data.calls.length,0);
  const ordinary=await api('/calls',{user:'admin',method:'POST',body:{...body,sos:false}});
  assert.equal(ordinary.status,409);
  const original=await online('h1');assert.equal(original.data.personId,'real-person','Business assignment must remain unchanged');
  assert.equal((await api('/calls',{user:'admin',method:'POST',body})).status,200);assert.equal(events.length,1);
});

test('unassigned device permits SOS only when test wearer is also empty',async t=>{
  const {api,online,events}=await fixture(t,{assignedPerson:''});await online('h1',{personId:'test-person'});await api('/state');
  const body={deviceIds:['h1'],direction:'incoming',sos:true};
  assert.equal((await api('/calls',{user:'admin',method:'POST',body})).status,409);assert.equal(events.length,0);
  await online('h1',{personId:''});const incoming=await api('/calls',{user:'admin',method:'POST',body});
  assert.equal(incoming.status,200);assert.equal(incoming.data.participants[0].personId,'');assert.equal(events.length,1);
});
