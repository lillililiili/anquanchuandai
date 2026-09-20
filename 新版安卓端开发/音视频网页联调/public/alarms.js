const $ = id => document.getElementById(id);
const typeNames = { helmet: '安全帽', belt: '安全腰带', watch: '手表' };
const eventNames = { sos: 'SOS', fall: '跌落', impact: '撞击', realtime: '实时告警', geofence: '围栏告警' };
const statusNames = { open: '待认领', claimed: '已认领', handling: '处理中', pending_review: '待复核', closed: '已关闭' };
const state = { token: '', me: null, scenarios: [], scenario: null, device: null, event: null, last: null, busy: false, captcha: '' };
function node(tag, text, className) {
  const el = document.createElement(tag);
  if (text != null) el.textContent = text;
  if (className) el.className = className;
  return el;
}
function notice(message, error = false) { $('notice').textContent = message; $('notice').dataset.error = error; $('notice').hidden = false; }
function output(value) { $('result').textContent = JSON.stringify(value, null, 2); }
function role(...roles) { return !!state.me?.roles?.some(r => roles.includes(r)); }
function canEdit() { return state.me?.admin || role('wear_device_admin', 'wear_platform_admin', 'admin'); }
function canClaim() { return role('wear_duty', 'wear_team_lead'); }
function canSimulate() { return state.me?.admin || role('wear_platform_admin', 'admin', 'wear_duty', 'wear_team_lead'); }
function canReview() { return state.me?.admin || role('wear_reviewer', 'wear_platform_admin', 'admin'); }
function isLabEvent(e) { return e?.demo === true && e.source === 'simulator' && e.sourceEventId?.startsWith('call-lab:'); }
function controls() {
  const logged = !!state.me, device = !!state.device, busy = state.busy, e = state.event;
  for (const el of document.querySelectorAll('input,select,button')) el.disabled = busy;
  $('signOut').disabled = busy || !logged;
  for (const id of ['site', 'refreshDevices', 'device', 'refreshEvents']) $(id).disabled = busy || !logged;
  $('createDevice').disabled = busy || !logged || !canEdit() || !$('site').value;
  $('saveDevice').disabled = busy || !device || !canEdit();
  $('sendAlarm').disabled = busy || !device || !state.scenario || !canSimulate();
  $('repeatAlarm').disabled = busy || !state.last || !canSimulate() || state.last.siteId !== $('site').value || state.last.deviceId !== state.device?.id;
  const mutable = !busy && isLabEvent(e);
  $('claimEvent').disabled = !mutable || !canClaim() || e.status !== 'open';
  $('handleEvent').disabled = !mutable || !canClaim() || !['claimed','handling'].includes(e.status) || e.claimantUserId !== state.me?.userId;
  $('closeEvent').disabled = !mutable || !(e.severity === 'high' ? canReview() && e.status === 'pending_review' : canClaim() && e.status === 'handling');
}
async function run(fn) {
  if (state.busy) return;
  state.busy = true; controls();
  try { await fn(); }
  catch (error) { notice(error.message, true); }
  finally { state.busy = false; controls(); }
}
async function api(path, { method = 'GET', body, anonymous = false } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (!anonymous && state.token) headers.Authorization = 'Bearer ' + state.token;
  if (!anonymous && state.me && $('site').value) headers['X-Site-Id'] = $('site').value;
  const res = await fetch(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(28000) });
  let json;
  try { json = await res.json(); } catch { throw new Error('后端没有返回 JSON，请检查 BACKEND_URL 与服务状态'); }
  if (!res.ok || (json.code != null && Number(json.code) !== 200)) {
    if (Number(json.code) === 401 && !anonymous) reset();
    throw new Error((json.msg || json.message || '请求失败') + '（' + (json.code || res.status) + '）');
  }
  return json;
}
async function data(path, options) { return (await api('/api/v1' + path, options)).data; }
async function captcha() {
  const result = await api('/captchaImage', { anonymous: true });
  state.captcha = result.uuid || '';
  $('captchaBox').hidden = result.captchaEnabled === false || !result.img;
  $('captchaImage').src = result.img ? 'data:image/png;base64,' + result.img : '';
  $('captcha').value = '';
}
function clearDevice() {
  state.device = null; state.event = null; state.last = null;
  $('eventPanel').hidden = true; $('events').replaceChildren(node('p', '选择设备后读取事件', 'empty'));
  $('deviceInfo').textContent = '暂无设备'; $('externalCode').value = '';
}
function reset() {
  state.token = ''; state.me = null; state.scenarios = []; state.scenario = null; clearDevice();
  $('site').replaceChildren(node('option','请先登录')); $('device').replaceChildren(node('option','请先登录'));
  $('connection').textContent = '尚未登录项目'; $('accountInfo').textContent = '已退出；页面没有保存密码和令牌。';
  $('scenarios').replaceChildren(node('p','登录后加载场景','hint')); $('measurements').replaceChildren();
  $('catalogStatus').textContent = '等待连接'; output({ message: '已清除本页认证信息' });
}
async function login() {
  // Discard previous identity before switching, including an unsuccessful switch.
  reset();
  try {
    const result = await api('/login', { method:'POST', anonymous:true, body: {
      username: $('username').value.trim(), password: $('password').value,
      code: $('captcha').value.trim(), uuid: state.captcha
    } });
    state.token = result.token;
    if (!state.token) throw new Error('后端未返回登录令牌');
    state.me = await data('/me');
  } catch (err) { reset(); await captcha().catch(() => {}); throw err; }
  finally { $('password').value = ''; }
  const me = state.me;
  $('accountInfo').textContent = me.userName + '\n角色：' + me.roles.join('、');
  $('connection').textContent = '已连接 · ' + me.userName;
  $('site').replaceChildren(...me.authorizedSites.map(s => new Option(s.name, s.id)));
  if (me.currentSiteId && me.authorizedSites.some(s => s.id === me.currentSiteId)) $('site').value = me.currentSiteId;
  try {
    state.scenarios = await data('/events/simulation-scenarios');
    $('catalogStatus').textContent = state.scenarios.length + ' 个场景';
  } catch (err) {
    $('catalogStatus').textContent = '模拟接口不可用';
    notice('已登录，告警接口未启用或后端未升级。需非 prod 环境，并开启 melhat.demo-mode 或 melhat.simulation-enabled。' + err.message, true);
  }
  renderScenarios();
  await loadDevices();
  if (state.scenarios.length) notice('项目已连接。请选择设备和测试场景。');
}
function renderScenarios() {
  const scenarios = state.scenarios.filter(s => s.deviceType === $('deviceType').value);
  state.scenario = scenarios[0] || null;
  $('scenarios').replaceChildren(...scenarios.map(s => {
    const button = node('button',s.label,'scenario');
    button.type = 'button'; button.dataset.scenario = s.id;
    button.append(node('small', (s.optional ? '选配 · ' : '') + (s.deviceType === 'helmet' ? '资料场景' : '联调假设')));
    button.addEventListener('click', () => { state.scenario = s; renderFields(); controls(); });
    return button;
  }));
  renderFields();
}
function renderFields() {
  const s = state.scenario;
  for (const el of $('scenarios').children) el.setAttribute('aria-pressed', String(el.dataset.scenario === s?.id));
  $('measurements').replaceChildren();
  $('scenarioDescription').textContent = s ? s.basis + '。入库类型：' + eventNames[s.type] + '。' : '没有可用场景，请检查后端模拟接口配置。';
  for (const f of s?.fields || []) {
    const wrap = node('div'), label = node('label', f.label + ' / ' + f.unit), input = node('input');
    input.id = 'measure-' + f.key; label.htmlFor = input.id;
    Object.assign(input, { type:'number', min:String(f.min), max:String(f.max), step:'0.001', value:String(f.value), required:true });
    input.dataset.measure = f.key; wrap.append(label,input); $('measurements').append(wrap);
  }
}
async function loadDevices(preferred) {
  clearDevice();
  $('device').replaceChildren();
  if (!$('site').value) { $('deviceInfo').textContent = '账号未授权任何厂站'; return; }
  let devices = [], page = 1, total = 0;
  do {
    const batch = await data('/devices?typeCode=' + $('deviceType').value + '&size=100&current=' + page++);
    devices.push(...batch.records); total = batch.total;
  } while (devices.length < total && page <= 50);
  devices = devices.filter(d => d.siteId === $('site').value);
  $('device').replaceChildren(...devices.map(d => new Option(d.sn + ' · ' + (d.modelName || d.typeCode), d.id)));
  if (preferred && devices.some(d => d.id === preferred)) $('device').value = preferred;
  if ($('device').value) await loadDevice();
  else $('deviceInfo').textContent = '该厂站暂无此类设备。可用设备管理员账号创建专用测试设备。';
}
async function loadDevice() {
  state.event = null; state.last = null; $('eventPanel').hidden = true;
  const device = await data('/devices/' + encodeURIComponent($('device').value));
  state.device = device;
  $('externalCode').value = device.externalCode || '';
  $('deviceInfo').textContent = 'SN：' + device.sn + '\n型号：' + device.modelName +
    '\n厂站：' + device.siteName + '\n状态：' + device.assetStatus +
    '\n佩戴人：' + (device.currentAssignment?.personName || '未分配（告警仍可入库）') +
    '\n设备 ID：' + device.id + ' · 版本 ' + device.version;
  await loadEvents();
}
async function createDevice() {
  const type = $('deviceType').value, siteId = $('site').value, code = 'CALL-LAB-' + type.toUpperCase();
  let models = await data('/product-models?typeCode=' + type);
  let model = models.find(m => m.modelCode === code);
  if (!model) model = await data('/product-models', { method:'POST', body:{
    typeCode:type, modelCode:code, manufacturerCode:'CALL-LAB', name:typeNames[type] + '（联调虚拟型号）',
    protocolVersion:'call-lab/1', capabilities:{ protocolVersion:'call-lab/1', attributes:[], actions:[], events:[] }
  } });
  const sn = code + '-' + siteId;
  const existing = await data('/devices?sn=' + encodeURIComponent(sn) + '&size=100');
  let device = existing.records.find(d => d.sn === sn && d.manufacturerCode === 'CALL-LAB');
  if (device && (device.siteId !== siteId || device.typeCode !== type)) throw new Error('同名测试设备的厂站或类型不同，请检查台账');
  if (!device) device = await data('/devices', { method:'POST', body:{ sn, modelId:model.id, manufacturerCode:'CALL-LAB', siteId, externalCode:sn } });
  await loadDevices(device.id); output({operation:'创建 / 复用测试设备',device:state.device});
  notice('测试设备已从项目回读：' + state.device.sn + '。未分配佩戴人，可直接做事件链路测试。');
}
async function saveDevice() {
  const d = state.device, value = $('externalCode').value.trim();
  if (!value) throw new Error('请填写资产编码');
  await data('/devices/' + d.id, { method:'PUT', body:{ externalCode:value, version:d.version } });
  await loadDevice();
  if (state.device.externalCode !== value) throw new Error('保存接口已返回，但回读值不一致，请核对项目数据');
  output({operation:'修改资产编码并回读',device:state.device}); notice('已保存到项目；回读值与提交值一致。');
}
function payload() {
  if (!state.device || !state.scenario) throw new Error('请选择设备和场景');
  const lat = $('lat').value, lng = $('lng').value;
  if ((lat === '') !== (lng === '')) throw new Error('经纬度必须一起填写或一起留空');
  return {sourceEventId:'call-lab:' + crypto.randomUUID(), siteId:$('site').value,
    deviceId:state.device.id, scenarioCode:state.scenario.id, type:state.scenario.type,
    occurredAt:new Date().toISOString(), measurements:Object.fromEntries([...document.querySelectorAll('[data-measure]')].map(el => [el.dataset.measure, Number(el.value)])),
    ...(lat !== '' ? {lat:Number(lat),lng:Number(lng)} : {})};
}
async function sendAlarm(repeat = false) {
  const body = repeat ? state.last : payload();
  if (!body) throw new Error('暂无可重发的事件');
  // Keep the same key even if a timeout makes the write result uncertain.
  state.last = body;
  $('lastSend').textContent = '请求标识：' + body.sourceEventId + '。若网络超时，可重发同一事件核对结果。';
  output({request:body});
  const written = await data('/events/simulate', {method:'POST',body});
  await loadEvents(written.id);
  const readback = await selectEvent(written.id);
  output({request:body,writeResult:written,readback:eventResult(readback)});
  if (!isLabEvent(readback.event) || readback.event.deviceId !== body.deviceId) throw new Error('回读来源或设备不一致，请核对后端数据');
  notice((repeat ? '去重重发完成' : '告警已写入并回读') + ' · 事件 ' + written.id + ' · 重复次数 ' + readback.event.repeatCount);
}
function eventResult(result) { return { event:result.event, actions:result.actions }; }
async function loadEvents(selectedId = state.event?.id) {
  if (!state.device) return;
  const list = await data('/events?status=all&size=100&sn=' + encodeURIComponent(state.device.sn));
  const events = list.records.filter(e => e.deviceId === state.device.id);
  $('events').replaceChildren(...events.map(e => {
    const button = node('button',null,'event-row'); button.dataset.event = e.id;
    const left = node('span', '#' + e.id + ' · ' + (eventNames[e.type] || e.type));
    left.append(node('small', (isLabEvent(e) ? 'CALL-LAB 测试' : (e.demo ? '其他模拟事件' : '项目事件')) + ' · ' + e.occurredAt));
    button.append(left,node('span',statusNames[e.status] || e.status));
    button.addEventListener('click', () => run(() => selectEvent(e.id)));
    return button;
  }));
  if (!events.length) $('events').append(node('p','该设备暂无事件，生成一条测试告警开始验证。','empty'));
  if (selectedId) await selectEvent(selectedId);
}
async function selectEvent(id) {
  const [event, actions] = await Promise.all([data('/events/' + id),data('/events/' + id + '/actions')]);
  state.event = event;
  $('eventPanel').hidden = false;
  const simulation = actions.find(a => a.action === 'simulate');
  let detail;
  try { detail = JSON.parse(simulation?.reason); } catch {}
  $('eventTitle').textContent = '#' + event.id + ' · ' + (detail?.label || eventNames[event.type] || event.type);
  $('eventStatus').textContent = statusNames[event.status] || event.status;
  $('eventFacts').textContent = '来源：' + event.source + ' · demo=' + event.demo + ' · 风险：' + event.severity +
    '\n设备：' + (event.sn || '—') + ' · 人员：' + (event.personName || '未分配') +
    '\n重复次数：' + event.repeatCount + ' · 版本：' + event.version +
    (detail ? '\n测试参数：' + JSON.stringify(detail.measurements) : '');
  $('eventActions').replaceChildren(...actions.map(a => {
    const row = node('div',a.action + ' · ' + (a.actor || 'system'),'action-row');
    row.append(node('small',a.createTime || ''), node('span',a.reason || '状态已更新')); return row;
  }));
  $('workflowHint').textContent = isLabEvent(event)
    ? '流程：待认领 → 认领 → 处置；高风险进入待复核，需切换复核账号关闭。按钮按当前账号权限和事件状态启用。'
    : '此事件不是本工具生成的模拟事件，仅供查看。';
  for (const el of $('events').children) el.classList.toggle('selected',el.dataset.event === id);
  output({event,actions}); controls();
  return {event,actions};
}
async function transition(action) {
  const e = state.event, reason = $('reason').value.trim();
  if (!isLabEvent(e)) throw new Error('只允许处置本工具的模拟事件');
  if (action !== 'claim' && !reason) throw new Error('请填写处置说明或关闭原因');
  try {
    await data('/events/' + e.id + '/' + action, {method:'POST',body:{version:e.version,reason,comment:reason}});
  } catch (error) {
    await selectEvent(e.id).catch(() => {}); throw error;
  }
  await loadEvents(e.id); notice('操作已完成并回读，当前状态：' + statusNames[state.event.status]);
}
$('loginForm').addEventListener('submit', e => {e.preventDefault();run(login);});
$('alarmForm').addEventListener('submit', e => {e.preventDefault();run(() => sendAlarm());});
$('refreshCaptcha').onclick = () => run(captcha);
$('signOut').onclick = () => run(async () => {
  try { await api('/logout', {method:'POST'}); } finally { reset(); await captcha().catch(() => {}); }
});
$('site').onchange = () => run(() => loadDevices());
$('deviceType').onchange = () => run(async () => {renderScenarios(); if(state.me) await loadDevices();});
$('device').onchange = () => run(loadDevice);
$('refreshDevices').onclick = () => run(() => loadDevices(state.device?.id));
$('createDevice').onclick = () => run(createDevice);
$('saveDevice').onclick = () => run(saveDevice);
$('repeatAlarm').onclick = () => run(() => sendAlarm(true));
$('refreshEvents').onclick = () => run(() => loadEvents());
for (const action of ['claim','handle','close']) $(action + 'Event').onclick = () => run(() => transition(action));
controls();
run(captcha);
