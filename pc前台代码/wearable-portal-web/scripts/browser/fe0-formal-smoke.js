async (page) => {
  // Requires test-only CLI routes for captchaImage/login/getInfo/context/logout.
  const errors = [], failedAssets = [], onError = e => errors.push(e.message);
  const onResponse = r => { if (/\.(js|css|webp|svg)(\?|$)/.test(r.url()) && r.status() >= 400) failedAssets.push(r.url()); };
  page.on('pageerror', onError); page.on('response', onResponse);
  const checks = [];
  try {
    await page.getByRole('textbox', { name: '账号', exact: true }).fill('formal-test');
    await page.getByRole('textbox', { name: '密码', exact: true }).fill('fixture-only');
    await page.getByRole('button', { name: '登录', exact: true }).click();
    await page.getByRole('heading', { name: '综合总览', exact: true }).waitFor(); checks.push('正式构建沿用账号密码及 HTTP 认证');
    if (await page.getByRole('button', { name: '服务未接入 · 本地工作空间：打开场景控制' }).count()) throw new Error('Formal build includes mock controls');
    checks.push('正式模式无本地入口');
    for (const name of ['人员与装备', '定位与轨迹', '现场资料', '视频监看', '告警与核验', '作业监护', '调度通信', '统计追溯']) { await page.getByRole('link', { name, exact: true }).click(); await page.waitForTimeout(250); checks.push('正式导航：' + name); }
    await page.getByRole('button', { name: '用户菜单' }).click(); await page.getByRole('menuitem', { name: '退出登录' }).click(); await page.getByRole('heading', { name: '工作账号登录', exact: true }).waitFor(); checks.push('正式退出登录');
    if (errors.length || failedAssets.length) throw new Error(JSON.stringify({ errors, failedAssets }));
    return { checks, count: checks.length, errors, failedAssets };
  } finally { page.off('pageerror', onError); page.off('response', onResponse); }
}
