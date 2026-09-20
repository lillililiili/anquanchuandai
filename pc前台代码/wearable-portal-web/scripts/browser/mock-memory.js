async (page) => {
  const checks = [];
  // Accidental database use must fail, without touching any existing database.
  await page.addInitScript(() => {
    Object.defineProperty(window, 'indexedDB', { configurable: true, get() { throw new Error('IndexedDB forbidden in memory mock test'); } });
  });
  await page.goto('http://127.0.0.1:5179/#/personnel');
  await page.reload();
  await page.waitForTimeout(900);
  if (await page.getByRole('button', { name: '进入系统', exact: true }).count()) await page.getByRole('button', { name: '进入系统', exact: true }).click();
  await page.getByText('共 25 人', { exact: true }).waitFor();
  checks.push('IndexedDB unavailable: simulated login and personnel still work');
  await page.getByRole('button', { name: '服务未接入 · 本地工作空间：打开场景控制' }).click();
  await page.getByLabel('目标模块').selectOption('people');
  await page.getByLabel('查询场景').selectOption('failure');
  await page.getByRole('button', { name: '应用场景', exact: true }).click();
  await page.getByText('预置数据故障', { exact: false }).waitFor();
  await page.getByRole('link', { name: '安全总览', exact: true }).click();
  await page.getByRole('link', { name: '人员装备', exact: true }).click();
  await page.getByText('预置数据故障', { exact: false }).waitFor();
  checks.push('SPA navigation shares the same in-memory dataset');
  await page.reload(); await page.getByText('共 25 人', { exact: true }).waitFor();
  if (await page.getByText('预置数据故障', { exact: false }).count()) throw new Error('Scenario survived reload');
  checks.push('Reload restores seeds and scenarios but keeps simulated login');
  await page.getByRole('button', { name: '服务未接入 · 本地工作空间：打开场景控制' }).click();
  if (await page.getByLabel('查询场景').inputValue() !== 'normal') throw new Error('Scenario was not reset');
  await page.getByRole('button', { name: '重置本地数据', exact: true }).click();
  await page.getByRole('button', { name: '确认恢复', exact: true }).click();
  await page.getByRole('button', { name: '进入系统', exact: true }).waitFor();
  checks.push('Manual reset returns to identity selection');
  return { checks, count: checks.length };
}
