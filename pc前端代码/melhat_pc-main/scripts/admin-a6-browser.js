async (page) => {
  page.on('dialog', dialog => dialog.accept())
  const base = page.url().split('/').slice(0, 3).join('/'), requests = [], errors = []
  page.on('request', r => requests.push({ url: r.url(), method: r.method() }))
  page.on('pageerror', e => errors.push(e.message))
  const check = (ok, why) => { if (!ok) throw new Error(why) }
  const button = name => page.getByRole('button', { name, exact: true })
  const dialog = () => page.locator('dialog[open]').last()
  async function ready() { await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))); await page.waitForFunction(() => !document.querySelector('[aria-busy="true"]') && !Array.from(document.querySelectorAll('[role="status"], [aria-live]')).some(e => /正在读取|正在加载|正在查询/.test(e.textContent))); }
  async function route(path) { await page.evaluate(path => { location.hash = '#' + path }, path); await ready() }
  async function connector(kind) { await route('/admin/integrations/integration-site-1-' + kind + '?siteId=site-1'); await button('模拟测试').waitFor(); await ready() }
  async function shot(name) { for (const [width, height] of [[1440, 900], [1672, 941], [1920, 1080]]) { await page.setViewportSize({ width, height }); check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), name + ' overflow'); await page.screenshot({ path: `output/playwright/admin-a6/${base.endsWith(':5182') ? 'preview-' : ''}${name}-${width}.png` }) } }
  async function preview() { await button('预览模拟样本').click(); await page.getByRole('heading', { name: '模拟同步任务', exact: true }).waitFor(); await ready() }
  async function confirm() { await button('确认导入模拟样本').click(); await dialog().waitFor(); await dialog().getByRole('button', { name: '确认导入模拟样本', exact: true }).click(); await page.locator('dialog[open]').waitFor({ state: 'hidden' }); await ready(); await page.getByText('已完成', { exact: true }).waitFor() }
  async function map() { await page.getByRole('combobox', { name: '映射厂站', exact: true }).selectOption('site-1'); await page.getByRole('combobox', { name: '映射区域', exact: true }).selectOption('area-1'); await button('保存本地配置').click(); await ready(); await page.getByText('本地配置已保存。', { exact: false }).waitFor() }
  await page.goto(base + '/#/admin/login')
  if (await button('退出登录').count()) await button('退出登录').click()
  await page.reload()
  await page.getByRole('textbox', { name: '账号', exact: true }).fill('admin'); await page.getByRole('textbox', { name: '密码', exact: true }).fill('Admin@2026'); await button('登录').click(); await page.getByLabel('当前厂站').waitFor(); await ready()
  await route('/admin/integrations?siteId=site-1'); await page.getByRole('link', { name: '配置与记录' }).first().waitFor(); check(await page.getByRole('link', { name: '配置与记录' }).count() === 6, 'six connectors missing'); await shot('connectors')
  await connector('DEVICE'); await preview(); await page.getByText('冲突阻止', { exact: true }).waitFor(); check(await button('确认导入模拟样本').isDisabled(), 'unmapped batch confirm enabled')
  await connector('DEVICE'); await page.getByLabel('确定性演示场景').selectOption('TIMEOUT'); await button('保存本地配置').click(); await ready(); await button('模拟测试').click(); await ready(); await page.getByText(/模拟超时.*真实状态仍为未接入/).first().waitFor()
  await preview(); await page.getByText('模拟失败', { exact: true }).waitFor(); await button('重试此任务').click(); await ready(); await page.getByText('模拟失败', { exact: true }).waitFor()
  await connector('DEVICE'); await page.getByLabel('确定性演示场景').selectOption('SUCCESS'); await map(); await button('模拟测试').click(); await ready(); await page.getByText(/模拟测试通过.*真实状态仍为未接入/).first().waitFor(); await shot('configuration')
  await preview(); check((await page.locator('main').innerText()).includes('新增 1 · 更新 1'), 'device preview counts'); await shot('preview'); await confirm(); await shot('completed')
  await connector('DEVICE'); await preview(); check((await page.locator('main').innerText()).includes('跳过 2'), 'device repeat is not skip'); await confirm()
  await connector('PERSON'); await map(); await preview(); check((await page.locator('main').innerText()).includes('新增 2'), 'same-name people merged'); await confirm(); await connector('PERSON'); await preview(); check((await page.locator('main').innerText()).includes('跳过 2'), 'people duplicated'); await confirm()
  for (const kind of ['WORK_TICKET', 'SAFETY', 'SUMMARY_RETURN', 'VERIFICATION_RETURN']) { await connector(kind); await map(); await button('生成模拟回执').click(); await ready(); await page.getByText(/模拟回执成功.*未实际发送/).first().waitFor() }
  await route('/admin/integrations/settings?siteId=site-1'); await page.getByLabel('默认演示场景').selectOption('FIELD_MISMATCH'); await button('保存演示参数').click(); await ready()
  await connector('PERSON'); await button('模拟测试').click(); await ready(); await page.getByText(/模拟字段不匹配.*真实状态仍为未接入/).first().waitFor()
  await route('/admin/audit?siteId=site-1'); await button('查看详情').first().waitFor(); await page.getByLabel('动作', { exact: true }).fill('integrations.update'); await button('查询').click(); await ready(); check(await page.locator('tbody tr').count() > 0, 'audit filter empty'); await button('查看详情').first().click(); await dialog().getByRole('heading', { name: '字段差异', exact: true }).waitFor(); await shot('audit-detail'); await button('关闭面板').click(); await button('清除筛选').click(); await ready(); await shot('audit')
  const downloadPromise = page.waitForEvent('download'); await button('导出全部筛选结果').click(); const download = await downloadPromise; await download.saveAs(`output/playwright/admin-a6/${base.endsWith(':5182') ? 'preview-' : ''}audit.csv`)
  check(errors.length === 0, 'page errors: ' + errors.join(';'))
  check(requests.every(r => r.url.startsWith(base + '/') || r.url.startsWith('data:') || r.url.startsWith('blob:')), 'external request')
  check(!requests.some(r => r.method !== 'GET' || /\/dev-api|\/api\/|agora|\.mp4|\.flv/i.test(r.url)), 'business/media request')
  await page.reload(); await ready(); await connector('DEVICE'); check(await page.getByRole('combobox', { name: '映射厂站', exact: true }).inputValue() === '', 'refresh persisted mock business data')
  return { passed: true, base, requestCount: requests.length, errors, workflow: 'mapping-conflict/timeout/retry/preview-confirm/repeat-skip/same-name-people/four-receipts/settings/audit/export/refresh', viewports: 3 }
}


