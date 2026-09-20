async page => {
  const checks=[], errors=[];let login=0,info=0,logout=0
  const error=e=>errors.push(e.message);page.on('pageerror',error)
  await page.route('**/stage-api/**',async route=>{
    const path=route.request().url().split('?')[0];let data
    if(path.endsWith('/captchaImage'))data={code:200,captchaEnabled:false}
    else if(path.endsWith('/login')){login++;data={code:200,token:'isolated-v27-fixture'}}
    else if(path.endsWith('/getInfo')){info++;if(route.request().headers().authorization!=='Bearer isolated-v27-fixture')throw Error('Bearer missing');data={code:200,user:{userId:'fixture',userName:'fixture',nickName:'隔离验收'},roles:[],permissions:[]}}
    else if(path.endsWith('/context'))data={code:200,data:{sites:[],selectedSiteId:null,areas:[],teams:[],shifts:[],permissions:[],availability:{roster:'NOT_INTEGRATED',areas:'NOT_INTEGRATED',teams:'NOT_INTEGRATED',shifts:'NOT_INTEGRATED'},capabilities:{people:{state:'UNKNOWN'},equipmentHistory:{state:'UNKNOWN'}}}}
    else if(path.endsWith('/logout')){logout++;data={code:200}}
    else throw Error('意外接口 '+path)
    await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(data)})
  })
  try{
    await page.goto('http://127.0.0.1:5190/'); await page.evaluate(() => sessionStorage.removeItem('Wearable-Portal-Token')); await page.goto('about:blank'); login=0; info=0; logout=0
    await page.goto('http://127.0.0.1:5190/#/statistics?tab=events');await page.getByRole('textbox',{name:'账号',exact:true}).fill('fixture');await page.getByRole('textbox',{name:'密码',exact:true}).fill('fixture-only');await page.getByRole('button',{name:'登录',exact:true}).click();await page.getByRole('heading',{name:'统计分析',exact:true,level:1}).waitFor()
    if(!page.url().includes('tab=events'))throw Error('恢复丢失统计参数');checks.push('正式认证和统计目标恢复')
    if(await page.getByRole('button',{name:'服务未接入 · 本地工作空间：打开场景控制'}).count()||await page.locator('.stats-metric').count())throw Error('正式模式出现本地统计');checks.push('正式统计未接入且无本地控件')
    for(const name of ['安全总览','现场监看','人员装备','作业监护','事件处置','调度协同','查询分析']){await page.getByRole('navigation',{name:'前台主导航'}).getByRole('link',{name,exact:true}).click();await page.waitForTimeout(250);checks.push('正式隔离导航 '+name)}
    await page.getByRole('button',{name:'用户菜单'}).click();await page.getByText('退出登录',{exact:true}).click();await page.getByRole('button',{name:'登录',exact:true}).waitFor()
    if(login!==1||info!==1||logout!==1||errors.length)throw Error(JSON.stringify({login,info,logout,errors}));checks.push('真实请求契约隔离测试退出通过，非真实后端验收');return checks
  }finally{await page.unroute('**/stage-api/**');page.off('pageerror',error)}
}
