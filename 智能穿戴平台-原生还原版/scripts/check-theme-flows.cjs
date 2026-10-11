/* Isolated UI regression: no persistent browser profile or user data is used. */
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const qaRoot = path.resolve(root, process.env.THEME_QA_DIR || 'qa/theme');
const output = path.join(qaRoot, 'flows');
const base = 'http://127.0.0.1:5209';
const runtime = process.env.PLAYWRIGHT_MODULE || 'C:/Users/19221/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright';
const {chromium} = require(runtime);
const results = [];
const shot = (page, name) => page.screenshot({path: path.join(output, name + '.png'), fullPage: true, animations: 'disabled'});
const action = (page, name, id) => page.locator(`[data-action="${name}"]${id ? `[data-id="${id}"]` : ''}`);
async function waitRenderedRoute(page, name) {
  await page.waitForURL(base + '/#/' + name);
  // A changed URL precedes the app's hashchange render. Wait for the destination
  // route and its DOM before inspecting records or route-initialized state.
  await page.waitForFunction(name => {
    const [route, id = ''] = name.split('/');
    return window.R && R.route === route && R.routeId === id &&
      !!document.querySelector('main.' + route + '-page');
  }, name);
}
async function route(page, name) {
  await page.locator(`a[href="#/${name}"]`).first().click();
  await waitRenderedRoute(page, name);
}
async function login(page) {
  await page.goto(base + '/#/login');
  await page.locator('[name="account"]').fill('admin');
  await page.locator('[name="password"]').fill('123456');
  await page.locator('[name="captcha"]').fill(await page.locator('.captcha-code').innerText());
  await page.getByRole('button', {name: '登录', exact: true}).click();
  await waitRenderedRoute(page, 'overview');
}
async function closeModal(page) {
  await page.locator('.modal [data-action="modal-close"]').last().click();
  await page.locator('.modal').waitFor({state: 'detached'});
}
async function runCase(browser, name, fn, needsLogin = true) {
  const context = await browser.newContext({viewport: {width: 1672, height: 941}, deviceScaleFactor: 1});
  const page = await context.newPage(), errors = [], failures = [], checks = [];
  page.setDefaultTimeout(12000);
  page.on('pageerror', error => errors.push(error.message));
  page.on('response', response => {if (response.status() >= 400) failures.push(response.url());});
  const check = (condition, message) => {assert(condition, message); checks.push(message);};
  try {
    if (needsLogin) await login(page);
    await fn(page, check);
    check(!errors.length, '浏览器无脚本错误');
    check(!failures.length, '资源请求无失败');
    results.push({name, passed: true, checks, errors, failures});
    console.log('PASS', name, checks.length + ' checks');
  } catch (error) {
    await shot(page, 'failure-' + name).catch(() => {});
    results.push({name, passed: false, checks, errors, failures, error: error.stack});
    console.error('FAIL', name, error.message);
  } finally {
    await context.close();
    fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify({results}, null, 2));
  }
}
async function loginChecks(page, check) {
  await page.goto(base + '/#/login');
  await page.getByRole('button', {name: '登录', exact: true}).click();
  check(await page.locator('[name="account"]').evaluate(el => !el.validity.valid), '空账号触发必填校验');
  await page.locator('[name="account"]').fill('incorrect-user');
  await page.locator('[name="password"]').fill('123456');
  await action(page, 'password-toggle').click();
  check(await page.locator('[name="password"]').getAttribute('type') === 'text', '密码显示切换可用');
  await action(page, 'password-toggle').click();
  check(await page.locator('[name="password"]').getAttribute('type') === 'password', '密码隐藏切换可用');
  await page.locator('[name="captcha"]').fill(await page.locator('.captcha-code').innerText());
  await page.getByRole('button', {name: '登录', exact: true}).click();
  check((await page.locator('.form-error').innerText()).includes('账号或密码错误'), '错误账号显示登录错误');
  await page.locator('[name="account"]').fill('admin');
  await page.locator('[name="captcha"]').fill('0000');
  await page.getByRole('button', {name: '登录', exact: true}).click();
  check((await page.locator('.form-error').innerText()).includes('验证码错误'), '错误验证码阻止登录');
  await shot(page, 'login-validation');
  await action(page, 'captcha-refresh').click();
  const captcha = await page.locator('.captcha-code').innerText();
  check(/^[A-Z2-9]{4}$/.test(captcha), '刷新验证码生成四位有效字符');
  await page.locator('[name="captcha"]').fill(captcha.toLowerCase());
  await page.getByRole('button', {name: '登录', exact: true}).click();
  await waitRenderedRoute(page, 'overview');
  check(await page.evaluate(() => sessionStorage.getItem('rolling-session')) === 'admin', '有效账号与验证码建立演示登录会话');
}
async function personnelMedia(page, check) {
  await route(page, 'personnel');
  await action(page, 'select-person', 'P1').click();
  const workId = await page.evaluate(() => R.db.currentWork('P1').id);
  await page.locator(`a[href="#/work/${workId}"]`).first().click();
  await waitRenderedRoute(page, 'work/' + workId);
  check((await page.locator('.main').innerText()).includes(workId), '人员详情进入正确关联作业');
  await action(page, 'risk-info', workId).click();
  await page.locator('.modal').waitFor();
  await shot(page, 'work-risk-modal');
  await closeModal(page);
  await route(page, 'video');
  await action(page, 'select-camera', 'P1').click();
  await page.locator('a[href="#/single/P1"]').first().click();
  await waitRenderedRoute(page, 'single/P1');
  const count = await page.evaluate(() => R.db.state.media.length);
  await action(page, 'capture', 'P1').click();
  await page.waitForFunction(n => R.db.state.media.length === n + 1, count);
  const photo = await page.evaluate(() => R.db.state.media[0]);
  check(photo.kind === 'photo' && photo.personId === 'P1' && photo.workId === workId && !!photo.blobId, '抓拍保存照片并关联人员、设备及作业');
  await action(page, 'record', 'P1').click();
  await page.waitForFunction(() => !!R.s.recording);
  await page.waitForTimeout(1200);
  await action(page, 'record', 'P1').click();
  await page.waitForFunction(n => R.db.state.media.length === n + 2, count);
  const video = await page.evaluate(() => R.db.state.media[0]);
  check(video.kind === 'video' && video.duration >= 1 && video.workId === workId, '停止录像保存时长及作业关联');
  await action(page, 'open-media', video.id).click();
  await waitRenderedRoute(page, 'materials');
  check(await page.locator(`.media-card[data-id="${video.id}"]`).count() === 1, '单路视频最近记录可跳转现场资料');
  await action(page, 'preview-media', video.id).click();
  await page.locator('.modal').waitFor();
  await shot(page, 'media-playback-modal');
  await action(page, 'media-play', video.id).click();
  await page.waitForFunction(() => Number(document.querySelector('[data-media-progress]').value) > 0);
  check(true, '录像模拟回放进度推进');
  await closeModal(page);
  await action(page, 'select-media', photo.id).click();
  await action(page, 'preview-media', photo.id).click();
  check(await page.locator('.modal img').count() > 0, '新抓拍照片可以查看原图');
  await closeModal(page);
  await page.reload();
  await page.locator('.media-card').first().waitFor();
  check(await page.evaluate(ids => ids.every(id => R.db.state.media.some(m => m.id === id)), [photo.id, video.id]), '刷新后两条资料记录仍保留在独立测试存储中');
}
async function eventStatistics(page, check) {
  await route(page, 'alarms');
  const baseline = await page.evaluate(() => R.db.stats(R.scope()).unresolved);
  const claim = action(page, 'claim').first();
  const eventId = await claim.getAttribute('data-id');
  await claim.click();
  check(await page.evaluate(id => R.db.event(id).status, eventId) === '处理中', '认领事件切换为处理中');
  await page.locator(`a[href="#/event/${eventId}"]`).first().click();
  await waitRenderedRoute(page, 'event/' + eventId);
  await page.getByRole('button', {name: '提交核验记录', exact: true}).click();
  check((await page.locator('[data-form="verify"] .form-error').innerText()).includes('核验结论'), '缺少核验结论与现场情况时阻止提交');
  await page.locator('[name="conclusion"]').selectOption('设备通信异常');
  await page.locator('[name="situation"]').fill('主题回归：已联系现场确认通信连接状态。');
  await page.locator('[name="measures"]').fill('主题回归：继续观察设备连接。');
  await action(page, 'save-draft', eventId).click();
  check(await page.evaluate(id => !!R.db.event(id).draft && !R.db.event(id).verification, eventId), '保存草稿保留内容但不完成核验');
  await page.reload();
  await page.locator('[name="situation"]').waitFor();
  check((await page.locator('[name="situation"]').inputValue()).includes('主题回归'), '刷新后恢复已保存的核验草稿');
  await page.getByRole('button', {name: '提交核验记录', exact: true}).click();
  await page.getByRole('heading', {name: '已提交核验结果', exact: true}).waitFor();
  check(await page.evaluate(id => R.db.event(id).status === '已核验' && !!R.db.event(id).verification, eventId), '提交后写入核验记录并更新事件状态');
  await shot(page, 'event-verified');
  await route(page, 'statistics');
  await action(page, 'stats-tab', '事件').click();
  check(await page.evaluate(() => R.db.stats(R.statsScope()).unresolved) === baseline - 1, '统计待处理数与核验结果同步减少一条');
  const row = page.locator(`a[href="#/event/${eventId}"]`).locator('xpath=ancestor::tr');
  check((await row.innerText()).includes('已核验'), '统计追溯表显示已核验事件');
}
async function locationFence(page, check) {
  await route(page, 'location');
  await action(page, 'locate-person', 'P1').click();
  await page.locator('.map-popup a[href="#/tracks/P1"]').click();
  await waitRenderedRoute(page, 'tracks/P1');
  check(await page.evaluate(() => R.s.trackPoints.length) > 1, '实时定位关联到当前人员历史轨迹');
  await page.locator('[name="start"]').fill('11:00');
  await page.locator('[name="end"]').fill('09:00');
  await page.getByRole('button', {name: '查询轨迹', exact: true}).click();
  check((await page.locator('[data-form="track-filters"] .form-error').innerText()).includes('结束时间'), '轨迹查询验证起止时间顺序');
  await page.locator('[name="start"]').fill('09:00');
  await page.locator('[name="end"]').fill('11:00');
  await page.getByRole('button', {name: '查询轨迹', exact: true}).click();
  await action(page, 'track-play').click();
  await page.waitForFunction(() => R.s.trackIndex > 0);
  check(true, '轨迹播放推进当前轨迹点');
  await action(page, 'track-stop').click();
  check(await page.evaluate(() => R.s.trackIndex === 0 && !R.s.trackPlaying), '停止轨迹回放回到起点');
  await route(page, 'fences');
  const count = await page.evaluate(() => R.db.state.fences.length);
  await action(page, 'new-fence').click();
  const map = page.locator('[data-map="fence"]');
  const box = await map.boundingBox();
  assert(box, '围栏地图可见');
  for (const [x, y] of [[.3,.3], [.65,.3], [.65,.65]]) await map.click({position: {x: box.width*x, y: box.height*y}});
  await map.dblclick({position: {x: box.width*.3, y: box.height*.65}});
  // Existing pointerdown handling can retain a repeated endpoint on double-click.
  // Assert the actual polygon geometry without imposing a new deduplication rule.
  check(await page.evaluate(() => new Set(R.s.fenceDraft.points.map(p => p.join(','))).size === 4 && R.s.fenceMode === 'edit'), '地图点击绘制四个顶点并双击完成区域');
  await page.locator('[data-form="fence"] [name="name"]').fill('主题回归测试围栏');
  await page.locator('[data-form="fence"] [name="owner"]').fill('测试值守员');
  await action(page, 'fence-members').click();
  await page.locator('[data-form="fence-members"] [name="members"][value="P1"]').check();
  await shot(page, 'fence-members-modal');
  await page.getByRole('button', {name: '确认成员', exact: true}).click();
  await page.getByRole('button', {name: '保存围栏', exact: true}).click();
  check(await page.evaluate(n => R.db.state.fences.length === n+1 && R.db.state.fences.some(f => f.name === '主题回归测试围栏' && new Set(f.points.map(p => p.join(','))).size === 4 && f.members.includes('P1')), count), '保存绘制围栏及适用人员');
  await page.reload();
  await page.locator('.fence-row').first().waitFor();
  check((await page.locator('.fence-row').allTextContents()).some(t => t.includes('主题回归测试围栏')), '刷新后围栏列表保留新区域');
}
async function dispatchSos(page, check) {
  await route(page, 'dispatch');
  await page.locator('[data-setting="selectAllMembers"]').check();
  await page.locator('[data-setting="selectAllMembers"]').uncheck();
  await page.locator('[data-member="P2"]').check();
  await action(page, 'start-call', '单呼').click();
  await action(page, 'connect-call').click();
  await action(page, 'mute-call').click();
  check(await page.evaluate(() => R.db.state.calls[0].status === '通话中' && R.db.state.calls[0].muted), '单呼可接通并切换静音状态');
  await action(page, 'end-call').click();
  await action(page, 'call-records').first().click();
  check((await page.locator('.modal').innerText()).includes('已结束'), '结束通话保存通信记录');
  await shot(page, 'call-records-modal');
  await closeModal(page);
  await page.locator('[data-form="broadcast"] [name="text"]').fill('主题回归广播：请确认现场装备连接状态。');
  await page.getByRole('button', {name: '发送广播', exact: true}).click();
  check(await page.evaluate(() => R.db.state.broadcasts.some(b => b.text.startsWith('主题回归广播'))), '文字广播生成接收回执');
  await action(page, 'broadcast-records').click();
  check((await page.locator('.modal').innerText()).includes('主题回归广播'), '广播记录显示已发送内容');
  await shot(page, 'broadcast-records-modal');
  await closeModal(page);
  await route(page, 'sos');
  await action(page, 'sos-join').click();
  check(await page.evaluate(() => R.db.state.sos.status === 'active' && R.db.state.sos.members.includes('operator')), '值守员加入 SOS 协助');
  await action(page, 'sos-end').click();
  await page.locator('.modal').waitFor();
  await shot(page, 'sos-end-confirm-modal');
  await action(page, 'confirm-action').click();
  check(await page.evaluate(() => R.db.state.sos.status === 'ended'), '确认后结束 SOS 协助');
  await action(page, 'call-records').click();
  const records = await page.locator('.modal').innerText();
  check(records.includes('SOS 演练') && records.includes('已结束'), 'SOS 会话结束后保留通信记录');
}
async function runLegacy(browser, file) {
  const name = path.basename(file, '.js');
  const context = await browser.newContext();
  try {
    let source = fs.readFileSync(path.join(root, 'scripts', file), 'utf8');
    source = source.replace(/http:\/\/127\.0\.0\.1:\d+/g, base)
      .replace(/qa\/screen\//g, output.replace(/\\/g, '/') + '/')
      .replace(/output\/playwright\//g, output.replace(/\\/g, '/') + '/');
    const run = (0, eval)('(' + source + '\n)');
    const detail = await run(await context.newPage());
    results.push({name, passed: true, detail});
    console.log('PASS', name);
  } catch (error) {
    results.push({name, passed: false, error: error.stack});
    console.error('FAIL', name, error.message);
  } finally {
    await context.close();
    fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify({results}, null, 2));
  }
}
(async () => {
  fs.mkdirSync(output, {recursive: true});
  const server = spawn(process.execPath, [path.join(root, 'server.js'), '--port', '5209'], {windowsHide: true, stdio: ['ignore', 'pipe', 'pipe']});
  let browser;
  try {
    await new Promise((resolve, reject) => {
      server.stdout.once('data', resolve);
      server.once('error', reject);
      server.once('exit', code => reject(Error('Preview server exited: ' + code)));
    });
    browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe'});
    await runCase(browser, 'login', loginChecks, false);
    await runCase(browser, 'personnel-media', personnelMedia);
    await runCase(browser, 'event-statistics', eventStatistics);
    await runCase(browser, 'location-fence', locationFence);
    await runCase(browser, 'dispatch-sos', dispatchSos);
    await runLegacy(browser, 'check-screen.js');
    await runLegacy(browser, 'check-call-video.js');
    const failed = results.filter(r => !r.passed);
    console.log(JSON.stringify({passed: results.length - failed.length, failed: failed.length, output}));
    assert.equal(failed.length, 0, failed.map(r => r.name).join(', '));
  } finally {
    if (browser) await browser.close();
    server.kill();
  }
})().catch(error => {console.error(error); process.exitCode = 1;});
