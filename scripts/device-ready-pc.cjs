// Run only with the separately provisioned device-ready QA backend on 18085.
// API traffic from the existing dev pages is forwarded to that real backend.
// This is not a mocked response test and never invokes device voice/broadcast.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
assert.equal(process.env.DEVICE_READY_QA, '1', 'Explicit isolated QA opt-in required');
const base = 'http://127.0.0.1:18085';
const output = path.resolve(__dirname, '../output/device-ready/pc-flow');
fs.mkdirSync(output, { recursive: true });
const steps = [], errors = [], sessions = [];
const password = process.env.DEVICE_READY_USER_PASSWORD;
assert(password && process.env.DEVICE_READY_ADMIN_PASSWORD, 'Credentials must be supplied through environment');
async function api(route, token, body, expected = 200) {
  const response = await fetch(base + '/api/guardian/v1' + route, {
    method: body === undefined ? 'GET' : 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { 'X-Wearable-Token': token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const result = await response.json();
  assert.equal(response.status, expected, `${route}: ${JSON.stringify(result)}`);
  return result;
}
async function member(name) {
  const result = await api('/mobile/login', null, { account: name, password });
  sessions.push(result.token);
  return result.token;
}
async function capture(page, name, expected) {
  await page.getByText(expected, { exact: false }).first().waitFor();
  const text = await page.locator('body').innerText();
  assert(!/后端未连接|业务数据读取失败|加载失败/.test(text), `${name}: data not available`);
  await page.screenshot({ path: path.join(output, name + '.png'), fullPage: true });
  fs.writeFileSync(path.join(output, name + '.txt'), text);
  steps.push({ name, url: page.url(), passed: true });
  console.log('PASS ' + name);
}
async function run() {
  const browser = await chromium.launch({ headless: true, channel: 'msedge' });
  try {
    const context = await browser.newContext({ viewport: { width: 1920, height: 1080 } });
    await context.route('**/api/**', async route => {
      const url = new URL(route.request().url());
      assert(['127.0.0.1', 'localhost'].includes(url.hostname));
      const response = await route.fetch({ url: base + url.pathname + url.search });
      await route.fulfill({ response });
    });
    const user = await member('wear_user'), peer = await member('wear_peer');
    const input = { requestId: randomUUID(), siteId: 'site-1', description: '隔离验收：周明手机求助', locationDescription: '' };
    let first = await api('/sos', user, input);
    assert.equal((await api('/sos', user, input)).id, first.id, 'Retry must not create another SOS');
    const second = await api('/sos', peer, { requestId: randomUUID(), siteId: 'site-1', description: '隔离验收：李志远另一条求助' });
    assert.notEqual(first.id, second.id);
    first = await api(`/events/${first.id}/observations`, user, { requestId: randomUUID(), expectedVersion: first.version, situation: '隔离验收现场记录：已经到达安全区域，等待核验。' });
    await api(`/events/${second.id}`, user, undefined, 404);
    steps.push({ name: 'mobile-two-sos-idempotency-scope-observation', passed: true, eventIds: [first.id, second.id] });
    const portal = await context.newPage();
    portal.on('pageerror', e => errors.push({ surface: 'portal', message: e.message }));
    await portal.goto('http://127.0.0.1:5191/');
    await portal.getByPlaceholder('请输入工作账号').fill('wear_duty');
    await portal.getByPlaceholder('请输入密码', { exact: true }).fill(password);
    await portal.getByRole('button', { name: '登录', exact: true }).click();
    await portal.waitForURL(/overview/);
    await portal.locator('header.topbar').getByRole('button', { name: /陈建国/ }).click();
    await capture(portal, '01-actual-operator', 'wear_duty');
    assert((await portal.locator('body').innerText()).includes('平台值守员'));
    await portal.keyboard.press('Escape');
    await portal.goto('http://127.0.0.1:5191/#/sos');
    await portal.locator(`a[href="#/sos?eventId=${first.id}"]`).click();
    await capture(portal, '02-first-sos', first.id);
    await portal.getByRole('button', { name: '接警认领', exact: true }).click();
    await portal.getByText('已接警', { exact: true }).first().waitFor();
    await portal.getByRole('button', { name: '加入协助', exact: true }).click();
    await portal.getByText('正在协助', { exact: true }).waitFor();
    await portal.getByRole('button', { name: '结束协助', exact: true }).click();
    await portal.getByRole('button', { name: '确认', exact: true }).click();
    await portal.getByText('协助已结束', { exact: true }).waitFor();
    first = await api(`/events/${first.id}`, user);
    assert.equal(first.status, '处理中');
    assert.equal(first.assistance.status, 'ended');
    assert.equal((await api(`/events/${second.id}`, peer)).assistance.status, 'waiting');
    await capture(portal, '03-end-assistance-await-verification', '协助已结束');
    await portal.locator(`a[href="#/sos?eventId=${second.id}"]`).click();
    await capture(portal, '04-other-sos-unaffected', second.id);
    assert.equal(await portal.locator('.sos-banner .session-badge').innerText(), '待接警');
    await portal.goto(`http://127.0.0.1:5191/#/event/${first.id}`);
    await capture(portal, '05-mobile-observation-on-pc', '隔离验收现场记录');
    await portal.locator('select[name="conclusion"]').selectOption('需现场处理');
    await portal.locator('textarea[name="situation"]').fill('隔离验收：PC 值守人员完成现场核查。');
    await portal.locator('textarea[name="measures"]').fill('隔离验收：人员已转移，真实设备效果另行验收。');
    await portal.getByRole('button', { name: '保存草稿', exact: true }).click();
    await portal.getByText('核验草稿已保存', { exact: true }).waitFor();
    assert.equal((await api(`/events/${first.id}`, user)).draft.conclusion, '需现场处理');
    await portal.getByRole('button', { name: '提交核验记录', exact: true }).click();
    await capture(portal, '06-pc-final-verification', '已提交核验结果');
    const verified = await api(`/events/${first.id}`, user);
    assert.equal(verified.status, '已核验');
    assert.equal(verified.verification.situation, '隔离验收：PC 值守人员完成现场核查。');
    assert.equal(verified.observations[0].situation, '隔离验收现场记录：已经到达安全区域，等待核验。');
    assert.equal(await portal.locator('textarea[name="situation"]').getAttribute('readonly'), '');
    steps.push({ name: 'pc-verification-visible-through-mobile-session', passed: true });
    await portal.locator('header.topbar').getByRole('button', { name: /陈建国/ }).click();
    await portal.getByRole('button', { name: '退出登录', exact: true }).click();
    await portal.waitForURL(/login/);
    await capture(portal, '07-portal-logout', '登录');
    const admin = await context.newPage();
    admin.on('pageerror', e => errors.push({ surface: 'admin', message: e.message }));
    await admin.goto('http://127.0.0.1:5181/');
    await admin.getByPlaceholder('请输入管理账号').fill('admin');
    await admin.getByPlaceholder('请输入密码', { exact: true }).fill(process.env.DEVICE_READY_ADMIN_PASSWORD);
    await admin.getByRole('button', { name: '登录', exact: true }).click();
    await admin.waitForURL(/overview/);
    await admin.getByRole('link', { name: '权限协作', exact: true }).click();
    await capture(admin, '08-shared-accounts', 'wear_user');
    for (const name of ['wear_user', 'wear_peer', 'wear_duty']) assert((await admin.locator('body').innerText()).includes(name));
    await admin.getByRole('button', { name: '退出登录', exact: true }).click();
    await admin.waitForURL(/login/);
    await capture(admin, '09-admin-logout', '欢迎登录');
    assert.deepEqual(errors, []);
  } finally {
    await Promise.allSettled(sessions.map(token => api('/logout', token, {})));
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify({ base, steps, errors }, null, 2));
    await browser.close();
  }
}
run().catch(error => { console.error(error); process.exitCode = 1; });
