async page => {
  const origin=page.url().split('/').slice(0,3).join('/'), checks=[], errors=[], network=[]
  const button=name=>page.getByRole('button',{name,exact:true}), check=(ok,label)=>{if(!ok)throw Error(label);checks.push(label)}
  const error=e=>errors.push(e.message), request=r=>{if(!r.url().startsWith(origin+'/')||r.method()!=='GET'||/\/(api\/portal|dev-api|demo-api)\//.test(r.url()))network.push(r.url())}
  page.on('pageerror',error);page.on('request',request)
  try {
    await page.reload();await page.getByRole('button',{name:/^(用户菜单|进入系统)$/}).first().waitFor()
    if(await button('用户菜单').count()){await button('用户菜单').click();await page.getByText('退出登录',{exact:true}).click()}
    await page.getByLabel('预置身份',{exact:true}).selectOption('owner');await button('进入系统').click();await button('用户菜单').waitFor()
    for(const [width,height]of [[1440,900],[1672,941],[1920,1080]]){
      await page.setViewportSize({width,height})
      for(const label of ['安全总览','现场监看','人员装备','作业监护','事件处置','调度协同','查询分析']){
        await page.getByRole('navigation',{name:'前台主导航'}).getByRole('link',{name:label,exact:true}).click();await page.waitForTimeout(550)
        check(!await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),'七菜单布局 '+label+' '+width)
        if(label==='安全总览')await page.screenshot({path:'output/playwright/v27-workbench-'+width+'.png'})
      }
    }
    await page.getByRole('link',{name:'安全总览',exact:true}).click();await page.locator('.workbench-metrics').waitFor()
    await page.locator('.workbench-event[href$="selectedId=event-1-1"]').click();await page.locator('.event-table').waitFor()
    await page.getByRole('link',{name:'查看核验详情',exact:true}).click();await button('认领事件').waitFor();await button('认领事件').click();await page.locator('.event-phase.PROCESSING').waitFor()
    await button('转现场核验').click();await page.locator('.event-phase.AWAITING_VERIFICATION').waitFor();await button('编写核验 / 我的草稿').click()
    const dialog=page.getByRole('dialog',{name:'本地核验编辑',exact:true});await dialog.getByLabel('核验结论',{exact:true}).selectOption('COMMUNICATION_ISSUE');await dialog.getByLabel('现场情况',{exact:true}).fill('V2-7预置核实，真实现场未验证')
    await button('提交核验').click();await button('确认操作').click();await dialog.waitFor({state:'hidden'});await page.locator('.event-phase.AWAITING_VERIFICATION').waitFor()
    await button('完成本地跟进').click();await button('确认操作').click();await page.locator('.event-phase.LOCAL_COMPLETED').waitFor()
    await page.goto(origin+'/#/statistics?siteId=mock-site-1&tab=events');await page.locator('[data-metric="completed"]').waitFor()
    check(await page.locator('[data-metric="completed"] strong').innerText()==='1','工作台进入事件显式完成后统计1')
    await page.locator('[data-metric="completed"]').click();check((await page.locator('.stats-table tbody').innerText()).includes('event-1-1'),'完成明细指向同一事件');await page.locator('.el-dialog__headerbtn:visible').click()
    await page.locator('.stat-chart button').first().focus();await page.keyboard.press('Enter');await page.locator('.stats-table').waitFor();check(true,'图表键盘下钻')
    await page.keyboard.press('Escape');await page.locator('.stats-table').waitFor({state:'hidden'})
    await page.reload();await page.locator('[data-metric="completed"]').waitFor();check(await page.locator('[data-metric="completed"] strong').innerText()==='0','完整刷新可重演')
    check(!errors.length,'无脚本错误 '+errors.join(';'));check(!network.length,'无真实网络 '+network.join(';'));return checks
  }finally{page.off('pageerror',error);page.off('request',request)}
}
