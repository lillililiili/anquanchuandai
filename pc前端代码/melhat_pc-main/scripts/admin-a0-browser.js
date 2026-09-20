async (page) => {
  const base = page.url().split('/').slice(0, 3).join('/')
  const requests = [], sockets = [], errors = []
  page.on('request', r => requests.push(r.url()))
  page.on('websocket', s => sockets.push(s.url()))
  page.on('pageerror', e => errors.push(e.message))
  const check = (value, message) => { if (!value) throw new Error(message) }
  const button = name => page.getByRole('button', { name, exact: true })
  async function ready() { await page.getByRole('button', { name: /资产总数/ }).waitFor() }
  async function login(name = '演示系统管理员') {
    await page.getByRole('radio', { name: new RegExp(name) }).check()
    await button('进入管理中心').click(); await ready()
  }
  await page.goto(base + '/#/admin/overview')
  await page.evaluate(() => sessionStorage.removeItem('Wearable-Admin-Mock-Token'))
  await page.reload(); await page.getByRole('heading', { name: '选择演示身份进入' }).waitFor()
  for (const [width, height] of [[1440, 900], [1672, 941], [1920, 1080]]) {
    await page.setViewportSize({ width, height })
    check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'login overflow')
    await page.screenshot({ path: `output/playwright/admin-a0/login-${width}.png` })
  }
  await login()
  for (const [width, height] of [[1440, 900], [1672, 941], [1920, 1080]]) {
    await page.setViewportSize({ width, height }); await page.evaluate(() => scrollTo(0, 0))
    check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'overview overflow')
    await page.screenshot({ path: `output/playwright/admin-a0/overview-${width}.png` })
    await page.getByRole('button', { name: /资产总数/ }).click()
    await page.getByText('共 36 条 · 每页20条 · 第 1 页').waitFor()
    check(await page.locator('dialog[open] tbody tr').count() === 20, 'first page count')
    await page.screenshot({ path: `output/playwright/admin-a0/details-${width}.png` })
    await button('下一页').click(); await page.getByText('共 36 条 · 每页20条 · 第 2 页').waitFor()
    check(await page.locator('dialog[open] tbody tr').count() === 16, 'second page count')
    await page.keyboard.press('Escape')
    check(await page.getByRole('button', { name: /资产总数/ }).evaluate(e => e === document.activeElement), 'focus restore')
  }
  const site = page.getByLabel('当前厂站')
  await site.selectOption('site-empty'); await ready()
  check((await page.getByRole('button', { name: /资产总数/ }).innerText()).includes('0'), 'empty site')
  await site.selectOption('site-2'); await ready()
  await site.selectOption('site-1'); await ready()
  for (const mode of ['unavailable', 'failure', 'forbidden']) {
    await button('演示控制').click(); await page.getByLabel('查询状态').selectOption(mode)
    await button('应用场景').click()
    await page.getByRole('button', { name: /资产总数/ }).waitFor({ state: 'hidden' })
    await button('演示控制').click(); await button('恢复默认场景').click(); await ready()
  }
  await button('演示控制').click()
  await page.getByLabel('下一次查询延迟3秒（验证切站竞态）').check()
  await button('应用场景').click(); await site.selectOption('site-empty'); await ready()
  await page.waitForTimeout(3200)
  check((await page.getByRole('button', { name: /资产总数/ }).innerText()).includes('0'), 'late response leaked')
  await site.selectOption('site-1'); await ready()
  await button('演示控制').click(); await button('使当前会话失效').click()
  await page.getByText('模拟会话已失效，请重新选择身份。').waitFor(); await login()
  await page.getByRole('navigation', { name: '主导航' }).getByRole('link', { name: '装备资产' }).click()
  await page.getByRole('heading', { name: '设备台账', exact: true }).waitFor()
  await button('退出 / 切换身份').click()
  await button('进入管理中心').click()
  await page.getByRole('heading', { name: '设备台账', exact: true }).waitFor()
  await page.getByRole('navigation', { name: '主导航' }).getByRole('link', { name: '管理工作台' }).click(); await ready()
  for (const [name, count] of [['演示厂站管理员', 1], ['演示资产管理员', 1], ['演示审计员', 2]]) {
    await button('退出 / 切换身份').click(); await login(name)
    check(await page.getByLabel('当前厂站').locator('option').count() === count, 'role scope ' + name)
    if (name === '演示资产管理员') {
      await page.getByRole('navigation', { name: '主导航' }).getByRole('link', { name: '接入配置' }).click()
      await page.getByRole('heading', { name: '无权限访问', exact: true }).waitFor()
      await page.getByRole('link', { name: '返回管理工作台', exact: true }).click(); await ready()
      await page.goto(base + '/#/admin/overview?siteId=site-2')
      await page.getByText(/无权访问链接指定的厂站/).waitFor()
      await page.getByLabel('当前厂站').selectOption('site-1'); await ready()
    }
  }
  await page.evaluate(() => sessionStorage.setItem('A0-unrelated-test', 'keep'))
  await button('演示控制').click(); await button('恢复初始演示数据').click()
  await page.getByRole('heading', { name: '确认重置本后台演示？' }).waitFor()
  await button('确认重置并退出').click()
  await page.getByRole('heading', { name: '选择演示身份进入' }).waitFor()
  check(await page.evaluate(() => sessionStorage.getItem('A0-unrelated-test')) === 'keep', 'unrelated storage cleared')
  await page.evaluate(() => sessionStorage.removeItem('A0-unrelated-test'))
  await login(); await page.reload(); await ready()
  check((await page.getByRole('button', { name: /资产总数/ }).innerText()).includes('36'), 'refresh seed')
  const foreign = requests.filter(url => !url.startsWith(base + '/') && !url.startsWith('data:'))
  check(!foreign.length, 'external requests: ' + foreign.join(','))
  check(!requests.some(url => /\/dev-api|\/api\/|agora|rtc|\.mp4|\.flv/i.test(url)), 'business/media requests')
  check(sockets.every(url => url.startsWith(base.replace('http', 'ws') + '/')), 'foreign websocket')
  check(!errors.length, 'page errors: ' + errors.join(','))
  if (base.endsWith(':5182')) check(sockets.length === 0, 'production preview websocket')
  return { passed: true, base, viewports: 3, requests: requests.length, sockets, errors }
}
