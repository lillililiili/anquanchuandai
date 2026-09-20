async (page) => {
  await page.goto('http://localhost:5176/#/location?tab=tracks');
  await page.getByRole('button', { name: '登录', exact: true }).waitFor();
  if (!page.url().includes('redirect=/location')) throw new Error('未登录拦截未保留目标');
  await page.waitForFunction(() => !document.querySelector('.login-submit').disabled);
  if (await page.locator('input[name=captcha]').count()) throw new Error('真实后端已关闭验证码但页面仍显示');
  for (const [width, height] of [[1672, 941], [1440, 900]]) {
    await page.setViewportSize({ width, height });
    await page.screenshot({ path: `output/playwright/login-real-${width}.png` });
    if (await page.evaluate(() => document.documentElement.scrollWidth > innerWidth || document.documentElement.scrollHeight > innerHeight)) throw new Error(`登录布局溢出 ${width}`);
  }
  console.log('PASS: 真实验证码关闭配置、未登录拦截、目标保留、登录页两个尺寸无溢出');
}
