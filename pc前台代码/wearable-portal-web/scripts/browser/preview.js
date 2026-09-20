async (page) => {
  const checks = [];
  const errors = [];
  const failedAssets = [];
  const onError = error => errors.push(error.message);
  const onResponse = response => {
    if (/\.(js|css|webp|svg)(\?|$)/.test(response.url()) && response.status() >= 400) failedAssets.push(response.url());
  };
  page.on('pageerror', onError);
  page.on('response', onResponse);
  await page.route('**/prod-api/**', route => {
    const path = route.request().url();
    const data = path.endsWith('/context') ? {code:200,data:{sites:[],selectedSiteId:null,areas:[],teams:[],shifts:[],permissions:[],availability:{roster:'NOT_INTEGRATED',areas:'NOT_INTEGRATED',teams:'NOT_INTEGRATED',shifts:'NOT_INTEGRATED'},capabilities:{people:{state:'UNKNOWN',reasonCode:'SITE_SCOPE_NOT_INTEGRATED'},equipmentHistory:{state:'UNKNOWN',reasonCode:'HISTORY_NOT_INTEGRATED'}}}} : path.endsWith('/captchaImage') ? { code: 200, captchaEnabled: false } : path.endsWith('/login') ? { code: 200, token: 'preview-fixture' } : path.endsWith('/getInfo') ? { code: 200, user: { userName: '预览验收账号' }, roles: [], permissions: [] } : { code: 200 };
    return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(data) });
  });
  await page.goto('http://localhost:5177/#/login');
  await page.getByRole('textbox', { name: '账号', exact: true }).fill('preview-fixture');
  await page.getByRole('textbox', { name: '密码', exact: true }).fill('fixture-only');
  await page.waitForFunction(() => !document.querySelector('.login-submit').disabled);
  await page.getByRole('button', { name: '登录', exact: true }).click();
  await page.getByRole('heading', { name: '综合总览', level: 1 }).waitFor();
  if (!await page.getByRole('button', { name: '管理中心（地址待配置）' }).isDisabled()) throw new Error('生产后台入口未正确禁用');
  checks.push('生产空后台地址禁用');
  for (const title of ['综合总览','人员与装备','作业监护','视频监看','调度通信','定位与轨迹','告警与核验','现场资料','统计追溯']) {
    await page.getByRole('navigation').getByRole('link', { name: title, exact: true }).click();
    await page.getByRole('heading', { name: title === '人员与装备' ? '当班人员与装备' : title, level: 1 }).waitFor();
  }
  checks.push('生产九个懒加载页面');
  await page.getByRole('navigation').getByRole('link', { name: '定位与轨迹', exact: true }).click();
  await page.getByRole('tab', { name: '电子围栏' }).click();
  await page.reload();
  await page.getByRole('tab', { name: '电子围栏' }).waitFor();
  if (await page.getByRole('tab', { name: '电子围栏' }).getAttribute('aria-selected') !== 'true') throw new Error('定位标签刷新未恢复');
  checks.push('生产 hash 深链接刷新');
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.screenshot({ path: 'output/playwright/preview-location-1440.png' });
  if (errors.length || failedAssets.length) throw new Error(JSON.stringify({ errors, failedAssets }));
  checks.push('生产无 JS 运行异常及静态资源404');
  await page.getByRole('button', { name: '用户菜单' }).click();
  await page.getByRole('menuitem', { name: '退出登录' }).click();
  await page.getByRole('heading', { name: '工作账号登录' }).waitFor();
  await page.unroute('**/prod-api/**');
  page.off('pageerror', onError);
  page.off('response', onResponse);
  const old = await page.context().newPage();
  try {
    await old.goto('http://localhost:5175', { waitUntil: 'domcontentloaded', timeout: 60000 });
    await old.locator('input').first().waitFor({ timeout: 60000 });
    if (!(await old.title())) throw new Error('旧 PC 无页面标题');
    checks.push('旧 PC 5175 与新 PC 5176 独立运行');
  } finally { await old.close(); }
  await page.goto('http://localhost:5176/#/login');
  await page.reload();
  await page.getByRole('button', { name: '登录', exact: true }).waitFor();
  return { passed: checks.length, checks, errors, failedAssets };
}
