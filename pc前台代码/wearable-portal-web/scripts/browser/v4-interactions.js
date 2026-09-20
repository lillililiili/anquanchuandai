async (page) => {
  const origin = page.url().split('/').slice(0, 3).join('/'), checks = [];
  await page.goto(origin + '/#/location?tab=live&siteId=mock-site-1');
  await page.locator('.s2-map-caption').filter({ hasText: '预置位置' }).waitFor({ timeout: 25000 });
  const mapState = () => page.locator('.amap-scene').evaluate(el => {
    const state = el.__vueParentComponent.setupState;
    return { zoom: state.map.getZoom(), points: state.pointOverlays.length, fences: state.fenceOverlays.length, center: state.map.getCenter().toArray() };
  });
  const before = await mapState();
  if (before.points < 1 || before.fences !== 0 || before.zoom < 10) throw new Error('Map bounds or position-only overlays are incorrect');
  await page.getByRole('button', { name: '放大地图', exact: true }).click();
  await page.waitForTimeout(400);
  if ((await mapState()).zoom <= before.zoom) throw new Error('Zoom control failed');
  await page.getByRole('checkbox', { name: '卫星影像', exact: true }).check();
  await page.waitForTimeout(1000);
  await page.screenshot({ path: 'output/playwright/v4-satellite.png' });
  await page.getByRole('checkbox', { name: '卫星影像', exact: true }).uncheck();
  await page.getByRole('button', { name: '显示全部位置', exact: true }).click();
  checks.push({ map: await mapState(), zoomAndSatellite: 'passed' });
  await page.goto(origin + '/#/video?siteId=mock-site-1');
  await page.getByRole('button', { name: '2×4', exact: true }).click();
  await page.waitForTimeout(700);
  await page.locator('img').evaluateAll(async items => { await Promise.all(items.map(async image => { image.loading = 'eager'; try { await image.decode(); } catch { /* Missing images are reported by the following inspection. */ } })); });
  await page.screenshot({ path: 'output/playwright/v4-video-grid.png' });
  checks.push({ videoGrid: await page.locator('.video-player').count() });
  await page.goto(origin + '/#/overview?siteId=mock-site-1');
  await page.getByRole('button', { name: /^当班人数/ }).click();
  await page.getByRole('dialog').waitFor();
  checks.push({ metricDrill: await page.getByRole('dialog').innerText() });
  await page.keyboard.press('Escape');
  return checks;
}
