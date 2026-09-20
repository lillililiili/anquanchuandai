async (page) => {
  const origin = page.url().split('/').slice(0, 3).join('/'), checks = [], errors = [], network = []
  const check = (ok, label) => { if (!ok) throw new Error(label); checks.push(label) }
  const onError = e => errors.push(e.message), onRequest = r => { if (!r.url().startsWith('blob:') && (!r.url().startsWith(origin + '/') || r.method() !== 'GET' || /\/(dev-api|demo-api|api\/portal)\//.test(r.url()))) network.push(r.url()) }
  page.on('pageerror', onError); page.on('request', onRequest)
  const button = name => page.getByRole('button', { name, exact: true })
  const go = async path => { await page.goto(origin + '/#' + path); await page.waitForTimeout(1100) }
  const dialog = title => page.getByRole('dialog', { name: title, exact: true })
  const login = async role => { await page.getByLabel('预置身份', { exact: true }).selectOption(role); await button('进入系统').click(); await button('用户菜单').waitFor() }
  try {
    await page.reload(); await page.waitForTimeout(900)
    await page.getByRole('button', { name: /^(用户菜单|进入系统)$/ }).first().waitFor()
    if (await button('用户菜单').count()) { await button('用户菜单').click(); await page.getByText('退出登录', { exact: true }).click() }
    await login('owner'); await go('/location?tab=fences&siteId=mock-site-1')
    await button('新建围栏').click()
    const editor = dialog('本地围栏编辑')
    await editor.getByLabel('围栏名称', { exact: true }).fill('预置V2-2围栏')
    await editor.getByLabel('规则', { exact: true }).selectOption('DENY_ENTRY')
    await editor.getByLabel('适用对象', { exact: true }).selectOption('ALL')
    for (const [index, p] of [[0, [116.31, 39.9]], [1, [116.32, 39.9]], [2, [116.32, 39.91]]]) {
      await button('添加坐标节点').click()
      await editor.getByLabel('经度 ' + (index + 1), { exact: true }).fill(String(p[0])); await editor.getByLabel('纬度 ' + (index + 1), { exact: true }).fill(String(p[1])); await editor.getByLabel('纬度 ' + (index + 1), { exact: true }).press('Tab')
    }
    await button('定位到草图').click()
    for (const width of [1440, 1672]) {
      await page.setViewportSize({ width, height: width === 1440 ? 900 : 941 })
      check(await editor.evaluate(el => el.scrollWidth <= el.clientWidth), '围栏弹窗无溢出' + width)
      await page.screenshot({ path: 'output/playwright/v22-fence-' + width + '.png' })
    }
    await button('取消编辑').click(); await button('继续编辑').click()
    check(await editor.getByLabel('围栏名称', { exact: true }).inputValue() === '预置V2-2围栏', '拒绝离开保留编辑')
    await button('保存围栏').click(); await editor.waitFor({ state: 'hidden' })
    await page.locator('.s2-list-row').filter({ hasText: '预置V2-2围栏' }).click(); await page.waitForTimeout(500)
    await button('启用围栏').click(); await button('停用围栏').waitFor()
    await button('历史版本').click(); await dialog('围栏版本历史（只读）').waitFor()
    check(await page.locator('.local-versions li').count() === 2, '保存与启停生成两版本')
    await page.keyboard.press('Escape'); await dialog('围栏版本历史（只读）').waitFor({ state: 'hidden' })
    await button('删除围栏').click(); await button('确认删除').click(); await page.waitForTimeout(700)
    await button('历史版本').click(); await dialog('围栏版本历史（只读）').waitFor(); check(await page.locator('.local-versions li').count() === 3, '删除保留第三版本')
    await page.keyboard.press('Escape'); await dialog('围栏版本历史（只读）').waitFor({ state: 'hidden' })
    await go('/materials?siteId=mock-site-1')
    await page.locator('.s2-material-card').filter({ hasText: /^资料1\b/ }).count().catch(() => 0)
    await button('导入本地资料').click()
    const importer = dialog('导入本地资料（仅内存）')
    await importer.getByLabel('本地文件').evaluate(input => { const transfer = new DataTransfer(); transfer.items.add(new File(['<html>bad</html>'], 'bad.png', { type: 'image/png' })); input.files = transfer.files; input.dispatchEvent(new Event('change', { bubbles: true })) })
    await button('确认导入').click(); await importer.getByRole('alert').waitFor()
    check((await importer.innerText()).includes('不一致'), '伪装文件拒绝且弹窗保留')
    const png = await page.evaluate(() => { const c = document.createElement('canvas'); c.width = 320; c.height = 180; const g = c.getContext('2d'); g.fillStyle = '#08314a'; g.fillRect(0, 0, 320, 180); g.fillStyle = '#76dfff'; g.font = '22px sans-serif'; g.fillText('MOCK V2-2', 65, 95); return c.toDataURL('image/png').split(',')[1] })
    await importer.getByLabel('本地文件').evaluate((input, data) => { const transfer = new DataTransfer(); transfer.items.add(new File([Uint8Array.from(atob(data), c => c.charCodeAt(0))], '预置本地图片.png', { type: 'image/png' })); input.files = transfer.files; input.dispatchEvent(new Event('change', { bubbles: true })) }, png)
    await button('确认导入').click(); await importer.waitFor({ state: 'hidden', timeout: 20000 })
    const card = page.locator('.s2-material-card').filter({ hasText: '预置本地图片.png' }); await card.click()
    await button('预览所选资料').waitFor(); await page.waitForTimeout(450); await button('预览所选资料').click()
    const preview = dialog('本地内存资料预览'); await preview.locator('img').waitFor()
    check(await preview.locator('img').evaluate(i => i.complete && i.naturalWidth === 320), '图片真实解码与预览')
    await page.keyboard.press('Escape'); await preview.waitFor({ state: 'hidden' })
    await page.evaluate(() => {
      const action = [...document.querySelectorAll('button')].find(b => b.textContent.trim() === '预览所选资料')
      action.click()
      ;[...document.querySelectorAll('.s2-material-card')].find(c => !c.textContent.includes('预置本地图片.png')).click()
    })
    await page.waitForTimeout(700)
    check(!await preview.isVisible(), '切换资料不被迟到预览重新打开')
    await card.click(); await page.waitForTimeout(500)
    const downloadPromise = page.waitForEvent('download'); await button('下载所选资料').click(); const download = await downloadPromise
    check(download.suggestedFilename() === '预置本地图片.png', '下载本地文件')
    await button('人工关联').click(); await dialog('人工关联').getByLabel('关联人员').selectOption('9007199254740993101')
    await button('保存人工关联').click(); await dialog('人工关联').waitFor({ state: 'hidden' }); await page.waitForTimeout(450)
    check((await page.locator('.s2-detail').innerText()).includes('人工关联'), '人工关联不冒充历史证据')
    await button('选择事件证据').click(); const evidence = dialog('冻结事件证据引用')
    await evidence.getByLabel('关联事件', { exact: true }).selectOption('event-1-1')
    await evidence.getByRole('radio', { name: /预置本地图片.png/ }).check(); await button('冻结引用').click(); await evidence.waitFor({ state: 'hidden' }); await page.waitForTimeout(500)
    check(await button('删除资料').isDisabled() && await button('人工关联').isDisabled(), '冻结版本禁止改删')
    for (const width of [1440, 1672]) {
      await page.setViewportSize({ width, height: width === 1440 ? 900 : 941 })
      check(!await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), '资料页面无溢出' + width)
      await page.screenshot({ path: 'output/playwright/v22-materials-' + width + '.png' })
    }
    await go('/alarms/event-1-1/verification?siteId=mock-site-1'); await page.getByText('预置本地图片.png', { exact: true }).waitFor()
    check((await page.locator('.event-evidence').first().innerText()).includes('人工关联'), '事件查看冻结证据及人工来源')
    await go('/materials?siteId=mock-site-1'); await page.locator('.s2-material-card').filter({ hasText: '预置本地图片.png' }).waitFor()
    await page.reload(); await page.waitForTimeout(1200)
    check(!await page.locator('.s2-material-card').filter({ hasText: '预置本地图片.png' }).count(), '刷新同时清理导入元数据与文件')
    await go('/video?siteId=mock-site-1&selectedId=device-1-1-watch'); await page.getByText('所选设备不在当前页', { exact: false }).waitFor()
    check(!await page.locator('.video-slot.is-selected').count(), '无视频映射不替换为第一设备')
    await button('用户菜单').click(); await page.getByText('退出登录', { exact: true }).click(); await login('reader')
    await go('/materials?siteId=mock-site-1'); check(await button('导入本地资料').isDisabled(), '只读身份不能导入')
    await go('/location?tab=fences&siteId=mock-site-1'); check(await button('新建围栏').isDisabled(), '只读身份不能编辑围栏')
    check(errors.length === 0, '无脚本错误：' + errors.join(';')); check(network.length === 0, '无后端写入或外部服务：' + network.join(';'))
    return { count: checks.length, checks }
  } finally { page.off('pageerror', onError); page.off('request', onRequest) }
}
