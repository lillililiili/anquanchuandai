async (page) => {
  const origin = page.url().split('/').slice(0, 3).join('/'), checks = [], errors = [], requests = [];
  const check = (ok, message) => { if (!ok) throw new Error(message); checks.push(message); };
  const onError = e => errors.push(e.message), onRequest = r => { if (!r.url().startsWith(origin + '/') || /\/(dev-api|demo-api|api\/portal)\//.test(r.url()) || r.method() !== 'GET') requests.push(r.url()); };
  page.on('pageerror', onError); page.on('request', onRequest);
  const go = async path => { await page.goto(origin + '/#' + path); await page.waitForTimeout(1000); };
  const login = async role => { await page.getByLabel('预置身份', { exact: true }).selectOption(role); await page.getByRole('button', { name: '进入系统', exact: true }).click(); await page.getByRole('button', { name: '用户菜单' }).waitFor(); };
  const logout = async () => { await page.getByRole('button', { name: '用户菜单' }).click(); await page.getByText('退出登录', { exact: true }).click(); await page.getByRole('button', { name: '进入系统', exact: true }).waitFor(); };
  const ready = () => page.locator('.workbench-metrics strong').first().waitFor();
  try {
    await go('/overview');
    await page.reload();
    await page.getByRole('button', { name: '用户菜单' }).or(page.getByRole('button', { name: '进入系统', exact: true })).waitFor();
    if (await page.getByRole('button', { name: '用户菜单' }).count()) await logout();
    await login('owner'); await go('/overview'); await ready();
    check(await page.locator('.main-nav a').count() === 7, '七个一级菜单');
    for (const width of [1440, 1672]) {
      await page.setViewportSize({ width, height: width === 1440 ? 900 : 941 });
      check((await page.locator('.workbench-metrics strong').allTextContents()).join(',') === '25,68,15,5', '指标口径 ' + width);
      check(!await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), '工作台无横向溢出 ' + width);
      await page.screenshot({ path: `output/playwright/v20-workbench-${width}.png` });
      for (const [name, total] of [['当班人数', 25], ['已领用装备数', 68], ['未完成事件数', 15], ['本人待办数', 5]]) {
        await page.getByRole('button', { name: new RegExp('^' + name) }).click();
        const dialog = page.getByRole('dialog'); await dialog.waitFor();
        check((await dialog.innerText()).includes('共 ' + total + ' 条'), '同口径明细 ' + name + ' ' + width);
        if (total > 20) { await dialog.locator('.el-pager li').filter({ hasText: /^2$/ }).click(); check(await dialog.locator('tbody tr').count() === Math.min(20, total - 20), '明细分页 ' + name + ' ' + width); }
        await page.keyboard.press('Escape'); await dialog.waitFor({ state: 'hidden' });
      }
    }
    await page.getByLabel('当前厂站').selectOption('mock-site-empty'); await page.waitForTimeout(500);
    check((await page.locator('.workbench-metrics strong').allTextContents()).join(',') === '0,0,0,0', '空厂站真实零记录');
    await page.getByLabel('当前厂站').selectOption('mock-site-2'); await page.waitForTimeout(500);
    check((await page.locator('.workbench-metrics strong').allTextContents()).join(',') === '25,68,15,10', '二号站负责人待办');
    await page.getByRole('link', { name: '现场监看', exact: true }).click(); await page.waitForTimeout(500);
    check(page.url().includes('mock-site-2'), '菜单保留厂站');
    await page.getByRole('navigation', { name: '工作区导航' }).getByRole('link', { name: '视频', exact: true }).click(); await page.waitForTimeout(500);
    check(await page.locator('.main-nav a[aria-current="page"]').innerText() === '现场监看', '视频归属现场监看');
    await go('/video/device-1-1-helmet?siteId=mock-site-1');
    check(await page.locator('.main-nav a[aria-current="page"]').innerText() === '现场监看', '单路旧地址归属高亮');
    await page.getByRole('navigation', { name: '工作区导航' }).getByRole('link', { name: '轨迹', exact: true }).click();
    check(page.url().includes('deviceId=device-1-1-helmet'), '监看携带明确设备到轨迹');
    await page.getByLabel('当前厂站').selectOption('mock-site-2'); await page.waitForTimeout(400);
    check(!page.url().includes('device-1-1-helmet'), '切站清除旧设备选择');
    await go('/statistics'); check(await page.locator('.main-nav a[aria-current="page"]').innerText() === '查询分析', '旧统计地址保留');
    await go('/personnel/9007199254740993101?siteId=mock-site-1&returnTo=%2Foverview%3FsiteId%3Dmock-site-1');
    await page.getByRole('link', { name: '← 返回来源页面' }).click(); await ready(); check(page.url().includes('/overview'), '人员详情安全返回工作台');
    await logout(); await login('reader'); await go('/overview'); await ready();
    check(await page.getByRole('button', { name: /^本人待办数/ }).isDisabled(), '只读身份待办禁用');
    check((await page.locator('.workbench').innerText()).includes('当前身份无处置权限'), '无权限不伪装零待办');
    await logout(); await login('verifier'); await go('/overview'); await ready();
    check((await page.locator('.workbench-metrics strong').allTextContents()).join(',') === '25,68,15,5', '核验员本人待办');
    await go('/overview?siteId=mock-site-2'); check(!await page.locator('.workbench-metrics').count(), '未授权站点不显示数量');
    await logout(); await go('/video/device-1-1-helmet?siteId=mock-site-1'); await login('owner');
    await page.waitForTimeout(700); check(page.url().includes('/video/device-1-1-helmet'), '登录恢复旧单路链接');
    await go('/overview'); await ready(); await page.reload(); await ready();
    check((await page.locator('.workbench-metrics strong').allTextContents()).join(',') === '25,68,15,5', '刷新回到初始概况');
    check(!errors.length, '无运行异常：' + errors.join(';')); check(!requests.length, '无业务网络及外部请求：' + requests.join(';'));
    return { count: checks.length, checks, errors, requests };
  } finally { page.off('pageerror', onError); page.off('request', onRequest); }
}
