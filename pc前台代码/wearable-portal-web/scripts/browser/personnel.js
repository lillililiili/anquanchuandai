async (page) => {
  const origin = page.url().includes(':5177') ? 'http://localhost:5177' : 'http://localhost:5176';
  const samples = {"context-authorized":{"sites":[{"siteId":"syn-site-1","name":"合成厂站","timeZone":null}],"selectedSiteId":"syn-site-1","areas":[],"teams":[],"shifts":[{"shiftId":"syn-shift-1","siteId":"syn-site-1","name":"合成班次","startsAt":null,"endsAt":null,"isCurrent":true}],"availability":{"roster":"AVAILABLE","areas":"NOT_INTEGRATED","teams":"NOT_INTEGRATED","shifts":"AVAILABLE"},"capabilities":{"people":{"state":"SUPPORTED","reasonCode":null},"equipmentHistory":{"state":"UNKNOWN","reasonCode":"HISTORY_NOT_INTEGRATED"}},"permissions":["portal:person:read"]},"context-no-scope":{"sites":[],"selectedSiteId":null,"areas":[],"teams":[],"shifts":[],"availability":{"roster":"NOT_INTEGRATED","areas":"NOT_INTEGRATED","teams":"NOT_INTEGRATED","shifts":"NOT_INTEGRATED"},"capabilities":{"people":{"state":"UNSUPPORTED","reasonCode":"NO_AUTHORIZED_SITE"},"equipmentHistory":{"state":"UNKNOWN","reasonCode":"HISTORY_NOT_INTEGRATED"}},"permissions":[]},"people-roster-missing":{"state":"NOT_INTEGRATED","reasonCode":"ROSTER_NOT_INTEGRATED","items":[],"total":null,"pageNum":1,"pageSize":20,"scope":{"siteId":"syn-site-1","shiftId":"syn-shift-1"}},"people-empty":{"state":"AVAILABLE","reasonCode":null,"items":[],"total":0,"pageNum":1,"pageSize":20,"scope":{"siteId":"syn-site-1","shiftId":"syn-shift-1"}},"people-equipment-states":{"state":"AVAILABLE","reasonCode":null,"items":[{"personId":"syn-person-1","personCode":"SYN-P-001","name":"合成人员甲","avatarUrl":null,"phoneMasked":null,"siteId":"syn-site-1","team":null,"area":null,"accountId":null,"legacy":{"userId":null},"dataUpdatedAt":null,"duty":{"state":"AVAILABLE","data":{"shiftId":"syn-shift-1","state":"ON_DUTY"},"reasonCode":null},"works":{"state":"NOT_INTEGRATED","data":null,"reasonCode":"SOURCE_NOT_INTEGRATED"},"equipment":{"state":"AVAILABLE","data":{"helmet":{"type":"HELMET","assignmentState":"ASSIGNED","devices":[{"deviceId":"syn-device-1","deviceCode":"SYN-H-001","type":"HELMET","model":null,"legacyHatId":"9007199254740993","communication":{"state":"OFFLINE","sourceKind":"PLATFORM_QUERY","sourceTime":null,"receivedAt":null,"observedAt":"2026-09-17T03:00:00Z","freshness":"UNKNOWN","reasonCode":"SOURCE_TIME_MISSING"},"battery":{"value":null,"sourceTime":null,"receivedAt":null,"freshness":"UNKNOWN","reasonCode":"SOURCE_SEMANTICS_UNCONFIRMED"},"capabilities":{"video":{"state":"UNKNOWN","verification":"UNVERIFIED","reasonCode":"CAPABILITY_NOT_VERIFIED"},"talk":{"state":"UNKNOWN","verification":"UNVERIFIED","reasonCode":"CAPABILITY_NOT_VERIFIED"},"location":{"state":"UNKNOWN","verification":"UNVERIFIED","reasonCode":"CAPABILITY_NOT_VERIFIED"},"capture":{"state":"UNKNOWN","verification":"UNVERIFIED","reasonCode":"CAPABILITY_NOT_VERIFIED"},"record":{"state":"UNKNOWN","verification":"UNVERIFIED","reasonCode":"CAPABILITY_NOT_VERIFIED"}},"manufacturerExtensions":{}}],"reasonCode":null},"belt":{"type":"BELT","assignmentState":"UNKNOWN","devices":[],"reasonCode":"ASSIGNMENT_SOURCE_NOT_INTEGRATED"},"watch":{"type":"WATCH","assignmentState":"UNASSIGNED","devices":[],"reasonCode":"AUTHORITATIVE_NO_ASSIGNMENT"}},"reasonCode":null},"actions":{"viewHistory":{"allowed":false,"reasonCode":"HISTORY_NOT_INTEGRATED"},"viewVideo":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"},"talk":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"},"viewWork":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"},"viewEvent":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"}}}],"total":1,"pageNum":1,"pageSize":20,"scope":{"siteId":"syn-site-1","shiftId":"syn-shift-1"}},"person-detail":{"person":{"personId":"syn-person-1","personCode":"SYN-P-001","name":"合成人员甲","avatarUrl":null,"phoneMasked":null,"siteId":"syn-site-1","team":null,"area":null,"accountId":null,"legacy":{"userId":null},"dataUpdatedAt":null,"duty":{"state":"AVAILABLE","data":{"shiftId":"syn-shift-1","state":"ON_DUTY"},"reasonCode":null},"works":{"state":"NOT_INTEGRATED","data":null,"reasonCode":"SOURCE_NOT_INTEGRATED"},"equipment":{"state":"AVAILABLE","data":{"helmet":{"type":"HELMET","assignmentState":"ASSIGNED","devices":[{"deviceId":"syn-device-1","deviceCode":"SYN-H-001","type":"HELMET","model":null,"legacyHatId":"9007199254740993","communication":{"state":"OFFLINE","sourceKind":"PLATFORM_QUERY","sourceTime":null,"receivedAt":null,"observedAt":"2026-09-17T03:00:00Z","freshness":"UNKNOWN","reasonCode":"SOURCE_TIME_MISSING"},"battery":{"value":null,"sourceTime":null,"receivedAt":null,"freshness":"UNKNOWN","reasonCode":"SOURCE_SEMANTICS_UNCONFIRMED"},"capabilities":{"video":{"state":"UNKNOWN","verification":"UNVERIFIED","reasonCode":"CAPABILITY_NOT_VERIFIED"},"talk":{"state":"UNKNOWN","verification":"UNVERIFIED","reasonCode":"CAPABILITY_NOT_VERIFIED"},"location":{"state":"UNKNOWN","verification":"UNVERIFIED","reasonCode":"CAPABILITY_NOT_VERIFIED"},"capture":{"state":"UNKNOWN","verification":"UNVERIFIED","reasonCode":"CAPABILITY_NOT_VERIFIED"},"record":{"state":"UNKNOWN","verification":"UNVERIFIED","reasonCode":"CAPABILITY_NOT_VERIFIED"}},"manufacturerExtensions":{}}],"reasonCode":null},"belt":{"type":"BELT","assignmentState":"UNKNOWN","devices":[],"reasonCode":"ASSIGNMENT_SOURCE_NOT_INTEGRATED"},"watch":{"type":"WATCH","assignmentState":"UNASSIGNED","devices":[],"reasonCode":"AUTHORITATIVE_NO_ASSIGNMENT"}},"reasonCode":null},"actions":{"viewHistory":{"allowed":false,"reasonCode":"HISTORY_NOT_INTEGRATED"},"viewVideo":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"},"talk":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"},"viewWork":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"},"viewEvent":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"}}},"equipment":{"state":"AVAILABLE","data":{"helmet":{"type":"HELMET","assignmentState":"ASSIGNED","devices":[{"deviceId":"syn-device-1","deviceCode":"SYN-H-001","type":"HELMET","model":null,"legacyHatId":"9007199254740993","communication":{"state":"OFFLINE","sourceKind":"PLATFORM_QUERY","sourceTime":null,"receivedAt":null,"observedAt":"2026-09-17T03:00:00Z","freshness":"UNKNOWN","reasonCode":"SOURCE_TIME_MISSING"},"battery":{"value":null,"sourceTime":null,"receivedAt":null,"freshness":"UNKNOWN","reasonCode":"SOURCE_SEMANTICS_UNCONFIRMED"},"capabilities":{"video":{"state":"UNKNOWN","verification":"UNVERIFIED","reasonCode":"CAPABILITY_NOT_VERIFIED"},"talk":{"state":"UNKNOWN","verification":"UNVERIFIED","reasonCode":"CAPABILITY_NOT_VERIFIED"},"location":{"state":"UNKNOWN","verification":"UNVERIFIED","reasonCode":"CAPABILITY_NOT_VERIFIED"},"capture":{"state":"UNKNOWN","verification":"UNVERIFIED","reasonCode":"CAPABILITY_NOT_VERIFIED"},"record":{"state":"UNKNOWN","verification":"UNVERIFIED","reasonCode":"CAPABILITY_NOT_VERIFIED"}},"manufacturerExtensions":{}}],"reasonCode":null},"belt":{"type":"BELT","assignmentState":"UNKNOWN","devices":[],"reasonCode":"ASSIGNMENT_SOURCE_NOT_INTEGRATED"},"watch":{"type":"WATCH","assignmentState":"UNASSIGNED","devices":[],"reasonCode":"AUTHORITATIVE_NO_ASSIGNMENT"}},"reasonCode":null},"works":{"state":"NOT_INTEGRATED","data":null,"reasonCode":"SOURCE_NOT_INTEGRATED"},"duty":{"state":"AVAILABLE","data":{"shiftId":"syn-shift-1","state":"ON_DUTY"},"reasonCode":null},"events":{"state":"NOT_INTEGRATED","data":null,"reasonCode":"SOURCE_NOT_INTEGRATED"},"location":{"state":"NOT_INTEGRATED","data":null,"reasonCode":"HISTORICAL_ATTRIBUTION_UNKNOWN"},"media":{"state":"NOT_INTEGRATED","data":null,"reasonCode":"SOURCE_NOT_INTEGRATED"},"historySummary":{"state":"NOT_INTEGRATED","data":null,"reasonCode":"HISTORY_NOT_INTEGRATED"},"actions":{"viewHistory":{"allowed":false,"reasonCode":"HISTORY_NOT_INTEGRATED"},"viewVideo":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"},"talk":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"},"viewWork":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"},"viewEvent":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"}}},"history-snapshot":{"state":"AVAILABLE","reasonCode":null,"items":[{"recordId":"syn-record-1","relationId":"syn-relation-1","personId":"syn-person-1","deviceId":"syn-device-1","deviceCode":"SYN-H-001","deviceType":"HELMET","action":"MIGRATION_SNAPSHOT","occurredAt":null,"startedAt":null,"endedAt":null,"operator":null,"state":"UNKNOWN","evidenceQuality":"CURRENT_SNAPSHOT_ONLY","legacy":{"hatId":"9007199254740993","userId":null}}],"total":1,"pageNum":1,"pageSize":20,"scope":{"siteId":"syn-site-1"}},"history-missing":{"state":"NOT_INTEGRATED","reasonCode":"HISTORY_NOT_INTEGRATED","items":[],"total":null,"pageNum":1,"pageSize":20,"scope":{"siteId":"syn-site-1"}},"detail-partial-failure":{"person":{"personId":"syn-person-1","personCode":"SYN-P-001","name":"合成人员甲","avatarUrl":null,"phoneMasked":null,"siteId":"syn-site-1","team":null,"area":null,"accountId":null,"legacy":{"userId":null},"dataUpdatedAt":null,"duty":{"state":"AVAILABLE","data":{"shiftId":"syn-shift-1","state":"ON_DUTY"},"reasonCode":null},"works":{"state":"NOT_INTEGRATED","data":null,"reasonCode":"SOURCE_NOT_INTEGRATED"},"equipment":{"state":"UNAVAILABLE","data":null,"reasonCode":"SOURCE_UNAVAILABLE"},"actions":{"viewHistory":{"allowed":false,"reasonCode":"SECTION_FORBIDDEN"},"viewVideo":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"},"talk":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"},"viewWork":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"},"viewEvent":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"}}},"equipment":{"state":"UNAVAILABLE","data":null,"reasonCode":"SOURCE_UNAVAILABLE"},"works":{"state":"NOT_INTEGRATED","data":null,"reasonCode":"SOURCE_NOT_INTEGRATED"},"duty":{"state":"AVAILABLE","data":{"shiftId":"syn-shift-1","state":"ON_DUTY"},"reasonCode":null},"events":{"state":"NOT_INTEGRATED","data":null,"reasonCode":"SOURCE_NOT_INTEGRATED"},"location":{"state":"NOT_INTEGRATED","data":null,"reasonCode":"HISTORICAL_ATTRIBUTION_UNKNOWN"},"media":{"state":"NOT_INTEGRATED","data":null,"reasonCode":"SOURCE_NOT_INTEGRATED"},"historySummary":{"state":"FORBIDDEN","data":null,"reasonCode":"SECTION_FORBIDDEN"},"actions":{"viewHistory":{"allowed":false,"reasonCode":"SECTION_FORBIDDEN"},"viewVideo":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"},"talk":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"},"viewWork":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"},"viewEvent":{"allowed":false,"reasonCode":"MODULE_NOT_ENABLED"}}}};
  const copy = x => JSON.parse(JSON.stringify(x));
  const checks = [], errors = [], commands = [], assets = [];
  const verify = (ok, msg) => { if (!ok) throw new Error(msg); checks.push(msg); };
  const onError = e => errors.push(e.message);
  const onResponse = r => { if (/\.(js|css|webp|svg)(\?|$)/.test(r.url()) && r.status() >= 400) assets.push(r.url()); };
  page.on('pageerror', onError); page.on('response', onResponse);
  let mode = 'normal', calls = 0, lastParams, logged = false, historyPage = 0;
  const context = copy(samples['context-authorized']);
  context.sites.push({siteId:'syn-site-2',name:'合成厂站乙',timeZone:null});
  context.shifts.push({shiftId:'syn-shift-2',siteId:'syn-site-2',name:'合成班次乙',startsAt:null,endsAt:null,isCurrent:true});
  const detail = copy(samples['person-detail']);
  detail.actions.viewHistory = {allowed:true,reasonCode:null}; detail.person.actions = detail.actions;
  detail.historySummary = {state:'AVAILABLE',data:{total:0,lastOccurredAt:null},reasonCode:null};
  await page.unroute('**/*-api/**');
  await page.route('**/*-api/**', async route => {
    const req = route.request(), raw = req.url(), path = raw.split('?')[0].replace(/^https?:\/\/[^/]+/, '');
    const params = Object.fromEntries((raw.split('?')[1] || '').split('&').filter(Boolean).map(pair => { const [k,v=''] = pair.split('='); return [decodeURIComponent(k),decodeURIComponent(v.replace(/\+/g,' '))]; }));
    const url = { searchParams: { get: key => params[key] || null } };
    let data, status = 200;
    if (path.endsWith('/captchaImage')) data = {code:200,captchaEnabled:false};
    else if (path.endsWith('/login')) { logged = true; data = {code:200,token:'s1-browser-only-token'}; }
    else if (path.endsWith('/getInfo')) data = logged ? {code:200,user:{userName:'s1-test',nickName:'隔离测试'},roles:[],permissions:['portal:person:read','portal:person:history']} : {code:401,msg:'测试会话已失效'};
    else if (path.endsWith('/logout')) { logged = false; data = {code:200}; }
    else if (path.endsWith('/context')) data = {code:200,data:mode === 'noScope' ? {...copy(samples['context-no-scope']),capabilities:{people:{state:'UNKNOWN',reasonCode:'SITE_SCOPE_NOT_INTEGRATED'}}} : context};
    else if (path.endsWith('/people')) {
      calls++; lastParams = params;
      if (mode === 'fail') { status=503;data={code:503,errorCode:'SOURCE_UNAVAILABLE',requestId:'s1-error',msg:'合成数据源不可用'}; }
      else if(mode === '401') { data={code:401,msg:'合成会话过期'};logged=false; }
      else {
        const d = copy(samples[mode === 'empty' ? 'people-empty' : mode === 'missing' ? 'people-roster-missing' : 'people-equipment-states']);
        d.pageNum=Number(url.searchParams.get('pageNum')||1);d.pageSize=Number(url.searchParams.get('pageSize')||20);
        d.scope.siteId=url.searchParams.get('siteId');
        if(d.items.length) {
          d.total=21; d.items[0].siteId=d.scope.siteId;
          if(d.scope.siteId==='syn-site-2')d.items[0].name='合成人员乙';
          if(mode==='long') {d.items[0].name='用于验收超长姓名的合成人员甲';d.items[0].equipment.data.helmet.devices[0].deviceCode='SYN-HELMET-VERY-LONG-DEVICE-CODE-000000000001';}
          if(mode==='stale') {d.items[0].equipment.data.helmet.devices[0].communication.sourceTime='2026-09-17T02:00:00Z';d.items[0].equipment.data.helmet.devices[0].communication.freshness='STALE';}
        }
        if(mode==='race' && url.searchParams.get('keyword')==='旧条件') await page.waitForTimeout(700);
        data={code:200,data:d};
      }
    }
    else if(path.endsWith('/equipment-history')) {
      historyPage=Number(url.searchParams.get('pageNum')||1);
      const h=copy(samples['history-snapshot']);h.pageNum=historyPage;h.pageSize=10;h.total=11;
      data={code:200,data:h};
    }
    else if(/\/people\//.test(path)) {
      if(mode==='404') {status=404;data={code:404,errorCode:'PERSON_NOT_FOUND',msg:'人员不存在或不可见'};}
      else if(mode==='partial') data={code:200,data:copy(samples['detail-partial-failure'])};
      else {const d=copy(detail); if(mode==='long')d.person.name='用于验收超长姓名的合成人员甲';data={code:200,data:d};}
    } else { commands.push(path);data={code:500,msg:'测试禁止未声明请求'}; }
    if(!['GET'].includes(req.method()) && !/\/(login|logout)$/.test(path)) commands.push(path);
    if(data.code===200) {data.requestId='s1-fixture';data.asOf='2026-09-17T03:00:00Z';}
    try {await route.fulfill({status,contentType:'application/json',body:JSON.stringify(data)});} catch(e) { if(!route.request().failure()) throw e; }
  });
  await page.goto(origin + '/#/login');
  await page.evaluate(()=>sessionStorage.removeItem('Wearable-Portal-Token'));
  await page.goto('about:blank');
  await page.goto(origin + '/#/personnel?siteId=syn-site-1');
  await page.getByRole('textbox',{name:'账号',exact:true}).waitFor();
  verify(page.url().includes('/login?redirect='),'未登录拦截');
  await page.getByRole('textbox',{name:'账号',exact:true}).fill('s1-test');
  await page.getByRole('textbox',{name:'密码',exact:true}).fill('test-only-not-real');
  await page.getByRole('button',{name:'登录',exact:true}).click();
  await page.locator('.people-table tbody tr').first().waitFor();
  verify(page.url().includes('/personnel?siteId=syn-site-1'),'登录恢复人员列表');
  verify(await page.getByText('请选择人员',{exact:true}).isVisible(),'默认未选择人员');
  await page.locator('.person-row-button').first().click();
  await page.getByRole('button',{name:'查看完整详情',exact:true}).waitFor();
  for(const tab of ['装备信息','作业信息','事件信息','人员信息']) await page.getByRole('tab',{name:tab,exact:true}).click();
  verify(await page.getByRole('tab',{name:'人员信息',exact:true}).getAttribute('aria-selected')==='true','右侧四标签切换');
  verify(await page.getByRole('tabpanel',{name:'人员信息'}).getByText('领用情况未知',{exact:true}).isVisible(),'未知领用不显示未领用');
  verify(await page.getByRole('tabpanel',{name:'人员信息'}).getByText('未领用',{exact:true}).isVisible(),'明确未领用状态');
  verify(await page.getByRole('tabpanel',{name:'人员信息'}).getByText('离线',{exact:true}).isVisible(),'离线状态显示');
  for(const [width,height] of [[1672,941],[1440,900]]) {
    await page.setViewportSize({width,height});
    await page.screenshot({path:'output/playwright/s1-F07-'+width+'.png'});
    verify(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth && document.querySelector('.main-content').scrollWidth<=document.querySelector('.main-content').clientWidth),'F07无页面横向溢出 '+width);
  }
  await page.getByRole('button',{name:'查看完整详情',exact:true}).click();
  await page.getByRole('region',{name:'领用绑定历史',exact:true}).waitFor();
  await page.getByRole('cell',{name:'当前关系快照（非领用流水） 历史证据不足',exact:true}).waitFor();
  verify(page.url().includes('/personnel/syn-person-1'),'独立详情路由');
  verify(await page.getByRole('cell',{name:'当前关系快照（非领用流水） 历史证据不足',exact:true}).isVisible(),'快照不冒充领取历史');
  await page.reload();await page.getByRole('cell',{name:'当前关系快照（非领用流水） 历史证据不足',exact:true}).waitFor();
  checks.push('详情刷新及历史加载');
  await page.getByRole('region',{name:'领用绑定历史',exact:true}).locator('.el-pager').getByText('2',{exact:true}).click();
  await page.waitForTimeout(150);verify(historyPage===2,'领用历史独立分页');
  await page.screenshot({path:'output/playwright/s1-history-pagination.png'});
  for(const [width,height] of [[1672,941],[1440,900]]) {
    await page.setViewportSize({width,height});
    await page.evaluate(()=>document.querySelector('.main-content').scrollTo(0,0));
    await page.screenshot({path:'output/playwright/s1-F03-'+width+'.png',fullPage:true});
    verify(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth && document.querySelector('.main-content').scrollWidth<=document.querySelector('.main-content').clientWidth),'F03无页面横向溢出 '+width);
  }
  await page.getByRole('link',{name:'← 返回人员列表',exact:true}).click();await page.locator('.people-table tbody tr').first().waitFor();
  verify(page.url().includes('siteId=syn-site-1'),'返回筛选');
  await page.getByRole('textbox',{name:'姓名或人员编号'}).fill('合成');
  await page.getByRole('button',{name:'查询',exact:true}).click();
  await page.waitForFunction(()=>location.hash.includes('keyword='));
  await page.getByText('请选择人员',{exact:true}).waitFor();
  verify(lastParams.keyword==='合成','筛选参数与清除选中');
  const pager=page.locator('.el-pager').getByText('2',{exact:true});await pager.click();
  await page.waitForFunction(()=>location.hash.includes('pageNum=2'));
  checks.push('人员分页');
  mode='stale';await page.reload();await page.locator('.people-table').getByText('数据已过期',{exact:true}).waitFor();checks.push('过期数据与离线分开显示');
  mode='empty'; await page.reload();await page.getByText('暂无当班人员',{exact:true}).waitFor();checks.push('空名册显示0人');
  mode='missing';await page.reload();await page.getByText('当班名册未接入',{exact:true}).waitFor();verify(await page.getByText('共 0 人',{exact:true}).count()===0,'未接入不显示0人');
  mode='fail';await page.reload();await page.getByText('合成数据源不可用',{exact:true}).waitFor();checks.push('503失败不伪装空数据');
  mode='normal';await page.getByRole('button',{name:'重新读取',exact:true}).click();await page.locator('.people-table tbody tr').first().waitFor();checks.push('失败可重试');
  mode='race';await page.getByRole('textbox',{name:'姓名或人员编号'}).fill('旧条件');await page.getByRole('button',{name:'查询',exact:true}).click();
  await page.getByRole('combobox',{name:'当前厂站'}).selectOption('syn-site-2');
  await page.locator('.person-row-button').getByText('合成人员乙',{exact:true}).waitFor();
  await page.waitForTimeout(900);verify(await page.locator('.person-row-button').getByText('合成人员乙',{exact:true}).isVisible(),'切厂站旧请求不覆盖');
  mode='long';await page.getByRole('combobox',{name:'当前厂站'}).selectOption('syn-site-1');await page.locator('.person-row-button').first().waitFor();
  await page.setViewportSize({width:1440,height:900});await page.locator('.person-row-button').first().focus();await page.keyboard.press('Enter');await page.getByRole('button',{name:'查看完整详情',exact:true}).waitFor();checks.push('键盘选择人员');
  await page.screenshot({path:'output/playwright/s1-long-text.png'});
  verify(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'长文本无整页溢出');
  mode='partial';await page.getByRole('button',{name:'查看完整详情',exact:true}).click();await page.getByText('数据源暂时不可用，请稍后重试',{exact:true}).waitFor();checks.push('装备分区失败');
  verify(await page.getByText('当前账号无权查看',{exact:true}).isVisible(),'历史分区无权限');
  mode='404';await page.reload();await page.getByText('人员不存在或当前账号不可见',{exact:true}).waitFor();checks.push('详情404');
  mode='noScope';await page.goto(origin + '/#/personnel');await page.reload();await page.locator('.personnel-table-panel').getByText('厂站数据待接入',{exact:true}).waitFor();checks.push('默认来源未接入');
  mode='normal';await page.reload();await page.locator('.people-table tbody tr').first().waitFor();
  mode='401';await page.reload();await page.getByRole('textbox',{name:'账号',exact:true}).waitFor();
  verify(await page.evaluate(()=>sessionStorage.getItem('Wearable-Portal-Token'))===null,'业务401清理会话');
  verify(page.url().includes('/login?redirect='),'401保留恢复目标');
  mode='normal';
  await page.goto(origin + '/#/personnel/syn-person-1?siteId=syn-site-1&returnTo=' + encodeURIComponent('/personnel?siteId=syn-site-1&keyword=合成'));
  await page.getByRole('textbox',{name:'账号',exact:true}).fill('s1-test');
  await page.getByRole('textbox',{name:'密码',exact:true}).fill('test-only-not-real');
  await page.getByRole('button',{name:'登录',exact:true}).click();
  await page.getByRole('region',{name:'人员装备',exact:true}).waitFor();
  verify(page.url().includes('/personnel/syn-person-1?'),'登录恢复独立人员详情');
  await page.getByRole('link',{name:'← 返回人员列表',exact:true}).click();
  await page.locator('.people-table tbody tr').first().waitFor();
  verify(page.url().includes('keyword='),'独立详情登录后返回原筛选');
  await page.getByRole('button',{name:'用户菜单',exact:true}).click();
  await page.getByRole('menuitem',{name:'退出登录',exact:true}).click();
  await page.getByRole('textbox',{name:'账号',exact:true}).waitFor();
  verify(await page.evaluate(()=>sessionStorage.getItem('Wearable-Portal-Token'))===null,'退出清理会话和上下文');
  verify(commands.length===0,'无设备命令或未声明请求');verify(errors.length===0,'无浏览器异常 '+errors.join(','));verify(assets.length===0,'无资源404');
  page.off('pageerror',onError);page.off('response',onResponse);
  return {checks,calls,errors,commands,assets};
}
