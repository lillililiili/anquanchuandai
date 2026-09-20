async (page) => {
  const origin = page.url().includes(':5177') ? 'http://localhost:5177' : 'http://localhost:5176';
  const checks = [], forbidden = [], errors = [];
  const verify = (value, name) => { if (!value) throw Error(name); checks.push(name); };
  let mode = 'normal';
  const missing = (reasonCode = 'SOURCE_NOT_INTEGRATED') => ({ state: 'NOT_INTEGRATED', data: null, reasonCode });
  const ctx = { sites: [{ siteId: 's', name: '隔离厂站甲' }, { siteId: 's2', name: '隔离厂站乙' }], selectedSiteId: 's', areas: [], teams: [], shifts: [], availability: { roster: 'NOT_INTEGRATED' }, capabilities: { people: { state: 'UNKNOWN', reasonCode: 'SITE_SCOPE_NOT_INTEGRATED' }, video: { state: 'UNKNOWN' } }, permissions: ['portal:video:read', 'portal:person:read', 'portal:track:read'] };
  const device = (id, site) => ({ deviceId: id, siteId: site, name: (mode === 'long' ? '长名称合成视频设备用于检验文本换行'.repeat(5) : '合成安全帽') + id, deviceCode: 'TEST-' + id, type: 'HELMET', communication: { state: 'ONLINE', sourceTime: null, sourceKind: 'PLATFORM_QUERY' }, video: { state: 'UNKNOWN', verification: 'UNVERIFIED' }, streamState: 'INTERRUPTED', freshness: 'UNKNOWN', sourceTime: null, unavailableReason: 'MEDIA_ACCESS_NOT_ENABLED' });
  const handler = async route => {
    const req = route.request(), raw = req.url(), path = raw.split('?')[0].replace(/^https?:\/\/[^/]+/, '').replace(/^\/(dev|prod|stage)-api/, '');
    if (!raw.startsWith(origin + '/')) { forbidden.push(raw); return route.abort(); }
    if (!/\/(dev|prod|stage)-api\//.test(raw)) return route.continue();
    const q = Object.fromEntries((raw.split('?')[1] || '').split('&').filter(Boolean).map(pair => { const [k,v=''] = pair.split('='); return [decodeURIComponent(k), decodeURIComponent(v.replace(/\+/g, ' '))]; })), site = q.siteId || 's';
    let data, code = 200, status = 200;
    if (path === '/captchaImage') return route.fulfill({ json: { code: 200, captchaEnabled: false } });
    if (path === '/login') return route.fulfill({ json: { code: 200, token: 's3-isolated-token' } });
    if (path === '/getInfo') return route.fulfill({ json: { code: 200, user: { userId: 1, nickName: '隔离测试' }, roles: [], permissions: ctx.permissions } });
    if (path === '/logout') return route.fulfill({ json: { code: 200 } });
    if (req.method() !== 'GET') forbidden.push(req.method() + path);
    if (path.endsWith('/context')) data = mode === 'no-site' ? { ...ctx, sites: [], selectedSiteId: null } : ctx;
    else if (mode === '401') code = 401;
    else if (mode === 'failure') code = status = 503;
    else if (mode === 'forbidden') code = status = 403;
    else if (path.endsWith('/video-sources')) {
      if (q.keyword === 'old') await page.waitForTimeout(500);
      const rows = Array.from({ length: Number(q.pageSize || 8) }, (_, i) => device(q.keyword ? q.keyword + i : 'd' + i, site));
      data = { state: mode === 'missing' ? 'NOT_INTEGRATED' : 'AVAILABLE', reasonCode: mode === 'missing' ? 'VIDEO_NOT_INTEGRATED' : null, items: ['empty', 'missing'].includes(mode) ? [] : rows, total: mode === 'missing' ? null : mode === 'empty' ? 0 : rows.length, pageNum: Number(q.pageNum || 1), pageSize: Number(q.pageSize || 8), scope: { siteId: site }, filters: { areas: missing(), works: missing() }, statistics: missing('STATISTICS_NOT_INTEGRATED') };
    } else if (path.includes('/video-sources/')) {
      const id = path.split('/').at(-1);
      data = { device: device(id, site), person: missing('HISTORICAL_ATTRIBUTION_UNKNOWN'), equipment: missing(), works: missing(), location: { state: 'FORBIDDEN', data: null, reasonCode: 'SECTION_FORBIDDEN' }, events: { state: 'UNAVAILABLE', data: null, reasonCode: 'SOURCE_UNAVAILABLE' }, materials: missing('HISTORICAL_ATTRIBUTION_UNKNOWN') };
    } else { forbidden.push(path); code = status = 500; }
    try { await route.fulfill({ status, json: { code, data, msg: code === 503 ? '测试来源故障' : code === 403 ? '测试权限拒绝' : '成功', errorCode: code === 200 ? null : 'TEST_' + code, requestId: 's3-isolated', asOf: '2026-09-17T00:00:00Z' } }); } catch (e) { if (!req.failure()) throw e; }
  };
  const onError = e => errors.push(e.message);
  page.on('pageerror', onError);
  await page.addInitScript(() => {
    const add = document.addEventListener.bind(document), remove = document.removeEventListener.bind(document), active = new Set();
    document.addEventListener = (kind, fn, ...rest) => { if (kind === 'visibilitychange') active.add(fn); return add(kind, fn, ...rest); };
    document.removeEventListener = (kind, fn, ...rest) => { if (kind === 'visibilitychange') active.delete(fn); return remove(kind, fn, ...rest); };
    window.__s3TestVisibilityListeners = () => active.size;
  });
  await page.unrouteAll({ behavior: 'wait' }); await page.route('**/*', handler);
  async function goto(path) { await page.goto('about:blank'); await page.goto(origin + '/#' + path); }
  async function snap(name, width, height) { await page.setViewportSize({ width, height }); await page.locator('.main-content').evaluate(e => { e.scrollTop = 0; }); await page.screenshot({ path: `output/playwright/s3-${name}-${width}.png` }); verify(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.querySelector('.main-content').scrollWidth <= document.querySelector('.main-content').clientWidth), name + '无横向溢出' + width); }
  try {
    await goto('/video/d0?siteId=s&returnTo=%2Fvideo%3Flayout%3D3x3');
    await page.getByRole('heading', { name: '工作账号登录' }).waitFor();
    await page.getByRole('textbox', { name: '账号', exact: true }).fill('synthetic'); await page.getByLabel('密码', { exact: true }).fill('isolated'); await page.getByRole('button', { name: '登录', exact: true }).click();
    await page.locator('.single-video').waitFor(); verify(page.url().includes('/video/d0?'), '登录恢复单路目标');
    verify(await page.getByRole('button', { name: '抓拍', exact: true }).isDisabled(), '抓拍禁用');
    verify(await page.getByRole('button', { name: '发起音视频通话' }).isDisabled(), '远程指导禁用');
    verify(await page.locator('.video-related').getByText('当前账号无权查看').isVisible(), '关联分区独立无权限');
    for (const [w,h] of [[1672,941],[1440,900]]) await snap('F08', w,h);
    await page.getByRole('link', { name: '← 返回视频墙' }).click(); await page.locator('.video-grid').waitFor(); verify(page.url().includes('layout=3x3'), '返回恢复布局');
    for (const name of ['1+7', '2×4', '3×3']) { await page.getByRole('button', { name, exact: true }).click(); await page.locator('.video-device-tab').first().waitFor(); await page.waitForTimeout(100); verify(await page.locator('.video-slot').count() === (name === '3×3' ? 9 : 8), name + '槽位'); for (const [w,h] of [[1672,941],[1440,900]]) await snap('F04-' + name.replace('×','x'),w,h); }
    verify((await page.locator('.video-statistics').innerText()).includes('待接入'), '统计缺失不补算');
    verify(await page.locator('video[src]').count() === 0, '没有媒体地址或拉流');
    await page.locator('.video-device-tab').nth(2).focus(); await page.keyboard.press('Enter'); verify(page.url().includes('selectedId=d2'), '键盘选择保存在 query');
    await page.clock.install(); await page.getByRole('button', { name: '开启轮播' }).click(); verify(await page.getByRole('button', { name: '停止轮播' }).isVisible(), '轮播显式开启');
    await page.clock.fastForward(30010); await page.waitForTimeout(80); verify(page.url().includes('selectedId=d3'), '30秒轮播只切换主选设备');
    await page.locator('.video-device-tab').first().click(); verify(await page.getByRole('button', { name: '开启轮播' }).isVisible(), '手动选择停止轮播'); await page.clock.resume();
    await page.getByLabel('设备', { exact: true }).fill('old'); await page.getByRole('button', { name: '查询', exact: true }).click(); await page.getByLabel('设备', { exact: true }).fill('new'); await page.getByRole('button', { name: '查询', exact: true }).click(); await page.waitForTimeout(650); verify((await page.locator('.video-device-strip').innerText()).includes('new0') && !(await page.locator('.video-device-strip').innerText()).includes('old0'), '旧响应不能覆盖新筛选');
    await page.getByLabel('当前厂站').selectOption('s2'); await page.waitForTimeout(200); verify(page.url().includes('siteId=s2') && !page.url().includes('keyword='), '切厂站清除筛选和选择');
    for (let i=0;i<4;i++) { await page.getByRole('button', { name: '2×4', exact: true }).click(); await page.getByRole('button', { name: '1+7', exact: true }).click(); }
    await page.waitForTimeout(200); verify(await page.locator('video').count() <= 8, '反复布局切换媒体元素不累积'); verify(await page.evaluate(() => window.__s3TestVisibilityListeners() <= 9), '反复布局切换监听器不累积');
    mode = 'long'; await goto('/video?siteId=s'); await page.locator('.video-grid').waitFor(); await snap('long',1440,900);
    for (const [m, text] of [['empty','当前筛选范围暂无授权视频设备'],['missing','数据待接入'],['failure','测试来源故障'],['forbidden','测试权限拒绝'],['no-site','厂站数据待接入']]) { mode=m; await goto('/video?siteId=' + (m==='no-site'?'':'s')); await page.locator('.video-workspace').getByText(text, { exact: true }).first().waitFor(); checks.push(m+'状态'); }
    mode='normal'; await goto('/video?siteId=s'); await page.locator('.video-grid').waitFor(); mode='401'; await page.getByRole('button',{name:'查询',exact:true}).click(); await page.getByLabel('设备',{exact:true}).fill('expire'); await page.getByRole('button',{name:'查询',exact:true}).click(); await page.getByRole('heading',{name:'工作账号登录'}).waitFor(); verify(await page.evaluate(()=>!sessionStorage.getItem('Wearable-Portal-Token')), '业务401清理会话');
    verify(forbidden.length===0, '无外部媒体、RTC、存储或写请求'); verify(errors.length===0, '无页面异常');
    return { checks, count:checks.length, forbidden, errors };
  } finally { page.off('pageerror',onError); await page.unrouteAll({behavior:'wait'}); await page.evaluate(()=>sessionStorage.removeItem('Wearable-Portal-Token')); await goto('/login'); }
}
