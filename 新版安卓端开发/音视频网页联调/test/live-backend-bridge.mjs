// Explicitly invoked local integration test. All HTTP goes through Java :18084.
// Uses existing helmets 12/13; only lab state is changed, never assignment/SOS.
// Do not run concurrently with emulator call QA using these accounts/devices.
import assert from 'node:assert/strict';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const base=new URL(process.env.BUSINESS_BACKEND_URL||'http://127.0.0.1:18084');
if(!['127.0.0.1','localhost'].includes(base.hostname)||base.protocol!=='http:'||base.port!=='18084'||base.pathname!=='/'||base.username||base.password||base.search||base.hash)throw Error('This script only permits the local Java backend on HTTP port 18084');
const site='1',deviceIds=['12','13'];
const fixture=await readFile(new URL('alarms-browser.mjs',import.meta.url),'utf8');
const password=process.env.LAB_TEST_PASSWORD||fixture.match(/password = process.env.LAB_TEST_PASSWORD \|\| '([^']+)'/)?.[1];
if(!password)throw Error('Provide LAB_TEST_PASSWORD using the local test environment');
const accounts={admin:process.env.LAB_ADMIN||'admin',duty:process.env.LAB_DUTY||'siteA_duty',reader:process.env.LAB_READER||'siteA_readonly',other:process.env.LAB_OTHER||'siteA_reviewer'};
const tokens=new Map(),changedDevices=new Set(),artifact={startedAt:new Date().toISOString(),backendOrigin:base.origin,site,devices:deviceIds,scope:'Local Java relay integration, simulated state only; no SOS or assignment writes',requests:[],checks:[],cleanup:[]};
const output=new URL('../artifacts/live-backend-bridge.json',import.meta.url);
let callId='',closed=false,failed;

function summary(path,json) {
  const data=json?.data;
  if(path==='/login')return {authenticated:typeof json?.token==='string'&&!!json.token};
  if(path.endsWith('/bridge-info')) {
    // Only non-secret identity/configuration fields; never persist raw payloads.
    const safe={};
    for(const key of ['enabled','simulation','realMedia','mode','bridge','transport','provider','backend','relay','route','upstream','upstreamType','service','via']) {
      const value=data?.[key];if(typeof value==='boolean'||typeof value==='number'||(typeof value==='string'&&value.length<200&&!/token|password|secret|certificate|bearer/i.test(value)))safe[key]=value;
    }
    return {responseKeys:data&&typeof data==='object'?Object.keys(data):[],configuration:safe};
  }
  if(path.startsWith('/api/v1/lab/calls')&&data?.id)return {callId:String(data.id),state:data.state,video:data.video===true,videoEnabled:data.videoEnabled===true,createdAt:data.createdAt,connectedAt:data.connectedAt,participants:(data.participants||[]).map(p=>({deviceId:String(p.deviceId),state:p.state}))};
  if(path.startsWith('/api/v1/lab/state'))return {devices:(data?.devices||[]).filter(d=>deviceIds.includes(String(d.deviceId))).map(d=>({deviceId:String(d.deviceId),online:d.online===true})),currentCall:callId?(data?.calls||[]).filter(c=>c.id===callId).map(c=>({callId:c.id,state:c.state,videoEnabled:c.videoEnabled===true,connectedAt:c.connectedAt,participants:c.participants.map(p=>({deviceId:String(p.deviceId),state:p.state}))})):[],activeCallCount:(data?.calls||[]).filter(c=>['ringing','connected'].includes(c.state)).length};
  if(path==='/api/v1/lab/presence')return {deviceId:String(data?.deviceId||''),online:data?.online===true,simulation:data?.simulation===true};
  if(path.startsWith('/api/v1/devices/'))return {deviceId:String(data?.id||''),siteId:String(data?.siteId||''),typeCode:data?.typeCode};
  return {hasData:data!=null};
}
async function request(path,{account='duty',method='GET',body,expected=200,requestSite=site}={}) {
  const headers={'Content-Type':'application/json','X-Site-Id':requestSite};
  if(tokens.has(account))headers.Authorization='Bearer '+tokens.get(account);
  const url=new URL(path,base),entry={at:new Date().toISOString(),origin:url.origin,path:url.pathname+url.search,method,account,site:requestSite};artifact.requests.push(entry);
  try {
    const response=await fetch(url,{method,headers,body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(30000),redirect:'error'});
    entry.httpStatus=response.status;const json=await response.json();entry.code=json.code;entry.result=summary(url.pathname,json);
    const code=Number(json.code??response.status);
    const allowed=Array.isArray(expected)?expected:[expected];
    assert.ok(allowed.includes(code),`${method} ${url.pathname} returned ${code}, expected ${allowed.join('/')} for ${account}`);
    if(allowed.length===1&&allowed[0]===200)assert.equal(response.ok,true,`${method} ${url.pathname} HTTP failure`);
    return json;
  } catch(error) {entry.failed=true;throw error;}
}
function check(name,fn) {fn();artifact.checks.push({name,passed:true});}
async function login(account) {
  const json=await request('/login',{account,method:'POST',body:{username:accounts[account],password}});
  assert.equal(typeof json.token,'string','Business login must return a token');assert.ok(json.token,'Business login token must be nonempty');tokens.set(account,json.token);
}
async function data(path,options){return (await request('/api/v1'+path,options)).data;}

