async (page) => {
  const origin = page.url().split('/').slice(0, 3).join('/'), errors = [], results = [];
  const onError = error => errors.push(error.message);
  page.on('pageerror', onError);
  await page.goto(origin + '/#/login');
  await page.getByRole('textbox', { name: '账号', exact: true }).waitFor();
  await page.screenshot({ path: 'output/playwright/v6-login.png' });
  results.push({ path: '/login', overflow: await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 2) });
  if (await page.getByRole('button', { name: '用户菜单' }).count() === 0) {
    await page.getByRole('textbox', { name: '账号', exact: true }).fill('admin');
    await page.getByRole('textbox', { name: '密码', exact: true }).fill('Admin@2026');
    await page.getByRole('button', { name: '登录', exact: true }).click();
    await page.getByRole('button', { name: '用户菜单' }).waitFor();
  }
  for (const path of ['/overview', '/personnel', '/personnel/9007199254740993101', '/equipment', '/video', '/materials', '/supervision', '/alarms', '/dispatch', '/statistics', '/location?tab=live', '/location?tab=tracks', '/location?tab=fences']) {
    await page.goto(origin + '/#' + path + (path.includes('?') ? '&' : '?') + 'siteId=mock-site-1');
    await page.waitForTimeout(path.includes('location') ? 3500 : 650);
    await page.locator('h1').first().waitFor();
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 2);
    const name = path.replace(/[^a-z0-9]+/gi, '-').replace(/^-/, '');
    await page.screenshot({ path: 'output/playwright/v6-' + name + '.png' });
    results.push({ path, horizontalOverflow: overflow });
  }
  await page.goto(origin + '/#/overview?siteId=mock-site-1');
  await page.getByRole('button', { name: /^当班人数/ }).click();
  await page.getByRole('dialog').waitFor();
  await page.screenshot({ path: 'output/playwright/v6-dialog.png' });
  await page.keyboard.press('Escape');
  for (const width of [1440, 1024]) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto(origin + '/#/overview?siteId=mock-site-1');
    await page.waitForTimeout(600);
    results.push({ width, overflow: await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 2) });
    await page.screenshot({ path: 'output/playwright/v6-overview-' + width + '.png' });
    await page.goto(origin + '/#/personnel?siteId=mock-site-1');
    await page.locator('h1').first().waitFor();
    await page.screenshot({ path: 'output/playwright/v6-personnel-' + width + '.png' });
  }
  page.off('pageerror', onError);
  return { results, errors };
}
