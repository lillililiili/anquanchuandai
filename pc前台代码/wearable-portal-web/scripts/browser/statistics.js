async page => {
  const origin = page.url().split('/').slice(0, 3).join('/'), checks = [], errors = [], network = []
  const button = name => page.getByRole('button', { name, exact:true }), check = (ok, name) => { if (!ok) throw Error(name); checks.push(name) }
  const onError = e => errors.push(e.message), onRequest = r => { if (!r.url().startsWith(origin + '/') || r.method() !== 'GET' || /\/(api\/portal|dev-api|demo-api)\//.test(r.url())) network.push(r.url()) }
  const go = async path => { await page.goto(origin + '/#' + path); await page.waitForTimeout(700) }
  const count = id => page.locator('[data-metric="' + id + '"] strong').innerText()
  page.on('pageerror', onError); page.on('request', onRequest)
  try {
    await page.reload(); await page.getByRole('button', {name:/^(进入系统|用户菜单)$/}).first().waitFor()
    if (await button('用户菜单').count()) { await button('用户菜单').click(); await page.getByText('退出登录',{exact:true}).click() }
    await page.getByLabel('预置身份',{exact:true}).selectOption('owner'); await button('进入系统').click(); await button('用户菜单').waitFor()
    await go('/statistics?siteId=mock-site-1'); await page.locator('[data-metric="assignment-ASSIGNED"]').waitFor()
    check(await count('assignment-ASSIGNED') === '68','领用基线68'); check(await count('completed') === '0','种子完成不计显式完成')
    for (const [width,height] of [[1440,900],[1672,941],[1920,1080]]) {
      await page.setViewportSize({width,height})
      for (const label of ['综合','人员','装备','任务','事件']) { await button(label).click(); await page.locator('.stats-metric').first().waitFor(); check(!await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),'统计'+label+'无溢出'+width) }
      await page.screenshot({path:'output/playwright/v27-statistics-'+width+'.png'})
    }
    await button('人员').click(); await page.locator('[data-metric="duty"]').click()
    const dialog=page.getByRole('dialog',{name:'当班人数',exact:true})
    check(await dialog.locator('tbody tr').count()===20,'明细分页20条'); await dialog.locator('.btn-next').click(); check(await dialog.locator('tbody tr').count()===5,'明细第二页5条')
    await page.keyboard.press('Tab'); check(await dialog.evaluate(el=>el.contains(document.activeElement)),'明细焦点不越界')
    const download=page.waitForEvent('download'); await button('导出当前口径 CSV').click(); const file=await download; check(file.suggestedFilename()==='本地统计明细.csv','下载CSV文件'); await file.saveAs('output/playwright/v27-statistics.csv')
    await dialog.locator('.el-dialog__headerbtn').click()
    await page.getByLabel('开始时间 UTC',{exact:true}).fill('2000-01-01T00:00:00Z'); await page.getByLabel('结束时间 UTC（不含）',{exact:true}).fill('2000-01-02T00:00:00Z'); await button('应用历史区间').click(); await page.waitForTimeout(400)
    await button('综合').click(); check(await count('occurred')==='0' && await count('duty')==='25','历史筛选不改变当前快照')
    await go('/personnel/9007199254740993102?siteId=mock-site-1'); await button('领用安全帽').click(); const issue=page.locator('.el-dialog:visible'); await issue.getByLabel('可领用装备').selectOption({index:1}); await button('确认领用').click(); await issue.waitFor({state:'hidden'})
    await go('/statistics?siteId=mock-site-1&tab=equipment'); check(await count('assignment-ASSIGNED')==='69','领用后统计69')
    await go('/equipment/device-1-2-helmet?siteId=mock-site-1'); await button('归还安全帽').click(); await button('确认归还').click(); await page.locator('.el-dialog:visible').waitFor({state:'hidden'})
    await go('/statistics?siteId=mock-site-1'); check(await count('assignment-ASSIGNED')==='68','归还后统计68')
    await button('服务未接入 · 本地工作空间：打开场景控制').click(); await page.getByLabel('目标模块',{exact:true}).selectOption('equipment'); await page.getByLabel('查询场景',{exact:true}).selectOption('forbidden'); await button('应用场景').click(); await page.waitForTimeout(800)
    check(await page.locator('[data-metric="assignment-ASSIGNED"]').isDisabled() && await count('assignment-ASSIGNED')==='—','无权分区不泄露计数'); check(await count('duty')==='25','人员分区独立可见')
    await button('服务未接入 · 本地工作空间：打开场景控制').click(); await button('恢复正常场景').click(); await page.waitForTimeout(600)
    await page.getByLabel('当前厂站',{exact:true}).selectOption('mock-site-empty'); await page.waitForTimeout(700); check(await count('duty')==='0','空厂站真实空结果')
    await page.getByLabel('当前厂站',{exact:true}).selectOption('mock-site-1'); await page.waitForTimeout(700); await button('事件').click()
    await button('服务未接入 · 本地工作空间：打开场景控制').click(); await button('本地会话失效').click(); await button('进入系统').waitFor(); await page.getByLabel('预置身份',{exact:true}).selectOption('reader'); await button('进入系统').click(); await page.locator('[data-metric="occurred"]').waitFor(); check(page.url().includes('tab=events'),'登录恢复统计视图')
    await page.reload(); await page.locator('[data-metric="completed"]').waitFor(); check(await count('completed')==='0','刷新恢复种子')
    check(errors.length===0,'无脚本异常：'+errors.join(';')); check(network.length===0,'无真实业务或外部请求：'+network.join(';'))
    return checks
  } finally { page.off('pageerror',onError); page.off('request',onRequest) }
}
