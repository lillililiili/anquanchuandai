async page => {
  const origin = page.url().split('/').slice(0, 3).join('/'), checks = []
  const button = name => page.getByRole('button', { name, exact: true }), check = (ok, label) => { if (!ok) throw Error(label); checks.push(label) }
  async function identity(role) { await button('用户菜单').click(); await page.getByText('退出登录', { exact: true }).click(); await page.getByLabel('预置身份', { exact: true }).selectOption(role); await button('进入系统').click(); await button('用户菜单').waitFor() }
  async function scenario(module, mode, slow = false) { await button('服务未接入 · 本地工作空间：打开场景控制').click(); await page.getByLabel('目标模块').selectOption(module); await page.getByLabel('查询场景').selectOption(mode); await page.getByRole('checkbox', { name: '该模块下一次查询延迟 3 秒' }).setChecked(slow); await button('应用场景').click(); await page.getByRole('dialog', { name: '本地场景控制' }).waitFor({ state: 'hidden' }) }
  await page.reload(); await button('用户菜单').waitFor(); await identity('owner')
  await page.goto(origin + '/#/supervision?siteId=mock-site-1'); await button('巡检作业1').click(); await button('安排监护人员').waitFor()
  for (const [width, height] of [[1440, 900], [1672, 941]]) { await page.setViewportSize({ width, height }); check(!await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), '列表布局无横向溢出' + width); await page.screenshot({ path: 'output/playwright/v25-list-' + width + '.png' }) }
  await button('安排监护人员').click(); await page.getByLabel('监护人', { exact: true }).selectOption('9007199254740993101')
  await page.evaluate(() => { location.hash = '/supervision?siteId=mock-site-2' }); await button('继续编辑').click(); await page.getByRole('dialog', { name: '放弃未保存内容？', exact: true }).waitFor({ state: 'hidden' }); check(await page.getByLabel('监护人', { exact: true }).inputValue() === '9007199254740993101', '切站拒绝离开保留输入')
  await button('取消编辑').click(); await button('放弃编辑').click(); await page.getByRole('dialog', { name: '安排本地监护', exact: true }).waitFor({ state: 'hidden' })
  await scenario('works', 'not-integrated'); await page.getByText('数据待接入', { exact: false }).first().waitFor(); check(await page.locator('.work-table tbody tr').count() === 0, '作业未接入不冒充空结果')
  await scenario('works', 'failure'); await page.getByText('预置数据故障，请恢复场景后重试', { exact: false }).first().waitFor(); check(true, '来源失败明确显示')
  await scenario('works', 'normal', true); await page.getByLabel('当前厂站', { exact: true }).selectOption('mock-site-empty'); await page.getByText('当前厂站或筛选条件下没有作业', { exact: true }).waitFor(); await page.waitForTimeout(3200)
  check(await page.locator('.work-table tbody tr').count() === 0 && page.url().includes('mock-site-empty'), '迟到查询不覆盖新厂站空数据')
  await page.getByLabel('当前厂站', { exact: true }).selectOption('mock-site-1'); await button('巡检作业1').click(); await page.getByRole('link', { name: '进入作业监护详情 →' }).click(); await button('安排监护人员').waitFor()
  await scenario('events', 'forbidden'); await page.getByRole('heading', { name: '关联事件 · 独立处置' }).waitFor(); await page.waitForTimeout(500)
  check(await page.locator('.work-person').count() === 1 && (await page.locator('.work-facts').innerText()).includes('无权或暂不可读取'), '事件分区无权限不影响人员与来源事实')
  await scenario('events', 'normal'); await button('安排监护人员').waitFor()
  await identity('reader'); await page.goto(origin + '/#/supervision/work-1-1?siteId=mock-site-1'); await button('安排监护人员').waitFor(); check(await button('安排监护人员').isDisabled() && await button('开始监护').isDisabled(), '只读身份不能修改监护')
  await identity('verifier'); await page.goto(origin + '/#/supervision/work-1-1?siteId=mock-site-1'); await button('开始监护').waitFor(); check(await button('开始监护').isDisabled(), '核验员只读监护')
  await button('服务未接入 · 本地工作空间：打开场景控制').click(); await button('本地会话失效').click(); await button('进入系统').waitFor(); check(page.url().includes('redirect='), '失效保留详情恢复地址')
  await page.getByLabel('预置身份', { exact: true }).selectOption('owner'); await button('进入系统').click(); await button('安排监护人员').waitFor(); check(page.url().includes('/supervision/work-1-1'), '登录恢复作业详情')
  return checks
}
