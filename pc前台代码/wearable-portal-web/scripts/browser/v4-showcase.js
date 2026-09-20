async (page) => {
  const origin = page.url().split('/').slice(0, 3).join('/'), errors = [], results = [];
  const onError = error => errors.push(error.message);
  page.on('pageerror', onError);
  for (const path of ['/overview', '/personnel', '/personnel/9007199254740993101', '/equipment', '/video', '/materials', '/supervision', '/alarms', '/dispatch', '/statistics', '/location?tab=live', '/location?tab=tracks', '/location?tab=fences']) {
    await page.goto(origin + '/#' + path + (path.includes('?') ? '&' : '?') + 'siteId=mock-site-1');
    await page.waitForTimeout(path.includes('location') ? 3500 : 650);
    await page.locator('h1').first().waitFor();
    await page.locator('img').evaluateAll(async items => { await Promise.all(items.map(async image => { image.loading = 'eager'; try { await image.decode(); } catch { /* Missing images are reported by the following inspection. */ } })); });
    const images = await page.locator('img').evaluateAll(items => items.filter(i => !i.complete || i.naturalWidth === 0).map(i => i.getAttribute('src')));
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 2);
    const name = path.replace(/[^a-z0-9]+/gi, '-').replace(/^-/, '');
    await page.screenshot({ path: 'output/playwright/v4-' + name + '.png' });
    results.push({ path, imagesMissing: images, horizontalOverflow: overflow });
  }
  for (const width of [1366, 1024, 768, 390]) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto(origin + '/#/overview?siteId=mock-site-1');
    await page.waitForTimeout(600);
    results.push({ width, overflow: await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 2) });
    await page.screenshot({ path: 'output/playwright/v4-overview-' + width + '.png' });
  }
  await page.setViewportSize({ width: 1600, height: 1000 });
  await page.goto(origin + '/#/overview?siteId=mock-site-1');
  page.off('pageerror', onError);
  return { results, errors };
}
