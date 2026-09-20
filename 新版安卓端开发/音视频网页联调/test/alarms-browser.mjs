// Writes three dedicated test devices and three clearly marked simulator events.
// Run only against a local test backend. Account passwords are never printed.
import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const { chromium } = createRequire(import.meta.url)('playwright');
const base = process.env.CALL_LAB_URL || 'http://localhost:5188';
const password = process.env.LAB_TEST_PASSWORD || 'admin123';
const browser = await chromium.launch({ channel:'chrome', headless:true });
const artifacts = new URL('../artifacts/',import.meta.url);
await mkdir(artifacts,{recursive:true});
const page = await browser.newPage({viewport:{width:1440,height:1100}});
const errors = [], results = [], devices = {}, events = {};
page.on('pageerror', e => errors.push(e.message));
async function ready() { await page.waitForFunction(() => !document.getElementById('signIn').disabled); }
async function click(id) { await page.locator('#'+id).click(); await ready(); }
async function login(username) {
  await ready(); await page.locator('#username').fill(username); await page.locator('#password').fill(password);
  await click('signIn');
  assert.match(await page.locator('#connection').innerText(),new RegExp(username));
}
async function type(value) {
  await page.locator('#deviceType').selectOption(value); await ready();
}
async function pickTestDevice(value) {
  await type(value);
  await page.locator('#device').selectOption(devices[value]); await ready();
}
async function selectedEvent(id) {
  await page.locator('[data-event="'+id+'"]').click(); await ready();
}
async function api(token,path,method='GET',body,site) {
  const res = await fetch(base+path,{method,headers:{'Content-Type':'application/json',Authorization:'Bearer '+token,...(site?{'X-Site-Id':site}:{})},body:body===undefined?undefined:JSON.stringify(body)});
  return res.json();
}
async function token(username) {
  const res = await api('', '/login','POST',{username,password});
  assert.equal(res.code,200); return res.token;
}
try {
  await page.goto(base+'/alarms'); await ready();
  await login(process.env.LAB_ADMIN || 'admin');
  await page.getByText('没有合适的设备？创建测试设备',{exact:true}).click();
  for (const kind of ['helmet','belt','watch']) {
    await type(kind); await click('createDevice');
    devices[kind] = await page.locator('#device').inputValue();
    assert.ok(devices[kind]); assert.match(await page.locator('#deviceInfo').innerText(),/CALL-LAB/);
  }
  await page.getByText('修改设备台账',{exact:true}).click();
  await page.locator('#externalCode').fill('CALL-LAB-WATCH-VERIFIED');
  await click('saveDevice');
  assert.match(await page.locator('#notice').innerText(),/回读值与提交值一致/);
  results.push('Created/reused helmet, belt and watch test devices; asset edit verified by real readback');
  await login('siteA_duty');
  assert.equal(await page.locator('#createDevice').isDisabled(),true);
  const cases = {helmet:'helmet.sos',belt:'belt.unhooked',watch:'watch.heart_high'};
  for (const kind of ['helmet','belt','watch']) {
    await pickTestDevice(kind);
    await page.locator('[data-scenario="'+cases[kind]+'"]').click();
    await click('sendAlarm');
    assert.match(await page.locator('#notice').innerText(),/告警已写入并回读/);
    let result = JSON.parse(await page.locator('#result').textContent());
    events[kind] = result.readback.event.id;
    assert.equal(result.readback.event.demo,true);
    assert.equal(JSON.parse(result.readback.actions.find(a=>a.action==='simulate').reason).scenarioCode,cases[kind]);
    await click('repeatAlarm');
    result = JSON.parse(await page.locator('#result').textContent());
    assert.equal(result.readback.event.id,events[kind]); assert.equal(result.readback.event.repeatCount,1);
    assert.equal(result.readback.actions.filter(a=>a.action==='simulate').length,1);
    await click('claimEvent'); assert.match(await page.locator('#eventStatus').innerText(),/已认领/);
    await click('handleEvent');
    if (kind === 'helmet') {
      assert.equal(await page.locator('#eventStatus').innerText(),'待复核');
      assert.equal(await page.locator('#closeEvent').isDisabled(),true);
    } else {
      await click('closeEvent'); assert.equal(await page.locator('#eventStatus').innerText(),'已关闭');
    }
    results.push(kind+': real event write/read, scenario audit, idempotent repeat, claim and handle verified');
  }
  await page.screenshot({path:fileURLToPath(new URL('alarms-desktop.png',artifacts)),fullPage:true});
  await login('siteA_reviewer');
  await pickTestDevice('helmet'); await selectedEvent(events.helmet);
  await click('closeEvent'); assert.equal(await page.locator('#eventStatus').innerText(),'已关闭');
  results.push('High risk event closed only after switching to reviewer');
  const dutyToken = await token('siteA_duty'), readonlyToken = await token('siteA_readonly');
  const me = (await api(dutyToken,'/api/v1/me')).data;
  const site = me.authorizedSites[0].id;
  const bad = {sourceEventId:'call-lab:'+crypto.randomUUID(),siteId:site,deviceId:devices.helmet,type:'realtime',scenarioCode:'watch.heart_high',measurements:{heartRate:130}};
  assert.equal((await api(dutyToken,'/api/v1/events/simulate','POST',bad,site)).code,400);
  bad.scenarioCode='helmet.sos';bad.type='sos';bad.measurements={};
  assert.equal((await api(readonlyToken,'/api/v1/events/simulate','POST',bad,site)).code,403);
  const adminToken=await token(process.env.LAB_ADMIN || 'admin');
  const d=(await api(adminToken,'/api/v1/devices/'+devices.watch,'GET',undefined,site)).data;
  assert.equal((await api(adminToken,'/api/v1/devices/'+d.id,'PUT',{externalCode:'must-not-write',version:d.version-1},site)).code,409);
  results.push('Server rejects mismatched device scenario, readonly event writes, and stale device version');
  await page.setViewportSize({width:390,height:844});
  await page.screenshot({path:fileURLToPath(new URL('alarms-mobile.png',artifacts)),fullPage:true});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
  await page.locator('nav a[href="/"]').click(); await page.waitForSelector('#transport');
  await page.locator('a[href="/alarms"]').click(); await page.waitForSelector('#loginForm');
  assert.equal(await page.locator('#connection').innerText(),'尚未登录项目');
  assert.deepEqual(errors,[]);
  results.push('Mobile no overflow, page navigation and memory-only authentication verified');
  await writeFile(new URL('alarms-test-results.json',artifacts),JSON.stringify({time:new Date().toISOString(),devices,events,results},null,2));
  console.log(JSON.stringify({devices,events,results},null,2));
} catch (error) {
  await page.screenshot({path:fileURLToPath(new URL('alarms-failure.png',artifacts)),fullPage:true}).catch(()=>{});
  console.error('Page notice:',await page.locator('#notice').textContent().catch(()=>'unavailable'));
  throw error;
} finally { await browser.close(); }
