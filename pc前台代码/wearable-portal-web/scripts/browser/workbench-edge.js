async (page) => {
  const checks = [], origin = page.url().split('/').slice(0, 3).join('/');
  const check = (ok, name) => { if (!ok) throw new Error(name); checks.push(name); };
  await page.goto(origin + '/#/overview');
  if (await page.getByRole('button', { name: '进入系统', exact: true }).count()) await page.getByRole('button', { name: '进入系统', exact: true }).click();
  await page.locator('.workbench-metrics').waitFor();
  const control = async mode => {
    await page.getByRole('button', { name: '服务未接入 · 本地工作空间：打开场景控制' }).click();
    await page.getByLabel('目标模块').selectOption('events');
    await page.getByLabel('查询场景').selectOption(mode);
    await page.getByRole('button', { name: '应用场景', exact: true }).click();
    await page.waitForTimeout(600);
  };
  for (const [mode, text] of [['failure', '读取失败'], ['not-integrated', '待接入'], ['forbidden', '无权限']]) {
    await control(mode);
    const values = await page.locator('.workbench-metrics strong').allTextContents();
    check(values[0] === '25' && values[2] === text, '首页独立分区 ' + mode);
  }
  await page.reload(); await page.locator('.workbench-metrics').waitFor();
  check((await page.locator('.workbench-metrics strong').allTextContents())[2] === '15', '刷新清除首页异常场景');
  const metric = page.getByRole('button', { name: /^当班人数/ }); await metric.focus(); await page.keyboard.press('Enter');
  await page.getByRole('dialog').waitFor(); check(await page.getByRole('dialog').isVisible(), '键盘打开指标明细');
  await page.keyboard.press('Escape'); await page.getByRole('dialog').waitFor({ state: 'hidden' });
  check(await metric.evaluate(el => document.activeElement === el), '关闭弹窗焦点回到指标');
  await page.getByRole('link', { name: '现场监看', exact: true }).click(); await page.getByRole('heading', { name: '实时定位', exact: true }).waitFor();
  check(await page.locator('.workspace-navigation a[aria-current="page"]').count() === 1, '位置页内导航唯一高亮');
  await page.getByRole('navigation', { name: '工作区导航' }).getByRole('link', { name: '轨迹', exact: true }).click();
  await page.getByRole('heading', { name: '历史轨迹', exact: true }).waitFor();
  check(await page.locator('.workspace-navigation a[aria-current="page"]').count() === 1, '轨迹页内导航唯一高亮');
  await page.getByRole('button', { name: '收起侧栏', exact: true }).click();
  check(await page.getByRole('link', { name: '安全总览', exact: true }).isVisible(), '折叠菜单保留可访问名称');
  await page.getByRole('link', { name: '安全总览', exact: true }).click(); await page.locator('.workbench-metrics').waitFor();
  await page.getByRole('button', { name: '展开侧栏', exact: true }).click();
  return { checks, count: checks.length };
}
