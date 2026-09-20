async (page) => {
  // Development-only fault injection. No application fault switch or HTTP mock.
  const origin = page.url().split('/').slice(0, 3).join('/'), checks = []
  const check = (ok, name) => { if (!ok) throw new Error(name); checks.push(name) }
  const go = async path => { await page.goto(origin + '/#' + path); await page.waitForTimeout(800) }
  const dialog = () => page.locator('.el-dialog:visible')
  const fault = async kind => page.evaluate(async kind => {
    const url = performance.getEntriesByType('resource').map(x => x.name).find(x => new URL(x).pathname === '/src/mock/storage.js')
    const store = await import(url)
    if (kind === 'version') store.transact(d => { d.entities.devices.find(x => x.deviceId === 'device-1-2-helmet').version++ })
    else store.saveScenario({ module: 'equipment', mode: kind, slowNext: false })
  }, kind)
  await page.reload(); await page.waitForTimeout(900)
  if (await page.getByRole('button', { name: '用户菜单' }).count()) {
    await page.getByRole('button', { name: '用户菜单' }).click(); await page.getByText('退出登录', { exact: true }).click()
  }
  await page.getByLabel('预置身份', { exact: true }).selectOption('owner')
  await page.getByRole('button', { name: '进入系统', exact: true }).click(); await page.waitForTimeout(700)
  await go('/personnel/9007199254740993102?siteId=mock-site-1')
  await page.getByRole('button', { name: '领用安全帽', exact: true }).click()
  await dialog().getByLabel('可领用装备').selectOption({ index: 1 })
  const input = await dialog().getByLabel('可领用装备').inputValue()
  await fault('failure')
  await dialog().getByRole('button', { name: '确认领用', exact: true }).click(); await page.waitForTimeout(450)
  check((await dialog().innerText()).includes('操作未提交'), '来源失败明确未提交')
  check(await dialog().getByLabel('可领用装备').inputValue() === input, '失败保留选择')
  await fault('normal'); await fault('version')
  await dialog().getByRole('button', { name: '确认领用', exact: true }).click(); await page.waitForTimeout(450)
  check((await dialog().innerText()).includes('数据版本已变化'), '旧版本提示冲突')
  check(await dialog().getByRole('button', { name: '确认领用', exact: true }).isDisabled(), '冲突不自动重试')
  await dialog().getByRole('button', { name: '重新读取并核对', exact: true }).click(); await page.waitForTimeout(400)
  check(await dialog().getByLabel('可领用装备').inputValue() === input, '重新读取保留仍合法选择')
  await dialog().getByRole('button', { name: '确认领用', exact: true }).click(); await page.waitForTimeout(800)
  await page.waitForFunction(() => document.querySelectorAll('.history-table tbody tr').length === 3, undefined, { timeout: 10000 })
  check(await page.locator('.history-table tbody tr').count() === 3, '两次失败不生成流水')
  await page.getByRole('button', { name: '领用安全带', exact: true }).click()
  await dialog().getByLabel('可领用装备').selectOption({ index: 1 })
  await page.goto(origin + '/#/equipment?siteId=mock-site-2')
  await page.getByRole('button', { name: '继续编辑', exact: true }).click(); await page.waitForTimeout(300)
  check(await page.getByLabel('当前厂站').inputValue() === 'mock-site-1', '拒绝离开不提前切换厂站')
  check(!!await dialog().getByLabel('可领用装备').inputValue(), '离开取消不丢失输入')
  await dialog().getByRole('button', { name: '取消', exact: true }).click()
  await page.getByRole('button', { name: '放弃选择', exact: true }).click(); await page.waitForTimeout(300)
  await page.getByRole('button', { name: '领用安全带', exact: true }).click()
  await dialog().getByLabel('可领用装备').selectOption({ index: 1 })
  await page.evaluate(async () => {
    const url = performance.getEntriesByType('resource').map(x => x.name).find(x => new URL(x).pathname === '/src/mock/request.js')
    const request = await import(url); request.expireSession()
  })
  await page.getByRole('button', { name: '进入系统', exact: true }).waitFor()
  check(await page.locator('.assignment-form:visible').count() === 0, '会话失效直接清空弹窗')
  return { passed: checks.length, checks }
}
