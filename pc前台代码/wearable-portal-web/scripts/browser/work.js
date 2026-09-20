async page => {
  const origin = page.url().split('/').slice(0, 3).join('/'), checks = [], errors = [], network = []
  const button = name => page.getByRole('button', { name, exact: true }), check = (ok, name) => { if (!ok) throw Error(name); checks.push(name) }
  const onError = e => errors.push(e.message), onRequest = r => { if (!r.url().startsWith(origin + '/') || r.method() !== 'GET' || /\/(api\/portal|dev-api|demo-api)\//.test(r.url())) network.push(r.url()) }
  page.on('pageerror', onError); page.on('request', onRequest)
  try {
    await page.reload(); await page.getByRole('button', { name: /^(用户菜单|进入系统)$/ }).first().waitFor()
    if (await button('用户菜单').count()) { await button('用户菜单').click(); await page.getByText('退出登录', { exact: true }).click() }
    await page.getByLabel('预置身份', { exact: true }).selectOption('owner'); await button('进入系统').click(); await button('用户菜单').waitFor()
    await page.goto(origin + '/#/supervision?siteId=mock-site-1'); await button('巡检作业1').waitFor()
    check(await page.locator('.work-table tbody tr').count() === 20, '作业列表第一页20条')
    await page.locator('.el-pager').getByText('2', { exact: true }).click(); await button('巡检作业25').waitFor(); check(await page.locator('.work-table tbody tr').count() === 5, '第二页5条')
    await page.getByLabel('作业名称或单号', { exact: true }).fill('WORK-1-1'); await button('查询作业').click(); await button('巡检作业1').waitFor()
    await button('巡检作业1').focus(); await page.keyboard.press('Enter'); await button('安排监护人员').waitFor()
    await button('开始监护').click(); await page.getByRole('alert').filter({ hasText: '需安排有效监护人' }).waitFor(); check(true, '未安排监护人禁止开始')
    await button('安排监护人员').click(); const edit = page.getByRole('dialog', { name: '安排本地监护', exact: true })
    await edit.getByLabel('监护人', { exact: true }).selectOption('9007199254740993101')
    await edit.getByRole('checkbox', { name: '人员1-05', exact: true }).check()
    await button('取消编辑').click(); await button('继续编辑').click(); await page.getByRole('dialog', { name: '放弃未保存内容？', exact: true }).waitFor({ state: 'hidden' })
    check(await edit.getByRole('checkbox', { name: '人员1-05', exact: true }).isChecked(), '取消离开保留人员选择')
    await button('保存监护设置').click(); await edit.waitFor({ state: 'hidden' }); await page.getByText('2（关联名册，不是在线数）', { exact: true }).waitFor()
    await page.getByRole('link', { name: '进入作业监护详情 →', exact: true }).click(); await page.getByRole('heading', { name: '参与人员与作业前装备检查', exact: true }).waitFor()
    check(await page.locator('.work-person').count() === 2, '详情展示同一关联名册两人')
    await button('记录人工检查').click(); const inspection = page.getByRole('dialog', { name: '记录人工检查（非安全许可）', exact: true })
    await inspection.getByLabel('检查对象', { exact: true }).selectOption('9007199254740993105'); await inspection.getByLabel('检查说明', { exact: true }).fill('本地读数过期，需现场核实，不作为许可')
    await button('保存监护设置').click(); await inspection.waitFor({ state: 'hidden' }); await page.getByText(/待进一步核实 · 本地读数过期/).waitFor()
    check(true, '人工检查说明与设备报告分列')
    await button('开始监护').click(); await page.locator('.work-status[data-state=ACTIVE]').waitFor(); await button('暂停监护').click(); await page.locator('.work-status[data-state=PAUSED]').waitFor(); await button('恢复监护').click(); await page.locator('.work-status[data-state=ACTIVE]').waitFor()
    check(true, '开始暂停恢复按状态推进')
    for (const [width, height] of [[1440, 900], [1672, 941]]) { await page.setViewportSize({ width, height }); check(!await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), '监护详情无横向溢出' + width); await page.screenshot({ path: 'output/playwright/v25-detail-' + width + '.png' }) }
    await page.getByRole('link', { name: /安全帽1.*进入后手动播放/ }).click(); await button('播放本地视频').waitFor(); check(await page.locator('video[src]').count() === 0, '作业进入视频不自动拉流')
    await page.getByRole('link', { name: '← 返回来源页面', exact: true }).click(); await button('结束监护').waitFor()
    await page.getByRole('link', { name: /事件1.*待认领/ }).click(); await button('认领事件').click(); await page.locator('.event-phase.PROCESSING').waitFor(); await page.getByRole('link', { name: '← 返回来源页面', exact: true }).click(); await button('结束监护').waitFor()
    check((await page.locator('.work-related-grid').innerText()).includes('处理中'), '事件处置后返回作业显示最新阶段')
    await button('结束监护').click(); await page.getByText(/当前仍有 1 件未完成事件/).waitFor(); await button('继续监护').click(); await page.getByRole('dialog', { name: '确认结束本地监护' }).waitFor({ state: 'hidden' }); check(await button('暂停监护').isEnabled(), '取消结束仍可继续监护')
    await button('结束监护').click(); await button('确认结束').click(); await page.locator('.work-status[data-state=ENDED]').waitFor()
    check(await button('开始监护').isDisabled() && (await page.locator('.work-related-grid').innerText()).includes('处理中'), '结束不重开且未关闭事件')
    await page.getByRole('link', { name: '返回作业列表', exact: true }).click(); await button('巡检作业1').waitFor(); check(page.url().includes('keyword=WORK-1-1') && page.url().includes('selectedId=work-1-1'), '返回恢复筛选和选择')
    await page.getByRole('link', { name: '安全总览', exact: true }).click(); await page.getByRole('heading', { name: '作业监护摘要' }).waitFor(); check((await page.locator('.workbench-panel').filter({ hasText: '作业监护摘要' }).innerText()).includes('已结束 · 2 人 · 1 件未完成事件'), '工作台作业人数阶段及事件同步')
    await page.reload(); await page.getByRole('heading', { name: '作业监护摘要' }).waitFor(); await page.goto(origin + '/#/supervision/work-1-1?siteId=mock-site-1'); await page.locator('.work-status[data-state=PENDING]').waitFor(); check(true, '刷新恢复待开始种子')
    check(errors.length === 0, '无运行异常：' + errors.join(';')); check(network.length === 0, '无真实写请求或外部服务：' + network.join(';'))
    return checks
  } finally { page.off('pageerror', onError); page.off('request', onRequest) }
}
