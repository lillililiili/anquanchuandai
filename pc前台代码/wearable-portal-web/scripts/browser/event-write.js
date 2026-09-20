async (page) => {
  const origin = page.url().split('/').slice(0, 3).join('/'), checks = [], errors = [], forbidden = []
  const button = name => page.getByRole('button', { name, exact: true })
  const check = (ok, label) => { if (!ok) throw new Error(label); checks.push(label) }
  const onError = e => errors.push(e.message), network = r => { if (!r.url().startsWith(origin + '/') || r.method() !== 'GET' || /\/(api\/portal|dev-api|demo-api)\//.test(r.url())) forbidden.push(r.url()) }
  page.on('pageerror', onError); page.on('request', network)
  try {
    await page.reload(); await page.getByRole('button', { name: /^(用户菜单|进入系统)$/ }).first().waitFor()
    if (await button('用户菜单').count()) { await button('用户菜单').click(); await page.getByText('退出登录', { exact: true }).click() }
    await page.getByLabel('预置身份', { exact: true }).selectOption('owner'); await button('进入系统').click(); await button('用户菜单').waitFor()
    await page.goto(origin + '/#/alarms/event-1-1/verification?siteId=mock-site-1')
    await button('认领事件').waitFor(); await button('认领事件').click(); await page.locator('.event-phase.PROCESSING').waitFor()
    check(true, '认领后进入处理中')
    await button('转现场核验').click(); await page.locator('.event-phase.AWAITING_VERIFICATION').waitFor()
    await button('编写核验 / 我的草稿').click()
    const dialog = page.getByRole('dialog', { name: '本地核验编辑', exact: true })
    await dialog.getByRole('button', { name: '保存核验草稿', exact: true }).waitFor()
    await dialog.getByLabel('现场情况', { exact: true }).fill('预置现场仍需确认')
    await dialog.getByLabel('核验结论', { exact: true }).selectOption('UNCONFIRMED')
    await button('关闭编辑').click(); await button('继续编辑').click()
    await page.getByRole('dialog', { name: '放弃未保存内容？', exact: true }).waitFor({ state: 'hidden' }); await page.waitForTimeout(350)
    await dialog.locator('.event-editor').evaluate(e => { e.scrollTop = 0 })
    check(await dialog.getByLabel('现场情况', { exact: true }).inputValue() === '预置现场仍需确认', '关闭确认取消保留输入')
    for (const [width, height] of [[1440, 900], [1672, 941]]) {
      await page.setViewportSize({ width, height }); check(!await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), '编辑布局无横向溢出' + width)
      await page.screenshot({ path: 'output/playwright/v24-editor-' + width + '.png' })
    }
    await button('保存核验草稿').click(); await dialog.waitFor({ state: 'hidden' }); await page.locator('.event-phase.AWAITING_VERIFICATION').waitFor()
    await button('编写核验 / 我的草稿').click(); await dialog.getByLabel('现场情况', { exact: true }).waitFor(); await page.waitForTimeout(400)
    check(await dialog.getByLabel('现场情况', { exact: true }).inputValue() === '预置现场仍需确认', '草稿再次打开恢复且阶段不变')
    await button('提交核验').click(); await button('确认操作').click(); await dialog.waitFor({ state: 'hidden' }); await page.locator('.event-phase.AWAITING_VERIFICATION').waitFor()
    await button('完成本地跟进').click(); await button('确认操作').click(); await page.locator('.local-toolbar [role=alert]').waitFor()
    check(true, '无法确认的提交不能完成本地跟进')
    await button('编写核验 / 我的草稿').click(); await page.waitForTimeout(400)
    await dialog.getByLabel('核验结论', { exact: true }).selectOption('ACTION_REQUIRED')
    await dialog.getByLabel('现场情况', { exact: true }).fill('预置已现场核实，需处理')
    await button('提交核验').click(); await button('确认操作').click(); await dialog.getByRole('alert').waitFor()
    check(await dialog.getByLabel('现场情况', { exact: true }).inputValue() === '预置已现场核实，需处理', '缺少措施拒绝并保留输入')
    await dialog.getByLabel('后续措施', { exact: true }).fill('预置措施已记录')
    await button('提交核验').click(); await button('确认操作').click(); await dialog.waitFor({ state: 'hidden' }); await page.locator('.event-phase.AWAITING_VERIFICATION').waitFor()
    check(true, '有效提交仍不自动完成')
    await button('本地回执').click(); await button('摘要本地失败').click(); await page.getByRole('dialog', { name: '本地外部回执（不联网）' }).waitFor({ state: 'hidden' }); await page.locator('.event-phase.AWAITING_VERIFICATION').waitFor()
    await button('本地回执').click(); await button('核验本地成功').click(); await page.getByRole('dialog', { name: '本地外部回执（不联网）' }).waitFor({ state: 'hidden' }); await page.locator('.event-phase.AWAITING_VERIFICATION').waitFor()
    check(true, '两种本地回执不改变跟进阶段')
    await button('完成本地跟进').click(); await button('确认操作').click(); await page.locator('.event-phase.LOCAL_COMPLETED').waitFor()
    check(await button('编写核验 / 我的草稿').isDisabled() && await button('转交事件').isDisabled(), '显式完成后不能重开转交或再提交')
    await page.goto(origin + '/#/alarms?siteId=mock-site-1&mine=true'); await page.locator('.event-table tbody').waitFor()
    check(!await page.locator('.event-table a[href*="/event-1-1/verification"]').count(), '我的待办移除已完成事件')
    await page.reload(); await page.locator('.event-table tbody').waitFor(); await page.goto(origin + '/#/alarms/event-1-1/verification?siteId=mock-site-1'); await page.locator('.event-phase.UNCLAIMED').waitFor()
    check(true, '刷新恢复种子事件')
    check(errors.length === 0, '无脚本错误：' + errors.join(';')); check(forbidden.length === 0, '无真实写请求及外部服务：' + forbidden.join(';'))
    return checks
  } finally { page.off('pageerror', onError); page.off('request', network) }
}
