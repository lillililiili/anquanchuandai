async page => {
  const origin = page.url().split('/').slice(0, 3).join('/'), checks = []
  const button = name => page.getByRole('button', { name, exact: true }), check = (ok, label) => { if (!ok) throw new Error(label); checks.push(label) }
  async function identity(role) { await button('用户菜单').click(); await page.getByText('退出登录', { exact: true }).click(); await page.getByLabel('预置身份', { exact: true }).selectOption(role); await button('进入系统').click(); await button('用户菜单').waitFor() }
  await page.reload(); await button('用户菜单').waitFor(); await identity('owner')
  await page.goto(origin + '/#/alarms/event-1-1/verification?siteId=mock-site-1'); await button('认领事件').click(); await page.locator('.event-phase.PROCESSING').waitFor()
  await button('转交事件').click(); await page.getByLabel('转交处置人', { exact: true }).selectOption('mock-verifier'); await button('确认转交').click(); await button('确认操作').click(); await page.getByRole('dialog', { name: '本地事件转交' }).waitFor({ state: 'hidden' }); await page.locator('.event-phase.PROCESSING').waitFor()
  check(await button('转现场核验').isDisabled(), '转交后原负责人不能推进阶段')
  await identity('verifier'); await page.goto(origin + '/#/alarms/event-1-1/verification?siteId=mock-site-1'); await button('转现场核验').click(); await page.locator('.event-phase.AWAITING_VERIFICATION').waitFor()
  await button('编写核验 / 我的草稿').click(); const dialog = page.getByRole('dialog', { name: '本地核验编辑', exact: true })
  await dialog.getByLabel('现场情况', { exact: true }).fill('核验员键盘验证')
  await dialog.getByLabel('核验结论', { exact: true }).selectOption('COMMUNICATION_ISSUE')
  await dialog.getByRole('radio').first().focus(); await page.keyboard.press('Space'); await button('加入核验证据').click()
  check(await dialog.locator('li').filter({ hasText: '版本1' }).count() === 1, '键盘选择资料并加入证据')
  await button('提交核验').click(); await button('确认操作').click(); await dialog.waitFor({ state: 'hidden' }); await page.locator('.event-phase.AWAITING_VERIFICATION').waitFor()
  await page.waitForFunction(() => document.querySelector('.event-verification-form textarea')?.value === '核验员键盘验证')
  check(await page.locator('.event-verification-form textarea').first().getAttribute('readonly') !== null, '已提交核验记录只读')
  for (const [width, height] of [[1440, 900], [1672, 941]]) { await page.setViewportSize({ width, height }); check(!await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), '详情布局无横向溢出' + width); await page.screenshot({ path: 'output/playwright/v24-detail-' + width + '.png' }) }
  await identity('reader'); await page.goto(origin + '/#/alarms/event-1-1/verification?siteId=mock-site-1'); await button('认领事件').waitFor()
  check(await button('认领事件').isDisabled() && await button('编写核验 / 我的草稿').isDisabled(), '只读身份无操作入口')
  await page.goto(origin + '/#/alarms?siteId=mock-site-1'); await button('我的待办').waitFor(); check(await button('我的待办').isDisabled(), '只读身份不能切换处置待办')
  return checks
}
