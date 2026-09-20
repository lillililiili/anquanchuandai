// Browser contract tests with isolated fixtures: no real business records are written.
import { createRequire } from 'node:module';
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const { chromium }=createRequire(import.meta.url)('playwright');
const publicDir=new URL('../public/',import.meta.url),artifacts=new URL('../artifacts/',import.meta.url);
const server=createServer(async(req,res)=>{try{const path=req.url==='/'||req.url==='/business'?'business.html':req.url.slice(1);const data=await readFile(new URL(path,publicDir));res.setHeader('Content-Type',path.endsWith('.js')?'text/javascript':path.endsWith('.css')?'text/css':path.endsWith('.svg')?'image/svg+xml':'text/html');res.end(data);}catch{res.writeHead(404).end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({channel:'chrome',headless:true}),page=await browser.newPage({viewport:{width:1440,height:1000}});
const errors=[],writes=[];let stateReads=0,ttsDelay=0;page.on('pageerror',e=>errors.push(e.message));
const people=[{id:'11',name:'陈建国',personCode:'P-001'},{id:'12',name:'周明',personCode:'P-002'}];
const devices=[{id:'21',sn:'LAB-H001',typeCode:'helmet',siteId:'1',currentAssignment:{personId:'11'}},{id:'22',sn:'LAB-H002',typeCode:'helmet',siteId:'1',currentAssignment:{personId:'12'}},{id:'23',sn:'LAB-W001',typeCode:'watch',siteId:'1',currentAssignment:{personId:'11'}}];
const tasks=[{id:'31',siteId:'1',title:'锅炉平台检修',status:'ready',members:[{personId:'11',name:'陈建国'}]}];
const live={devices:[],calls:[],messages:[],dispatchers:[{userId:'7',name:'当前值班员',duty:true}]};
const body=r=>r.postDataJSON()||{};
await page.route('**/*',async route=>{
  const r=route.request(),u=new URL(r.url()),path=u.pathname;let result;
  if(!path.startsWith('/api/')&&!['/login','/captchaImage'].includes(path))return route.continue();
  if(r.method()!=='GET'&&path!=='/login')writes.push({path,method:r.method(),body:body(r),site:r.headers()['x-site-id']});
  if(path==='/captchaImage')result={code:200,captchaEnabled:false};
  else if(path==='/login')result={code:200,token:'fixture-token'};
  else if(path==='/api/v1/me')result={code:200,data:{userId:'7',userName:'fixture',roles:['wear_duty'],permissions:['wear:call:start','wear:command:tts'],authorizedSites:[{id:'1',name:'演示厂站A'},{id:'2',name:'演示厂站B'}],currentSiteId:'1'}};
  else if(path==='/api/v1/lab/roster')result={code:200,data:r.headers()['x-site-id']==='2'?{people:[],devices:[],tasks:[]}:{people,devices:devices.map(d=>({...d,lab:live.devices.find(v=>v.deviceId===d.id)})),tasks}};
  else if(path==='/api/v1/lab/state'){stateReads++;result={code:200,data:r.headers()['x-site-id']==='2'?{devices:[],calls:[],messages:[],dispatchers:[]}:live};}
  else if(path==='/api/v1/lab/presence') {const b=body(r),d=devices.find(d=>d.id===b.deviceId),v={...b,sn:d.sn,typeCode:d.typeCode,controller:'7'};live.devices=live.devices.filter(v=>v.deviceId!==b.deviceId);live.devices.push(v);result={code:200,data:v};}
  else if(path==='/api/v1/lab/calls') {const b=body(r);assert.equal(b.deviceIds.length,1,'Device incoming call must have one source');assert.equal(Object.hasOwn(b,'video'),false,'Unified call does not request a video call');assert.equal(Object.hasOwn(b,'targetUserId'),false,'Helmet cannot select a recipient');const v={...b,userId:'7',video:false,videoEnabled:false,id:'incoming-'+live.calls.length,state:'ringing',createdAt:Date.now(),participants:b.deviceIds.map(id=>({...live.devices.find(d=>d.deviceId===id),state:'ringing'}))};live.calls.unshift(v);result={code:200,data:v};}
  else if(/^\/api\/v1\/lab\/calls\/[^/]+\/(accept|reject|end)$/.test(path)) {const parts=path.split('/'),c=live.calls.find(c=>c.id===parts[5]),p=c.participants.find(p=>p.deviceId===body(r).deviceId),action=parts[6];p.state=action==='accept'?'connected':action==='reject'?'rejected':'ended';if(action==='accept')c.state='connected';else if(!c.participants.some(p=>['ringing','connected'].includes(p.state)))c.state='ended';result={code:200,data:c};}
  else if(path==='/api/v1/lab/tts') {const b=body(r),m={id:'message-'+live.messages.length,text:b.text,createdAt:Date.now(),receipts:b.deviceIds.map(id=>({deviceId:id,state:'sent'}))};live.messages.unshift(m);if(ttsDelay)await new Promise(r=>setTimeout(r,ttsDelay));result={code:200,data:m};}
  else if(path==='/api/v1/lab/tts/ack'){const b=body(r),m=live.messages.find(m=>m.id===b.id);m.receipts.find(v=>v.deviceId===b.deviceId).state='acknowledged';result={code:200,data:m};}
  else if(path==='/api/v1/work-tasks/31/members'){for(const id of body(r).personIds)tasks[0].members.push({personId:id,name:people.find(p=>p.id===id).name});result={code:200,data:tasks[0]};}
  else if(path.startsWith('/api/v1/work-tasks/31/members/')){tasks[0].members=tasks[0].members.filter(m=>m.personId!==path.split('/').at(-1));result={code:200,data:tasks[0]};}
  else throw new Error('Unexpected fixture route '+path);
  await route.fulfill({contentType:'application/json',body:JSON.stringify(result)});
});
async function ready(){await page.waitForFunction(()=>!document.getElementById('signIn').disabled);}
async function click(selector){await page.locator(selector).click();await ready();}
try {
  await page.goto('http://127.0.0.1:'+server.address().port+'/business');await ready();
  await page.locator('#username').fill('fixture');await page.locator('#password').fill('fixture-password');await click('#signIn');
  assert.equal(await page.locator('#password').inputValue(),'');assert.equal(writes.length,0);
  await page.locator('[data-device="21"] .device-title input').check();await page.locator('[data-device="22"] .device-title input').check();await click('#onlineSelected');
  assert.equal(live.devices.filter(d=>d.online).length,2);assert.equal(await page.locator('#selectedCount').innerText(),'已选 2 台');
  await page.locator('[data-device="21"] .device-checks input').nth(1).check();await click('[data-device="21"] button[data-write]');assert.equal(live.devices.find(d=>d.deviceId==='21').abnormal,true);
  assert.equal(await page.locator('[data-device="21"] .actions button').count(),2);
  assert.equal(await page.locator('select#dispatcher').count(),0);
  await click('[data-helmet-call="21"]');assert.equal(live.calls[0].sos,false);assert.equal(live.calls[0].userId,'7');
  assert.equal(await page.locator('[data-helmet-call="21"]').isDisabled(),true,'Outgoing helmet call cannot be repeated while waiting');
  await click('[data-helmet-end="21"]');assert.equal(live.calls[0].state,'ended');live.calls=[];
  assert.equal(await page.locator('#video').count(),0);await click('#sosCall');assert.equal(live.calls.length,0);assert.match(await page.locator('#notice').innerText(),/每次请选择 1 台/);
  await page.locator('[data-device="22"] .device-title input').uncheck();await click('#sosCall');
  assert.equal(live.calls[0].sos,true);assert.equal(live.calls[0].video,false);assert.equal(live.calls[0].videoEnabled,false);assert.equal(live.calls[0].userId,'7');assert.equal(live.calls[0].participants.length,1);
  await page.locator('[data-device="22"] .device-title input').check();
  live.calls=[];live.calls.push({id:'outgoing-1',direction:'outgoing',video:false,videoEnabled:false,state:'ringing',createdAt:Date.now(),participants:live.devices.map(d=>({...d,state:'ringing'}))});
  await page.waitForSelector('[data-call="outgoing-1"]');await click('[data-helmet-call="21"]');
  assert.equal(live.calls[0].participants.find(p=>p.deviceId==='21').state,'connected');
  assert.match(await page.locator('[data-camera="21"]').innerText(),/画面查看未开启/);
  live.calls[0].videoEnabled=true;
  await page.waitForFunction(()=>document.querySelector('[data-camera="21"]')?.textContent==='画面查看中（单向模拟）');
  assert.match(await page.locator('[data-call="outgoing-1"]').innerText(),/值班端查看安全帽画面（单向模拟）/);
  assert.equal(await page.locator('[data-camera="22"]').innerText(),'未接通 · 不可查看画面');
  live.calls[0].videoEnabled=false;
  await page.waitForFunction(()=>document.querySelector('[data-camera="21"]')?.textContent==='画面查看未开启');
  await click('[data-helmet-end="22"]');assert.equal(live.calls[0].participants.find(p=>p.deviceId==='22').state,'rejected');
  await click('[data-helmet-end="21"]');assert.equal(live.calls[0].state,'ended');
  live.dispatchers.push({userId:'8',name:'另一个值班账号',duty:true});
  await page.waitForFunction(()=>document.getElementById('dispatcherHint').textContent.includes('多个在线值班账号'));
  assert.equal(await page.locator('[data-helmet-call="21"]').isDisabled(),true);assert.equal(await page.locator('#normalCall').isDisabled(),true);
  live.dispatchers.pop();await page.waitForFunction(()=>document.getElementById('dispatcherHint').textContent.includes('唯一在线'));
  await page.locator('#ttsText').fill('测试群发播报');
  await page.locator('[data-device="21"] select').selectOption('12');
  ttsDelay=2600;const readsBefore=stateReads;await page.locator('#sendTts').click();
  await page.waitForFunction(()=>document.getElementById('heartbeat').textContent.startsWith('心跳已续期'));
  assert.equal(await page.locator('#signIn').isDisabled(),true);assert.ok(stateReads>readsBefore,'Busy submit must keep console presence heartbeats');
  assert.equal(await page.locator('[data-device="21"] select').inputValue(),'12','Heartbeat must retain unsaved wearer draft');
  await ready();ttsDelay=0;assert.equal(live.messages[0].receipts.length,2);
  await page.locator('[data-device="21"] select').selectOption('11');
  await page.locator('#messages button').first().click();await ready();
  assert.equal(live.messages[0].receipts.filter(r=>r.state==='acknowledged').length,1);
  assert.equal(writes.filter(w=>w.path.includes('/work-tasks/')).length,0);
  await page.locator('#taskMembers input[value="12"]').check();await page.locator('#taskMembers input[value="11"]').uncheck();await click('#saveMembers');assert.deepEqual(tasks[0].members.map(m=>m.personId),['12']);
  await page.locator('#taskFilter').selectOption('31');assert.equal(await page.locator('.device').count(),1);
  await page.locator('#taskFilter').selectOption('');
  await mkdir(artifacts,{recursive:true});await page.screenshot({path:fileURLToPath(new URL('business-desktop.png',artifacts)),fullPage:true});
  await page.setViewportSize({width:390,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
  await page.screenshot({path:fileURLToPath(new URL('business-mobile.png',artifacts)),fullPage:true});
  await page.locator('#site').selectOption('2');await ready();assert.equal(await page.locator('.device').count(),0);assert.equal(await page.locator('#selectedCount').innerText(),'已选 0 台');assert.equal(live.devices.filter(d=>d.online).length,0);assert.equal(await page.locator('#calls .session').count(),0);
  await click('#signOut');assert.equal(await page.locator('#workspace').isHidden(),true);
  assert.deepEqual(errors,[]);console.log('PASS: multi-device presence, abnormal draft, unified SOS incoming, one-way dispatcher viewing state for connected helmets only, per-device accept/reject/end, group TTS receipts, explicit business task membership, site cleanup, sign-out, mobile width. Isolated browser fixtures; no real business writes.');
} finally {await browser.close();await new Promise(r=>server.close(r));}
