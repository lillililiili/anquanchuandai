async (page) => {
  const base = page.url().split('/').slice(0, 3).join('/'), requests = [], sockets = [], errors = []
  page.on('request', r => requests.push(r.url())); page.on('websocket', s => sockets.push(s.url())); page.on('pageerror', e => errors.push(e.message))
  const check = (yes, message) => { if (!yes) throw new Error(message) }
  const button = name => page.getByRole('button', { name, exact: true })
  const nav = name => page.getByRole('navigation', { name: '主导航' }).getByRole('link', { name, exact: true }).click()
  async function ready() { await page.getByRole('heading', { name: '设备台账', exact: true }).waitFor(); await page.getByText('正在读取模拟数据…', { exact: true }).waitFor({ state: 'hidden' }) }
  async function save() { await button('保存模拟设备').click(); await page.locator('dialog[open] .master-form').waitFor({ state: 'hidden' }) }
  async function login(name = '演示系统管理员') { await page.getByRole('radio', { name: new RegExp(name) }).check(); await button('进入管理中心').click(); await page.getByLabel('当前厂站').waitFor() }
  async function openDevice(code) { await page.getByRole('link', { name: code, exact: true }).click(); await page.getByRole('heading', { name: '设备档案', exact: true }).waitFor(); await page.getByText('正在读取模拟数据…', { exact: true }).first().waitFor({ state: 'hidden' }) }
  await page.goto(base + '/#/admin/login'); await page.evaluate(() => sessionStorage.removeItem('Wearable-Admin-Mock-Token')); await page.reload(); await login()
  await page.getByLabel('当前厂站').selectOption('site-empty')
  await nav('人员组织'); await page.getByRole('link', { name: '组织与区域', exact: true }).click(); await button('管理区域').click(); await button('新增区域').click()
  await page.getByLabel('编号', { exact: true }).fill('DEMO-A2-AREA'); await page.getByLabel('名称 / 姓名', { exact: true }).fill('演示A2设备区'); await button('保存模拟记录').click(); await page.locator('dialog[open] .master-form').waitFor({ state: 'hidden' })
  await nav('装备资产'); await ready()
  for (const [type, code, name] of [['HELMET', 'A2-HAT', '演示A2安全帽'], ['BELT', 'A2-BELT', '演示A2安全带'], ['WATCH', 'A2-WATCH', '演示A2手表']]) {
    await button('新建设备').click(); await page.getByLabel('平台编号', { exact: true }).fill(code); await page.getByLabel('设备名称', { exact: true }).fill(name); await page.locator('dialog').getByLabel('设备类型', { exact: true }).selectOption(type)
    await page.getByLabel('所属区域', { exact: true }).selectOption({ label: '演示A2设备区' })
    if (type === 'HELMET') { await page.getByLabel('型号模板').selectOption('demo-helmet-plus'); await page.getByLabel('定位模块（模拟选配）', { exact: true }).selectOption('INSTALLED') }
    await save(); await page.getByRole('link', { name: code, exact: true }).waitFor()
  }
  await nav('管理工作台'); const total = page.getByRole('button', { name: /资产总数/ }); await total.waitFor(); check((await total.innerText()).includes('3台'), 'asset metric not 3'); check((await page.getByRole('button', { name: /可领设备/ }).innerText()).includes('3台'), 'available metric not 3')
  await nav('装备资产'); await ready(); await openDevice('A2-HAT'); await button('编辑设备资料').click()
  await page.getByLabel('厂商', { exact: true }).fill('演示A2厂商'); await page.getByLabel('SN', { exact: true }).fill('A2-SN-HAT'); await save()
  await page.getByText('A2-SN-HAT', { exact: true }).first().waitFor(); await button('编辑设备资料').click(); await page.getByLabel('型号模板').selectOption('demo-helmet-basic')
  await button('保存模拟设备').click(); await page.getByText('请确认型号变更及选配清理', { exact: true }).first().waitFor()
  check(await page.evaluate(() => document.activeElement?.getAttribute('role') === 'alert'), 'error summary focus')
  await page.getByRole('checkbox', { name: '我已确认型号变更及选配清理' }).check(); await page.getByLabel('影像模块（模拟选配）', { exact: true }).selectOption('INSTALLED'); await save()
  await page.getByText('演示安全帽 · 基础型', { exact: true }).first().waitFor(); check(await page.getByText('待确认，未进行真机验证', { exact: true }).count() === 1, 'false real verification')
  await page.getByRole('link', { name: '返回设备台账', exact: true }).click(); await ready(); await button('新建设备').click(); await button('保存模拟设备').click(); await page.getByText('请填写平台编号', { exact: true }).first().waitFor()
  await page.getByLabel('平台编号', { exact: true }).fill('a2-hat'); await page.getByLabel('设备名称', { exact: true }).fill('演示重复设备'); await button('保存模拟设备').click(); await page.getByText('平台编号已存在，请核对后修改', { exact: true }).first().waitFor(); check(await page.getByLabel('设备名称', { exact: true }).inputValue() === '演示重复设备', 'failed form lost input')
  await page.evaluate(() => { window.__a2Confirm = window.confirm; window.confirm = () => false }); await button('关闭面板').click(); check(await page.locator('dialog[open]').count() === 1, 'dirty close not blocked')
  await page.evaluate(() => { window.confirm = () => true }); await button('取消').click(); await page.evaluate(() => { window.confirm = window.__a2Confirm; delete window.__a2Confirm })
  await page.getByLabel('设备类型', { exact: true }).selectOption('WATCH'); await button('查询').click(); await page.getByRole('link', { name: 'A2-WATCH', exact: true }).waitFor(); check(await page.getByRole('link', { name: 'A2-HAT', exact: true }).count() === 0, 'type filter')
  await openDevice('A2-WATCH'); await page.getByRole('link', { name: '返回设备台账', exact: true }).click(); await ready(); check(await page.getByLabel('设备类型', { exact: true }).inputValue() === 'WATCH', 'return filter lost'); await button('清除筛选').click(); await ready()
  for (const [width, height] of [[1440, 900], [1672, 941], [1920, 1080]]) {
    await page.setViewportSize({ width, height }); check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'list overflow'); await page.screenshot({ path: `output/playwright/admin-a2/list-${width}.png` }); await openDevice('A2-HAT')
    check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'detail overflow'); await page.screenshot({ path: `output/playwright/admin-a2/detail-${width}.png` })
    await button('编辑设备资料').click(); await page.locator('dialog[open] .master-form').waitFor(); await page.screenshot({ path: `output/playwright/admin-a2/editor-${width}.png` }); await page.keyboard.press('Escape'); await page.locator('dialog[open]').waitFor({ state: 'hidden' }); check(await button('编辑设备资料').evaluate(el => el === document.activeElement), 'editor close did not restore focus')
    await page.getByRole('link', { name: '返回设备台账', exact: true }).click(); await ready()
  }
  await button('退出 / 切换身份').click(); await login('演示审计员'); await nav('装备资产'); await ready(); check(await button('新建设备').isDisabled(), 'auditor can create')
  await page.getByLabel('当前厂站').selectOption('site-1'); await ready(); await openDevice('DEMO-1-001'); check(await button('编辑设备资料').isDisabled(), 'auditor can edit')
  await button('退出 / 切换身份').click(); await login(); await nav('装备资产'); await ready(); await openDevice('DEMO-1-001'); await button('编辑设备资料').click(); check(await page.getByLabel('平台编号', { exact: true }).isDisabled(), 'in-use identity editable'); await button('取消').click()
  await page.getByRole('link', { name: '返回设备台账', exact: true }).click(); await ready(); await page.getByLabel('生命周期', { exact: true }).selectOption('SCRAPPED'); await button('查询').click(); await openDevice('DEMO-1-032'); check(await button('编辑设备资料').isDisabled(), 'scrapped editable')
  await page.getByLabel('当前厂站').selectOption('site-empty'); await ready(); await page.reload(); await ready(); check(await page.getByRole('link', { name: 'A2-HAT', exact: true }).count() === 0, 'refresh did not reset')
  await button('演示控制').click(); await page.getByRole('combobox', { name: '目标查询', exact: true }).selectOption('devices'); await page.getByRole('combobox', { name: '查询状态', exact: true }).selectOption('failure'); await button('应用场景').click(); await page.getByText('读取失败', { exact: true }).waitFor()
  await button('演示控制').click(); await page.getByRole('combobox', { name: '查询状态', exact: true }).selectOption('unavailable'); await button('应用场景').click(); await page.locator('.query-state strong').filter({ hasText: /^未接入$/ }).waitFor()
  await button('演示控制').click(); await page.getByRole('combobox', { name: '查询状态', exact: true }).selectOption('normal'); await page.getByRole('checkbox', { name: /下一次查询延迟3秒/ }).check(); await button('应用场景').click(); await page.getByLabel('当前厂站').selectOption('site-1'); await ready(); await page.getByRole('link', { name: 'DEMO-1-001', exact: true }).waitFor()
  await openDevice('DEMO-1-001'); await button('演示控制').click(); await button('使当前会话失效').click(); await page.getByRole('heading', { name: '选择演示身份进入' }).waitFor(); await login(); await page.getByRole('heading', { name: '设备档案', exact: true }).waitFor(); await page.getByText('DEMO-1-001', { exact: true }).waitFor()
  check(errors.length === 0, 'page errors: ' + errors.join(';')); check(requests.every(url => url.startsWith(base + '/') || url.startsWith('data:')), 'external network'); check(!requests.some(url => /\/dev-api|\/api\/|agora|\.mp4|\.flv/i.test(url)), 'business/media request'); check(sockets.every(url => url.startsWith(base.replace('http', 'ws') + '/')), 'external websocket')
  if (base.endsWith(':5182')) check(sockets.length === 0, 'preview websocket')
  return { passed: true, base, requests: requests.length, sockets, errors, viewports: 3 }
}
