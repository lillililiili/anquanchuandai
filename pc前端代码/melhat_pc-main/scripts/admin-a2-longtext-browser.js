async (page) => {
  const button = name => page.getByRole('button', { name, exact: true })
  await page.getByRole('navigation', { name: '主导航' }).getByRole('link', { name: '装备资产', exact: true }).click()
  await button('新建设备').click()
  const code = 'DEMO-LONG-' + '1234567890'.repeat(8)
  await page.getByLabel('平台编号', { exact: true }).fill(code)
  await page.getByLabel('设备名称', { exact: true }).fill('演示长名称设备：' + '跨区域设备档案显示校验'.repeat(7))
  await page.getByLabel('备注', { exact: true }).fill('仅演示长文本，不代表真实设备资料。'.repeat(20))
  await button('保存模拟设备').click(); await page.locator('dialog[open] .master-form').waitFor({ state: 'hidden' })
  await page.getByLabel('编号 / SN关键词', { exact: true }).fill('DEMO-LONG'); await button('查询').click(); await page.getByRole('link', { name: code, exact: true }).waitFor()
  for (const [width, height] of [[1440, 900], [1672, 941], [1920, 1080]]) {
    await page.setViewportSize({ width, height }); if (!(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth))) throw new Error('long list overflow')
    await page.screenshot({ path: `output/playwright/admin-a2/long-list-${width}.png` })
  }
  await page.getByRole('link', { name: code, exact: true }).click(); await page.getByText(code, { exact: true }).waitFor()
  for (const [width, height] of [[1440, 900], [1672, 941], [1920, 1080]]) {
    await page.setViewportSize({ width, height }); if (!(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth))) throw new Error('long detail overflow')
    await page.screenshot({ path: `output/playwright/admin-a2/long-detail-${width}.png` })
  }
  return { passed: true, viewports: 3, codeLength: code.length }
}
