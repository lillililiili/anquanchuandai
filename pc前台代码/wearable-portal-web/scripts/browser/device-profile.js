async (page) => {
  const origin = page.url().split('/').slice(0, 3).join('/'), checks = [], errors = [], forbidden = []
  const check = (ok, name) => { if (!ok) throw new Error(name); checks.push(name) }
  const error = e => errors.push(e.message)
  const network = r => { if (!r.url().startsWith(origin + '/') || r.method() !== 'GET' || /\/(api\/portal|dev-api|demo-api)\//.test(r.url())) forbidden.push(r.url()) }
  page.on('pageerror', error); page.on('request', network)
  const go = async path => { await page.goto(origin + '/#' + path); await page.waitForTimeout(1600) }
  const person = n => '/personnel/' + (9007199254740993100n + BigInt(n)).toString() + '?siteId=mock-site-1'
  const panel = () => page.locator('.vitals-panel')
  const scenario = async mode => {
    await page.getByRole('button', { name: '服务未接入 · 本地工作空间：打开场景控制' }).click()
    await page.getByLabel('目标模块').selectOption('vitals')
    await page.getByLabel('查询场景').selectOption(mode)
    await page.getByRole('button', { name: '应用场景', exact: true }).click()
    await page.waitForTimeout(1800)
    await panel().locator('.vitals-status').filter({ hasText: { normal: '预置观测', forbidden: '无权查看体征', 'not-integrated': '体征未接入', failure: '体征读取失败' }[mode] }).waitFor({ timeout: 15000 })
  }
  try {
    await page.reload(); await page.waitForTimeout(800)
    if (await page.getByRole('button', { name: '进入系统', exact: true }).count()) {
      await page.getByLabel('预置身份', { exact: true }).selectOption('owner')
      await page.getByRole('button', { name: '进入系统', exact: true }).click(); await page.waitForTimeout(900)
    }
    await go(person(1))
    await panel().locator('.vitals-human svg').waitFor({ state: 'visible' })
    check(await panel().locator('.vitals-human svg').count() === 1, '完整人形SVG')
    await panel().getByText('118 / 76', { exact: true }).waitFor()
    check((await panel().locator('.vital-number strong').allTextContents()).join(',') === '72,98,36.5,118 / 76', '四类合成体征及血压双值')
    for (const [width, height] of [[1440, 900], [1672, 941], [1920, 1080]]) {
      await page.setViewportSize({ width, height }); await panel().scrollIntoViewIfNeeded()
      await page.screenshot({ path: 'output/playwright/v21a-person-' + width + '.png' })
      check(!await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), '人员页无横向溢出' + width)
      check(await panel().evaluate(el => el.scrollWidth <= el.clientWidth), '体征卡片容器不溢出' + width)
    }
    await page.emulateMedia({ reducedMotion: 'reduce' })
    check(await panel().locator('.human-outline').evaluate(el => getComputedStyle(el).filter === 'none'), '减少动态效果')
    await page.emulateMedia({ reducedMotion: 'no-preference' })
    for (const [n, text] of [[2, '未领用手表'], [3, '归属或能力未知'], [5, '历史读数 / 已过期'], [6, '源时间未知'], [7, '归属或能力未知'], [8, '指标缺失']]) {
      await go(person(n)); await panel().getByText(text, { exact: true }).first().waitFor(); check((await panel().innerText()).includes(text), '固定样例' + n + ':' + text)
    }
    await go(person(1))
    for (const [mode, text] of [['not-integrated', '体征未接入'], ['forbidden', '无权查看体征'], ['failure', '体征读取失败']]) {
      await scenario(mode)
      check((await panel().innerText()).includes(text), text)
      check((await panel().locator('.vital-number strong').allTextContents()).every(v => v === '—'), '异常不泄露旧读数:' + mode)
      check(await page.locator('.history-table tbody tr').count() > 0, '体征失败不抹掉其他分区:' + mode)
    }
    await scenario('normal')
    await page.getByRole('button', { name: '服务未接入 · 本地工作空间：打开场景控制' }).click()
    await page.getByLabel('该模块下一次查询延迟 3 秒').check()
    await page.getByRole('button', { name: '应用场景', exact: true }).click()
    await page.waitForTimeout(350)
    // Hash navigation preserves repository and the pending request.
    await page.evaluate(path => { location.hash = '#' + path }, person(8))
    await page.waitForTimeout(3600)
    await panel().locator('.vitals-footer').filter({ hasText: 'MOCK-1-8-watch' }).waitFor()
    check((await panel().innerText()).includes('MOCK-1-8-watch') && !(await panel().innerText()).includes('MOCK-1-1-watch'), '迟到查询不能覆盖新人')
    await page.getByLabel('当前厂站').selectOption('mock-site-2'); await page.waitForURL('**/#/personnel?siteId=mock-site-2'); await page.waitForTimeout(600)
    check(!(await page.locator('main').innerText()).includes('MOCK-1-8-watch'), '切厂站清理体征')
    await go('/equipment/device-1-1-watch?siteId=mock-site-1')
    await panel().locator('.vitals-footer').filter({ hasText: '历史预置观测' }).waitFor()
    check((await panel().innerText()).includes('历史预置观测'), '设备页明确历史观测')
    await page.getByRole('button', { name: '归还手表', exact: true }).click(); await page.waitForTimeout(400)
    await page.getByRole('button', { name: '确认归还', exact: true }).click(); await page.waitForTimeout(1000)
    await page.getByRole('button', { name: '领用手表', exact: true }).click(); await page.waitForTimeout(400)
    await page.getByLabel('领用人员').selectOption({ label: '人员1-02 · PERSON-1-2' })
    await page.getByRole('button', { name: '确认领用', exact: true }).click(); await page.waitForTimeout(900)
    await page.locator('.equipment-panel').filter({ hasText: '当前领用关系' }).getByText('人员1-02', { exact: true }).waitFor()
    await panel().locator('.vitals-footer').filter({ hasText: '人员1-01' }).waitFor()
    check((await panel().innerText()).includes('人员1-01'), '设备历史仍属于原测量人')
    await page.getByRole('link', { name: '查看人员及领用历史 →' }).click(); await page.waitForTimeout(900)
    await panel().locator('.vitals-status').filter({ hasText: '暂无本人观测' }).waitFor({ timeout: 15000 })
    check((await panel().innerText()).includes('暂无本人观测'), '新领用人没有继承旧体征')
    await page.reload(); await page.waitForTimeout(1000)
    await panel().locator('.vitals-status').filter({ hasText: '未领用手表' }).waitFor()
    check((await panel().innerText()).includes('未领用手表'), '刷新恢复种子')
    await go('/equipment/device-1-3-helmet?siteId=mock-site-1')
    await page.locator('.device-profile summary').click()
    check((await page.locator('.device-profile').innerText()).includes('资料存在差异'), '临电资料差异')
    check((await page.locator('.device-profile').innerText()).includes('预置未配置'), '本地配置不是资料推断')
    await go('/equipment/device-1-6-helmet?siteId=mock-site-1')
    check((await page.locator('.device-profile').innerText()).includes('本地已开启'), '本地隐私状态')
    await go('/equipment/device-1-1-belt?siteId=mock-site-1')
    check((await page.locator('.device-profile').innerText()).includes('锁扣闭合不证明挂点可靠'), '安全带不生成安全结论')
    await go('/personnel?siteId=mock-site-1')
    await page.getByText('人员1-01', { exact: true }).first().click(); await page.waitForTimeout(800)
    check(await page.locator('.vitals-compact').count() === 1, '右侧紧凑体征摘要')
    await page.getByRole('link', { name: '查看人形体征详情 →' }).focus(); await page.keyboard.press('Enter'); await page.waitForTimeout(800)
    check(await page.locator('.vitals-human').count() === 1, '摘要键盘跳转详情')
    await page.getByRole('button', { name: '服务未接入 · 本地工作空间：打开场景控制' }).click()
    await page.getByRole('button', { name: '本地会话失效', exact: true }).click(); await page.waitForTimeout(600)
    check(await panel().count() === 0 && page.url().includes('/login'), '会话失效清理体征')
    check(errors.length === 0, '无页面脚本错误:' + errors.join(','))
    check(forbidden.length === 0, '无真实接口/外部地图/媒体请求:' + forbidden.join(','))
    return checks
  } finally { page.off('pageerror', error); page.off('request', network) }
}
