async page => {
  const origin = page.url().split('/').slice(0, 3).join('/'), checks = [], errors = [], network = []
  const button = name => page.getByRole('button', { name, exact: true }), check = (ok, name) => { if (!ok) throw Error(name); checks.push(name) }
  const onError = e => errors.push(e.message), onRequest = r => { if (!r.url().startsWith(origin + '/') || r.method() !== 'GET' || /\/(api\/portal|dev-api|demo-api)\//.test(r.url())) network.push(r.url()) }
  page.on('pageerror', onError); page.on('request', onRequest)
  try {
    await page.reload(); await page.getByRole('button', { name: /^(用户菜单|进入系统)$/ }).first().waitFor()
    if (await button('用户菜单').count()) { await button('用户菜单').click(); await page.getByText('退出登录', { exact: true }).click() }
    await page.getByLabel('预置身份', { exact: true }).selectOption('owner'); await button('进入系统').click(); await button('用户菜单').waitFor()
    await page.goto(origin + '/#/dispatch?siteId=mock-site-1'); await page.getByRole('heading', { name: '联系人与设备', exact: true }).waitFor()
    check(await page.locator('.dispatch-contact').count() === 20, '联系人分页20条')
    const contact = id => page.locator('.dispatch-contact input[value="' + id + '"]')
    check(await contact('device-1-1-belt').isDisabled() && await contact('device-1-1-watch').isDisabled(), '带表未确认能力不能本地会话就绪')
    await contact('device-1-1-helmet').check(); await contact('device-1-2-helmet').check()
    await page.getByLabel('协助组名称', { exact: true }).fill('预置临时协助组'); await button('保存临时协助组').click(); await button('预置临时协助组 · 2 个对象').waitFor(); check(true, '临时组保存且非组织班组')
    await button('发起本地呼叫').click(); await page.locator('.dispatch-session-count').waitFor()
    check((await page.locator('.dispatch-session-count').innerText()).includes('0 / 2'), '群呼初始未接通')
    await page.locator('#dispatch-current .dispatch-participant').first().getByRole('button', { name: '本地会话就绪', exact: true }).click()
    await page.waitForFunction(() => document.querySelector('.dispatch-session-count')?.textContent.includes('1 / 2'))
    await page.locator('#dispatch-current .dispatch-participant').nth(1).getByRole('button', { name: '本地拒接', exact: true }).click(); await button('刷新协同数据').waitFor(); await page.waitForTimeout(350)
    check((await page.locator('.dispatch-session-count').innerText()).includes('1 / 2'), '部分接通与拒接分开')
    for (const [width, height] of [[1440,900],[1672,941]]) { await page.setViewportSize({ width, height }); check(!await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), '调度布局无横向溢出' + width); await page.screenshot({ path:'output/playwright/v26-dispatch-' + width + '.png' }) }
    await page.getByRole('link', { name: '安全总览', exact: true }).click(); await page.getByRole('link', { name: /本地会话进行中/ }).waitFor(); check(true, '切页保留全局会话提示')
    await page.getByRole('link', { name: /本地会话进行中/ }).click(); await button('结束本地会话').waitFor()
    await page.getByLabel('当前厂站', { exact: true }).selectOption('mock-site-2'); await button('保持当前会话').click(); await page.getByRole('dialog', { name: '结束本地会话后离开？' }).waitFor({ state:'hidden' }); check(await page.getByLabel('当前厂站').inputValue() === 'mock-site-1', '取消切站保留上下文')
    await button('用户菜单').click(); await page.getByText('退出登录', { exact:true }).click(); await button('保持当前会话').click(); await page.getByRole('dialog', { name:'结束本地会话后离开？' }).waitFor({ state:'hidden' }); check(await button('用户菜单').count() === 1, '取消退出保留身份及会话')
    await contact('device-1-1-helmet').check(); await button('处理已有本地会话').click(); await button('打开已有会话').click(); await page.getByRole('dialog', { name:'已有活动本地会话' }).waitFor({ state:'hidden' }); check(await page.locator('#dispatch-current .dispatch-participant').count() === 2, '新呼叫不静默覆盖已有会话')
    await page.getByLabel('广播内容（最多200字）').fill('预置集合说明，未发送设备'); await button('创建本地广播任务').click(); await page.getByText('预置集合说明，未发送设备 ·', { exact:false }).waitFor()
    await button('本地广播成功').click(); await page.getByText(/安全帽1 · 本地成功/).waitFor(); check(true,'广播独立任务和明确本地回执')
    await button('结束本地会话').click(); await button('确认结束').click(); await page.getByText('尚无活动会话；不会自动连接。',{exact:true}).waitFor()
    await button('发起本地呼叫').click(); await button('本地超时').click(); await page.getByText('尚无活动会话；不会自动连接。',{exact:true}).waitFor(); check(true,'单呼超时结束且不自动重连')
    await button('服务未接入 · 本地工作空间：打开场景控制').click(); await button('读取本地求助对象').click(); await page.getByLabel('求助来源设备').selectOption('device-1-1-belt'); await button('触发本地 SOS').click(); await page.getByRole('heading',{name:'SOS 紧急详情',exact:true}).waitFor(); await page.getByText('关联会话：尚无会话；报警可独立存在',{exact:true}).waitFor()
    check(await button('发起本地呼叫').isDisabled(), '安全带SOS独立存在但电话不可接通')
    const sosUrl=page.url(); await page.getByRole('link',{name:'进入事件处置与记录',exact:true}).click(); await button('认领事件').click(); await page.locator('.event-phase.PROCESSING').waitFor(); await page.getByRole('link',{name:'← 返回来源页面',exact:true}).click(); await page.getByRole('heading',{name:'SOS 紧急详情',exact:true}).waitFor(); check(page.url()===sosUrl,'SOS处置后安全返回来源详情')
    await button('服务未接入 · 本地工作空间：打开场景控制').click(); await button('本地会话失效').click(); await button('进入系统').waitFor(); check(page.url().includes('redirect='),'SOS登录恢复保留目标')
    await page.getByLabel('预置身份', { exact:true }).selectOption('reader'); await button('进入系统').click(); await page.getByRole('heading',{name:'SOS 紧急详情',exact:true}).waitFor(); await button('发起本地呼叫').waitFor(); check(await button('发起本地呼叫').isDisabled(),'只读身份不能发起协同')
    await page.reload(); await page.getByText('来源对象不存在或不可见',{exact:false}).waitFor(); check(true,'刷新清空合成SOS和协同记录')
    check(errors.length === 0,'无运行异常：'+errors.join(';')); check(network.length === 0,'无真实服务和写请求：'+network.join(';'))
    return checks
  } finally { page.off('pageerror',onError); page.off('request',onRequest) }
}
