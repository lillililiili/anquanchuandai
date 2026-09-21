async page => {
  const origin = page.url().split('/').slice(0, 3).join('/'), results = [], errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(origin + '/#/location?tab=fences&siteId=mock-site-1');
  await page.reload();
  await page.locator('.s2-list-row').first().waitFor();
  const state = () => page.locator('.amap-scene').evaluate(el => {
    const s = el.__vueParentComponent.setupState;
    return { points: s.pointOverlays.length, fences: s.fenceOverlays.length, ids: s.props.fences.map(f => f.id), pointIds: s.props.points.map(p => p.recordId), center: s.map.getCenter().toArray() };
  });
  await page.waitForFunction(() => {
    const s = document.querySelector('.amap-scene')?.__vueParentComponent.setupState;
    return s?.fenceOverlays.length === 1 && s.props.fences[0]?.id === 'fence-1-1';
  });
  await page.screenshot({ path: 'output/playwright/selection-fences-overview.png' });
  for (const index of [0, 8, 2]) {
    await page.locator('.s2-list-row').nth(index).click();
    await page.waitForFunction(() => {
      const s = document.querySelector('.amap-scene')?.__vueParentComponent.setupState;
      return s?.fenceOverlays.length === 1 && s.props.fences[0]?.id === new URLSearchParams(location.hash.split('?')[1]).get('selectedId');
    });
    const current = await state();
    if (current.ids[0] !== 'fence-1-' + (index + 1)) throw new Error('Wrong fence selected');
    results.push(current);
  }
  await page.getByRole('button', { name: '下一页', exact: true }).click();
  await page.locator('.s2-list-row').first().click();
  await page.waitForFunction(() => document.querySelector('.amap-scene')?.__vueParentComponent.setupState.props.fences[0]?.id === 'fence-1-21');
  await page.waitForTimeout(500);
  results.push(await state());
  await page.screenshot({ path: 'output/playwright/selection-fence-single.png' });
  await page.goto(origin + '/#/location?tab=live&siteId=mock-site-1');
  await page.locator('.s2-list-row').first().waitFor();
  for (const index of [0, 8, 2]) {
    await page.locator('.s2-list-row').nth(index).click();
    await page.waitForTimeout(700);
    const current = await state();
    if (current.fences !== 0 || current.points !== (index === 0 ? 1 : 0)) throw new Error('Location selection not isolated');
    if (index === 0 && current.pointIds[0] !== '9007199254740993101') throw new Error('Wrong person selected');
    results.push(current);
  }
  await page.locator('.s2-list-row').first().click();
  await page.waitForTimeout(700);
  await page.screenshot({ path: 'output/playwright/selection-person-single.png' });
  if (errors.length) throw new Error(errors.join('\n'));
  return results;
}
