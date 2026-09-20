async page => {
  const origin = page.url().split('/').slice(0,3).join('/'), checks=[]
  const button = name => page.getByRole('button',{ name,exact:true }), check = (ok,name) => { if (!ok) throw Error(name); checks.push(name) }
  async function go(path) { await page.goto(origin + '/#' + path) }
  async function scenario(mode,slow=false) { await button('服务未接入 · 本地工作空间：打开场景控制').click(); await page.getByLabel('目标模块').selectOption('dispatch'); await page.getByLabel('查询场景').selectOption(mode); await page.getByRole('checkbox',{name:'该模块下一次查询延迟 3 秒'}).setChecked(slow); await button('应用场景').click(); await page.getByRole('dialog',{name:'本地场景控制'}).waitFor({state:'hidden'}) }
  await page.reload(); await button('用户菜单').waitFor(); await button('用户菜单').click(); await page.getByText('退出登录',{exact:true}).click(); await page.getByLabel('预置身份',{exact:true}).selectOption('owner'); await button('进入系统').click(); await button('用户菜单').waitFor()
  for (const path of ['/personnel/9007199254740993101?siteId=mock-site-1','/supervision/work-1-1?siteId=mock-site-1','/video/device-1-1-helmet?siteId=mock-site-1','/alarms/event-1-1/verification?siteId=mock-site-1']) {
    await go(path); await page.getByRole('link',{name:'联系协助（本地）',exact:true}).click(); await page.getByRole('heading',{name:'联系人与设备',exact:true}).waitFor(); check(await button('发起本地呼叫').isEnabled(),'共享协同入口 '+path.split('?')[0])
  }
  await button('发起本地呼叫').click(); await button('本地会话就绪').waitFor()
  await button('处理已有本地会话').click(); await button('结束后新建').click(); await button('本地会话就绪').waitFor(); await page.waitForTimeout(400)
  await page.waitForFunction(() => [...document.querySelectorAll('.dispatch-record summary')].filter(e=>e.textContent.includes('平台语音')).length===2)
  check(true,'明确替换保留旧记录且仅一活动会话')
  await page.getByLabel('当前厂站').selectOption('mock-site-2'); await button('结束并离开').click(); await page.getByText('尚无活动会话；不会自动连接。',{exact:true}).waitFor(); check(await page.getByLabel('当前厂站').inputValue()==='mock-site-2','确认切站结束会话')
  await scenario('not-integrated'); await page.getByText('预置数据未接入',{exact:true}).waitFor(); check(await page.locator('.dispatch-contact').count()===0,'未接入不展示空联系人数量')
  await scenario('failure'); await page.getByText('预置数据不可用，请恢复场景',{exact:true}).waitFor(); check(true,'来源失败不降级')
  await scenario('normal',true); await page.getByLabel('当前厂站').selectOption('mock-site-empty'); await page.getByText('当前筛选没有联系人。',{exact:true}).waitFor(); await page.waitForTimeout(3200); check(await page.locator('.dispatch-contact').count()===0,'迟到响应不覆盖空厂站')
  await page.getByLabel('当前厂站').selectOption('mock-site-1'); await page.getByRole('heading',{name:'联系人与设备',exact:true}).waitFor()
  await button('服务未接入 · 本地工作空间：打开场景控制').click(); await button('读取本地求助对象').click(); await page.getByLabel('求助来源设备').selectOption('device-1-1-helmet'); await button('触发本地 SOS').click(); await page.getByRole('heading',{name:'SOS 紧急详情',exact:true}).waitFor(); await button('发起本地呼叫').waitFor()
  check(await page.locator('.dispatch-sos canvas').count()>0,'安全帽SOS冻结位置矢量图')
  for (const [width,height] of [[1440,900],[1672,941]]) { await page.setViewportSize({width,height}); check(!await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),'SOS无横向溢出'+width); await page.screenshot({path:'output/playwright/v26-sos-'+width+'.png'}) }
  await button('发起本地呼叫').click(); await button('本地会话就绪').click(); await page.waitForFunction(()=>document.querySelector('.dispatch-session-count')?.textContent.includes('1 / 1')); await button('结束本地会话').click(); await button('确认结束').click(); await page.getByText('尚无活动会话；不会自动连接。',{exact:true}).waitFor(); check((await page.locator('.dispatch-sos').innerText()).includes('待认领'),'结束SOS会话不完成事件')
  await page.getByRole('link',{name:'查看当前本地视频（非事发录像）',exact:true}).click(); await button('播放本地视频').waitFor(); check(await page.locator('video[src]').count()===0,'SOS视频不自动播放'); await page.getByRole('link',{name:'← 返回来源页面',exact:true}).click(); await button('发起本地呼叫').waitFor()
  await button('发起本地呼叫').click(); await button('本地会话就绪').waitFor(); await button('服务未接入 · 本地工作空间：打开场景控制').click(); await button('本地会话失效').click(); await button('进入系统').waitFor(); await page.getByLabel('预置身份',{exact:true}).selectOption('verifier'); await button('进入系统').click(); await page.getByText('尚无活动会话；不会自动连接。',{exact:true}).waitFor(); check(await button('发起本地呼叫').isDisabled(),'失效清理会话且核验员只读')
  return checks
}
