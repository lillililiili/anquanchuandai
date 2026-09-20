async (page) => {
  const origin = page.url().includes(':5177') ? 'http://localhost:5177' : 'http://localhost:5176';
  const checks = [], forbidden = [], errors = [], assets = [];
  const verify = (condition, name) => { if (!condition) throw Error(name); checks.push(name); };
  let mode = 'normal', trackCalls = 0;
  const onError = e => errors.push(e.message);
  page.on('pageerror', onError);
  const onResponse = r => { if (/\.(js|css|webp|svg)(\?|$)/.test(r.url()) && r.status() >= 400) assets.push(r.url()); };
  page.on('response', onResponse);
  const ctx = { sites: [{ siteId: 's', name: '合成厂站甲', timeZone: 'UTC' }, { siteId: 's2', name: '合成厂站乙', timeZone: 'UTC' }], selectedSiteId: 's', areas: [], teams: [], shifts: [], availability: { roster: 'NOT_INTEGRATED' }, capabilities: { people: { state: 'UNKNOWN', reasonCode: 'SOURCE_NOT_INTEGRATED' } }, permissions: ['portal:location:read', 'portal:track:read', 'portal:fence:read', 'portal:material:read'] };
  const pos = n => ({ longitude: 110 + n / 1000, latitude: 30 + n / 1000, coordinateSystem: 'WGS84', quality: 'VALID', sourceTime: `2026-09-17T00:0${n}:00Z`, receivedAt: null, source: '隔离测试来源', freshness: n === 0 ? 'STALE' : 'UNKNOWN' });
  const item = (id, siteId, name) => ({ id, siteId, name: mode === 'long' ? name + '用于检查长名称的合成设备资料及关联信息'.repeat(4) : name });
  const material = (id, siteId, type = 'PHOTO') => ({ ...item(id, siteId, '合成资料' + id), type, deviceId: 'd', deviceCode: 'SYN-H-001', source: '隔离测试', capturedAt: null, receivedAt: '2026-09-17T00:01:00Z', personId: null, personName: null, attribution: 'UNKNOWN', workId: null, eventId: null, accessReason: 'FILE_ACCESS_NOT_ENABLED' });
  const fence = (id, siteId) => ({ ...item(id, siteId, '合成围栏' + id), status: 'ENABLED', version: 'v1', rule: null, sourceTime: null, effectiveAt: null, coordinateSystem: 'WGS84', ring: [[110, 30], [110.002, 30], [110.002, 30.002], [110, 30]] });
  const handler = async route => {
    const req = route.request(), raw = req.url();
    const parsed = { origin: raw.match(/^https?:\/\/[^/]+/)?.[0], pathname: raw.split('?')[0].replace(/^https?:\/\/[^/]+/, ''), params: Object.fromEntries((raw.split('?')[1] || '').split('&').filter(Boolean).map(pair => { const [k,v=''] = pair.split('='); return [decodeURIComponent(k), decodeURIComponent(v.replace(/\+/g, ' '))]; })) };
    const url = { ...parsed, searchParams: { get: key => parsed.params[key] || null } };
    if (url.origin !== origin) { forbidden.push(req.url()); return route.abort(); }
    if (!/\/(dev|prod|stage)-api\//.test(url.pathname)) return route.continue();
    const path = url.pathname.replace(/^\/(dev|prod|stage)-api/, ''), site = url.searchParams.get('siteId') || 's';
    let data, status = 200, code = 200;
    const pageData = (items, reason) => ({ state: reason ? 'NOT_INTEGRATED' : 'AVAILABLE', items: reason ? [] : items, total: reason ? null : items.length, reasonCode: reason || null, pageNum: Number(url.searchParams.get('pageNum') || 1), pageSize: Number(url.searchParams.get('pageSize') || 20), scope: { siteId: site } });
    if (req.method() !== 'GET' && !['/login', '/logout'].includes(path)) forbidden.push(req.method() + path);
    if (path === '/captchaImage') return route.fulfill({ json: { code: 200, captchaEnabled: false } });
    if (path === '/login') return route.fulfill({ json: { code: 200, token: 's2-isolated-token' } });
    if (path === '/getInfo') return route.fulfill({ json: { code: 200, user: { userId: 1, userName: 'synthetic', nickName: '隔离测试' }, roles: [], permissions: ctx.permissions } });
    if (path === '/logout') return route.fulfill({ json: { code: 200 } });
    if (path === '/api/portal/v1/context') data = mode === 'no-site' ? { ...ctx, sites: [], selectedSiteId: null, capabilities: { people: { state: 'UNKNOWN', reasonCode: 'SITE_SCOPE_NOT_INTEGRATED' } } } : ctx;
    else if (mode === '401') { code = 401; }
    else if (mode === 'forbidden' && path.includes('/materials')) { code = status = 403; }
    else if (mode === 'detail-failure' && /\/materials\/m[123]$/.test(path)) { code = status = 503; }
    else if (mode === 'failure' && path.endsWith('/locations/latest')) { code = status = 503; }
    else if (path.endsWith('/devices')) data = pageData([{ ...item('d', site, '合成安全帽'), deviceCode: 'SYN-H-001', type: 'HELMET' }]);
    else if (path.endsWith('/locations/latest')) {
      if (url.searchParams.get('keyword') === 'old') await page.waitForTimeout(650);
      const name = url.searchParams.get('keyword') || (site === 's2' ? '厂站乙设备' : '合成位置');
      const rows = [{ ...item('l', site, name), deviceId: 'd', deviceCode: 'SYN-H-001', personId: null, personName: null, attribution: 'UNKNOWN', communication: 'OFFLINE', position: mode === 'invalid-coordinate' ? { ...pos(0), coordinateSystem: 'GCJ02' } : pos(0) }];
      data = pageData(mode === 'empty' ? [] : rows, mode === 'missing' ? 'LOCATION_NOT_INTEGRATED' : null);
    } else if (path.endsWith('/tracks')) {
      trackCalls++;
      data = { state: 'AVAILABLE', data: { ...item('t', site, '合成轨迹'), deviceId: 'd', personId: null, attribution: 'UNKNOWN', from: url.searchParams.get('from'), to: url.searchParams.get('to'), complete: true, segments: [{ segmentId: 'seg1', continuity: 'CONFIRMED', points: [pos(0), pos(1)] }, { segmentId: 'seg2', continuity: 'UNKNOWN', points: [pos(3), pos(4)] }], gaps: [{ from: pos(1).sourceTime, to: pos(3).sourceTime, reason: '来源确认缺口' }] } };
    } else if (path.endsWith('/fences')) data = pageData([fence('f', site)]);
    else if (path.endsWith('/fences/f')) data = fence('f', site);
    else if (path.endsWith('/materials')) { const type = url.searchParams.get('type'); data = pageData([material('m1', site), material('m2', site, 'VIDEO'), material('m3', site, 'AUDIO')].filter(m => !type || m.type === type)); }
    else if (/\/materials\/m[123]$/.test(path)) data = material(path.split('/').at(-1), site);
    else { forbidden.push(path); code = status = 500; }
    try { await route.fulfill({ status, contentType: 'application/json', body: JSON.stringify({ code, data, msg: code === 503 ? '测试来源故障' : code === 403 ? '测试权限拒绝' : '成功', errorCode: code === 200 ? null : 'TEST_' + code, requestId: 's2-test', asOf: '2026-09-17T02:00:00Z' }) }); } catch (e) { if (!req.failure()) throw e; }
  };
  await page.unrouteAll({ behavior: 'wait' });
  await page.route('**/*', handler);
  async function goto(path) { await page.goto('about:blank'); await page.goto(origin + '/#' + path); }
  async function login() { await page.getByRole('textbox', { name: '账号', exact: true }).fill('synthetic'); await page.getByLabel('密码', { exact: true }).fill('isolated-test'); await page.getByRole('button', { name: '登录', exact: true }).click(); }
  async function snap(name, width, height) { await page.setViewportSize({ width, height }); await page.locator('.main-content').evaluate(el => { el.scrollTop = 0; }); await page.screenshot({ path: `output/playwright/s2-${name}-${width}.png` }); verify(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.querySelector('.main-content').scrollWidth <= document.querySelector('.main-content').clientWidth), `${name}无横向溢出 ${width}`); }
  try {
    await goto('/login'); await page.evaluate(() => sessionStorage.removeItem('Wearable-Portal-Token')); await page.reload(); await goto('/location?tab=fences&siteId=s&selectedId=f');
    await page.waitForURL('**/#/login?redirect=**'); await page.getByRole('heading', { name: '工作账号登录' }).waitFor(); verify(page.url().includes('/login?redirect='), 'S2未登录拦截');
    await login(); await page.getByRole('heading', { name: '电子围栏', level: 1 }).waitFor(); await page.locator('.s2-detail').getByText('合成围栏f', { exact: true }).waitFor(); verify(true, '登录恢复标签、厂站及选中围栏');
    verify(await page.getByRole('button', { name: '保存', exact: true }).isDisabled(), '围栏保存禁用');
    for (const [w, h] of [[1672, 941], [1440, 900]]) await snap('F06', w, h);
    await page.getByRole('button', { name: '实时定位', exact: true }).click(); await page.getByRole('button', { name: /合成位置/ }).click();
    verify(await page.getByText('位置数据已过期，请现场核验', { exact: true }).isVisible(), '过期快照明确提示'); verify(await page.getByRole('button', { name: '查看人员', exact: true }).isDisabled(), '未知归属禁止跳人员');
    for (const [w, h] of [[1672, 941], [1440, 900]]) await snap('F10', w, h);
    await page.locator('.s2-position-card').getByRole('button', { name: '历史轨迹', exact: true }).click(); await page.getByRole('button', { name: '查询轨迹', exact: true }).waitFor(); verify(trackCalls === 0, '仅设备跳转不自动查轨迹');
    await page.getByLabel('开始时间（UTC）', { exact: true }).fill('2026-09-17T00:00'); await page.getByLabel('结束时间（UTC）', { exact: true }).fill('2026-09-17T01:00'); await page.getByRole('button', { name: '查询轨迹', exact: true }).click();
    await page.getByText('连续性未知 · 仅离散点', { exact: true }).waitFor(); verify(trackCalls === 1, '轨迹查询及片段展示'); verify(await page.getByRole('heading', { name: '数据缺口', exact: true }).isVisible(), '来源缺口展示');
    await page.getByRole('button', { name: '播放', exact: true }).click(); await page.getByRole('button', { name: '暂停', exact: true }).click(); await page.getByRole('button', { name: '停止', exact: true }).click(); verify(true, '轨迹播放暂停停止');
    for (const [w, h] of [[1672, 941], [1440, 900]]) await snap('F09', w, h);
    await goto('/materials?siteId=s'); await page.locator('.s2-material-card').first().click(); await page.getByText('真实文件访问暂未开放', { exact: true }).waitFor(); verify(await page.getByRole('button', { name: '下载', exact: true }).isDisabled(), '资料无真实下载');
    for (const [w, h] of [[1672, 941], [1440, 900]]) await snap('F05', w, h);
    await page.getByRole('button', { name: '音频', exact: true }).click(); await page.waitForFunction(() => document.querySelectorAll('.s2-material-card').length === 1); verify(await page.locator('.s2-material-card').innerText().then(t => t.includes('音频')), '音频分类'); verify(!page.url().includes('selectedId'), '筛选清理旧选择');
    await page.getByLabel('当前厂站').selectOption('s2'); await page.waitForFunction(() => location.hash.includes('siteId=s2')); verify(!page.url().includes('selectedId') && !page.url().includes('type='), '厂站切换清理筛选与选择');
    await goto('/location?tab=live&siteId=s'); await page.getByRole('button', { name: /合成位置/ }).waitFor();
    await page.getByLabel('名称或标识').fill('old'); await page.getByRole('button', { name: '查询', exact: true }).click(); await page.getByLabel('名称或标识').fill('new'); await page.getByRole('button', { name: '查询', exact: true }).click(); await page.getByRole('button', { name: /new/ }).waitFor(); await page.waitForTimeout(800); verify(await page.getByRole('button', { name: /new/ }).isVisible(), '旧响应不能覆盖新筛选');
    mode = 'empty'; await page.getByRole('button', { name: '刷新快照' }).click(); await page.getByText('暂无位置记录（不代表当班人数为 0）', { exact: true }).waitFor(); verify(true, '空记录不等于空名册');
    mode = 'missing'; await page.getByRole('button', { name: '刷新快照' }).click(); await page.getByText('定位数据待接入', { exact: true }).waitFor(); verify(true, '未接入区别于空记录');
    mode = 'failure'; await page.getByRole('button', { name: '刷新快照' }).click(); await page.getByText('测试来源故障', { exact: true }).waitFor(); verify(await page.getByText(/TEST_503/).isVisible(), '错误码与请求标识保留');
    mode = 'invalid-coordinate'; await page.getByRole('button', { name: '刷新快照' }).click(); await page.getByText('暂无可展示的可靠位置', { exact: true }).waitFor(); verify(true, '未知坐标系不落点');
    mode = 'long'; await goto('/materials?siteId=s'); await page.locator('.s2-material-card').first().focus(); await page.keyboard.press('Enter'); await page.getByText('真实文件访问暂未开放', { exact: true }).waitFor(); verify(true, '资料卡片键盘操作'); await snap('long', 1440, 900);
    mode = 'detail-failure'; await page.locator('.s2-material-card').nth(1).click(); await page.locator('.s2-detail').getByText('测试来源故障', { exact: true }).waitFor(); verify(await page.locator('.s2-material-card').count() === 3, '详情失败不清空列表');
    mode = 'forbidden'; await goto('/materials?siteId=s'); await page.getByText('测试权限拒绝', { exact: true }).waitFor(); verify(true, '无权限独立呈现');
    mode = '401'; await goto('/location?tab=live&siteId=s'); await page.getByRole('heading', { name: '工作账号登录' }).waitFor(); verify(await page.evaluate(() => !sessionStorage.getItem('Wearable-Portal-Token')), '业务401清理会话');
    mode = 'no-site'; await login(); await page.getByRole('heading', { name: '实时定位', level: 1 }).waitFor(); await goto('/location?tab=live'); await page.getByRole('button', { name: '厂站数据待接入' }).waitFor(); verify(await page.getByRole('button', { name: '刷新快照' }).isDisabled(), '无授权厂站不查询数据');
    await snap('missing', 1440, 900);
    verify(forbidden.length === 0, '无外部底图、文件存储或写接口请求'); verify(errors.length === 0, '无浏览器运行异常'); verify(assets.length === 0, '无脚本样式图片资源错误');
    return { passed: checks.length, checks, forbidden, errors, assets };
  } finally { await page.unroute('**/*', handler); page.off('pageerror', onError); page.off('response', onResponse); await goto('/login'); await page.evaluate(() => sessionStorage.removeItem('Wearable-Portal-Token')); await page.reload(); }
}
