async (page) => {
  const origin = page.url().includes(':5177') ? 'http://localhost:5177' : 'http://localhost:5176';
  const checks=[], forbidden=[], errors=[], assets=[], calls=[];
  const verify=(value,name)=>{if(!value)throw Error(name);checks.push(name);};
  let mode='normal';
  const missing=(reasonCode='SOURCE_NOT_INTEGRATED')=>({state:'NOT_INTEGRATED',data:null,reasonCode});
  const section=data=>({state:'AVAILABLE',data,reasonCode:null});
  const ctx={sites:[{siteId:'s',name:'隔离厂站甲',timeZone:'Asia/Shanghai'},{siteId:'s2',name:'隔离厂站乙',timeZone:null}],selectedSiteId:'s',areas:[],teams:[],shifts:[],availability:{roster:'NOT_INTEGRATED'},capabilities:{people:{state:'UNKNOWN',reasonCode:'SITE_SCOPE_NOT_INTEGRATED'},events:{state:'UNKNOWN'}},permissions:['portal:event:read','portal:event:verification:read','portal:person:read','portal:video:read','portal:material:read','portal:location:read']};
  const ref=(id,site,name)=>({id,siteId:site,name,attribution:'CONFIRMED',evidenceId:'proof',snapshotKind:'HISTORICAL',sourceTime:null});
  const fact=(id,site)=>({eventId:id,eventCode:id,siteId:site,title:mode==='long'?'用于校验长标题和未知归属的合成异常事件'.repeat(6):'合成设备异常',sourceSystem:'ISOLATED',sourceEventId:id,eventType:'TEST',rawType:'fall',rawLevel:'来源等级',legacyHandled:1,phase:'UNKNOWN',deviceId:'d',deviceCode:'SYN-D',occurredAt:null,receivedAt:'2026-09-17T00:01:00Z',sourceUpdatedAt:null,freshness:'UNKNOWN',person:missing('HISTORICAL_ATTRIBUTION_UNKNOWN')});
  const evidence=site=>({...ref('m',site,'合成证据资料'),type:'PHOTO',version:'v1',digest:'test-only-digest',capturedAt:null,receivedAt:'2026-09-17T00:01:00Z'});
  const handler=async route=>{
    const req=route.request(),raw=req.url();if(!raw.startsWith(origin+'/')){forbidden.push(raw);return route.abort();}if(!/\/(dev|prod|stage)-api\//.test(raw))return route.continue();
    const path=raw.split('?')[0].replace(/^https?:\/\/[^/]+/,'').replace(/^\/(dev|prod|stage)-api/,''),q=Object.fromEntries((raw.split('?')[1]||'').split('&').filter(Boolean).map(pair=>{const[k,v='']=pair.split('=');return[decodeURIComponent(k),decodeURIComponent(v.replace(/\+/g,' '))];})),site=q.siteId||'s';
    calls.push({path,q,method:req.method()});
    if(path==='/captchaImage')return route.fulfill({json:{code:200,captchaEnabled:false}});
    if(path==='/login')return route.fulfill({json:{code:200,token:'s4-isolated-token'}});
    if(path==='/getInfo')return route.fulfill({json:{code:200,user:{userId:1,nickName:'S4隔离测试'},roles:[],permissions:ctx.permissions}});
    if(path==='/logout')return route.fulfill({json:{code:200}});
    if(req.method()!=='GET')forbidden.push(req.method()+path);
    let data,code=200,status=200;
    const pageData=(items,total,eventId)=>({state:'AVAILABLE',reasonCode:null,items,total,pageNum:Number(q.pageNum||1),pageSize:Number(q.pageSize||20),scope:{siteId:site,...(eventId?{eventId}:{})}});
    if(path.endsWith('/context'))data=mode==='no-site'?{...ctx,sites:[],selectedSiteId:null}:ctx;
    else if(mode==='401')code=401;
    else if(mode==='forbidden')code=status=403;
    else if(mode==='failure'&&path.endsWith('/events')||mode==='summary-failure'&&path.endsWith('/summary')||mode==='detail-failure'&&/\/events\/e[12]$/.test(path))code=status=503;
    else if(path.endsWith('/events')){
      if(q.keyword==='old')await page.waitForTimeout(700);
      const rows=mode==='empty'||mode==='missing'?[]:[fact(q.keyword||'e1',site),fact('e2',site)];
      data={...pageData(rows,mode==='empty'?0:42),filters:{keyword:true,timeRange:true,phase:true,eventTypes:section([{value:'TEST',label:'来源合成类型'}])}};
      if(mode==='missing')Object.assign(data,{state:'NOT_INTEGRATED',total:null,reasonCode:'EVENT_NOT_INTEGRATED'});
    }else if(path.endsWith('/summary'))data=mode==='missing'?missing('STATISTICS_NOT_INTEGRATED'):section({total:42,counts:{UNCLAIMED:1,PROCESSING:2,AWAITING_VERIFICATION:3,LOCAL_COMPLETED:4,UNKNOWN:32},sourceTime:null});
    else if(/\/events\/[^/]+\/timeline$/.test(path)){
      const id=path.split('/').at(-2);data=pageData([{id:'t'+(q.pageNum||1),eventId:id,siteId:site,kind:'SOURCE_FACT',title:'来源事实记录第'+(q.pageNum||1)+'页',sequence:Number(q.pageNum||1),sourceTime:null}],11,id);
    }else if(/\/events\/[^/]+\/verifications$/.test(path)){
      const id=path.split('/').at(-2);if(mode==='verification-forbidden')code=status=403;
      else{const state=q.pageNum==='2'?'SUBMITTED':'DRAFT';data=pageData(mode==='no-records'?[]:[{id:'v'+(q.pageNum||1),eventId:id,siteId:site,state,conclusion:'UNCONFIRMED',scene:'合成现场情况，不能用作真实记录',measures:'待进一步核验',version:'1',sourceTime:null,submittedAt:state==='SUBMITTED'?'2026-09-17T00:00:00Z':null,evidence:section([evidence(site)])}],mode==='no-records'?0:12,id);}
    }else if(/\/events\/[^/]+$/.test(path)){
      const id=path.split('/').at(-1);if(id==='hidden')code=status=404;
      else data={event:fact(id,site),owner:section([ref('p',site,'合成负责人')]),equipment:section([{...ref('d',site,'合成安全帽'),deviceType:'HELMET',communication:'OFFLINE'},{...ref('current',site,'当前设备'),deviceType:'HELMET',communication:'ONLINE',snapshotKind:'CURRENT'}]),works:{state:'FORBIDDEN',data:null,reasonCode:'SECTION_FORBIDDEN'},location:section({...ref('loc',site,'事件位置'),longitude:0,latitude:0,coordinateSystem:'WGS84',quality:'VALID',freshness:'UNKNOWN',receivedAt:null}),video:section([ref('d',site,'合成安全帽')]),materials:section([evidence(site)]),summaryDelivery:section({state:'SUCCESS',sourceTime:null,receiptId:null}),verificationDelivery:section({state:'FAILED',sourceTime:null,receiptId:null}),originalSystem:section({sourceSystem:'ISOLATED',sourceEventId:'legacy',status:'原系统处理中',sourceTime:null})};
    }else{forbidden.push(path);code=status=500;}
    try{await route.fulfill({status,json:{code,data,msg:code===503?'隔离来源读取失败':code===403?'隔离权限拒绝':code===404?'事件不存在或不可见':'成功',errorCode:code===200?null:'TEST_'+code,requestId:'s4-isolated',asOf:'2026-09-17T00:00:00Z'}});}catch(e){if(!req.failure())throw e;}
  };
  const onError=e=>errors.push(e.message),onResponse=r=>{if(/\.(js|css|webp|svg)(\?|$)/.test(r.url())&&r.status()>=400)assets.push(r.url());};page.on('pageerror',onError);page.on('response',onResponse);
  await page.unrouteAll({behavior:'wait'});await page.route('**/*',handler);
  const goto=async path=>{await page.goto('about:blank');await page.goto(origin+'/#'+path);};
  async function snap(name,w,h){await page.setViewportSize({width:w,height:h});await page.locator('.main-content').evaluate(e=>{e.scrollTop=0;});await page.screenshot({path:`output/playwright/s4-${name}-${w}.png`});verify(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth&&document.querySelector('.main-content').scrollWidth<=document.querySelector('.main-content').clientWidth),name+'无横向溢出'+w);}
  try{
    await goto('/alarms?siteId=s');await page.getByRole('heading',{name:'工作账号登录'}).waitFor();verify(page.url().includes('redirect='),'未登录拦截');await page.getByRole('textbox',{name:'账号',exact:true}).fill('synthetic');await page.getByLabel('密码',{exact:true}).fill('isolated');await page.getByRole('button',{name:'登录',exact:true}).click();await page.locator('.event-row-select').first().waitFor();
    verify(await page.getByText('请选择事件查看摘要',{exact:true}).isVisible(),'初始不选择事件');verify((await page.locator('.event-statistics').innerText()).includes('32'),'独立统计不取当前页数量');
    await page.locator('.event-row-select').first().focus();await page.keyboard.press('Enter');await page.locator('.event-aside .event-facts').waitFor();verify(page.url().includes('selectedId=e1'),'键盘选择保存在query');verify((await page.locator('.event-aside').innerText()).includes('不等于已核验或结案'),'旧处理不冒充核验');verify((await page.locator('.event-aside').innerText()).includes('归属未知'),'未知历史归属');
    for(const[w,h]of[[1672,941],[1440,900]])await snap('F13',w,h);
    await page.getByRole('link',{name:'查看核验详情',exact:true}).click();await page.getByLabel('核验结论',{exact:true}).waitFor();await page.getByLabel('现场情况',{exact:true}).waitFor();await page.waitForTimeout(200);
    verify(await page.getByLabel('现场情况',{exact:true}).getAttribute('readonly')!==null,'核验表单只读');for(const label of ['保存草稿','提交核验记录','添加现场照片','选择证据'])verify(await page.getByRole('button',{name:label,exact:true}).isDisabled(),label+'禁用');
    verify((await page.locator('.event-verification-form').innerText()).includes('无法确认不等于完成跟进'),'无法确认不自动完成');verify((await page.locator('.event-equipment').innerText()).includes('当前状态，不代表事件时状态'),'历史快照和当前状态分开');
    for(const[w,h]of[[1672,941],[1440,900]])await snap('F12',w,h);
    const timelinePanel=page.locator('.event-section').filter({has:page.getByRole('heading',{name:'事实时间线',exact:true})}).first();await timelinePanel.locator('.btn-next').click();await page.getByText('来源事实记录第2页',{exact:true}).waitFor();verify(!calls.filter(c=>c.path.endsWith('/verifications')).at(-1).q.pageNum||calls.filter(c=>c.path.endsWith('/verifications')).at(-1).q.pageNum==='1','时间线独立分页');
    await page.locator('.event-verification-form').locator('.btn-next').click();await page.waitForTimeout(150);verify((await page.locator('.event-verification-form').innerText()).includes('已提交'),'已提交记录只读展示');verify(calls.filter(c=>c.path.endsWith('/timeline')).at(-1).q.pageNum==='2','核验分页不改时间线页');
    verify(await page.locator('video[src]').count()===0,'事件影像无真实拉流');verify((await page.getByRole('link',{name:/查看当前设备单路监看/}).getAttribute('href')).includes('/video/d?siteId=s'),'视频跳转保持厂站及设备');verify((await page.getByRole('link',{name:'查看授权资料元数据 ↗'}).first().getAttribute('href')).includes('selectedId=m'),'资料只跳元数据');
    await page.getByRole('link',{name:'← 返回列表'}).click();await page.locator('.event-aside .event-facts').waitFor();verify(page.url().includes('selectedId=e1'),'返回恢复选择');
    await page.getByLabel('发生时间起').fill('2026-09-17T08:00');await page.getByLabel('发生时间止').fill('2026-09-17T09:00');await page.getByRole('button',{name:'查询',exact:true}).click();await page.locator('.event-row-select').first().waitFor();verify(calls.filter(c=>c.path.endsWith('/events')).at(-1).q.from==='2026-09-17T00:00:00.000Z','厂站时区转换UTC');verify(!page.url().includes('selectedId='),'筛选清理选择');
    await page.locator('.event-table-panel').locator('.btn-next').click();await page.waitForTimeout(150);verify(page.url().includes('pageNum=2'),'事件列表分页');
    await page.evaluate(()=>{location.hash='/alarms?siteId=s&keyword=old';});await page.waitForTimeout(80);await page.evaluate(()=>{location.hash='/alarms?siteId=s&keyword=new';});await page.waitForTimeout(800);verify((await page.locator('.event-table').innerText()).includes('new')&&!(await page.locator('.event-table').innerText()).includes('old'),'查询竞态不覆盖');
    await page.getByLabel('当前厂站').selectOption('s2');await page.locator('.event-row-select').first().waitFor();verify(!page.url().includes('keyword=')&&page.url().includes('siteId=s2'),'切厂站清理条件');verify((await page.locator('.event-filters').innerText()).includes('按 UTC'),'厂站时区缺失显式UTC');
    mode='summary-failure';await goto('/alarms?siteId=s');await page.locator('.event-row-select').first().waitFor();verify(await page.getByText('隔离来源读取失败',{exact:true}).isVisible(),'统计失败不清空列表');
    mode='detail-failure';await goto('/alarms?siteId=s&selectedId=e1');await page.locator('.event-row-select').first().waitFor();await page.locator('.event-aside').getByText('隔离来源读取失败',{exact:true}).waitFor();checks.push('详情失败不清空列表');
    mode='verification-forbidden';await goto('/alarms/e1/verification?siteId=s');await page.locator('.event-verification-form').getByText('隔离权限拒绝',{exact:true}).waitFor();verify(await page.getByRole('heading',{name:'事实时间线',exact:true}).isVisible(),'核验拒绝不隐藏事件事实');
    mode='no-records';await goto('/alarms/e1/verification?siteId=s');await page.getByText('暂无核验记录',{exact:true}).waitFor();verify(await page.getByLabel('现场情况',{exact:true}).inputValue()==='','无记录不显示草稿示例');
    mode='normal';await goto('/alarms/hidden/verification?siteId=s');await page.getByText('事件不存在或不可见',{exact:true}).waitFor();checks.push('不可见事件404');
    mode='long';await goto('/alarms?siteId=s&selectedId=e1');await page.locator('.event-aside .event-facts').waitFor();await snap('long',1440,900);
    for(const[m,text]of[['empty','当前筛选范围暂无事件'],['missing','事件来源待接入'],['failure','隔离来源读取失败'],['forbidden','隔离权限拒绝'],['no-site','厂站数据待接入']]){mode=m;await goto('/alarms'+(m==='no-site'?'':'?siteId=s'));await page.locator('.event-table-panel').getByText(text,{exact:true}).first().waitFor();checks.push(m+'状态');}
    mode='normal';await goto('/alarms/e1/verification?siteId=s&returnTo=%2Falarms%3FsiteId%3Ds%26phase%3DUNKNOWN');await page.getByLabel('现场情况',{exact:true}).waitFor();mode='401';await page.reload();await page.getByRole('heading',{name:'工作账号登录'}).waitFor();verify(await page.evaluate(()=>!sessionStorage.getItem('Wearable-Portal-Token')),'会话失效清理');verify(page.url().includes('verification'),'会话失效保留核验目标');
    verify(forbidden.length===0,'无外部媒体、存储或写请求');verify(errors.length===0,'无浏览器异常');verify(assets.length===0,'无资源路径错误');return{count:checks.length,checks,forbidden,errors,assets};
  }finally{page.off('pageerror',onError);page.off('response',onResponse);await page.unrouteAll({behavior:'wait'});await page.evaluate(()=>sessionStorage.removeItem('Wearable-Portal-Token'));await goto('/login');}
}
