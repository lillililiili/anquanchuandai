async (page) => {
  const checks = [];
  const verify = (condition, message) => { if (!condition) throw new Error(message); checks.push(message); };
  let mode = 'ok';
  let token = 'edge-fixture-1';
  let failCaptcha = false;
  await page.unroute('**/dev-api/**');
  await page.route('**/dev-api/**', async route => {
    const path = route.request().url();
    let data = { code: 200 };
    if (path.endsWith('/captchaImage')) {
      if (failCaptcha) return route.abort('connectionrefused');
      data.captchaEnabled = false;
    } else if (path.endsWith('/login')) {
      if (mode === 'network-login') return route.abort('connectionrefused');
      if (mode === 'timeout') return route.abort('timedout');
      data.token = token;
    } else if (path.endsWith('/getInfo')) {
      if (mode === 'info401') data = { code: 401, msg: '本地会话过期' };
      else if (mode === 'bad-info') data = { code: 200 };
      else data = { code: 200, user: { userName: 'edge_fixture' }, roles: ['operator'], permissions: ['fixture:read'] };
    } else if (path.endsWith('/http401')) {
      return route.fulfill({ status: 401, contentType: 'application/json', body: JSON.stringify({ msg: 'expired' }) });
    } else if (path.endsWith('/business401')) data = { code: 401, msg: 'expired' };
    else if (path.endsWith('/logout') && mode === 'logout-fail') return route.abort('connectionrefused');
    else if (path.endsWith('/context')) data = {code:200,data:{sites:[],selectedSiteId:null,areas:[],teams:[],shifts:[],permissions:[],availability:{roster:'NOT_INTEGRATED',areas:'NOT_INTEGRATED',teams:'NOT_INTEGRATED',shifts:'NOT_INTEGRATED'},capabilities:{people:{state:'UNKNOWN',reasonCode:'SITE_SCOPE_NOT_INTEGRATED'}}}};
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(data) });
  });
  const login = async (redirect = '/overview') => {
    await page.goto(`http://localhost:5176/#/login?redirect=${encodeURIComponent(redirect)}`);
    await page.getByRole('textbox', { name: '账号', exact: true }).fill('edge_fixture');
    await page.getByRole('textbox', { name: '密码', exact: true }).fill('fixture-password');
    await page.waitForFunction(() => !document.querySelector('.login-submit').disabled);
    await page.getByRole('button', { name: '登录', exact: true }).click();
  };
  await page.evaluate(() => sessionStorage.removeItem('Wearable-Portal-Token'));
  await page.reload();
  mode = 'network-login';
  await login();
  await page.getByRole('alert').filter({ hasText: '暂时无法连接后端服务' }).waitFor();
  verify(await page.evaluate(() => !sessionStorage.getItem('Wearable-Portal-Token')), '后端不可达不产生会话');
  mode = 'bad-info';
  await login();
  await page.getByText('用户信息不完整，请联系管理员').waitFor();
  verify(await page.evaluate(() => !sessionStorage.getItem('Wearable-Portal-Token')), 'getInfo 失败回滚登录凭证');
  mode = 'ok';
  await login('https://example.com/unsafe');
  await page.getByRole('heading', { level: 1, name: '综合总览', exact: true }).waitFor();
  verify(page.url().endsWith('/overview'), '拒绝外部返回地址');
  const permissionResult = await page.evaluate(async () => {
    const { hasRole, hasPermission } = await import('/src/utils/permission.js');
    return hasRole('operator') && !hasRole('admin') && hasPermission('fixture:read') && !hasPermission('fixture:write');
  });
  verify(permissionResult, '角色权限保留和工具判断');
  const redirects = await page.evaluate(async () => {
    const { safeRedirect } = await import('/src/router/index.js');
    return ['//evil.example', '/login', '/unknown', '/\\evil', ['bad'], '/location?tab=fences'].map(safeRedirect);
  });
  verify(redirects.slice(0, 5).every(item => item === '/overview') && redirects[5] === '/location?tab=fences', '返回地址白名单');
  await page.evaluate(async () => {
    const moduleUrl = performance.getEntriesByType('resource').find(entry => entry.name.includes('/src/utils/request.js'))?.name || '/src/utils/request.js';
    const { default: request } = await import(moduleUrl);
    await Promise.allSettled([request.get('/http401'), request.get('/business401'), request.get('/business401')]);
  });
  await page.getByRole('heading', { name: '工作账号登录' }).waitFor();
  verify(await page.locator('.el-message').count() === 1, 'HTTP/业务并发401仅提示一次');
  verify(await page.evaluate(() => !sessionStorage.getItem('Wearable-Portal-Token')), '401清理会话并跳登录');
  await login('/video');
  await page.getByRole('heading', { level: 1, name: '现场视频墙', exact: true }).waitFor();
  mode = 'info401';
  await page.reload();
  await page.getByRole('heading', { name: '工作账号登录' }).waitFor();
  verify(page.url().includes('redirect=/video'), '刷新遇到失效会话保留目标');
  mode = 'ok'; token = 'edge-fixture-2';
  await login('/statistics');
  await page.getByRole('heading', { level: 1, name: '统计追溯', exact: true }).waitFor();
  mode = 'logout-fail';
  await page.getByRole('button', { name: '用户菜单' }).click();
  await page.getByRole('menuitem', { name: '退出登录' }).click();
  await page.getByRole('heading', { name: '工作账号登录' }).waitFor();
  verify(await page.evaluate(() => !sessionStorage.getItem('Wearable-Portal-Token')), '退出失败仍清理本机Token');
  await page.getByText('本机登录已退出，服务端退出未确认；请检查网络').waitFor();
  failCaptcha = true;
  await page.reload();
  await page.getByRole('button', { name: '重新获取' }).waitFor();
  verify(await page.getByRole('button', { name: '登录', exact: true }).isDisabled(), '验证码接口不可达禁用登录并可重试');
  failCaptcha = false;
  await page.getByRole('button', { name: '重新获取' }).click();
  await page.waitForFunction(() => !document.querySelector('.login-submit').disabled);
  checks.push('验证码请求恢复');
  await page.unroute('**/dev-api/**');
  await page.goto('http://localhost:5176/#/login');
  await page.reload();
  return { passed: checks.length, checks };
}
