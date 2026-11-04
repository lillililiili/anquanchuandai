// Candidate-only browser test. Every API response comes from this in-memory fixture.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const assert = require('node:assert/strict');
const output = path.resolve(__dirname, '../output/work-business/portal-ui');
const base = process.env.PORTAL_UI_BASE || 'http://127.0.0.1:5193/';
fs.mkdirSync(output, { recursive: true });
const errors = [], steps = [], requests = [];

async function run() {
  const { fixtureState } = await import(pathToFileURL(path.resolve(__dirname, '../output/work-business/client-candidate/pc前台项目/tests/fixtures/person-device-data.mjs')));
  const state = fixtureState('belt');
  let config = state.businessConfig;
  Object.assign(state.works[0], { name: 'QA本地登记检修', source: 'LOCAL', status: '进行中' });
  Object.assign(state.events[0], { title: '安全带挂接信号待核验', type: '设备通信', status: '处理中', protocol: 'direct-belt',
    snapshot: { personName: '隔离验收人员', workName: 'QA本地登记检修', supervisorName: '事发监护人' },
    claimedByName: '认领验收人', externalId: 'QA-EXTERNAL-1', externalStatus: '已回传', permissions: { 'events:verify': true, 'events:observe': true } });
  const browser = await chromium.launch({ headless: true, channel: 'msedge' });
  let page;
  try {
    const context = await browser.newContext({ viewport: { width: 1600, height: 1000 } });
    await context.addInitScript(() => {
      sessionStorage.setItem('wearable-guardian-token', 'fixture-only');
      sessionStorage.setItem('rolling-session', 'fixture-only');
      sessionStorage.setItem('rolling-view', JSON.stringify({ viewVersion: 'wearable-person-v2', station: 'S1', person: 'QA-PERSON', event: 'QA-SOS', work: 'QA-WORK', filters: { location: { workId: 'OLD-WORK' }, personnel: { workStatus: 'idle' } }, formDrafts: {} }));
    });
    await context.route('**/*', route => {
      const url = new URL(route.request().url());
      if (url.origin !== new URL(base).origin) return route.abort();
      if (!url.pathname.startsWith('/api/')) return route.continue();
      requests.push({ method: route.request().method(), path: url.pathname });
      const reply = json => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(json) });
      if (url.pathname.endsWith('/business-config')) return reply(config);
      if (url.pathname.endsWith('/snapshot')) return reply({ state: { ...state, businessConfig: config } });
      if (url.pathname.endsWith('/locations/history')) return reply({ rows: [], nextCursor: '' });
      if (url.pathname.endsWith('/mobile/calls') && route.request().method() === 'GET') return reply([]);
      if (url.pathname.includes('/helmet/media')) return reply({ items: [] });
      errors.push('Unexpected API: ' + url.pathname);
      return route.fulfill({ status: 503, contentType: 'application/json', body: '{"message":"隔离浏览器不连接设备"}' });
    });
    page = await context.newPage();
    page.on('pageerror', error => errors.push(error.message));
    const goto = async route => { await page.goto(base + '#/' + route); await page.locator('.connection-notice').waitFor({ state: 'hidden' }); };
    await goto('overview');
    await page.locator('.overview-page').getByText('QA本地登记检修', { exact: true }).waitFor();
    await page.screenshot({ path: path.join(output, '01-enabled-overview.png'), fullPage: true });
    await goto('work/QA-WORK');
    await page.getByText('本地登记 · 只读', { exact: true }).waitFor();
    assert.equal(await page.locator('body').innerText().then(text => text.includes('工作票编号')), false);
    steps.push('local-work-source-and-number');

    await goto('event/QA-SOS');
    await page.locator('textarea[name="situation"]').fill('切换开关时保留的核验草稿');
    config = { ...config, workBusinessEnabled: false, version: 2 };
    await page.evaluate(() => document.dispatchEvent(new Event('visibilitychange')));
    await page.getByText('事发作业监护人', { exact: true }).waitFor({ state: 'hidden' });
    assert.equal(await page.locator('textarea[name="situation"]').inputValue(), '切换开关时保留的核验草稿');
    assert.equal(await page.getByText('原安监系统', { exact: true }).count(), 0);
    assert.equal(await page.getByText('当前现场视频', { exact: true }).count(), 0);
    await page.screenshot({ path: path.join(output, '02-disabled-verification-draft.png'), fullPage: true });
    steps.push('mode-refresh-preserves-verification-draft-and-belt-has-no-video');

    await goto('work/QA-WORK');
    await page.waitForURL('**/#/overview');
    steps.push('old-work-link-returns-overview');
    await goto('personnel?workId=OLD-WORK&tab=%E4%BB%BB%E5%8A%A1&personId=QA-PERSON');
    await page.waitForURL('**/#/personnel?personId=QA-PERSON');
    await page.reload();
    await page.locator('.connection-notice').waitFor({ state: 'hidden' });
    await page.locator('.list-detail-column').getByText('隔离验收人员', { exact: true }).waitFor();
    steps.push('old-query-tabs-and-reloaded-cache-cleared-without-hiding-people');
    const forbidden = /作业监护|当前作业|关联作业|作业编号|作业分组|作业筛选|作业状态|作业信息|作业台账|台账作业|作业关联|待分配作业|工作票|原安监系统|外部系统状态|QA本地登记检修|QA-EXTERNAL-1/;
    for (const route of ['overview', 'personnel', 'person/QA-PERSON', 'video', 'materials', 'location', 'alarms', 'event/QA-SOS', 'statistics', 'dispatch', 'tracks/QA-PERSON', 'fences', 'single/QA-PERSON', 'screen']) {
      await goto(route);
      if (route === 'screen') await page.locator('.screen-stats').waitFor();
      const body = await page.locator('body').innerText();
      assert.doesNotMatch(body, forbidden, route);
      assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), route + ' must not overflow the page horizontally');
      if (route === 'alarms') {
        await page.locator('a.btn.wide').filter({ hasText: /^去核验$/ }).waitFor();
        assert.equal(await page.getByText('现场视频', { exact: true }).count(), 0);
        await page.screenshot({ path: path.join(output, '03-disabled-belt-alarm.png'), fullPage: true });
      }
      if (route === 'screen') {
        assert.equal(await page.locator('.screen-stat').count(), 3);
        await page.screenshot({ path: path.join(output, '04-disabled-screen.png'), fullPage: true });
      }
      steps.push('disabled:' + route);
    }
    config = { ...config, workBusinessEnabled: true, version: 3 };
    await goto('overview');
    await page.evaluate(() => document.dispatchEvent(new Event('visibilitychange')));
    await page.locator('.overview-page').getByText('QA本地登记检修', { exact: true }).waitFor();
    steps.push('reenable-restores-local-work');
    assert.deepEqual(errors, []);
  } catch (error) {
    if (page) { await page.screenshot({ path: path.join(output, 'failure.png'), fullPage: true }); errors.push({ url: page.url(), body: await page.locator('body').innerText() }); }
    throw error;
  } finally {
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify({ fixture: true, dailyBackendRequests: 0, steps, errors, requests }, null, 2));
    await browser.close();
  }
  console.log(JSON.stringify({ passed: true, steps, output }));
}
run().catch(error => { console.error(error); process.exitCode = 1; });
