async (page) => {
  const origin = page.url().split('/').slice(0, 3).join('/'), checks = [], errors = [], forbidden = []
  const check = (ok, label) => { if (!ok) throw new Error(label); checks.push(label) }
  const error = e => errors.push(e.message)
  const network = r => { if (!r.url().startsWith(origin + '/') || r.method() !== 'GET' || /\/(dev-api|demo-api|api\/portal)\//.test(r.url())) forbidden.push(r.url()) }
  page.on('pageerror', error); page.on('request', network)
  const go = async path => { await page.goto(origin + '/#' + path); await page.waitForTimeout(800) }
  const dialog = () => page.locator('.el-dialog:visible')
  const person = '/personnel/9007199254740993102?siteId=mock-site-1'
  try {
    await page.reload(); await page.waitForTimeout(1000)
    if (await page.getByRole('button', { name: '进入系统', exact: true }).count()) {
      await page.getByLabel('预置身份', { exact: true }).selectOption('owner')
      await page.getByRole('button', { name: '进入系统', exact: true }).click()
      await page.getByRole('button', { name: '用户菜单' }).waitFor()
    }
    await go(person)
    await page.locator('.history-table tbody tr').first().waitFor()
    check(await page.locator('.history-table tbody tr').count() === 2, '刷新恢复种子历史')
    await page.getByRole('button', { name: '领用安全帽', exact: true }).click()
    await dialog().getByLabel('可领用装备').selectOption({ index: 1 })
    for (const width of [1440, 1672]) {
      await page.setViewportSize({ width, height: width === 1440 ? 900 : 941 })
      await page.screenshot({ path: 'output/playwright/v21-dialog-' + width + '.png' })
      check(!await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), '弹窗无横向溢出 ' + width)
      await page.keyboard.press('Tab')
      check(await dialog().evaluate(el => el.contains(document.activeElement)), '弹窗键盘焦点 ' + width)
    }
    await dialog().getByRole('button', { name: '取消', exact: true }).click()
    await page.getByRole('button', { name: '继续编辑', exact: true }).click()
    check(!!await dialog().getByLabel('可领用装备').inputValue(), '取消离开保留选择')
    await dialog().getByRole('button', { name: '确认领用', exact: true }).click()
    await page.waitForTimeout(1000)
    check(await page.locator('.history-table tbody tr').count() === 3, '人员入口领用新增流水')
    check(await page.getByRole('button', { name: '归还安全帽', exact: true }).isEnabled(), '人员当前装备更新')
    await go('/overview?siteId=mock-site-1')
    check((await page.locator('.workbench-metrics strong').allTextContents())[1] === '69', '工作台领用数69')
    await go('/equipment?siteId=mock-site-1&type=HELMET&keyword=MOCK-1-2-helmet')
    check(await page.locator('.equipment-table tbody tr').count() === 1, '装备筛选')
    check((await page.locator('.equipment-table tbody').innerText()).includes('人员1-02'), '设备与人员关系一致')
    for (const width of [1440, 1672]) {
      await page.setViewportSize({ width, height: width === 1440 ? 900 : 941 })
      check(!await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), '装备列表无溢出 ' + width)
      await page.screenshot({ path: 'output/playwright/v21-equipment-' + width + '.png' })
    }
    await page.getByRole('link', { name: '装备详情 →', exact: true }).click(); await page.waitForTimeout(500)
    await page.getByRole('button', { name: '归还安全帽', exact: true }).click()
    await dialog().getByRole('button', { name: '确认归还', exact: true }).click()
    await page.waitForTimeout(800)
    check(await page.getByRole('button', { name: '领用安全帽', exact: true }).isEnabled(), '设备详情归还')
    await go(person)
    check(await page.locator('.history-table tbody tr').count() === 4, '独立归还流水')
    await go('/overview?siteId=mock-site-1')
    check((await page.locator('.workbench-metrics strong').allTextContents())[1] === '68', '工作台恢复68')
    await go('/equipment/device-1-2-helmet?siteId=mock-site-1')
    await page.getByRole('button', { name: '领用安全帽', exact: true }).click()
    await dialog().getByLabel('领用人员').selectOption({ index: 1 })
    await dialog().getByRole('button', { name: '确认领用', exact: true }).click(); await page.waitForTimeout(700)
    check(await page.getByRole('button', { name: '归还安全帽', exact: true }).isEnabled(), '设备入口选择人员领用')
    await page.reload(); await page.waitForTimeout(900)
    check(await page.getByRole('button', { name: '领用安全帽', exact: true }).isEnabled(), '刷新恢复未领用')
    await go('/equipment/device-1-8-helmet?siteId=mock-site-1')
    await page.getByRole('button', { name: '归还安全帽', exact: true }).click(); await page.waitForTimeout(400)
    check((await dialog().innerText()).includes('离线'), '离线提醒可见')
    check(await dialog().getByRole('button', { name: '确认归还', exact: true }).isEnabled(), '离线不阻止归还')
    await dialog().getByRole('button', { name: '取消', exact: true }).click()
    await go('/equipment?siteId=mock-site-1&assignmentState=CONFLICT')
    check(await page.locator('.equipment-table tbody button:disabled').count() === 2, '冲突设备操作禁用')
    await page.getByLabel('当前厂站').selectOption('mock-site-empty'); await page.waitForTimeout(600)
    check((await page.locator('main').innerText()).includes('暂无装备'), '空厂站无伪造数据')
    await page.getByRole('button', { name: '用户菜单' }).click()
    await page.getByText('退出登录', { exact: true }).click()
    await page.getByLabel('预置身份', { exact: true }).selectOption('reader')
    await page.getByRole('button', { name: '进入系统', exact: true }).click(); await page.waitForTimeout(600)
    await go('/equipment/device-1-2-helmet?siteId=mock-site-1')
    check(await page.getByRole('button', { name: '领用安全帽', exact: true }).isDisabled(), '只读身份不能领用')
    check((await page.locator('main').innerText()).includes('仅负责人'), '无权限原因可见')
    check(errors.length === 0, '无页面异常 ' + errors.join(';'))
    check(forbidden.length === 0, '无后端写入或外部网络 ' + forbidden.join(';'))
    return { passed: checks.length, checks }
  } finally { page.off('pageerror', error); page.off('request', network) }
}
