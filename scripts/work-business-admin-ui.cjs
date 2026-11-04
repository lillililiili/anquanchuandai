// Isolated browser UI test: all API calls are fulfilled by this in-memory fixture.
// The daily backend receives no reads or writes from this browser context.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const output = path.resolve(__dirname, '../output/work-business/admin-ui');
fs.mkdirSync(output, { recursive: true });
const site = { id: 'site-1', name: '测试厂区', enabled: true, timezone: 'Asia/Shanghai' };
const identity = { id: 'demo-system', loginName: 'admin', name: '系统管理员', enabled: true, roleIds: ['system'], credentialVersion: 1 };
const people = ['陈建国', '周明', '李志远'].map((name, i) => ({ id: 'P' + (i + 1), name, code: 'P' + (i + 1), siteId: site.id, active: true }));
let config = { workBusinessEnabled: true, simulatedWatchVisible: true, version: 1 }, works = [];
const state = { revision: 1, sites: [site], accounts: [identity], roles: [{ id: 'system', enabled: true, grants: [{ operations: ['*'], siteIds: [site.id] }] }], people: [], devices: [], organizations: [], areas: [], assignments: [], history: [], dutyShifts: [], audit: [], businessConfig: config };
const errors = [], steps = [], requests = [];
const response = (route, json, status = 200) => route.fulfill({ status, contentType: 'application/json; charset=utf-8', body: JSON.stringify(json) });
async function run() {
  const browser = await chromium.launch({ headless: true, channel: 'msedge' });
  let page;
  try {
    const context = await browser.newContext({ viewport: { width: 1600, height: 1000 } });
    await context.addInitScript(() => {
      sessionStorage.setItem('wearable-admin-token', 'fixture-only');
      sessionStorage.setItem('Wearable-Admin-Mock-Token', 'demo-system');
      sessionStorage.setItem('Wearable-Admin-Mock-Session-Version', '1');
    });
    await context.route('**/api/**', async route => {
      const req = route.request(), url = new URL(req.url()), body = req.postDataJSON();
      requests.push({ method: req.method(), path: url.pathname });
      if (url.pathname === '/api/admin/v1/state') return response(route, { state });
      if (url.pathname === '/api/admin/v1/query') return response(route, { data: { sites: [site], identity } });
      if (url.pathname === '/api/guardian/v1/snapshot') return response(route, { state: { version: 1, people: [], devices: [], bindings: [] } });
      if (url.pathname === '/api/admin/v1/business-config') {
        if (req.method() === 'PATCH') { assert.equal(body.expectedVersion, config.version); config = { ...config, ...body, version: config.version + 1, updatedByName: identity.name, updatedAt: new Date().toISOString() }; }
        return response(route, config);
      }
      if (url.pathname === '/api/admin/v1/works/options') return response(route, { sites: [site], people, businessConfig: config });
      if (url.pathname === '/api/admin/v1/works' && req.method() === 'GET') return response(route, { rows: works, total: works.length, pageNum: 1, pageSize: 10, activeCount: works.filter(w => w.status === '进行中').length, businessConfig: config });
      if (url.pathname === '/api/admin/v1/works' && req.method() === 'POST') {
        assert(config.workBusinessEnabled); assert(body.requestId); assert.equal(body.leader, 'P1'); assert.equal(body.supervisor, 'P2');
        assert.deepEqual(new Set(body.members), new Set(['P1','P2']));
        const row = { ...body, id: 'LOCAL-fixture-1', version: 1, source: 'LOCAL', status: '待开始', participantNames: Object.fromEntries(people.map(p => [p.id,p.name])), timeline: [] };
        works.push(row); return response(route, row);
      }
      if (url.pathname === '/api/admin/v1/works/LOCAL-fixture-1') return response(route, works[0]);
      if (url.pathname === '/api/admin/v1/works/LOCAL-fixture-1/actions') {
        assert(config.workBusinessEnabled); assert.equal(body.expectedVersion, works[0].version);
        works[0] = { ...works[0], status: { start: '进行中', finish: '已结束', cancel: '已取消' }[body.action], version: works[0].version + 1 };
        return response(route, works[0]);
      }
      errors.push('Unexpected API: ' + req.method() + ' ' + url.pathname); return response(route, { message: '未配置测试接口' }, 500);
    });
    page = await context.newPage();
    page.on('pageerror', e => errors.push(e.message));
    await page.goto((process.env.ADMIN_UI_BASE || 'http://127.0.0.1:5183/') + '#/workbusiness?siteId=site-1');
    await page.getByRole('button', { name: '关闭业务', exact: true }).waitFor();
    await page.screenshot({ path: path.join(output,'01-settings.png'), fullPage: true });
    await page.getByRole('button', { name: '作业登记', exact: true }).click();
    await page.getByRole('button', { name: '新增作业', exact: true }).click();
    await page.locator('#work-name').fill('设备平台现场检修');
    await page.locator('#work-area').fill('一号机组检修平台');
    await page.locator('#work-plannedStartAt').fill('2026-11-03T08:00'); await page.locator('#work-plannedStartAt').press('Tab');
    await page.locator('#work-plannedEndAt').fill('2026-11-04T18:00'); await page.locator('#work-plannedEndAt').press('Tab');
    await page.locator('#work-leader').click(); await page.getByRole('option', { name: '陈建国 · P1', exact: true }).click();
    await page.locator('#work-supervisor').click(); await page.getByRole('option', { name: '周明 · P2', exact: true }).click();
    await page.locator('#work-remarks').fill('隔离界面测试，不连接日常后端。');
    await page.screenshot({ path: path.join(output,'02-registration.png'), fullPage: true });
    await page.getByRole('button', { name: '保存登记', exact: true }).click();
    await page.getByText('作业登记已保存。', { exact: true }).waitFor();
    assert.equal(works.length, 1); steps.push('create-work-cross-day-and-automatic-participants');
    await page.getByRole('button', { name: '开始', exact: true }).click();
    await page.locator('dialog[open]').getByRole('button', { name: '开始作业', exact: true }).click();
    await page.getByText('开始作业成功。', { exact: true }).waitFor();
    await page.getByRole('button', { name: '业务设置', exact: true }).click();
    await page.getByRole('button', { name: '关闭业务', exact: true }).click();
    await page.getByText(/目前共有 1 项进行中作业/).waitFor();
    await page.getByRole('button', { name: '确认关闭', exact: true }).click();
    await page.getByRole('button', { name: '开启业务', exact: true }).waitFor();
    await page.getByRole('button', { name: '作业登记', exact: true }).click();
    assert(await page.getByRole('button', { name: '新增作业', exact: true }).isDisabled());
    assert(await page.getByRole('button', { name: '结束', exact: true }).isDisabled());
    assert.equal(works[0].status, '进行中'); steps.push('disable-preserves-running-work-and-locks-writes');
    await page.screenshot({ path: path.join(output,'03-disabled-history.png'), fullPage: true });
    await page.getByRole('button', { name: '详情', exact: true }).click();
    await page.getByText('作业登记详情', { exact: true }).waitFor();
    await page.locator('dialog[open]').getByRole('button', { name: '关闭', exact: true }).click();
    await page.getByRole('button', { name: '业务设置', exact: true }).click();
    await page.getByRole('button', { name: '开启业务', exact: true }).click();
    await page.getByRole('button', { name: '确认开启', exact: true }).click();
    await page.getByRole('button', { name: '关闭业务', exact: true }).waitFor();
    await page.getByRole('button', { name: '作业登记', exact: true }).click();
    await page.getByRole('button', { name: '结束', exact: true }).click();
    await page.getByRole('button', { name: '结束作业', exact: true }).click();
    await page.getByText('结束作业成功。', { exact: true }).waitFor();
    assert.equal(works[0].status, '已结束'); steps.push('reenable-and-manual-finish');
    await page.setViewportSize({ width: 1024, height: 768 });
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'Page must not overflow horizontally');
    assert(await page.locator('.table-scroll').evaluate(el => el.scrollWidth > el.clientWidth), 'Wide table retains its own scroll region');
    await page.screenshot({ path: path.join(output,'04-compact.png'), fullPage: true });
    assert.deepEqual(errors, []);
  } catch (error) {
    if (page) { await page.screenshot({ path: path.join(output, 'failure.png'), fullPage: true }); errors.push({ url: page.url(), body: await page.locator('body').innerText() }); }
    throw error;
  } finally {
    fs.writeFileSync(path.join(output,'result.json'), JSON.stringify({ fixture: true, dailyBackendRequests: 0, steps, errors, requests }, null, 2));
    await browser.close();
  }
  console.log(JSON.stringify({ passed: true, steps, output }));
}
run().catch(error => { console.error(error); process.exitCode = 1; });
