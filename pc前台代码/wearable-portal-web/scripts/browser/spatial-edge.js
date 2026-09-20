async (page) => {
  const origin = page.url().split('/').slice(0, 3).join('/'), checks = [], errors = []
  const check = (ok, text) => { if (!ok) throw new Error(text); checks.push(text) }
  const button = name => page.getByRole('button', { name, exact: true })
  const go = async path => { await page.goto(origin + '/#' + path); await page.waitForTimeout(1200) }
  const onError = e => errors.push(e.message); page.on('pageerror', onError)
  try {
    await page.reload(); await page.waitForTimeout(900)
    if (await button('用户菜单').count()) { await button('用户菜单').click(); await page.getByText('退出登录', { exact: true }).click() }
    await page.getByLabel('预置身份', { exact: true }).selectOption('owner'); await button('进入系统').click(); await button('用户菜单').waitFor()
    await go('/location?tab=fences&siteId=mock-site-1&selectedId=fence-1-1'); await button('编辑围栏').click()
    const dialog = page.getByRole('dialog', { name: '本地围栏编辑', exact: true })
    const longitude = dialog.getByLabel('经度 1', { exact: true }), initial = await longitude.inputValue()
    await longitude.fill('181'); await longitude.press('Tab'); await button('撤销').click()
    check(await longitude.inputValue() === initial, '节点修改可撤销')
    await longitude.fill('181'); await longitude.press('Tab')
    await dialog.getByLabel('规则', { exact: true }).selectOption('DENY_EXIT'); await dialog.getByLabel('适用对象', { exact: true }).selectOption('HELMET')
    await button('保存围栏').click(); await dialog.getByRole('alert').waitFor()
    check((await dialog.innerText()).includes('有效WGS84'), '非法节点拒绝并保留输入')
    await button('撤销').click()
    await page.getByLabel('当前厂站').selectOption('mock-site-2'); await button('继续编辑').click()
    check(await page.getByLabel('当前厂站').inputValue() === 'mock-site-1', '拒绝切站保留原厂站和草图')
    await page.evaluate(async () => { const { saveScenario } = await import('/src/mock/storage.js'); saveScenario({ module: 'fences', mode: 'failure' }) })
    await button('保存围栏').click(); await dialog.getByText('当前场景不允许修改', { exact: false }).waitFor()
    check(await dialog.getByLabel('围栏名称', { exact: true }).inputValue() === '围栏1', '来源失败不丢弃草稿')
    await page.evaluate(async () => { const { expireSession } = await import('/src/mock/request.js'); expireSession() })
    await button('进入系统').waitFor(); check(!await page.locator('.local-editor:visible').count(), '会话失效直接清理围栏草稿')
    await button('进入系统').click(); await button('用户菜单').waitFor(); await page.reload(); await page.waitForTimeout(1000)
    await go('/location?tab=live&siteId=mock-site-1'); await page.locator('.s2-list-row').first().click(); await page.waitForTimeout(500)
    await page.getByRole('navigation', { name: '工作区导航' }).getByRole('link', { name: '视频', exact: true }).click(); await page.waitForTimeout(700)
    check(page.url().includes('selectedId=device-1-1-helmet'), '位置选择准确携带设备到视频')
    await page.getByRole('navigation', { name: '工作区导航' }).getByRole('link', { name: '轨迹', exact: true }).click(); check(page.url().includes('deviceId=device-1-1-helmet'), '视频携带同一设备到轨迹')
    await page.getByRole('navigation', { name: '工作区导航' }).getByRole('link', { name: '围栏', exact: true }).click(); await page.waitForTimeout(600)
    check((await page.locator('.workspace-navigation').innerText()).includes('不推定设备与围栏关系'), '围栏不伪造设备绑定')
    await page.getByLabel('当前厂站').selectOption('mock-site-2'); await page.waitForTimeout(600)
    check(!(await page.locator('.workspace-navigation').innerText()).includes('device-1-1-helmet'), '切站清理共享设备')
    check(!errors.length, '无脚本错误：' + errors.join(';'))
    return checks
  } finally { page.off('pageerror', onError) }
}
