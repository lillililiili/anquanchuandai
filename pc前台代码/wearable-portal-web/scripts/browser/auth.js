async (page) => {
  const checks = [];
  const verify = (condition, message) => { if (!condition) throw new Error(message); checks.push(message); };
  const image = await page.evaluate(() => {
    const canvas = document.createElement('canvas'); canvas.width = 120; canvas.height = 48;
    const ctx = canvas.getContext('2d'); ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, 120, 48); ctx.fillStyle = '#122d54'; ctx.font = 'bold 28px sans-serif'; ctx.fillText('R7K2', 18, 34);
    return canvas.toDataURL('image/jpeg').split(',')[1];
  });
  let captchaCalls = 0, loginCalls = 0, infoCalls = 0, logoutCalls = 0;
  let mode = 'reject';
  let loginBody, authHeader;
  await page.unroute('**/dev-api/**');
  await page.route('**/dev-api/**', async route => {
    const path = route.request().url().split('?')[0];
    let json;
    if (path.endsWith('/captchaImage')) json = { code: 200, captchaEnabled: true, img: image, uuid: `fixture-${++captchaCalls}` };
    else if (path.endsWith('/login')) {
      loginCalls++; loginBody = route.request().postDataJSON();
      await page.waitForTimeout(350);
      json = mode === 'reject' ? { code: 500, msg: '账号或密码不正确（本地验证）' } : { code: 200, token: 'portal-browser-fixture' };
    } else if (path.endsWith('/getInfo')) {
      infoCalls++; authHeader = route.request().headers().authorization;
      json = { code: 200, user: { userId: 999999, userName: 'fixture_user', nickName: '框架验收账号' }, roles: [], permissions: ['fixture:read'] };
    } else if (path.endsWith('/logout')) { logoutCalls++; json = { code: 200 }; }
    else if (path.endsWith('/context')) json = {code:200,data:{sites:[],selectedSiteId:null,areas:[],teams:[],shifts:[],permissions:[],availability:{roster:'NOT_INTEGRATED',areas:'NOT_INTEGRATED',teams:'NOT_INTEGRATED',shifts:'NOT_INTEGRATED'},capabilities:{people:{state:'UNKNOWN',reasonCode:'SITE_SCOPE_NOT_INTEGRATED'},equipmentHistory:{state:'UNKNOWN',reasonCode:'HISTORY_NOT_INTEGRATED'}}}};
    else json = { code: 401, msg: '会话已过期' };
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(json) });
  });
  await page.evaluate(() => sessionStorage.removeItem('Wearable-Portal-Token'));
  await page.goto('about:blank');
  await page.goto('http://localhost:5176/#/location?tab=tracks');
  await page.getByRole('textbox', { name: '图形验证码', exact: true }).waitFor();
  await page.waitForFunction(() => !document.querySelector('.login-submit').disabled);
  await page.getByRole('button', { name: '登录', exact: true }).click();
  await page.getByText('请输入工作账号', { exact: true }).waitFor();
  verify(await page.getByText('请输入工作账号', { exact: true }).isVisible(), '必填表单校验');
  await page.getByRole('textbox', { name: '账号', exact: true }).fill('fixture_user');
  await page.getByRole('textbox', { name: '密码', exact: true }).fill('test-only-password');
  await page.getByRole('button', { name: '显示密码', exact: true }).click();
  verify(await page.locator('input[name=password]').getAttribute('type') === 'text', '密码显隐');
  await page.getByRole('button', { name: '隐藏密码', exact: true }).click();
  await page.getByRole('button', { name: '刷新验证码', exact: true }).click();
  await page.waitForFunction(() => !document.querySelector('.login-submit').disabled);
  verify(captchaCalls === 2, '验证码刷新请求');
  await page.getByRole('textbox', { name: '图形验证码', exact: true }).fill('R7K2');
  await page.getByRole('button', { name: '登录', exact: true }).click();
  verify(await page.getByRole('button', { name: '正在登录…', exact: true }).isDisabled(), '登录提交状态与防重复');
  await page.getByText('账号或密码不正确（本地验证）').waitFor();
  await page.waitForFunction(() => !document.querySelector('.login-submit').disabled);
  verify(captchaCalls === 3 && loginCalls === 1, '失败提示与验证码自动刷新');
  verify(await page.locator('input[name=captcha]').inputValue() === '', '失败后清空旧验证码');
  for (const [width, height] of [[1672, 941], [1440, 900]]) {
    await page.setViewportSize({ width, height });
    await page.screenshot({ path: `output/playwright/login-captcha-${width}.png` });
    verify(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.documentElement.scrollHeight <= innerHeight), `验证码及错误表单布局 ${width}`);
  }
  mode = 'success';
  await page.getByRole('textbox', { name: '图形验证码', exact: true }).fill('R7K2');
  await page.getByRole('button', { name: '登录', exact: true }).click();
  await page.getByRole('heading', { name: '历史轨迹', exact: true, level: 1 }).waitFor();
  verify(page.url().endsWith('/location?tab=tracks'), '登录恢复目标及查询参数');
  verify(loginBody.uuid === 'fixture-3' && loginBody.code === 'R7K2', '登录请求保持 code/uuid 契约');
  verify(authHeader === 'Bearer portal-browser-fixture', 'getInfo 携带 Bearer Token');
  verify(await page.evaluate(() => sessionStorage.getItem('Wearable-Portal-Token') === 'portal-browser-fixture' && !sessionStorage.getItem('Admin-Token')), '前后台 Token 隔离');
  verify(await page.getByRole('button', { name: '历史轨迹', exact: true }).getAttribute('aria-current') === 'page', '定位标签恢复');
  const menus = ['综合总览','人员与装备','作业监护','视频监看','调度通信','定位与轨迹','告警与核验','现场资料','统计追溯'];
  for (const title of menus) {
    await page.getByRole('navigation', { name: '前台主导航' }).getByRole('link', { name: title, exact: true }).click();
    await page.getByRole('heading', { name: ({ '人员与装备': '当班人员与装备', '定位与轨迹': '实时定位', '现场资料': '现场影像资料', '视频监看': '现场视频墙' })[title] || title, exact: true, level: 1 }).waitFor();
    verify(title === '告警与核验' ? await page.locator('.event-table-panel').getByText('厂站数据待接入', { exact: true }).isVisible() : title === '视频监看' ? await page.locator('.video-workspace').getByText('厂站数据待接入', { exact: true }).isVisible() : title === '人员与装备' ? await page.locator('.personnel-table-panel').getByText('厂站数据待接入', { exact: true }).isVisible() : ['定位与轨迹', '现场资料'].includes(title) ? await page.locator('.s2-page').getByText('厂站数据待接入', { exact: true }).first().isVisible() : await page.getByRole('heading', { name: '功能建设中', exact: true }).isVisible(), `${title}懒加载页面`);
  }
  verify(infoCalls === 1, '空角色用户不重复加载 getInfo');
  await page.reload();
  await page.getByRole('heading', { name: '统计追溯', level: 1 }).waitFor();
  verify(infoCalls === 2, '刷新恢复登录和当前路由');
  verify(await page.getByRole('button', { name: '厂站数据待接入' }).isDisabled(), '厂站选择禁用');
  verify((await page.getByRole('link', { name: '管理中心（新窗口，需独立登录）' }).getAttribute('href')).includes('5175'), '管理中心环境变量入口');
  await page.getByRole('navigation').getByRole('link', { name: '综合总览', exact: true }).click();
  for (const [width, height] of [[1672, 941], [1440, 900]]) {
    await page.setViewportSize({ width, height });
    await page.screenshot({ path: `output/playwright/overview-${width}.png` });
    verify(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.documentElement.scrollHeight <= innerHeight && document.querySelector('.main-content').scrollWidth <= document.querySelector('.main-content').clientWidth), `前台布局无溢出 ${width}`);
    await page.getByRole('button', { name: '收起侧栏', exact: true }).click();
    verify(await page.getByRole('navigation').getByRole('link').count() === 9, `侧栏收起保留九个入口 ${width}`);
    await page.screenshot({ path: `output/playwright/collapsed-${width}.png` });
    await page.getByRole('button', { name: '展开侧栏', exact: true }).click();
  }
  await page.goto('http://localhost:5176/#/missing-page');
  await page.getByRole('heading', { name: '页面未找到' }).waitFor();
  await page.goto('http://localhost:5176/#/401');
  await page.getByRole('heading', { name: '访问受限' }).waitFor();
  checks.push('401 与 404 页面');
  await page.getByRole('link', { name: '返回综合总览' }).click();
  await page.getByRole('button', { name: '用户菜单' }).click();
  await page.getByRole('menuitem', { name: '退出登录' }).click();
  await page.getByRole('heading', { name: '工作账号登录' }).waitFor();
  verify(logoutCalls === 1 && await page.evaluate(() => !sessionStorage.getItem('Wearable-Portal-Token')), '退出请求与本机会话清理');
  return { passed: checks.length, checks };
}
