const $ = id => document.getElementById(id);
const names = { helmet:'安全帽', belt:'安全腰带', watch:'手表', ringing:'响铃中', connected:'已接通', rejected:'已拒接', ended:'已结束', timed_out:'无人接听', offline:'已离线', sent:'已送达 · 待模拟确认', acknowledged:'已模拟确认', draft:'草稿', ready:'就绪', in_progress:'进行中', paused:'已暂停', completed:'已完成', cancelled:'已取消' };
const state = { token:'', me:null, site:'', epoch:0, busy:false, polling:false, captcha:'', people:[], devices:[], tasks:[], live:{devices:[],calls:[],messages:[],dispatchers:[]}, selected:new Set(), drafts:new Map(), callSignature:'', messageSignature:'' };
const stale = () => Object.assign(new Error('页面身份或厂站已变化，请重试'), { stale:true });
function node(tag,text,cls) { const el=document.createElement(tag); if(text!=null)el.textContent=text; if(cls)el.className=cls; return el; }
function notice(text,error=false) { $('notice').textContent=text; $('notice').dataset.error=error; $('notice').hidden=false; }
function scope() { return { token:state.token, site:state.site, epoch:state.epoch }; }
function current(s) { return s.epoch===state.epoch && s.token===state.token && s.site===state.site; }
function assertCurrent(s) { if(!current(s))throw stale(); }
function canConfigure() { return state.me?.admin || state.me?.roles?.some(r=>['wear_duty','wear_team_lead','wear_platform_admin'].includes(r)); }
function can(permission) { return state.me?.admin || state.me?.permissions?.some(p=>p===permission||p==='*:*:*'); }
function controls() {
  const logged=!!state.me, write=logged&&canConfigure(), busy=state.busy;
  for(const el of document.querySelectorAll('button,input,select,textarea'))el.disabled=busy;
  $('site').disabled=busy||!logged; $('signOut').disabled=busy||!logged;
  for(const el of document.querySelectorAll('#workspace button,#workspace input,#workspace select,#workspace textarea'))el.disabled=busy||!logged;
  for(const el of document.querySelectorAll('[data-write]'))el.disabled=busy||!write;
  for(const id of ['onlineSelected','offlineSelected'])$(id).disabled=busy||!write||!state.selected.size;
  for(const id of ['normalCall','sosCall'])$(id).disabled=busy||!write||!can('wear:call:start')||!state.selected.size||state.live.dispatchers.length!==1;
  $('sendTts').disabled=busy||!can('wear:command:tts')||!state.selected.size;
  $('saveMembers').disabled=busy||!logged||!$('editTask').value;
  for(const el of document.querySelectorAll('[data-helmet-call]')) {
    const id=el.dataset.helmetCall,call=deviceCall(id);
    const canAccept=(call?.p.direction||call?.c.direction)==='outgoing'&&call.p.state==='ringing';
    el.disabled=busy||!write||!liveDevice(id)?.online||(call?!canAccept:!can('wear:call:start')||state.live.dispatchers.length!==1);
  }
  for(const el of document.querySelectorAll('[data-helmet-end]'))el.disabled=busy||!write||!deviceCall(el.dataset.helmetEnd);
  for(const el of document.querySelectorAll('[data-helmet-state]')) {
    const id=el.dataset.helmetState,call=deviceCall(id);
    el.textContent=!liveDevice(id)?.online?'设备离线':!call?'待机 · 一键呼叫当前值班':call.p.state==='connected'?'通话中':(call.p.direction||call.c.direction)==='outgoing'?'来电响铃 · 呼叫 / 接听键接听，挂断键拒绝':'呼叫当前值班中 · 等待接听';
  }
}
async function run(fn) {
  if(state.busy)return;
  state.busy=true; controls();
  try { await fn(); } catch(e) { if(!e.stale)notice(e.message,true); }
  finally { state.busy=false; controls(); }
}
async function request(path,{method='GET',body,anonymous=false,s=scope(),detached=false}={}) {
  if(!anonymous&&!detached)assertCurrent(s);
  const headers={'Content-Type':'application/json'};
  if(!anonymous&&s.token)headers.Authorization='Bearer '+s.token;
  if(!anonymous&&s.site)headers['X-Site-Id']=s.site;
  const response=await fetch(path,{method,headers,body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
  if(!anonymous&&!detached)assertCurrent(s);
  let result; try { result=await response.json(); } catch { throw new Error('服务未返回 JSON，请检查联调服务与后端连接'); }
  if(!response.ok||(result.code!=null&&Number(result.code)!==200)) {
    if(!anonymous&&!detached&&(response.status===401||Number(result.code)===401))reset();
    throw new Error(result.msg||result.message||'请求失败（'+response.status+'）');
  }
  return result;
}
async function api(path,options) { return (await request('/api/v1'+path,options)).data; }
async function captcha() { const r=await request('/captchaImage',{anonymous:true}); state.captcha=r.uuid||''; $('captchaBox').hidden=r.captchaEnabled===false||!r.img; $('captchaImage').src=r.img?'data:image/png;base64,'+r.img:''; $('captcha').value=''; }
function clearWorkspace() {
  state.epoch++; state.people=[];state.devices=[];state.tasks=[];state.selected.clear();state.drafts.clear();
  state.live={devices:[],calls:[],messages:[],dispatchers:[]};state.callSignature='';state.messageSignature='';
  for(const id of ['devices','calls','messages','taskMembers'])$(id).replaceChildren();
  $('taskFilter').replaceChildren(new Option('全部作业',''));$('editTask').replaceChildren();$('dispatcher').textContent='暂无在线值班账号';
  $('search').value='';$('deviceType').value='';$('taskInfo').textContent='';$('ttsText').value='';$('selectVisible').checked=false;
  $('selectedCount').textContent='已选 0 台';$('heartbeat').textContent='等待同步';
}
function reset() {
  clearWorkspace();state.token='';state.me=null;state.site='';$('workspace').hidden=true;
  $('site').replaceChildren(new Option('请先登录',''));$('connection').textContent='尚未登录';$('accountInfo').textContent='已清除本页认证信息；没有保存密码或令牌。';
}
async function offlineOwned(s=scope()) {
  const owned=state.live.devices.filter(d=>d.online&&String(d.controller)===String(state.me?.userId));
  const results=await Promise.allSettled(owned.map(d=>api('/lab/presence',{method:'POST',body:{deviceId:d.deviceId,personId:d.personId,online:false,abnormal:d.abnormal},s,detached:true})));
  return results.every(r=>r.status==='fulfilled');
}
async function login() {
  const credentials={username:$('username').value.trim(),password:$('password').value,code:$('captcha').value.trim(),uuid:state.captcha};
  if(state.token)await offlineOwned();reset();
  try {
    const r=await request('/login',{method:'POST',body:credentials,anonymous:true});state.token=r.token;
    if(!state.token)throw new Error('后端未返回登录令牌');
    state.me=await api('/me');
    const sites=(state.me.authorizedSites||[]).filter(s=>s.status==null||String(s.status)==='0');
    $('site').replaceChildren(...sites.map(s=>new Option(s.name,String(s.id))));
    if(sites.some(s=>String(s.id)===String(state.me.currentSiteId)))$('site').value=String(state.me.currentSiteId);
    state.site=$('site').value;state.epoch++;
    $('connection').textContent='已连接 · '+(state.me.nickName||state.me.userName);
    $('accountInfo').textContent=(state.me.roles||[]).join('、')+' · 仅内存保存认证';$('workspace').hidden=false;
    if(!state.site)throw new Error('账号没有可访问的厂站');
    await refreshRoster();await poll();notice('名单已加载。勾选设备并上线后，可与安卓值班端联调。');
  } catch(e) {
    if(!state.me) { reset();await captcha().catch(()=>{}); }
    throw e;
  } finally { $('password').value=''; }
}
function personName(id) { return state.people.find(p=>String(p.id)===String(id))?.name||'未绑定人员'; }
function liveDevice(id) { return state.live.devices.find(d=>String(d.deviceId)===String(id)); }
function draft(device) {
  const id=String(device.id);
  if(!state.drafts.has(id)) { const p=liveDevice(id)||device.lab;state.drafts.set(id,{personId:String(p?.personId||device.currentAssignment?.personId||''),online:p?.online===true,abnormal:p?.abnormal===true}); }
  return state.drafts.get(id);
}
async function refreshRoster() {
  const s=scope(),result=await api('/lab/roster',{s});assertCurrent(s);
  state.people=result.people||[];state.devices=(result.devices||[]).filter(d=>d.siteId==null||String(d.siteId)===state.site);state.tasks=result.tasks||[];
  const ids=new Set(state.devices.map(d=>String(d.id)));
  state.selected=new Set([...state.selected].filter(id=>ids.has(id)));state.drafts.clear();
  const filter=$('taskFilter').value,task=$('editTask').value;
  $('taskFilter').replaceChildren(new Option('全部作业',''),...state.tasks.map(t=>new Option(`[${names[t.status]||t.status||'就绪'}] `+t.title,String(t.id))));
  if(state.tasks.some(t=>String(t.id)===filter))$('taskFilter').value=filter;
  $('editTask').replaceChildren(...state.tasks.map(t=>new Option(t.title+(t.demo?' · 演示':''),String(t.id))));
  if(state.tasks.some(t=>String(t.id)===task))$('editTask').value=task;
  renderDevices();renderMembers();
}
function visibleDevices() {
  const q=$('search').value.trim().toLowerCase(),type=$('deviceType').value,task=state.tasks.find(t=>String(t.id)===$('taskFilter').value);
  const members=task?new Set((task.members||[]).map(p=>String(p.personId))):null;
  return state.devices.filter(d=>{ const p=draft(d);return (!type||d.typeCode===type)&&(!members||members.has(p.personId))&&(!q||[d.sn,d.externalCode,personName(p.personId),state.people.find(v=>String(v.id)===p.personId)?.personCode].join(' ').toLowerCase().includes(q)); });
}
function checkbox(text,checked,change) { const label=node('label',null,'check'),input=node('input');input.type='checkbox';input.checked=checked;input.addEventListener('change',()=>change(input.checked));label.append(input,document.createTextNode(text));return label; }
function button(text,cls,handler) { const b=node('button',text,cls);b.type='button';b.addEventListener('click',()=>run(handler));return b; }
function badge(text,cls='') { return node('span',text,'badge '+cls); }
function renderDevices() {
  const visible=visibleDevices();$('devices').replaceChildren(...visible.map(d=>{
    const id=String(d.id),p=draft(d),card=node('article',null,'device');card.dataset.device=id;
    const head=node('div',null,'device-title'),pick=checkbox('',state.selected.has(id),v=>{v?state.selected.add(id):state.selected.delete(id);selection();});pick.querySelector('input').setAttribute('aria-label','选择设备 '+d.sn);
    head.append(pick,node('strong',d.sn),badge(p.online?'在线':'离线',p.online?'online':'offline'));head.lastChild.dataset.presence=id;
    card.append(head,node('p',(names[d.typeCode]||d.typeCode)+' · '+(d.modelName||'已有设备')+(d.demo?' · 演示':''),'device-subtitle'));
    const label=node('label','测试佩戴人（仅联调）'),select=node('select');select.setAttribute('aria-label',d.sn+' 测试佩戴人');select.dataset.write='';
    select.append(new Option('未绑定人员',''),...state.people.map(v=>new Option(v.name+' · '+(v.personCode||v.id),String(v.id))));select.value=p.personId;select.addEventListener('change',()=>p.personId=select.value);label.append(select);card.append(label);
    const checks=node('div',null,'device-checks');for(const [key,text]of[['online','在线'],['abnormal','异常']]) { const wrap=checkbox(text,p[key],v=>p[key]=v);wrap.querySelector('input').dataset.write='';checks.append(wrap); }card.append(checks);
    const save=button('应用此设备配置','secondary',async()=>{await savePresence(d);await poll();notice(d.sn+' 的联调配置已同步');});save.dataset.write='';card.append(save);
    if(d.typeCode==='helmet') {
      card.append(node('p','帽端按键模拟 · 无屏幕 / 无联系人选择','hint'));
      const keys=node('div',null,'actions');
      const callKey=button('呼叫 / 接听','primary',()=>helmetCall(id));callKey.dataset.helmetCall=id;
      const endKey=button('挂断','danger-outline',()=>helmetEnd(id));endKey.dataset.helmetEnd=id;
      keys.append(callKey,endKey);card.append(keys);
      const status=node('p',null,'hint');status.dataset.helmetState=id;card.append(status);
    }
    return card;
  }));
  if(!visible.length)$('devices').append(node('p','没有符合条件的设备','empty'));selection();controls();
}
function selection() { const visible=visibleDevices();$('selectedCount').textContent='已选 '+state.selected.size+' 台';$('selectVisible').checked=!!visible.length&&visible.every(d=>state.selected.has(String(d.id)));$('selectVisible').indeterminate=visible.some(d=>state.selected.has(String(d.id)))&&!$('selectVisible').checked;controls(); }
async function savePresence(d,s=scope()) { const p=draft(d);await api('/lab/presence',{method:'POST',body:{deviceId:String(d.id),...p},s});assertCurrent(s); }
async function setSelectedOnline(online) {
  const s=scope();let done=0;
  try { for(const id of state.selected) { assertCurrent(s);const d=state.devices.find(d=>String(d.id)===id);draft(d).online=online;await savePresence(d,s);done++; }notice(done+' 台设备已'+(online?'上线':'离线')); }
  catch(e) { throw new Error('已更新 '+done+' 台，后续失败：'+e.message); }
  finally { if(current(s)) { await poll();state.drafts.clear();renderDevices(); } }
}
function renderDispatchers() {
  const items=state.live.dispatchers||[];
  $('dispatcher').textContent=items.length===1?items[0].name+' · 唯一在线值班':items.length>1?'发现 '+items.length+' 个在线值班账号':'暂无在线值班账号';
  $('dispatcherHint').textContent=items.length===1?'联调将唯一在线值班账号映射为本班接听人；正式排班路由待接入，帽端不能选择联系人。':items.length>1?'当前厂站有多个在线值班账号，请仅保留本班值班账号在线后重试。联调不按心跳排序猜选接听人。':'请在安卓仅使用本班值班账号登录并启用联调。';
}
function deviceCall(id) {
  for(const c of state.live.calls||[]) { if(!['ringing','connected'].includes(c.state))continue;const p=c.participants.find(p=>String(p.deviceId)===String(id)&&['ringing','connected'].includes(p.state));if(p)return {c,p}; }
  return null;
}
async function helmetCall(id) {
  const active=deviceCall(id);
  if(active) {
    if((active.p.direction||active.c.direction)==='outgoing'&&active.p.state==='ringing')return callAction(active.c,active.p,'accept');
    throw new Error('当前正在呼叫或通话中，请勿重复呼叫');
  }
  return startCall(false,[id]);
}
async function helmetEnd(id) {
  const active=deviceCall(id);if(!active)throw new Error('此安全帽没有待处理通话');
  return callAction(active.c,active.p,(active.p.direction||active.c.direction)==='outgoing'&&active.p.state==='ringing'?'reject':'end');
}
async function startCall(sos,ids=[...state.selected]) {
  const s=scope(),devices=ids.map(id=>state.devices.find(d=>String(d.id)===id));
  if(ids.length!==1)throw new Error('设备来电每次请选择 1 台安全帽；多人群呼请从安卓多选设备发起');
  if(!ids.length||devices.some(d=>d.typeCode!=='helmet'))throw new Error('呼叫请选择安全帽；腰带、手表可测试在线状态与播报回执');
  if(ids.some(id=>!liveDevice(id)?.online))throw new Error('请先将所选安全帽上线');
  if(!state.live.dispatchers.length)throw new Error('当前没有在线值班账号');
  if(state.live.dispatchers.length!==1)throw new Error('当前厂站有多个在线值班账号，请仅保留本班值班账号在线后重试');
  await api('/lab/calls',{method:'POST',body:{direction:'incoming',deviceIds:ids,sos},s});
  await poll();notice((sos?'SOS 紧急':'普通')+'来电已发起，请在安卓值班端接听。');
}
function stamp(value) { return value?new Date(value).toLocaleString('zh-CN',{hour12:false}):'—'; }
function participantLabel(id,sn,personId) { const div=node('div',null,'person');div.append(node('strong',personName(personId)),node('small',sn||state.devices.find(d=>String(d.id)===String(id))?.sn||id));return div; }
async function callAction(call,person,action) { await api('/lab/calls/'+encodeURIComponent(call.id)+'/'+action,{method:'POST',body:{deviceId:person.deviceId}});await poll(); }
function renderCalls() {
  const items=state.live.calls||[],signature=JSON.stringify(items);
  if(signature===state.callSignature)return;state.callSignature=signature;
  $('calls').replaceChildren(...items.map(c=>{
    const card=node('article',null,'session');card.dataset.call=c.id;card.dataset.direction=c.direction;
    const head=node('div',null,'session-head');head.append(node('strong','呼叫 · '+(c.direction==='incoming'?'设备呼入安卓':'安卓呼叫设备')),badge(names[c.state]||c.state,c.state));if(c.sos)head.append(badge('SOS 紧急','sos'));
    card.append(head,node('p',stamp(c.createdAt)+' · '+c.participants.length+' 台设备'+(c.reason?' · '+c.reason:''),'hint'));
    if(c.videoEnabled===true)card.append(node('p','值班端查看安全帽画面（单向模拟）','hint'));
    for(const p of c.participants) {
      const row=node('div',null,'participant');row.dataset.participant=p.deviceId;
      const person=participantLabel(p.deviceId,p.sn,p.personId),connected=p.state==='connected'&&c.state==='connected';
      const camera=node('small',connected?(c.videoEnabled===true?'画面查看中（单向模拟）':'画面查看未开启'):'未接通 · 不可查看画面');camera.dataset.camera=p.deviceId;person.append(camera);
      row.append(person,badge(names[p.state]||p.state,p.state));
      card.append(row);
    }
    return card;
  }));if(!items.length)$('calls').append(node('p','暂无通话。可以从安卓外呼，或在上方模拟设备来电。','empty'));
}
function renderMessages() {
  const items=state.live.messages||[],signature=JSON.stringify(items);if(signature===state.messageSignature)return;state.messageSignature=signature;
  $('messages').replaceChildren(...items.map(m=>{
    const card=node('article',null,'message');card.dataset.message=m.id;card.append(node('p',stamp(m.createdAt)+' · '+m.receipts.length+' 台设备','hint'),node('div',m.text,'message-text'));
    for(const r of m.receipts) { const row=node('div',null,'participant'),device=liveDevice(r.deviceId);row.append(participantLabel(r.deviceId,device?.sn,device?.personId),badge(names[r.state]||r.state,r.state));
      if(r.state==='sent') { const b=button('模拟收到播报','secondary',async()=>{await api('/lab/tts/ack',{method:'POST',body:{id:m.id,deviceId:r.deviceId}});await poll();});b.dataset.write='';row.append(b); }card.append(row);
    }return card;
  }));if(!items.length)$('messages').append(node('p','暂无播报；安卓群发后可逐设备模拟确认。','empty'));
}
async function poll({heartbeatOnly=false}={}) {
  if(!state.me||!state.site||state.polling)return;
  const s=scope();state.polling=true;
  try {
    const result=await api('/lab/state?client=console',{s});assertCurrent(s);state.live=result;
    // Long roster/member writes must not suspend device leases. Background busy
    // polls renew presence without rebuilding selectors or touching form drafts.
    if(heartbeatOnly) { $('heartbeat').textContent='心跳已续期 '+new Date().toLocaleTimeString('zh-CN',{hour12:false});return; }
    renderDispatchers();renderCalls();renderMessages();
    for(const el of document.querySelectorAll('[data-presence]')) { const online=liveDevice(el.dataset.presence)?.online;el.textContent=online?'在线':'离线';el.className='badge '+(online?'online':'offline'); }
    $('heartbeat').textContent='已同步 '+new Date().toLocaleTimeString('zh-CN',{hour12:false});controls();
  } catch(e) { if(current(s)&&!e.stale)$('heartbeat').textContent='同步失败：'+e.message+'；重试中'; }
  finally { state.polling=false; }
}
function renderMembers() {
  const task=state.tasks.find(t=>String(t.id)===$('editTask').value),ids=new Set((task?.members||[]).map(m=>String(m.personId)));
  $('taskInfo').textContent=task?'作业状态：'+(names[task.status]||task.status)+' · 当前 '+ids.size+' 位成员（修改会写入业务项目）':'当前厂站暂无作业';
  $('taskMembers').replaceChildren(...state.people.map(p=>{const el=checkbox(p.name+' · '+(p.personCode||p.id),ids.has(String(p.id)),()=>{});el.querySelector('input').value=String(p.id);return el;}));
  controls();
}
async function saveMembers() {
  const s=scope(),task=state.tasks.find(t=>String(t.id)===$('editTask').value);if(!task)throw new Error('请选择作业');
  const selected=new Set([...$('taskMembers').querySelectorAll('input:checked')].map(el=>el.value)),old=new Set((task.members||[]).map(m=>String(m.personId)));
  const add=[...selected].filter(id=>!old.has(id)),remove=[...old].filter(id=>!selected.has(id));
  if(!add.length&&!remove.length) {notice('成员没有变化，无需提交');return;}
  let changed=0;
  try {
    if(add.length){await api('/work-tasks/'+encodeURIComponent(task.id)+'/members',{method:'POST',body:{personIds:add},s});changed+=add.length;}
    for(const id of remove) {assertCurrent(s);await api('/work-tasks/'+encodeURIComponent(task.id)+'/members/'+encodeURIComponent(id),{method:'DELETE',s});changed++;}
    notice('作业成员已保存并回读，安卓刷新后可按作业筛选。');
  } catch(e) { throw new Error('已提交 '+changed+' 项成员变更；'+e.message); }
  finally { if(current(s))await refreshRoster(); }
}
$('loginForm').addEventListener('submit',e=>{e.preventDefault();run(login);});
$('refreshCaptcha').addEventListener('click',()=>run(captcha));
$('signOut').addEventListener('click',()=>run(async()=>{const clean=await offlineOwned();reset();notice(clean?'已退出，当前账号控制的联调设备已离线。':'已退出；无法立即离线的联调设备将在心跳超时后自动离线。');await captcha();}));
$('site').addEventListener('change',()=>run(async()=>{const next=$('site').value;await offlineOwned();clearWorkspace();state.site=next;await refreshRoster();await poll();notice('已切换厂站并清除上一个厂站的选择。');}));
$('refreshRoster').addEventListener('click',()=>run(async()=>{await poll();await refreshRoster();notice('已回读最新人员、设备和作业。');}));
for(const id of ['search','deviceType','taskFilter'])$(id).addEventListener(id==='search'?'input':'change',renderDevices);
$('selectVisible').addEventListener('change',()=>{for(const d of visibleDevices())$('selectVisible').checked?state.selected.add(String(d.id)):state.selected.delete(String(d.id));renderDevices();});
$('onlineSelected').addEventListener('click',()=>run(()=>setSelectedOnline(true)));$('offlineSelected').addEventListener('click',()=>run(()=>setSelectedOnline(false)));
$('normalCall').addEventListener('click',()=>run(()=>startCall(false)));$('sosCall').addEventListener('click',()=>run(()=>startCall(true)));
$('sendTts').addEventListener('click',()=>run(async()=>{const text=$('ttsText').value.trim();if(!text)throw new Error('请输入播报内容');await api('/lab/tts',{method:'POST',body:{deviceIds:[...state.selected],text}});await poll();notice('测试播报已提交，请逐设备模拟确认回执。');}));
$('editTask').addEventListener('change',renderMembers);$('saveMembers').addEventListener('click',()=>run(saveMembers));
setInterval(()=>{void poll({heartbeatOnly:state.busy});},2000);
controls();run(captcha);
