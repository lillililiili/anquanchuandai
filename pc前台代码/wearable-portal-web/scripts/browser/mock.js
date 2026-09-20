async (page) => {
  // Run via playwright-cli run-code --filename scripts/browser/mock.js.
  // No network interception: exercises the application provider and shared memory.
  const origin = page.url().split('/').slice(0, 3).join('/'), checks = [], errors = [], network = [];
  const verify = (ok, name) => { if (!ok) throw new Error(name); checks.push(name); };
  const onError = e => errors.push(e.message);
  const onRequest = r => { if (!r.url().startsWith(origin + '/') || /\/(dev-api|demo-api|mock-disabled|api\/portal)\//.test(r.url()) || r.method() !== 'GET') network.push(r.url()); };
  page.on('pageerror', onError); page.on('request', onRequest);
  const text = () => page.locator('body').innerText();
  const waitText = value => page.getByText(value, { exact: false }).first().waitFor({ state: 'visible', timeout: 12000 });
  const go = async hash => { await page.goto(origin + '/#' + hash); await page.waitForTimeout(900); };
  const logout = async () => { await page.getByRole('button', { name: '用户菜单' }).click(); await page.getByText('退出登录', { exact: true }).click(); await page.getByRole('button', { name: '进入系统', exact: true }).waitFor(); };
  const login = async role => { await page.getByLabel('预置身份', { exact: true }).selectOption(role); await page.getByRole('button', { name: '进入系统', exact: true }).click(); await page.getByRole('button', { name: '用户菜单' }).waitFor(); await page.waitForTimeout(600); };
  const control = async (module, mode, slow = false) => { await page.getByRole('button', { name: '服务未接入 · 本地工作空间：打开场景控制' }).click(); await page.getByLabel('目标模块').selectOption(module); await page.getByLabel('查询场景').selectOption(mode); await page.getByLabel('该模块下一次查询延迟 3 秒').setChecked(slow); await page.getByRole('button', { name: '应用场景', exact: true }).click(); };
  const storage = () => page.evaluate(async () => { const moduleUrl = performance.getEntriesByType('resource').map(r => r.name).filter(n => new URL(n).pathname === '/src/mock/storage.js').at(-1); const { readDataset } = await import(moduleUrl); return readDataset(); });
  try {
    await go('/personnel');
    if (await page.getByRole('button', { name: '用户菜单' }).count()) await logout();
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.screenshot({ path: 'output/playwright/fe0-login-1440.png' });
    await login('owner'); await go('/personnel'); await waitText('共 25 人');
    verify((await page.getByLabel('当前厂站').locator('option').count()) === 4, '负责人可见三个厂站');
    await page.getByRole('button', { name: '服务未接入 · 本地工作空间：打开场景控制' }).click();
    await page.getByRole('button', { name: '重置本地数据', exact: true }).click();
    await page.getByRole('button', { name: '确认恢复', exact: true }).click();
    await page.getByRole('button', { name: '进入系统', exact: true }).waitFor(); await login('owner'); await go('/personnel');
    await waitText('共 25 人'); const initial = await storage();
    verify(initial.entities.people.length === 50, '内存初始化两个厂站 50 名人员');
    verify((await page.locator('.people-table tbody tr').count()) === 20, '人员第一页 20 条');
    await page.locator('.person-row-button').first().focus(); await page.keyboard.press('Enter'); await waitText('查看完整详情');
    verify(page.url().includes('selectedPersonId='), '键盘选择人员保存到 query');
    await page.getByRole('button', { name: '查看完整详情', exact: true }).click(); await page.locator('.history-table tbody tr').first().waitFor();
    verify(await page.locator('.history-table tbody tr').count() === 10, '人员详情独立历史第一页 10 条');
    await page.locator('.el-pager li').filter({ hasText: /^2$/ }).click(); await page.waitForTimeout(400);
    verify((await text()).includes('经办人'), '人员历史翻页');
    await page.getByRole('link', { name: '← 返回人员列表' }).click(); await waitText('共 25 人');
    await page.locator('.el-pager li').filter({ hasText: /^2$/ }).click(); await page.waitForTimeout(400);
    verify(await page.locator('.people-table tbody tr').count() === 5 && !page.url().includes('selectedPersonId='), '人员翻页清除选择');
    await page.reload(); await waitText('共 25 人'); verify(await page.locator('.people-table tbody tr').count() === 5, '刷新恢复页码和本地会话');
    verify((await storage()).config.mode === 'normal', '刷新恢复初始本地状态');
    await page.getByLabel('当前厂站').selectOption('mock-site-empty'); await waitText('暂无当班人员'); verify((await text()).includes('共 0 人'), '空厂站与未接入区分');
    await page.getByLabel('当前厂站').selectOption('mock-site-1'); await waitText('共 25 人');
    await control('people', 'not-integrated'); await waitText('数据待接入'); verify(!(await text()).includes('共 0 人'), '未接入不显示零人数');
    await control('people', 'failure'); await waitText('预置数据故障'); checks.push('故障不降级为空数据');
    await page.reload(); await waitText('共 25 人'); checks.push('刷新清除故障场景，恢复初始数据');
    await control('people', 'normal', true); await page.getByLabel('当前厂站').selectOption('mock-site-2'); await waitText('人员2-01'); await page.waitForTimeout(3300);
    verify(!(await text()).includes('人员1-01'), '延迟旧请求不能覆盖切换后的厂站');
    await page.getByLabel('当前厂站').selectOption('mock-site-1'); await waitText('共 25 人');
    const routes = [
      ['/personnel', '共 25 人'], ['/location?tab=live', '人员与设备位置'],
      ['/location?tab=fences', '围栏1'], ['/materials', '资料1'],
      ['/video', 'MOCK-1-1-helmet'], ['/video/device-1-1-helmet?siteId=mock-site-1', '单路'],
      ['/alarms', '事件1'], ['/alarms/event-1-1/verification?siteId=mock-site-1', '预置来源记录 1']
    ];
    for (const width of [1440, 1672]) {
      await page.setViewportSize({ width, height: width === 1440 ? 900 : 941 });
      for (let i = 0; i < routes.length; i++) {
        await go(routes[i][0]); await waitText(routes[i][1]);
        verify(!await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1), `无页面横向溢出 ${width} ${routes[i][0]}`);
        verify(!(await text()).includes('接口响应格式异常'), `契约及渲染 ${width} ${routes[i][0]}`);
        await page.screenshot({ path: `output/playwright/fe0-${width}-${i}.png` });
      }
    }
    verify(await page.locator('.event-timeline li').count() === 5, '时间线独立分页');
    await page.locator('.event-detail-primary .el-pager li').filter({ hasText: /^2$/ }).click(); await page.waitForTimeout(400); await waitText('预置来源记录 6'); checks.push('时间线第二页');
    await page.locator('.event-detail-secondary .el-pager li').filter({ hasText: /^2$/ }).click(); await page.waitForTimeout(400); verify((await text()).includes('版本 6'), '核验记录第二页不影响时间线');
    await go('/video'); await waitText('MOCK-1-1-helmet');
    for (const label of ['2×4', '3×3', '1+7']) { await page.getByRole('button', { name: label, exact: true }).click(); await page.waitForTimeout(600); verify(await page.locator('.video-slot').count() === (label === '3×3' ? 9 : 8), '视频布局 ' + label); }
    await go('/location?tab=tracks');
    await page.locator('.s2-device-picker select').selectOption('device-1-1-helmet');
    const base = Date.parse((await storage()).meta.baseTime);
    await page.getByLabel('开始时间（UTC）').fill(new Date(base - 120 * 60000).toISOString().slice(0, 16));
    await page.getByLabel('结束时间（UTC）').fill(new Date(base + 60000).toISOString().slice(0, 16));
    await page.getByRole('button', { name: '查询轨迹', exact: true }).click(); await waitText('本地采样缺口');
    await page.getByRole('button', { name: '播放', exact: true }).click(); await waitText('暂停'); checks.push('轨迹手动查询和真实样例点播放');
    await page.getByRole('button', { name: '停止', exact: true }).click();
    await control('tracks', 'forbidden'); await page.getByRole('button', { name: '查询轨迹', exact: true }).click(); await waitText('当前账号无权查看');
    await control('tracks', 'normal');
    await page.getByRole('button', { name: '服务未接入 · 本地工作空间：打开场景控制' }).click(); await page.getByRole('button', { name: '本地会话失效', exact: true }).click(); await page.getByRole('button', { name: '进入系统', exact: true }).waitFor();
    verify(page.url().includes('redirect='), '会话失效保留安全恢复地址'); await login('reader');
    verify(await page.getByLabel('当前厂站').locator('option').count() === 3, '只读身份两个厂站');
    await go('/alarms/event-1-1/verification?siteId=mock-site-1'); await waitText('当前身份无权查看核验记录');
    verify(await page.locator('.event-timeline li').count() === 5, '核验无权不影响事件及时间线');
    await logout(); await login('verifier'); verify(await page.getByLabel('当前厂站').locator('option').count() === 2, '核验员仅一号厂站');
    await go('/alarms/event-1-1/verification?siteId=mock-site-1'); await page.waitForFunction(() => document.querySelector('.event-verification-form textarea')?.value === '预置现场情况');
    await logout(); await login('owner'); await go('/personnel'); await waitText('共 25 人');
    verify(errors.length === 0, '无页面运行异常：' + errors.join(';'));
    verify(network.length === 0, '无后端、外部服务和写请求：' + network.join(';'));
    return { checks, count: checks.length, errors, network };
  } finally { page.off('pageerror', onError); page.off('request', onRequest); }
}
