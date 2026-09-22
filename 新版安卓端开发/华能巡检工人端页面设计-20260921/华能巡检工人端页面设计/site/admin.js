/* 本地页面演示；不调用定位、通信、告警或处置服务。 */
(() => {
  'use strict';
  const KEY = 'rolling_admin_demo_v2';
  const labels = { pending:'待认领', handling:'处置中', closed:'已关闭' };
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
  let panel, dialog, toastEl, timer, route = null, stack = [], filter = 'all', type = 'all', query = '', selected = 0;
  const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const icon = name => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${({back:'<path d="m14 5-7 7 7 7"/>',phone:'<path d="M8 3H4a1 1 0 0 0-1 1c0 9.4 7.6 17 17 17a1 1 0 0 0 1-1v-4l-5-2-2 2a15 15 0 0 1-6-6l2-2z"/>',video:'<rect x="3" y="6" width="12" height="12" rx="2"/><path d="m15 10 6-4v12l-6-4"/>'})[name] || ''}</svg>`;
  function allowed() { return window.currentUserRole === 'admin' && window.rollingPreviewReady === true && !['#/login','#/sites'].includes(location.hash); }
  function counts() { return { pending:events.filter(e=>e.status==='pending').length, handling:events.filter(e=>e.status==='handling').length, closed:events.filter(e=>e.status==='closed').length, fence:events.filter(e=>e.type==='fence' && e.status!=='closed').length }; }
  function toast(message) { toastEl.textContent=message; clearTimeout(timer); timer=setTimeout(()=>toastEl.textContent='',2800); }
  function sync(refresh=true) {
    try { sessionStorage.setItem(KEY, JSON.stringify(events)); } catch (_) { toast('当前浏览器无法保存，刷新后将恢复演示数据'); }
    if(refresh) window.refreshRollingHome?.();
  }
  function record(ev,title,note) { ev.actions.push({time:new Date().toLocaleTimeString('zh-CN',{hour12:false,hour:'2-digit',minute:'2-digit'}),title,note}); sync(); }
  function badge(ev) { return `<span class="admin-badge ${ev.status==='pending' ? '' : ev.status}">${labels[ev.status]}</span>`; }
  function header(title) { return `<header class="admin-header"><button class="admin-back" data-action="back" aria-label="返回上一层">${icon('back')}返回</button><h1>${title}</h1><span class="admin-demo">模拟数据</span></header>`; }
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
    panel.innerHTML = route.page==='lead' ? leadView() : route.page==='detail' ? detailView(route.id) : listView();
    panel.querySelector('.admin-body').scrollTop=route.scroll || 0;
  }
  const people = [ {name:'陈建国',place:'高压配电区东侧',device:'RL-H001',battery:86,x:42,y:32}, {name:'李志远',place:'汽机房南侧通道',device:'RL-H002',battery:78,x:68,y:62}, {name:'周明',place:'循环水泵房',device:'RL-H003',battery:92,x:22,y:64}, {name:'张伟',place:'凝汽器检修平台',device:'RL-H004',battery:82,x:75,y:24} ];
  function leadView() {
    const c=counts(), p=people[selected], fences=events.filter(e=>e.type==='fence' && e.status!=='closed');
    return header('全局态势') + `<div class="admin-body"><div class="admin-intro"><span>演示厂站 A · 今日现场概览</span><span>09月21日</span></div>
      <section class="admin-card admin-stats"><div class="admin-stat"><b>4</b><span>现场在岗</span></div><div class="admin-stat"><b>1</b><span>进行中作业</span></div><div class="admin-stat warn"><b>${c.fence}</b><span>围栏告警</span></div><div class="admin-stat"><b>88<small>%</small></b><span>装备在线率</span></div></section>
      <section class="admin-card"><div class="admin-section-heading"><h2>人员与围栏</h2><span class="admin-muted">点击人员查看</span></div>
      <div class="admin-map"><img src="assets/field-brand/preview/plant_map.jpg" alt="厂区平面示意图"><div class="admin-fence"></div>${people.map((p,i)=>`<button data-action="person" data-id="${i}" aria-label="查看${p.name}位置" class="admin-pin ${fences.some(e=>e.person===p.name)?'alert':''} ${selected===i?'selected':''}" style="left:${p.x}%;top:${p.y}%">${p.name[0]}</button>`).join('')}</div><div class="admin-legend"><span>在岗人员</span><span>围栏告警 / 管控范围</span></div>
      <div class="admin-person"><div class="admin-avatar">${p.name[0]}</div><div class="admin-person-info"><strong>${p.name}</strong><span class="admin-muted">巡检一班 · ${p.place}</span></div><span class="admin-badge handling">在线</span></div><div class="admin-note">安全帽 ${p.device} · 电量 ${p.battery}% · 位置更新时间 10:42</div>
      <div class="admin-actions"><button class="admin-button primary" data-action="call" data-name="${p.name}">${icon('phone')}语音联系</button><button class="admin-button" data-action="video" data-name="${p.name}">${icon('video')}视频协助</button></div></section>
      <section class="admin-card"><div class="admin-section-heading"><h2>围栏告警</h2><button class="admin-text-button" data-action="fence-list">查看全部 ›</button></div>${fences.length?fences.map(ev=>`<button class="admin-issue" data-action="detail" data-id="${ev.id}"><div class="admin-issue-line"><span class="admin-badge ${ev.severity}">${ev.id.endsWith('001')?'越界进入':'离开作业区'}</span><span class="admin-muted">${ev.time}</span></div><strong>${ev.title} <span style="float:right;color:#9aa9bc">›</span></strong><div class="admin-muted">${ev.person} · ${ev.area}</div></button>`).join(''):'<div class="admin-empty">当前无待处置围栏告警</div>'}</section>
      <section class="admin-card"><h2>现场通讯录</h2>${people.map(p=>`<div class="admin-person"><div class="admin-avatar">${p.name[0]}</div><div class="admin-person-info"><strong>${p.name}</strong><span class="admin-muted">${p.place}</span></div><button class="admin-button" data-action="call" data-name="${p.name}" aria-label="呼叫${p.name}">${icon('phone')}</button></div>`).join('')}</section><p class="admin-muted" style="text-align:center">现场数据与通信过程均为本地演示</p></div>`;
  }
  function eventCards() {
    const rows=events.filter(e=>(filter==='all'||e.status===filter)&&(type==='all'||e.type===type)&&(!query||[e.title,e.person,e.area,e.id].some(s=>s.includes(query))));
    return rows.length ? rows.map(ev=>`<button class="admin-card admin-event" data-action="detail" data-id="${ev.id}"><div class="admin-issue-line"><span class="admin-badge ${ev.severity}">${ev.category}</span>${badge(ev)}</div><h3>${ev.title}</h3><div class="admin-muted">${ev.person} · ${ev.area}</div><div class="admin-event-footer"><span>今日 ${ev.time} · ${ev.owner==='未认领'?'等待认领':escape(ev.owner)}</span><span>查看详情 ›</span></div></button>`).join('') : '<div class="admin-card admin-empty">暂无符合条件的事件<br><button class="admin-text-button" data-action="clear">清除筛选</button></div>';
  }
  function listView() {
    const c=counts();
    return header('作业研判')+`<div class="admin-body"><div class="admin-intro"><span>现场告警 · 认领、核验与闭环处置</span><button class="admin-text-button" data-action="reset">重置演示</button></div><div class="admin-tabs" aria-label="事件状态">${[['all','全部',events.length],['pending','待认领',c.pending],['handling','处置中',c.handling],['closed','已关闭',c.closed]].map(([v,l,n])=>`<button data-action="filter" data-id="${v}" aria-pressed="${filter===v}" class="${filter===v?'active':''}">${l} ${n}</button>`).join('')}</div>
      <div class="admin-search"><input class="admin-input" id="admin-search" aria-label="搜索事件或人员" placeholder="搜索事件 / 人员" value="${escape(query)}"><select class="admin-input" id="admin-type" aria-label="事件类型">${[['all','全部类型'],['fence','电子围栏'],['off_hat','脱帽告警'],['impact','撞击告警'],['sos','SOS 求助']].map(([v,l])=>`<option value="${v}" ${type===v?'selected':''}>${l}</option>`).join('')}</select></div><div id="admin-results">${eventCards()}</div></div>`;
  }
  function detailView(id) {
    const ev=events.find(e=>e.id===id);
    if(!ev) {route={page:'events'};return listView();}
    return header('事件详情')+`<div class="admin-body"><section class="admin-card"><div class="admin-issue-line"><span class="admin-badge ${ev.severity}">${ev.category}</span>${badge(ev)}</div><h2 class="admin-detail-title" style="display:block">${ev.title}</h2><span class="admin-muted">${ev.id} · 今日 ${ev.time}</span><div class="admin-note">${ev.status==='pending'?'请先认领事件，再核验现场情况。':ev.status==='handling'?'核验后填写处置意见，确认结果并关闭事件。':'该事件已关闭，可查看记录或重新开启。'}</div></section>
      <section class="admin-card"><h2>现场信息</h2><dl class="admin-kv"><dt>涉及人员</dt><dd>${ev.person} · 巡检一班</dd><dt>作业位置</dt><dd>${ev.area}</dd><dt>触发设备</dt><dd>${ev.device}</dd>${ev.fence?`<dt>电子围栏</dt><dd>${ev.fence}</dd><dt>触发规则</dt><dd>${ev.rule}</dd>`:''}<dt>处置责任人</dt><dd>${escape(ev.owner)}</dd></dl><div class="admin-actions"><button class="admin-button" data-action="call" data-name="${ev.person}">${icon('phone')}语音联系</button><button class="admin-button" data-action="video" data-name="${ev.person}">${icon('video')}视频核验</button></div></section>
      <section class="admin-card admin-form"><h2>研判与处置</h2>${ev.status==='pending'?'<button class="admin-button primary full" data-action="claim">认领此事件</button>':''}
      <label for="admin-note">现场核验与处置意见</label>${ev.status==='handling'?'<div class="admin-chips"><button data-action="phrase" data-id="现场人员已返回安全区域，已重新确认作业边界。">人员已回安全区</button><button data-action="phrase" data-id="已核查设备佩戴状态，现场未发现异常。">设备复查正常</button></div>':''}<textarea id="admin-note" class="admin-input" maxlength="1000" placeholder="请记录核查情况、人员状态及处理措施" ${ev.status!=='handling'?'disabled':''}>${escape(ev.note)}</textarea>
      <div class="admin-photo">${ev.photo?'<img src="assets/field-brand/preview/site_photo.jpg" alt="模拟现场凭证照片"><span class="admin-muted">示例凭证 · 非实时抓拍</span>':''}${ev.status==='handling'?`<button class="admin-text-button" data-action="photo">${ev.photo?'移除示例凭证':'+ 添加示例凭证'}</button>`:''}</div>
      ${ev.status==='handling'?'<div class="admin-actions"><button class="admin-button" data-action="save">保存处置意见</button><button class="admin-button primary" data-action="review">复核关闭</button></div><label for="admin-owner">转交责任人</label><select id="admin-owner" class="admin-input"><option>王班长</option><option>厂区值班室</option><option>安全主管 李工</option></select><button class="admin-text-button" data-action="transfer">确认转交 ›</button>':''}
      ${ev.status==='closed'?'<button class="admin-button full" data-action="reopen">重新开启事件</button>':''}<p class="admin-muted">所有处置仅保存为本地模拟记录。</p></section>
      <section class="admin-card"><h2>处置记录</h2><ol class="admin-timeline">${[...ev.actions].reverse().map(a=>`<li><strong>${escape(a.title)}</strong><span class="admin-muted"> · ${escape(a.time)}</span><p>${escape(a.note)}</p></li>`).join('')}<li><strong>生成模拟告警</strong><span class="admin-muted"> · ${ev.time}</span><p>${ev.title}</p></li></ol></section></div>`;
  }
  function showDialog(title,body,actions,kind='phone') {
    dialog.innerHTML=`<div class="admin-dialog-box" role="dialog" aria-modal="true" aria-labelledby="admin-dialog-title"><div class="admin-dialog-icon">${icon(kind)}</div><h2 id="admin-dialog-title">${title}</h2><p>${body}</p><div class="admin-actions">${actions}</div></div>`;
    dialog.hidden=false; dialog.querySelector('button').focus();
  }
  function call(name,video) { showDialog(`${video?'视频协助':'语音联系'} · ${escape(name)}`,'模拟呼叫中<br>当前为界面演示，不会拨打真实电话或访问摄像头。','<button class="admin-button full" data-action="dismiss">结束模拟呼叫</button>',video?'video':'phone'); }
  function handle(action,button) {
    if(!allowed()) {close();return;}
    if(route) route.scroll=panel.querySelector('.admin-body')?.scrollTop || 0;
    const ev=route?.page==='detail'?events.find(e=>e.id===route.id):null;
    const note=()=>panel.querySelector('#admin-note')?.value.trim() || '';
    if(ev && ev.status==='handling') ev.note=note();
    if(action==='back') return back();
    if(action==='dismiss') {dialog.hidden=true;panel.querySelector('.admin-back')?.focus();return;}
    if(action==='detail') return navigate({page:'detail',id:button.dataset.id});
    if(action==='person') {selected=Number(button.dataset.id);render();return;}
    if(action==='call'||action==='video') return call(button.dataset.name,action==='video');
    if(action==='fence-list') {type='fence';filter='all';query='';return navigate({page:'events'});}
    if(action==='filter') {filter=button.dataset.id;render();return;}
    if(action==='clear') {filter=type='all';query='';render();return;}
    if(action==='reset') return showDialog('重置演示数据','将清除本次演示中的认领、处置及转交记录，恢复初始示例。','<button class="admin-button" data-action="dismiss">取消</button><button class="admin-button primary" data-action="confirm-reset">确认重置</button>');
    if(action==='confirm-reset') {events=structuredClone(initial);filter=type='all';query='';dialog.hidden=true;sync();render();toast('已恢复初始模拟数据');return;}
    if(!ev) return;
    if(action==='claim' && ev.status==='pending') {ev.status='handling';ev.owner='管理员';record(ev,'管理员认领事件','进入现场核验流程（模拟）。');render();toast('已模拟认领事件');}
    if(action==='phrase' && ev.status==='handling') {const input=panel.querySelector('#admin-note');input.value=(input.value+' '+button.dataset.id).trim().slice(0,1000);ev.note=input.value;sync(false);}
    if(action==='photo' && ev.status==='handling') {ev.photo=!ev.photo;sync();render();}
    if(action==='save' && ev.status==='handling') {if(!ev.note)return toast('请先填写现场核验与处置意见');record(ev,'保存处置意见',ev.note);render();toast('处置意见已保存至本地演示');}
    if(action==='review' && ev.status==='handling') {if(!ev.note)return toast('请先填写现场核验与处置意见');showDialog('确认复核关闭','关闭后将保留处置记录，并同步更新主页及全局态势中的告警数量。<br>本操作仅影响模拟数据。','<button class="admin-button" data-action="dismiss">继续核验</button><button class="admin-button primary" data-action="confirm-close">确认关闭</button>');}
    if(action==='confirm-close' && ev.status==='handling') {ev.status='closed';record(ev,'管理员复核关闭',ev.note);dialog.hidden=true;render();toast('模拟事件已关闭，统计已更新');}
    if(action==='transfer' && ev.status==='handling') {ev.owner=panel.querySelector('#admin-owner').value;record(ev,'转交给'+ev.owner,'已保存本地转交记录，未发送真实通知。');render();toast('已模拟转交给'+ev.owner);}
    if(action==='reopen' && ev.status==='closed') {ev.status='handling';record(ev,'重新开启事件','需要继续核验现场情况（模拟）。');render();toast('模拟事件已重新开启');}
  }
  function init() {
    const phone=document.querySelector('#phone');
    panel=document.createElement('section');panel.className='admin-panel';panel.hidden=true;panel.setAttribute('aria-label','管理员现场管理');phone.appendChild(panel);
    dialog=document.createElement('div');dialog.className='admin-dialog';dialog.hidden=true;phone.appendChild(dialog);
    toastEl=document.createElement('div');toastEl.className='admin-toast';toastEl.setAttribute('role','status');phone.appendChild(toastEl);
    [panel,dialog].forEach(el=>el.addEventListener('click',e=>{const button=e.target.closest('[data-action]');if(button)handle(button.dataset.action,button);}));
    panel.addEventListener('input',e=>{if(e.target.id==='admin-search'){query=e.target.value.trim();panel.querySelector('#admin-results').innerHTML=eventCards();}if(e.target.id==='admin-note'){const ev=events.find(ev=>ev.id===route?.id);if(ev && ev.status==='handling'){ev.note=e.target.value;sync(false);}}});
    panel.addEventListener('change',e=>{if(e.target.id==='admin-type'){type=e.target.value;panel.querySelector('#admin-results').innerHTML=eventCards();}});
    window.addEventListener('rolling-preview-back',e=>{if(route){e.stopImmediatePropagation();back();}},true);
    window.addEventListener('rolling-role-changed',()=>{if(!allowed())close();});
    window.addEventListener('hashchange',()=>{if(['#/login','#/sites'].includes(location.hash)){window.rollingPreviewReady=false;close();window.dispatchEvent(new Event('rolling-preview-ready'));}});
    document.addEventListener('keydown',e=>{if(e.key==='Escape'&&route){e.stopImmediatePropagation();back();}},true);
    // 下方仍使用原生 Flutter 底部导航；切换主栏目时关闭管理子页。
    phone.addEventListener('pointerdown',e=>{const rect=phone.getBoundingClientRect();if(route && e.clientY>rect.bottom-60*rect.height/900)close();},true);
  }
  window.RollingAdmin={counts, canOpen:allowed};
  window.openFieldLead=window.openLeadPanel=()=>navigate({page:'lead'},true);
  window.closeFieldLead=()=>close();
  window.openRollingEvents=id=>navigate(id&&events.some(e=>e.id===id)?{page:'detail',id}:{page:'events'},true);
  window.closeRollingEvents=()=>close();
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();
