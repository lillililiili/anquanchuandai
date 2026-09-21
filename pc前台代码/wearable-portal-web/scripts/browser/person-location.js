async page => {
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('http://127.0.0.1:5179/#/location?tab=live&siteId=mock-site-1');
  await page.reload();
  await page.locator('.s2-list-row').first().waitFor();
  const names = await page.locator('.s2-list-row > strong').allTextContents();
  if (names.length !== 20 || names.some(n => !n.startsWith('人员'))) throw new Error('List not personnel based');
  const first = page.locator('.s2-list-row').first();
  if (await first.locator('.issued-device').count() !== 3) throw new Error('Missing issued equipment');
  await first.click();
  await page.waitForFunction(() => {
    const s = document.querySelector('.amap-scene')?.__vueParentComponent.setupState;
    return s?.pointOverlays.length === 1 && s.markerSource?.getFeatures().length === 1;
  });
  await page.screenshot({ path: 'output/playwright/person-location-issued.png' });
  await page.locator('.s2-list-row').nth(1).click();
  await page.waitForFunction(() => {
    const s = document.querySelector('.amap-scene')?.__vueParentComponent.setupState;
    return s?.pointOverlays.length === 0 && s.markerSource?.getFeatures().length === 0;
  });
  if (!(await page.locator('.s2-position-card').innerText()).includes('暂无可确认位置')) throw new Error('Missing no-location state');
  if (!(await page.getByRole('button', {name:'历史轨迹',exact:true}).isDisabled())) throw new Error('Track should be unavailable');
  await page.getByRole('button', {name:'下一页',exact:true}).click();
  await page.waitForFunction(() => document.querySelector('.s2-list-row > strong')?.textContent === '人员1-21');
  await page.locator('.s2-list-row').first().click();
  await page.getByPlaceholder('搜索人员姓名 / 编号').fill('人员1-01');
  await page.getByRole('button', {name:'查询',exact:true}).click();
  await page.waitForFunction(() => document.querySelectorAll('.s2-list-row').length === 1);
  await page.locator('.s2-list-row').first().click();
  if (!(await page.locator('.s2-position-card h2').innerText()).includes('人员1-01')) throw new Error('Wrong person');
  await page.setViewportSize({width:390,height:844});
  const widths = await page.evaluate(() => ({ client:document.documentElement.clientWidth, scroll:document.documentElement.scrollWidth }));
  if (widths.scroll > widths.client) throw new Error('Mobile overflow');
  await page.setViewportSize({width:1713,height:950});
  await page.goto('http://127.0.0.1:5179/#/location?tab=live&siteId=mock-site-1');
  await page.locator('.s2-list-row').first().waitFor();
  await page.locator('.s2-list-row').first().click();
  if (errors.length) throw new Error(errors.join('\n'));
  return {names, firstEquipment:await first.locator('.issued-device-summary').innerText(), mobile:widths, errors};
}