try {
  for(const account of ['admin','duty','reader','other'])await login(account);
  const bridge=await data('/lab/bridge-info',{account:'admin'});
  check('Java backend identifies its virtual helmet bridge exactly',()=>assert.deepEqual(bridge,{bridge:'java-business-backend',enabled:true,upstreamType:'virtual-helmet',simulation:true,realMedia:false}));
  const me=await data('/me');check('Duty account has site 1 access',()=>assert.ok(me.authorizedSites?.some(s=>String(s.id)===site)));
  const before=await data('/lab/state?client=console',{account:'admin'});
  check('No pre-existing call will be interrupted',()=>assert.equal((before.calls||[]).some(c=>['ringing','connected'].includes(c.state)&&(String(c.userId)===String(me.userId)||c.participants.some(p=>deviceIds.includes(String(p.deviceId))&&['ringing','connected'].includes(p.state)))),false));
  for(const deviceId of deviceIds) {
    const device=await data('/devices/'+deviceId,{account:'admin'});
    check('Existing helmet '+deviceId+' belongs to site 1',()=>{assert.equal(String(device.siteId),site);assert.equal(device.typeCode,'helmet');});
    changedDevices.add(deviceId);
    await data('/lab/presence',{account:'admin',method:'POST',body:{deviceId,online:true}});
  }
  await data('/lab/state');
  const created=await data('/lab/calls',{method:'POST',body:{deviceIds}});callId=created.id;
  check('Unified two-helmet call starts ringing without video',()=>{assert.ok(callId);assert.equal(created.state,'ringing');assert.equal(created.video,false);assert.equal(created.videoEnabled,false);assert.equal(created.participants.length,2);});
  await data(`/lab/calls/${callId}/video`,{method:'POST',body:{enabled:true},expected:409});
  const connected=await data(`/lab/calls/${callId}/accept`,{account:'admin',method:'POST',body:{deviceId:'12'}});
  const connectedAt=connected.connectedAt;
  check('One helmet accepts while the other remains ringing',()=>{assert.ok(connectedAt);assert.equal(connected.state,'connected');assert.deepEqual(connected.participants.map(p=>p.state),['connected','ringing']);});
  await data(`/lab/calls/${callId}/video`,{account:'reader',method:'POST',body:{enabled:true},expected:403});
  await data(`/lab/calls/${callId}/video`,{account:'other',method:'POST',body:{enabled:true},expected:403});
  await data(`/lab/calls/${callId}/video`,{account:'admin',requestSite:'2',method:'POST',body:{enabled:true},expected:[403,404]});
  const adminViewing=await data(`/lab/calls/${callId}/video`,{account:'admin',method:'POST',body:{enabled:true}});
  check('Same-site administrator may view helmets without a second call',()=>{assert.equal(adminViewing.id,callId);assert.equal(adminViewing.connectedAt,connectedAt);assert.equal(adminViewing.videoEnabled,true);assert.deepEqual(adminViewing.participants.map(p=>p.state),['connected','ringing']);});
  const adminStopped=await data(`/lab/calls/${callId}/video`,{account:'admin',method:'POST',body:{enabled:false}});
  check('Administrator may stop viewing without ending original call',()=>{assert.equal(adminStopped.id,callId);assert.equal(adminStopped.connectedAt,connectedAt);assert.equal(adminStopped.videoEnabled,false);assert.equal(adminStopped.state,'connected');});
  await data(`/lab/calls/${callId}/video`,{method:'POST',body:{enabled:'true'},expected:400});
  const enabled=await data(`/lab/calls/${callId}/video`,{method:'POST',body:{enabled:true}});
  check('Owner enables one-way view on same call without second ring',()=>{assert.equal(enabled.id,callId);assert.equal(enabled.connectedAt,connectedAt);assert.equal(enabled.videoEnabled,true);assert.equal(enabled.state,'connected');assert.deepEqual(enabled.participants.map(p=>p.state),['connected','ringing']);});
  const second=await data(`/lab/calls/${callId}/accept`,{account:'admin',method:'POST',body:{deviceId:'13'}});
  check('Second helmet joins original call without resetting connectedAt',()=>{assert.equal(second.id,callId);assert.equal(second.connectedAt,connectedAt);assert.ok(second.participants.every(p=>p.state==='connected'));});
  const disabled=await data(`/lab/calls/${callId}/video`,{method:'POST',body:{enabled:false}});
  check('View can stop without ending or recreating the call',()=>{assert.equal(disabled.id,callId);assert.equal(disabled.connectedAt,connectedAt);assert.equal(disabled.state,'connected');assert.equal(disabled.videoEnabled,false);});
  const sync=await data('/lab/state');const live=sync.calls.find(c=>c.id===callId);
  check('State read through Java preserves same connected call',()=>{assert.ok(live);assert.equal(live.connectedAt,connectedAt);assert.ok(live.participants.every(p=>p.state==='connected'));});
  await data(`/lab/calls/${callId}/video`,{method:'POST',body:{enabled:true}});
  const ended=await data(`/lab/calls/${callId}/end`,{method:'POST',body:{}});closed=true;
  check('End clears viewing and participant state',()=>{assert.equal(ended.id,callId);assert.equal(ended.state,'ended');assert.equal(ended.videoEnabled,false);assert.ok(ended.participants.every(p=>p.state==='ended'));});
  await data(`/lab/calls/${callId}/video`,{method:'POST',body:{enabled:true},expected:409});
  check('Every client request used Java port 18084, never Node directly',()=>assert.ok(artifact.requests.every(r=>r.origin===base.origin)));
  artifact.status='passed';
} catch(error) {failed=error;artifact.status='failed';artifact.error=String(error.message).replaceAll(password,'[redacted]');}
finally {
  if(callId&&!closed&&tokens.has('duty')) {
    try {await data(`/lab/calls/${callId}/end`,{method:'POST',body:{}});artifact.cleanup.push({callId,ended:true});}
    catch {artifact.cleanup.push({callId,ended:false});artifact.status='failed';}
  }
  for(const deviceId of changedDevices) {
    try {await data('/lab/presence',{account:'admin',method:'POST',body:{deviceId,online:false}});artifact.cleanup.push({deviceId,offline:true});}
    catch {artifact.cleanup.push({deviceId,offline:false});artifact.status='failed';}
  }
  artifact.finishedAt=new Date().toISOString();tokens.clear();
  await mkdir(new URL('../artifacts/',import.meta.url),{recursive:true});await writeFile(output,JSON.stringify(artifact,null,2),'utf8');
  console.log(JSON.stringify({status:artifact.status,checks:artifact.checks.length,artifact:fileURLToPath(output),note:'All requests used the Java backend; simulated state only. No phone camera or media assertions.'}));
}
if(failed||artifact.status!=='passed')process.exitCode=1;
