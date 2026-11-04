// Real HTTP/browser acceptance against the disposable, network-isolated clone only.
const { chromium, request } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const privateFile = path.resolve(__dirname, '../后端代码/melhat_server-dev/build/work-business-qa-20261103t060903z/qa-private/browser-session.private.json');
const session = JSON.parse(fs.readFileSync(privateFile, 'utf8'));
assert.equal(session.baseUrl, 'http://127.0.0.1:18085');
const adminBase = 'http://127.0.0.1:5185/', pcBase = 'http://127.0.0.1:5193/';
const output = path.resolve(__dirname, '../output/work-business/real-ui');
fs.mkdirSync(output, { recursive: true });
const errors = [], steps = [];
let createdWorkId = '', modeRestored = false, passed = false;
const localInput = value => new Date(value + 8 * 3600000).toISOString().slice(0, 16);

async function run() {
  const http = await request.newContext({ baseURL: session.baseUrl, extraHTTPHeaders: { 'X-Wearable-Token': session.adminToken } });
  const readConfig = async () => { const response = await http.get('/api/admin/v1/business-config'); assert.equal(response.status(), 200); return response.json(); };
  const browser = await chromium.launch({ headless: true, channel: 'msedge' });
  let admin, pc;
  try {
    assert.equal((await readConfig()).workBusinessEnabled, true);
    const response = await http.get('/api/admin/v1/state'); assert.equal(response.status(), 200);
    const state = (await response.json()).state;
    const identity = state.accounts.find(account => account.id === 'demo-system'); assert(identity);
    const optionResponse = await http.get('/api/admin/v1/works/options?siteId=site-1'); assert.equal(optionResponse.status(), 200);
    const choices = await optionResponse.json();
    const people = session.people.map(id => choices.people.find(person => person.id === id)); assert(people.every(Boolean));
    const adminContext = await browser.newContext({ viewport: { width: 1600, height: 1000 } });
    await adminContext.addInitScript(({ token, id, version }) => {
      sessionStorage.setItem('wearable-admin-token', token);
      sessionStorage.setItem('Wearable-Admin-Mock-Token', id);
      sessionStorage.setItem('Wearable-Admin-Mock-Session-Version', String(version));
    }, { token: session.adminToken, id: identity.id, version: identity.credentialVersion });
    await adminContext.route('**/*', route => new URL(route.request().url()).origin === new URL(adminBase).origin ? route.continue() : route.abort());
    admin = await adminContext.newPage(); admin.on('pageerror', error => errors.push(error.message));
    await admin.goto(adminBase + '#/workbusiness?siteId=site-1');
    await admin.getByRole('button', { name: '关闭业务', exact: true }).waitFor();
    await admin.getByRole('button', { name: '作业登记', exact: true }).click();
    await admin.getByRole('button', { name: '新增作业', exact: true }).click();
    const workName = 'QA浏览器登记-' + Date.now();
    await admin.locator('#work-name').fill(workName);
    await admin.locator('#work-area').fill('隔离测试区域，仅留存克隆环境');
    await admin.locator('#work-plannedStartAt').fill(localInput(Date.now() - 300000)); await admin.locator('#work-plannedStartAt').press('Tab');
    await admin.locator('#work-plannedEndAt').fill(localInput(Date.now() + 86400000)); await admin.locator('#work-plannedEndAt').press('Tab');
    const optionLabel = person => person.name + (person.code ? ' · ' + person.code : '');
    await admin.locator('#work-leader').click(); await admin.getByRole('option', { name: optionLabel(people[0]), exact: true }).click();
    await admin.locator('#work-supervisor').click(); await admin.getByRole('option', { name: optionLabel(people[1]), exact: true }).click();
    await admin.locator('#work-members label').filter({ hasText: people[2].name }).locator('input').check();
    await admin.locator('#work-remarks').fill('浏览器真实POST登记；仅用于隔离克隆环境验收。');
    const savedResponse = admin.waitForResponse(response => response.request().method() === 'POST' && new URL(response.url()).pathname === '/api/admin/v1/works');
    await admin.getByRole('button', { name: '保存登记', exact: true }).click();
    const savedHttp = await savedResponse; assert.equal(savedHttp.status(), 200);
    const saved = await savedHttp.json(); createdWorkId = saved.id;
    assert.equal(saved.source, 'LOCAL'); assert.deepEqual(new Set(saved.members), new Set(session.people));
    await admin.getByText('作业登记已保存。', { exact: true }).waitFor();
    const row = admin.getByRole('row').filter({ hasText: workName });
    await row.getByRole('button', { name: '编辑', exact: true }).click();
    const editNote = '浏览器真实PATCH修改成功；历史数据及设备未改变。';
    await admin.locator('#work-remarks').fill(editNote);
    const updatedResponse = admin.waitForResponse(response => response.request().method() === 'PATCH' && new URL(response.url()).pathname.endsWith('/works/' + createdWorkId));
    await admin.getByRole('button', { name: '保存登记', exact: true }).click();
    const updatedHttp = await updatedResponse; assert.equal(updatedHttp.status(), 200);
    const updated = await updatedHttp.json(); assert.equal(updated.remarks, editNote); assert.equal(updated.version, saved.version + 1);
    await admin.getByText('作业登记已保存。', { exact: true }).waitFor();
    await admin.screenshot({ path: path.join(output, '01-admin-real-registration-edit.png'), fullPage: true });
    steps.push('real-admin-form-create-and-edit-three-participants');

    const pcContext = await browser.newContext({ viewport: { width: 1600, height: 1000 } });
    await pcContext.addInitScript(({ token, personId, eventId, workId }) => {
      sessionStorage.setItem('wearable-guardian-token', token); sessionStorage.setItem('rolling-session', 'qa-authenticated');
      sessionStorage.setItem('rolling-view', JSON.stringify({ viewVersion: 'wearable-person-v2', station: 'S1', person: personId, event: eventId, work: workId, filters: {}, formDrafts: {} }));
    }, { token: session.pcToken, personId: session.people[0], eventId: session.eventId, workId: createdWorkId });
    await pcContext.route('**/*', route => new URL(route.request().url()).origin === new URL(pcBase).origin ? route.continue() : route.abort());
    pc = await pcContext.newPage(); pc.on('pageerror', error => errors.push(error.message));
    const gotoPc = async route => { await pc.goto(pcBase + '#/' + route); await pc.locator('.connection-notice').waitFor({ state: 'hidden' }); };
    await gotoPc('work/' + createdWorkId);
    await pc.getByText('本地登记 · 只读', { exact: true }).waitFor();
    assert.match(await pc.locator('body').innerText(), new RegExp(workName));
    await pc.screenshot({ path: path.join(output, '02-portal-local-registration.png'), fullPage: true });
    steps.push('pc-reads-real-local-registration');
    await gotoPc('event/' + session.eventId);
    await pc.getByText('已提交核验结果', { exact: true }).waitFor();
    await pc.getByText('手机 SOS', { exact: false }).first().waitFor();
    steps.push('pc-reads-mobile-sos-final-verification');

    await admin.getByRole('button', { name: '业务设置', exact: true }).click();
    await admin.getByRole('button', { name: '关闭业务', exact: true }).click();
    await admin.locator('dialog[open]').getByRole('button', { name: '确认关闭', exact: true }).click();
    await admin.getByText('已关闭，在线使用端将在刷新业务配置后同步。', { exact: true }).waitFor();
    assert.equal((await readConfig()).workBusinessEnabled, false);
    await pc.evaluate(() => document.dispatchEvent(new Event('visibilitychange')));
    await pc.getByText('事发作业监护人', { exact: true }).waitFor({ state: 'hidden' });
    await admin.getByRole('button', { name: '作业登记', exact: true }).click();
    assert.equal(await admin.getByRole('button', { name: '新增作业', exact: true }).isDisabled(), true);
    for (const button of await admin.getByRole('button', { name: '编辑', exact: true }).all()) assert.equal(await button.isDisabled(), true);
    const stillWaiting = await http.get('/api/admin/v1/works/' + createdWorkId); assert.equal((await stillWaiting.json()).status, '待开始');
    await admin.screenshot({ path: path.join(output, '03-admin-disabled-readonly.png'), fullPage: true });
    steps.push('admin-mode-off-keeps-record-readonly');
    const forbidden = /作业监护|当前作业|关联作业|作业编号|作业分组|作业筛选|作业状态|作业信息|作业台账|台账作业|作业关联|待分配作业|工作票|原安监系统|外部系统状态/;
    // The full 14-page sweep is covered by the isolated portal fixture. Here
    // exercise the real cross-client data and switch boundary without device actions.
    for (const route of ['event/' + session.eventId, 'statistics']) {
      await gotoPc(route);
      if (route === 'screen') await pc.locator('.screen-stats').waitFor();
      assert.doesNotMatch(await pc.locator('body').innerText(), forbidden, route);
      if (route.startsWith('event/')) await pc.screenshot({ path: path.join(output, '04-portal-real-sos-disabled.png'), fullPage: true });
      steps.push('real-disabled:' + route);
    }
    await gotoPc('work/' + createdWorkId); await pc.waitForURL('**/#/overview');
    await gotoPc('personnel?workId=' + createdWorkId + '&tab=%E4%BB%BB%E5%8A%A1'); await pc.waitForURL('**/#/personnel');
    steps.push('real-old-work-url-and-query-cleared');
    await admin.getByRole('button', { name: '业务设置', exact: true }).click();
    await admin.getByRole('button', { name: '开启业务', exact: true }).click();
    await admin.locator('dialog[open]').getByRole('button', { name: '确认开启', exact: true }).click();
    await admin.getByText('已开启，在线使用端将在刷新业务配置后同步。', { exact: true }).waitFor();
    assert.equal((await readConfig()).workBusinessEnabled, true); modeRestored = true;
    await pc.evaluate(() => document.dispatchEvent(new Event('visibilitychange')));
    await pc.locator('a[href="#/works"]').first().waitFor();
    await gotoPc('work/' + createdWorkId); await pc.getByText('本地登记 · 只读', { exact: true }).waitFor();
    steps.push('reenable-restores-local-history');
    await admin.getByRole('button', { name: '作业登记', exact: true }).click();
    await admin.getByRole('row').filter({ hasText: workName }).getByRole('button', { name: '取消', exact: true }).click();
    await admin.locator('dialog[open]').getByRole('button', { name: '取消作业', exact: true }).click();
    await admin.getByText('取消作业成功。', { exact: true }).waitFor();
    const archived = await http.get('/api/admin/v1/works/' + createdWorkId); assert.equal((await archived.json()).status, '已取消');
    steps.push('qa-registration-cancelled-and-retained-in-clone');
    assert.deepEqual(errors, []); passed = true;
  } catch (error) {
    if (pc) await pc.screenshot({ path: path.join(output, 'portal-failure.png'), fullPage: true });
    if (admin) await admin.screenshot({ path: path.join(output, 'admin-failure.png'), fullPage: true });
    errors.push(error.message);
    throw error;
  } finally {
    try {
      const config = await readConfig();
      if (!config.workBusinessEnabled) {
        const restored = await http.patch('/api/admin/v1/business-config', { data: { workBusinessEnabled: true, expectedVersion: config.version } });
        assert.equal(restored.status(), 200);
      }
      modeRestored = (await readConfig()).workBusinessEnabled === true;
    } finally {
      fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify({ passed, fixture: false, cloneBaseUrl: session.baseUrl, dailyBackendRequests: 0, createdWorkId, modeRestored, steps, errors }, null, 2));
      await browser.close(); await http.dispose();
    }
  }
  console.log(JSON.stringify({ passed, modeRestored, steps, output }));
}
run().catch(error => { console.error(error.stack); process.exitCode = 1; });
