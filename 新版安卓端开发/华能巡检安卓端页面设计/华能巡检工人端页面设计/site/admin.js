/* 本地页面演示；不调用定位、通信、告警或处置服务。 */
(() => {
  'use strict';
  const KEY = 'rolling_admin_demo_v2';
  const labels = { pending:'待处理', handling:'处置中', closed:'已关闭' };
  const initial = [
    { id:'EVT-20260921-001', title:'高压配电区人员越界进入', type:'fence', category:'电子围栏', severity:'critical', person:'陈建国', area:'1号机组 · 高压配电区东侧', time:'10:35', device:'智能安全帽 RL-H001', fence:'EF-01 高压配电区', rule:'未经授权进入管控区域', status:'pending', owner:'未认领', note:'', actions:[] },
    { id:'EVT-20260921-002', title:'巡检人员离开安全作业区', type:'fence', category:'电子围栏', severity:'major', person:'李志远', area:'汽机房 · 南侧安全通道', time:'10:40', device:'智能安全帽 RL-H002', fence:'EF-02 汽机房安全作业区', rule:'巡检期间离开指定作业范围', status:'pending', owner:'未认领', note:'', actions:[] },
    { id:'EVT-20260921-003', title:'作业期间安全帽佩戴异常', type:'off_hat', category:'脱帽告警', severity:'major', person:'张伟', area:'汽机房 · 凝汽器检修平台', time:'10:25', device:'智能安全帽 RL-H004', status:'pending', owner:'未认领', note:'', actions:[] },
    { id:'EVT-20260921-004', title:'循环水泵房设备撞击提醒', type:'impact', category:'撞击告警', severity:'major', person:'周明', area:'循环水泵房 · 1号主泵', time:'10:00', device:'智能手表 RL-W003', status:'handling', owner:'王班长', note:'已安排现场检查，待补充核验结果。', actions:[{ time:'10:03', title:'王班长认领事件', note:'已安排现场核验。' }] },
    { id:'EVT-20260921-005', title:'输煤廊道 SOS 联动演练', type:'sos', category:'SOS 求助', severity:'major', person:'周明', area:'3号输煤廊道 · 检修段', time:'09:15', device:'智能安全带 RL-B003', status:'closed', owner:'王班长', note:'班组演练结束，流程验证完成。', actions:[{time:'09:25',title:'演练事件关闭',note:'演示记录，未触发真实救援。'}] }
  ];
  let events = structuredClone(initial);
  try {
    const saved = JSON.parse(sessionStorage.getItem(KEY));
    if (Array.isArray(saved) && saved.length === initial.length && saved.every((e,i) => e.id === initial[i].id && labels[e.status] && Array.isArray(e.actions))) events = saved;
  } catch (_) { /* 损坏的演示存储回退到初始数据。 */ }
  let panel, dialog, toastEl, timer, route = null, stack = [], selected = 0;
  const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const icon = name => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${({back:'<path d="m14 5-7 7 7 7"/>',phone:'<path d="M8 3H4a1 1 0 0 0-1 1c0 9.4 7.6 17 17 17a1 1 0 0 0 1-1v-4l-5-2-2 2a15 15 0 0 1-6-6l2-2z"/>',video:'<rect x="3" y="6" width="12" height="12" rx="2"/><path d="m15 10 6-4v12l-6-4"/>'})[name] || ''}</svg>`;
  function allowed() { return window.currentUserRole === 'admin'; }
  function counts() { return { pending:events.filter(e=>e.status==='pending').length, handling:events.filter(e=>e.status==='handling').length, closed:events.filter(e=>e.status==='closed').length, fence:events.filter(e=>e.type==='fence' && e.status!=='closed').length }; }
  function toast(message) { toastEl.textContent=message; clearTimeout(timer); timer=setTimeout(()=>toastEl.textContent='',2800); }
  function sync(refresh=true) {
    try { sessionStorage.setItem(KEY, JSON.stringify(events)); } catch (_) { toast('当前浏览器无法保存，请检查存储设置'); }
    if(refresh) window.refreshRollingHome?.();
  }
  function record(ev,title,note) { ev.actions.push({time:new Date().toLocaleTimeString('zh-CN',{hour12:false,hour:'2-digit',minute:'2-digit'}),title,note}); sync(); }
  function badge(ev) { return `<span class="admin-badge ${ev.status==='pending' ? '' : ev.status}">${labels[ev.status]}</span>`; }
  function header(title) { return `<header class="admin-header"><button class="admin-back" data-action="back" aria-label="返回上一层">${icon('back')}返回</button><h1>${title}</h1><span></span></header>`; }
  function navigate(next, root=false) {
    if (!allowed()) { toast('仅管理员登录后可使用现场管理'); return; }
    if (root) stack=[]; else if(route) stack.push({...route,scroll:panel.querySelector('.admin-body')?.scrollTop || 0});
    route=next; render(); panel.hidden=false;
    panel.querySelector('.admin-back').focus({preventScroll:true});
  }
  function close() { panel.hidden=true; dialog.hidden=true; route=null; stack=[]; window.refreshRollingHome?.(); }
  function back() { if(!dialog.hidden) {dialog.hidden=true;return;} if(stack.length) {route=stack.pop();render();} else close(); }
  function render() {
    if(!allowed()) return close();
    panel.innerHTML = route.page==='lead' ? leadView() : route.page==='detail' ? detailView(route.id) : route.page==='events' ? eventsListView() : catalogView();
    panel.querySelector('.admin-body').scrollTop=route.scroll || 0;
  }
  const people = [ {name:'陈建国',place:'高压配电区东侧',device:'RL-H001',battery:86,x:42,y:32}, {name:'李志远',place:'汽机房南侧通道',device:'RL-H002',battery:78,x:68,y:62}, {name:'周明',place:'循环水泵房',device:'RL-H003',battery:92,x:22,y:64}, {name:'张伟',place:'凝汽器检修平台',device:'RL-H004',battery:82,x:75,y:24} ];
  function leadView() {
    const c=counts(), p=people[selected], fences=events.filter(e=>e.type==='fence' && e.status!=='closed');
    return header('现场全局态势与指挥调度') + `<div class="admin-body">
      <div class="admin-intro"><span>演示厂站 A · 今日现场概览</span><span>09月21日</span></div>
      <button class="admin-card admin-event" data-action="go-events" style="border:1.5px solid #ffd591;background:#fffaf0;margin-bottom:12px;text-align:left;cursor:pointer;">
        <div class="admin-issue-line"><strong style="color:#d46b08;">📋 切换至核心系统作业研判与处置</strong><span class="admin-badge warn">${c.pending}起待处理</span></div>
        <p class="admin-muted" style="color:#b56507;margin:4px 0 0;">查看告警要素、人员现场研判意见与复核闭环留痕 ›</p>
      </button>
      <section class="admin-card admin-stats"><div class="admin-stat"><b>4</b><span>现场在岗</span></div><div class="admin-stat"><b>1</b><span>进行中作业</span></div><div class="admin-stat warn"><b>${c.fence}</b><span>围栏告警</span></div><div class="admin-stat"><b>88<small>%</small></b><span>装备在线率</span></div></section>
      <section class="admin-card"><div class="admin-section-heading"><h2>人员与围栏</h2><span class="admin-muted">点击人员查看</span></div>
      <div class="admin-map"><img src="assets/field-brand/preview/plant_map.jpg" alt="厂区平面示意图"><div class="admin-fence"></div>${people.map((p,i)=>`<button data-action="person" data-id="${i}" aria-label="查看${p.name}位置" class="admin-pin ${fences.some(e=>e.person===p.name)?'alert':''} ${selected===i?'selected':''}" style="left:${p.x}%;top:${p.y}%">${p.name[0]}</button>`).join('')}</div><div class="admin-legend"><span>在岗人员</span><span>围栏告警 / 管控范围</span></div>
      <div class="admin-person"><div class="admin-avatar">${p.name[0]}</div><div class="admin-person-info"><strong>${p.name}</strong><span class="admin-muted">巡检一班 · ${p.place}</span></div><span class="admin-badge handling">在线</span></div><div class="admin-note">安全帽 ${p.device} · 电量 ${p.battery}% · 位置更新时间 10:42</div>
      <div class="admin-actions"><button class="admin-button primary" data-action="call" data-name="${p.name}">${icon('phone')}语音联系</button><button class="admin-button" data-action="video" data-name="${p.name}">${icon('video')}视频协助</button></div></section>
      </div>`;
  }
  let eventFilter = 'all';
  function eventsListView() {
    const c=counts();
    const filtered=events.filter(e=>{
      if(eventFilter==='pending')return e.status==='pending';
      if(eventFilter==='handling')return e.status==='handling';
      if(eventFilter==='closed')return e.status==='closed';
      if(eventFilter==='fence')return e.type==='fence';
      return true;
    });
    return header('核心系统作业研判与处置')+`<div class="admin-body">
      <div class="admin-intro"><span>核心事件研判 · 闭环处置留痕</span><span>今日共 ${events.length} 起</span></div>
      <button class="admin-card admin-event" data-action="go-lead" style="border:1.5px solid #adc6ff;background:#f0f7ff;margin-bottom:12px;text-align:left;cursor:pointer;">
        <div class="admin-issue-line"><strong style="color:#24529a;">🚨 切换至现场全局态势与指挥调度</strong><span class="admin-badge handling">UWB实景</span></div>
        <p class="admin-muted" style="color:#4a6da7;margin:4px 0 0;">查看厂区定位实景标定、人员在岗状态与一键呼叫直拨 ›</p>
      </button>
      <div style="display:flex;gap:6px;margin-bottom:12px;overflow-x:auto;">
        <button class="admin-button ${eventFilter==='all'?'primary':''}" data-action="filter-events" data-filter="all" style="padding:4px 8px;font-size:12px;">全部 (${events.length})</button>
        <button class="admin-button ${eventFilter==='pending'?'primary':''}" data-action="filter-events" data-filter="pending" style="padding:4px 8px;font-size:12px;">待处理 (${c.pending})</button>
        <button class="admin-button ${eventFilter==='handling'?'primary':''}" data-action="filter-events" data-filter="handling" style="padding:4px 8px;font-size:12px;">处置中 (${c.handling})</button>
        <button class="admin-button ${eventFilter==='closed'?'primary':''}" data-action="filter-events" data-filter="closed" style="padding:4px 8px;font-size:12px;">已关闭 (${c.closed})</button>
      </div>
      <div style="display:flex;flex-direction:column;gap:8px;">
        ${filtered.map(ev=>`
          <button class="admin-card admin-event" data-action="detail" data-id="${ev.id}">
            <div class="admin-issue-line"><span class="admin-badge ${ev.severity}">${ev.category}</span>${badge(ev)}</div>
            <strong style="display:block;margin:6px 0 2px;text-align:left;font-size:14px;color:#101f43;">${escape(ev.title)}</strong>
            <div class="admin-note" style="margin-top:2px;">${escape(ev.person)} · ${escape(ev.area)}<br>${escape(ev.device)} · 今日 ${escape(ev.time)}</div>
            <div style="display:flex;justify-content:space-between;align-items:center;margin-top:6px;font-size:11px;color:#307cff;font-weight:bold;">
              <span>责任人：${escape(ev.owner)}</span>
              <span>研判处置 ›</span>
            </div>
          </button>
        `).join('')}
      </div>
    </div>`;
  }
  function deviceRows() {
    const rows=people.map(p=>({id:p.device,name:'智能安全帽',person:p.name,battery:p.battery+'%',status:'在线'}));
    rows.push({id:'RL-W001',name:'智能手表',person:'陈建国',battery:'72%',status:'在线'}, {id:'RL-B001',name:'智能安全带',person:'陈建国',battery:'48%（最后上报）',status:'待连接'});
    events.forEach(ev=>{const id=ev.device.split(' ').pop();if(!rows.some(d=>d.id===id))rows.push({id,name:ev.device.split(' ')[0],person:ev.person,battery:'未上报',status:'未上报'});});
    return rows;
  }
  // 全员作业的本地设计示例；前三条沿用个人作业，补充其他人员的演示作业。
  let personalWorkStatus='进行中';
  const works=[
    {id:'WORK-001',title:'1号机组日常巡检',person:'陈建国',area:'汽机房',time:'今日 09:00—11:00',status:'进行中',requirement:'确认设备运行，检查泄漏与异响，发现异常及时上报。'},
    {id:'WORK-002',title:'循环水泵房巡检',person:'陈建国',area:'循环水泵房',time:'今日 14:00—15:00',status:'待执行',requirement:'检查水泵运行情况并记录现场异常。'},
    {id:'WORK-003',title:'班前设备检查',person:'陈建国',area:'班组室',time:'今日 08:30',status:'已完成',requirement:'确认穿戴设备连接与佩戴状态。'},
    {id:'WORK-004',title:'循环水泵房设备核查',person:'周明',area:'循环水泵房 · 1号主泵',time:'今日 10:00—11:00',status:'进行中',requirement:'核查现场设备情况并记录检查结果。'},
    {id:'WORK-005',title:'汽机房安全通道巡查',person:'李志远',area:'汽机房 · 南侧安全通道',time:'今日 10:00—11:00',status:'进行中',requirement:'检查通道畅通情况并确认安全作业边界。'},
    {id:'WORK-006',title:'凝汽器检修平台检查',person:'张伟',area:'汽机房 · 凝汽器检修平台',time:'今日 14:00—15:00',status:'待执行',requirement:'检查检修平台防护及人员佩戴情况。'}
  ];
  const profiles=[
    {code:'P-001',job:'设备巡检员',shift:'白班 08:00—17:00',skills:['设备巡检岗位培训','厂区安全教育'],duty:'负责1号机组设备巡检及异常上报'},
    {code:'P-003',job:'安全巡查员',shift:'白班 08:00—17:00',skills:['现场安全巡查培训','电子围栏与通行管理培训'],duty:'负责汽机房安全通道和作业边界巡查'},
    {code:'P-002',job:'设备检查员',shift:'白班 08:00—17:00',skills:['旋转设备检查培训','应急处置培训'],duty:'负责循环水泵房设备状态核查'},
    {code:'P-004',job:'检修巡检员',shift:'白班 08:00—17:00',skills:['检修平台安全培训','防坠落装备使用培训'],duty:'负责凝汽器检修平台防护检查'}
  ];
  const workDetails=[
    {kind:'日常巡检',members:['李志远','周明'],points:['汽机房入口设备状态确认','1号机组运行参数检查','高压配电区外围巡查'],risks:'带电设备、旋转机械与高温表面',safe:'保持安全距离，不进入未授权配电区域；发现异响或泄漏立即上报。',result:'已完成入口设备检查，正在检查机组运行状态。'},
    {kind:'日常巡检',members:['周明'],points:['泵房环境检查','水泵振动与异响检查','管路及阀门泄漏检查'],risks:'地面湿滑、旋转机械',safe:'沿指定通道行走，禁止接触运转部件，确认地面防滑。',result:'等待计划时间，尚未开始现场检查。'},
    {kind:'班前检查',members:[],points:['安全帽连接检查','安全带外观检查','通讯设备检查'],risks:'设备电量不足或连接异常',safe:'设备检查通过后再进入作业区域，异常装备及时更换。',result:'三项检查已完成，装备状态已确认。'},
    {kind:'专项核查',members:['陈建国'],points:['主泵外观核查','现场撞击情况核验','运行状态记录'],risks:'旋转机械、设备异常振动',safe:'与运转设备保持距离，发现异常先联系值班室。',result:'主泵外观已核查，正在确认现场撞击情况。'},
    {kind:'安全巡查',members:['张伟'],points:['南侧通道畅通检查','围栏边界与标识检查','应急出口检查'],risks:'通道占用、误入管控区',safe:'按授权路线巡查，禁止跨越安全围栏。',result:'通道畅通检查已完成，正在核对围栏边界。'},
    {kind:'检修检查',members:['李志远'],points:['平台护栏检查','安全带挂点检查','检修区域警示检查'],risks:'高处坠落、物体打击',safe:'进入平台前确认防护设施，按要求佩戴安全帽和安全带。',result:'待执行，进入平台前需完成防护确认。'}
  ];
  const currentWorks=()=>works.map((w,i)=>i===0?{...w,status:personalWorkStatus}:w);
  const kv=items=>`<dl class="admin-kv">${items.map(([k,v])=>`<dt>${escape(k)}</dt><dd>${escape(v)}</dd>`).join('')}</dl>`;
  const section=(title,body)=>`<section class="admin-card"><h2>${title}</h2>${body}</section>`;
  function personLink(name,label=name) {return `<button class="admin-button" data-action="person-profile" data-id="${people.findIndex(p=>p.name===name)}">${escape(label)} ›</button>`;}
  function workLink(w) {return `<button class="admin-card admin-event" data-action="work-profile" data-id="${works.findIndex(x=>x.id===w.id)}"><div class="admin-issue-line"><strong>${escape(w.title)}</strong><span class="admin-badge ${w.status==='进行中'?'handling':w.status==='已完成'?'closed':''}">${w.status}</span></div><p class="admin-muted">${escape(w.area)} · ${escape(w.time)}</p></button>`;}
  function personView(index) {
    const person=people[index], profile=profiles[index];
    const assigned=currentWorks().filter(w=>w.person===person.name);
    const related=events.filter(e=>e.person===person.name);
    return header('人员档案')+`<div class="admin-body">${section(person.name,`<div class="admin-person"><div class="admin-avatar">${person.name[0]}</div><div class="admin-person-info"><strong>${profile.job}</strong><span class="admin-muted">${profile.code} · 巡检一班</span></div><span class="admin-badge handling">在岗</span></div><p class="admin-muted">${profile.duty}</p><div class="admin-actions"><button class="admin-button" data-action="call" data-name="${person.name}">${icon('phone')}语音联系</button><button class="admin-button" data-action="video" data-name="${person.name}">${icon('video')}视频协助</button></div>`)}
      ${section('基本信息',kv([['所属厂站','演示厂站 A'],['所属部门','生产运行部'],['所属班组','巡检一班'],['岗位',profile.job],['当班时间',profile.shift],['现场位置',person.place],['位置更新','今日 10:42']]))}
      ${section('岗位培训与资质',profile.skills.map(x=>`<div class="admin-note">${x} · 已完成</div>`).join('')+'<p class="admin-muted">特殊作业资格以相应作业票核验结果为准。</p>')}
      ${section('关联设备',deviceRows().filter(d=>d.person===person.name).map(d=>`<button class="admin-card admin-event" data-action="device-profile" data-id="${deviceRows().findIndex(x=>x.id===d.id)}"><strong>${d.name}</strong><p class="admin-muted">${d.id} · ${d.status} · 电量 ${d.battery}</p></button>`).join(''))}
      ${section('负责作业',assigned.length?assigned.map(workLink).join(''):'<p class="admin-muted">暂无负责作业</p>')}
      ${section('相关告警',related.length?related.map(ev=>`<button class="admin-card admin-event" data-action="detail" data-id="${ev.id}"><strong>${escape(ev.title)}</strong><p class="admin-muted">今日 ${ev.time} · ${labels[ev.status]}</p></button>`).join(''):'<p class="admin-muted">暂无相关告警</p>')}</div>`;
  }
  function workDetailView(work,index) {
    const info=workDetails[index];
    const done=work.status==='已完成'?info.points.length:work.status==='进行中'?1:0;
    return header('作业详情')+`<div class="admin-body">${section(work.title,`<div class="admin-issue-line"><span class="admin-muted">${work.id} · ${info.kind}</span><span class="admin-badge ${work.status==='进行中'?'handling':work.status==='已完成'?'closed':''}">${work.status}</span></div><p class="admin-note">${escape(work.requirement)}</p>`)}
      ${section('作业安排',kv([['所属厂站','演示厂站 A'],['所属班组','巡检一班'],['作业位置',work.area],['计划时间',work.time],['作业类型',info.kind],['完成进度',`${done} / ${info.points.length} 项检查`]]))}
      ${section('参与人员',`<p class="admin-muted">负责人</p>${personLink(work.person)}<p class="admin-muted">协作人员</p><div class="admin-actions">${info.members.length?info.members.map(n=>personLink(n)).join(''):'<span>无协作人员</span>'}</div>`)}
      ${section('检查项目',`<ol class="admin-timeline">${info.points.map((point,i)=>`<li><strong>${point}</strong><p>${i<done?'已完成':i===done&&work.status==='进行中'?'检查中':'待检查'}</p></li>`).join('')}</ol>`)}
      ${section('安全要求',kv([['主要风险',info.risks],['防护要求',info.safe],['必备装备','智能安全帽、通讯设备；按现场要求佩戴其他防护装备'],['作业许可','按厂站授权范围执行，涉及特殊作业须核验作业票']]))}
      ${section('进展记录',`<p class="admin-note">${work.status==='已完成'?'全部检查项目已完成。':work.status==='待执行'?'作业尚未开始，等待现场执行。':info.result}</p><p class="admin-muted">记录人员：${work.person}</p>`)}</div>`;
  }
  function workView() {
    const rows=currentWorks();
    if(route.id!==undefined) {
      const work=rows[Number(route.id)];
      return work?workDetailView(work,Number(route.id)):header('作业不存在')+'<div class="admin-body">请返回列表重新选择。</div>';
    }
    const visible=rows.filter(w=>!route.person||w.person===route.person);
    return header('全部作业')+`<div class="admin-body"><div class="admin-intro">演示厂站 A · 所有人员的作业</div><label for="admin-worker" class="admin-muted">执行人员</label><select id="admin-worker" class="admin-input" style="margin:8px 0 14px" aria-label="筛选执行人员"><option value="">全部人员</option>${people.map(p=>`<option ${route.person===p.name?'selected':''}>${p.name}</option>`).join('')}</select><p class="admin-muted">共 ${visible.length} 项作业</p>${visible.map(work=>`<button class="admin-card admin-event" data-action="catalog-detail" data-id="${rows.indexOf(work)}"><div class="admin-issue-line"><strong>${work.title}</strong><span class="admin-badge ${work.status==='已完成'?'closed':work.status==='进行中'?'handling':''}">${work.status}</span></div><div class="admin-note">执行人员：${work.person}<br>${work.area} · ${work.time}</div></button>`).join('')}</div>`;
  }
  function catalogView() {
    if(route.page==='tasks')return workView();
    const devices=route.page==='devices', rows=devices?deviceRows():people;
    if(route.id!==undefined) {
      const row=rows[Number(route.id)];
      if(!row)return header('信息不存在')+'<div class="admin-body">请返回列表重新选择。</div>';
      if(!devices)return personView(Number(route.id));
      const items=devices?[['设备名称',row.name],['设备编号',row.id],['绑定人员',row.person],['连接状态',row.status],['设备电量',row.battery]]:[['姓名',row.name],['所属厂站','演示厂站 A'],['所属班组','巡检一班'],['现场位置',row.place],['关联设备',deviceRows().filter(d=>d.person===row.name).map(d=>d.name+' '+d.id).join('、')]];
      return header(devices?'设备信息':'人员档案')+`<div class="admin-body"><section class="admin-card"><h2>${row.name}</h2><dl class="admin-kv">${items.map(([k,v])=>`<dt>${k}</dt><dd>${v}</dd>`).join('')}</dl></section></div>`;
    }
    return header(devices?'全部设备信息':'人员档案')+`<div class="admin-body"><div class="admin-intro">演示厂站 A · ${rows.length} ${devices?'台设备':'名人员'}</div>${rows.map((row,i)=>`<button class="admin-card admin-event" data-action="catalog-detail" data-id="${i}"><div class="admin-issue-line"><strong>${devices?row.name+' '+row.id:row.name}</strong><span class="admin-muted">查看详情 ›</span></div><div class="admin-note">${devices?row.person+' · '+row.status+' · 电量 '+row.battery:'巡检一班 · '+row.place}</div></button>`).join('')}</div>`;
  }
  function detailView(id) {
    const ev=events.find(e=>e.id===id);
    if(!ev)return header('消息不存在');
    return header('消息详情')+`<div class="admin-body"><section class="admin-card ${ev.type==='fence' && ev.status!=='closed'?'admin-alert-card':''}"><div class="admin-issue-line"><span class="admin-badge ${ev.severity}">${ev.category}</span>${badge(ev)}</div><h2 class="admin-detail-title" style="display:block">${ev.title}</h2><span class="admin-muted">${ev.id} · 今日 ${ev.time}</span><div class="admin-note">${ev.status!=='closed'?'核实现场情况，填写处理意见后完成处理。':'该消息已处理，可查看处理记录。'}</div></section>
      <section class="admin-card"><h2>现场信息</h2><dl class="admin-kv"><dt>涉及人员</dt><dd>${ev.person} · 巡检一班</dd><dt>作业位置</dt><dd>${ev.area}</dd><dt>触发设备</dt><dd>${ev.device}</dd>${ev.fence?`<dt>电子围栏</dt><dd>${ev.fence}</dd><dt>触发规则</dt><dd>${ev.rule}</dd>`:''}<dt>处置责任人</dt><dd>${ev.owner==='未认领'?'待处理':escape(ev.owner)}</dd></dl><div class="admin-actions"><button class="admin-button" data-action="call" data-name="${ev.person}">${icon('phone')}语音联系</button><button class="admin-button" data-action="video" data-name="${ev.person}">${icon('video')}视频核验</button></div></section>
      <section class="admin-card admin-form"><h2>研判处理</h2><label for="admin-note">处理意见</label><textarea id="admin-note" class="admin-input" maxlength="1000" placeholder="填写现场情况和处理结果" ${ev.status==='closed'?'disabled':''}>${escape(ev.note)}</textarea>${ev.status!=='closed'?'<div class="admin-actions"><button class="admin-button" data-action="save">保存意见</button><button class="admin-button primary" data-action="finish">完成处理</button></div>':'<div class="admin-note">已完成处理</div>'}</section>
      <section class="admin-card"><h2>处置记录</h2><ol class="admin-timeline">${[...ev.actions].reverse().map(a=>`<li><strong>${escape(a.title)}</strong><span class="admin-muted"> · ${escape(a.time)}</span><p>${escape(a.note)}</p></li>`).join('')}<li><strong>告警触发</strong><span class="admin-muted"> · ${ev.time}</span><p>${ev.title}</p></li></ol></section></div>`;
  }
  function showDialog(title,body,actions,kind='phone') {
    dialog.innerHTML=`<div class="admin-dialog-box" role="dialog" aria-modal="true" aria-labelledby="admin-dialog-title"><div class="admin-dialog-icon">${icon(kind)}</div><h2 id="admin-dialog-title">${title}</h2><p>${body}</p><div class="admin-actions">${actions}</div></div>`;
    dialog.hidden=false; dialog.querySelector('button').focus();
  }
  function call(name,video) { showDialog(`${video?'视频协助':'语音联系'} · ${escape(name)}`,'正在呼叫，请等待接通。','<button class="admin-button full" data-action="dismiss">结束呼叫</button>',video?'video':'phone'); }
  function handle(action,button) {
    if(!allowed()) {close();return;}
    if(route) route.scroll=panel.querySelector('.admin-body')?.scrollTop || 0;
    const ev=route?.page==='detail'?events.find(e=>e.id===route.id):null;
    const note=()=>panel.querySelector('#admin-note')?.value.trim() || '';
    if(ev && ev.status!=='closed') ev.note=note();
    if(action==='back') return back();
    if(action==='dismiss') {dialog.hidden=true;panel.querySelector('.admin-back')?.focus();return;}
    if(action==='go-lead') return navigate({page:'lead'},true);
    if(action==='go-events') return navigate({page:'events'},true);
    if(action==='filter-events') { eventFilter=button.dataset.filter; render(); return; }
    if(action==='detail') return navigate({page:'detail',id:button.dataset.id});
    if(['person-profile','work-profile','device-profile'].includes(action)) return navigate({page:action==='person-profile'?'people':action==='work-profile'?'tasks':'devices',id:button.dataset.id});
    if(action==='catalog-detail') return navigate({page:route.page,id:button.dataset.id,person:route.person});
    if(action==='person') {selected=Number(button.dataset.id);render();return;}
    if(action==='call'||action==='video') return call(button.dataset.name,action==='video');
    if(!ev) return;
    if((action==='save'||action==='finish') && ev.status!=='closed') {
      if(!ev.note)return toast('请填写现场情况和处理意见');
      ev.owner='管理员';ev.status=action==='finish'?'closed':'handling';
      record(ev,action==='finish'?'完成处理':'保存处理意见',ev.note);render();toast(action==='finish'?'已完成处理，消息状态已更新':'处理意见已保存');
    }

  }
  function init() {
    const phone=document.querySelector('#phone');
    panel=document.createElement('section');panel.className='admin-panel';panel.hidden=true;panel.setAttribute('aria-label','管理员现场管理');phone.appendChild(panel);
    dialog=document.createElement('div');dialog.className='admin-dialog';dialog.hidden=true;phone.appendChild(dialog);
    toastEl=document.createElement('div');toastEl.className='admin-toast';toastEl.setAttribute('role','status');phone.appendChild(toastEl);
    [panel,dialog].forEach(el=>el.addEventListener('click',e=>{const button=e.target.closest('[data-action]');if(button)handle(button.dataset.action,button);}));
    panel.addEventListener('input',e=>{if(e.target.id==='admin-note'){const ev=events.find(ev=>ev.id===route?.id);if(ev && ev.status!=='closed'){ev.note=e.target.value;sync(false);}}});
    panel.addEventListener('change',e=>{if(e.target.id==='admin-worker'){route.person=e.target.value;route.scroll=0;render();}});
    window.addEventListener('rolling-preview-back',e=>{if(route){e.stopImmediatePropagation();back();}},true);
    window.addEventListener('rolling-role-changed',()=>{if(!allowed())close();});
    window.addEventListener('hashchange',()=>{if(['#/login','#/sites'].includes(location.hash)){window.rollingPreviewReady=false;close();window.dispatchEvent(new Event('rolling-preview-ready'));}});
    document.addEventListener('keydown',e=>{if(e.key==='Escape'&&route){e.stopImmediatePropagation();back();}},true);
    // 下方仍使用原生 Flutter 底部导航；切换主栏目时关闭管理子页。
    phone.addEventListener('pointerdown',e=>{const rect=phone.getBoundingClientRect();if(route && e.clientY>rect.bottom-60*rect.height/900)close();},true);
  }
  window.RollingAdmin={counts, canOpen:allowed, alarmMessages:()=>events.map(ev=>({...ev,statusLabel:labels[ev.status]}))};
  window.openFieldLead=window.openLeadPanel=()=>navigate({page:'lead'},true);
  window.closeFieldLead=()=>close();
  window.openRollingEvents=id=>{if(id&&events.some(e=>e.id===id))navigate({page:'detail',id},true);else navigate({page:'events'},true);};
  window.openRollingCatalog=(page,status)=>{if(['进行中','待执行','已完成'].includes(status))personalWorkStatus=status;if(['devices','people','tasks'].includes(page))navigate({page},true);};
  window.closeRollingEvents=()=>close();
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();
