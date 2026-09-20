async page => {
  const origin = page.url().split('/').slice(0, 3).join('/')
  await page.goto(origin + '/#/supervision/work-1-1?siteId=mock-site-1')
  await page.reload()
  await page.getByRole('button', { name: '查看人形生命体征（本地）', exact: true }).first().click()
  await page.getByRole('button', { name: '收起生命体征', exact: true }).waitFor()
  await page.waitForTimeout(500)
  if (!await page.locator('.work-person svg').count()) throw Error('人形未显示')
  for (const [width, height] of [[1440, 900], [1672, 941]]) {
    await page.setViewportSize({ width, height })
    if (await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)) throw Error('体征展开后横向溢出')
  }
  await page.getByRole('button', { name: '收起生命体征', exact: true }).click()
  return '作业人员生命体征展开、两种视口与收起通过'
}
