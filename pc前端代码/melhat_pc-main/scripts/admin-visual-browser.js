async (page) => {
  const base = page.url().split('/').slice(0, 3).join('/'), requests = [], errors = [], sockets = [], coverage = []
  page.on('request', r => requests.push({ url: r.url(), method: r.method() }))
  page.on('pageerror', e => errors.push(e.message))
  page.on('websocket', s => sockets.push(s.url()))
  const check = (ok, message) => { if (!ok) throw new Error(message) }
  async function ready() {
    await page.waitForFunction(() => !Array.from(document.querySelectorAll('[role="status"], [aria-live]')).some(e => /正在读取|正在加载|正在查询/.test(e.textContent)))
    await page.evaluate(() => document.fonts.ready)
  }
  async function shot(name) {
    for (const [width, height] of [[1440, 900], [1672, 941], [1920, 1080]]) {
      await page.setViewportSize({ width, height }); await ready()
      await page.evaluate(() => scrollTo(0, 0))
      check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), name + ': page overflow')
      check(await page.locator('dialog[open]').evaluateAll(elements => elements.every(e => e.scrollWidth <= e.clientWidth)), name + ': dialog overflow')
      check(await page.evaluate(() => Array.from(document.images).every(i => !i.complete || i.naturalWidth > 0)), name + ': broken image')
      await page.screenshot({ path: `output/playwright/admin-visual/${name}-${width}.png` })
    }
    coverage.push(name)
  }
  async function route(path, heading) {
    await page.goto(base + '/#' + path)
    await page.getByRole('heading', { name: heading, exact: true }).waitFor()
    await ready()
  }
  await page.goto(base + '/#/admin/login')
  await page.evaluate(() => { sessionStorage.removeItem('Wearable-Admin-Mock-Token'); sessionStorage.removeItem('Wearable-Admin-Mock-Session-Version') })
  await page.reload(); await page.getByRole('heading', { name: '选择演示身份进入' }).waitFor(); await shot('login')
  await page.getByRole('button', { name: '进入管理中心', exact: true }).click()
  await page.getByRole('button', { name: /资产总数/ }).waitFor(); await ready(); await shot('overview')
  const pages = [
    ['/admin/assets/devices', '设备台账', 'devices'],
    ['/admin/assets/devices/19007199254740993000', '设备档案', 'helmet-detail'],
    ['/admin/assets/devices/19007199254740993001', '设备档案', 'harness-detail'],
    ['/admin/assets/devices/19007199254740993002', '设备档案', 'watch-detail'],
    ['/admin/assets/assignments', '发放与回收', 'assignments'],
    ['/admin/assets/maintenance', '维修与退役', 'maintenance'],
    ['/admin/people', '人员档案', 'people'],
    ['/admin/people/person-1-0', '人员详情', 'person-detail'],
    ['/admin/organization', '组织与区域', 'organization'],
    ['/admin/sites', '厂站资料', 'sites'],
    ['/admin/duty', '班次名册', 'duty'],
    ['/admin/access/accounts', '模拟账号', 'accounts'],
    ['/admin/access/roles', '基础角色', 'roles'],
    ['/admin/access/groups', '常设协助组', 'groups'],
    ['/admin/access/groups/group-1', '协助组档案', 'group-detail'],
    ['/admin/integrations', '接入配置', 'integrations'],
    ['/admin/audit', '审计记录', 'audit'],
    ['/admin/legacy', '现场功能已迁往前台', 'legacy'],
    ['/admin/401', '无权限访问', '401'],
    ['/admin/not-found', '页面不存在', '404']
  ]
  for (const [path, heading, name] of pages) { await route(path + '?siteId=site-1', heading); await shot(name) }
  await route('/admin/assets/devices?siteId=site-1', '设备台账')
  await page.getByRole('button', { name: '新建设备', exact: true }).click()
  await page.locator('dialog[open]').waitFor(); await ready(); await shot('device-editor')
  await page.getByRole('button', { name: '关闭面板', exact: true }).click()
  await route('/admin/overview?siteId=site-1', '管理工作台')
  for (const mode of ['unavailable', 'failure', 'forbidden']) {
    await page.getByRole('button', { name: '演示控制', exact: true }).click()
    await page.getByLabel('目标查询').selectOption('overview')
    await page.getByLabel('查询状态').selectOption(mode)
    await page.getByRole('button', { name: '应用场景', exact: true }).click()
    await page.getByRole('button', { name: /资产总数/ }).waitFor({ state: 'hidden' }); await ready(); await shot('state-' + mode)
    await page.getByRole('button', { name: '演示控制', exact: true }).click()
    await page.getByRole('button', { name: '恢复默认场景', exact: true }).click()
    await page.getByRole('button', { name: /资产总数/ }).waitFor()
  }
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.getByRole('button', { name: '折叠菜单', exact: true }).click(); await shot('compact-menu')
  await page.getByRole('button', { name: '折叠菜单', exact: true }).click()
  check(errors.length === 0, 'page errors: ' + errors.join(';'))
  check(requests.every(r => r.url.startsWith(base + '/') || r.url.startsWith('data:')), 'external request')
  check(!requests.some(r => r.method !== 'GET' || /\/dev-api|\/api\/|agora|\.mp4|\.flv/i.test(r.url)), 'business/media request')
  if (base.endsWith(':5182')) check(!sockets.length, 'preview websocket')
  return { passed: true, base, coverage, viewports: 3, requests: requests.length, sockets, errors }
}
