import { identities, missing } from './seed.js'
import { projectDataset } from './assignment-model.js'
import { failure } from './errors.js'
export const participantLabels = { RINGING: '本地振铃', CONNECTED: '本地会话就绪', REJECTED: '本地拒接', TIMED_OUT: '本地超时', LEFT: '已退出本地' }
export const modeLabels = { VOICE: '平台语音（本地）', VIDEO: '视频协同（本地）', PHONE: '电话（声明，未接入）' }
const clone = v => structuredClone(v)
export function dispatchData(d) { return d.relations.dispatch ||= { version: 1, sessions: [], groups: [], broadcasts: [], operations: [] } }
export function closeActiveDispatch(d, reason) {
  const x = dispatchData(d), active = x.sessions.find(s => s.state === 'ACTIVE')
  if (!active) return false
  active.state = 'ENDED'; active.endedAt = new Date().toISOString()
  active.participants.forEach(p => { if (['RINGING', 'CONNECTED'].includes(p.state)) p.state = 'LEFT' })
  active.timeline.unshift({ time: active.endedAt, title: reason }); x.version++
  return true
}
function scope(d, role, siteId, write = false) {
  const identity = identities.find(i => i.id === role)
  if (!identity) throw failure(401, '当前身份失效')
  if (!identity.sites.includes(siteId) || write && role !== 'owner') throw failure(403, '无厂站权限或仅负责人可操作协同')
}
function source(d, module) {
  if (d.config.module === module && d.config.mode !== 'normal') throw failure(d.config.mode === 'forbidden' ? 403 : 503, d.config.mode === 'not-integrated' ? '预置数据未接入' : '预置数据不可用，请恢复场景', d.config.mode === 'not-integrated' ? 'NOT_INTEGRATED' : 'SOURCE_UNAVAILABLE')
}
export function contacts(d, siteId) {
  const p = projectDataset(d)
  return p.entities.devices.filter(v => v.siteId === siteId).map(v => {
    const person = d.config.module === 'people' && d.config.mode !== 'normal' ? null : p.entities.people.find(person => Object.values(person.equipment.data || {}).some(slot => slot.assignmentState === 'ASSIGNED' && slot.devices.some(device => device.deviceId === v.deviceId)))
    const cap = key => v.profile?.capabilities[key]?.installation === 'PRESENT' && v.profile?.capabilities[key]?.integration === 'MOCK_READY' && v.profile?.privacy !== 'ON'
    const modes = v.type === 'HELMET' ? ['VOICE', 'VIDEO'].filter(m => cap(m === 'VOICE' ? 'talk' : 'video') && !(m === 'VIDEO' && d.config.module === 'video' && d.config.mode !== 'normal')) : []
    return { deviceId: v.deviceId, name: v.name, deviceCode: v.deviceCode, type: v.type, personId: person?.personId || null, personName: person?.name || '当前领用关系未知或无明确人员', communication: v.communication.state, modes, reason: modes.length ? '仅合成会话，不建立真实连接；离线/过期状态需核实' : v.type === 'BELT' ? '紧急电话仅需求声明，号码与厂家协议未接入' : '型号、装配、隐私或协议条件未确认，不能本地会话就绪' }
  })
}
function object(d, table, field, id, siteId) {
  const item = d.entities[table].find(i => i[field] === id && i.siteId === siteId)
  if (!item) throw failure(404, '来源对象不存在或不可见')
  return item
}
export function queryDispatch(d, role, q = {}) {
  scope(d, role, q.siteId); source(d, 'dispatch')
  const allowed = ['siteId', 'keyword', 'personId', 'deviceId', 'workId', 'eventId', 'pageNum', 'pageSize']
  if (Object.entries(q).some(([k, v]) => v != null && v !== '' && !allowed.includes(k))) throw failure(400, '不支持的调度筛选')
  const pageNum = Number(q.pageNum || 1), pageSize = Number(q.pageSize || 20)
  if (!Number.isSafeInteger(pageNum) || pageNum < 1 || pageNum > 2147483647 || !Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > 100 || q.keyword && (typeof q.keyword !== 'string' || q.keyword.length > 100)) throw failure(400, '分页或关键词无效')
  source(d, 'equipment')
  const x = dispatchData(d), all = contacts(d, q.siteId)
  let selected = []
  if (q.personId) { source(d, 'people'); object(d, 'people', 'personId', q.personId, q.siteId); selected = all.filter(c => c.personId === q.personId) }
  if (q.workId) { source(d, 'works'); object(d, 'works', 'workId', q.workId, q.siteId); const m = d.relations.monitoring.find(m => m.workId === q.workId); selected = all.filter(c => m?.personIds.includes(c.personId)) }
  if (q.deviceId) selected = [all.find(c => c.deviceId === object(d, 'devices', 'deviceId', q.deviceId, q.siteId).deviceId)]
  if (q.eventId) { source(d, 'events'); const e = object(d, 'events', 'eventId', q.eventId, q.siteId); selected = all.filter(c => c.deviceId === e.deviceId) }
  const rows = all.filter(c => !q.keyword || [c.name, c.deviceCode, c.personName].join(' ').toLowerCase().includes(q.keyword.toLowerCase()))
  const sosState = d.config.module !== 'events' || d.config.mode === 'normal' ? 'AVAILABLE' : { forbidden: 'FORBIDDEN', failure: 'ERROR', 'not-integrated': 'NOT_INTEGRATED' }[d.config.mode]
  return { state: 'AVAILABLE', sosState, siteId: q.siteId, version: x.version, items: rows.slice((pageNum - 1) * pageSize, pageNum * pageSize), total: rows.length, pageNum, pageSize, suggested: selected, active: clone(x.sessions.find(s => s.state === 'ACTIVE' && s.siteId === q.siteId) || null), sessions: clone(x.sessions.filter(s => s.siteId === q.siteId)), groups: clone(x.groups.filter(s => s.siteId === q.siteId)), broadcasts: clone(x.broadcasts.filter(s => s.siteId === q.siteId)), sos: d.config.module === 'events' && d.config.mode !== 'normal' ? [] : clone(d.entities.events.filter(e => e.siteId === q.siteId && /SOS$/.test(e.deviceReport?.category || '')).map(e => ({ ...e, positionSnapshot: d.config.module === 'locations' && d.config.mode !== 'normal' ? null : d.relations.sosLocations?.[e.eventId] || null }))) }
}
export function dispatchCommand(d, role, action, q) {
  scope(d, role, q.siteId, true); source(d, 'dispatch')
  const x = dispatchData(d)
  if (!/^[\w-]{1,48}$/.test(q.operationId || '')) throw failure(400, '操作标识无效')
  const fingerprint = JSON.stringify({ action, ...q }), prior = x.operations.find(o => o.id === q.operationId)
  if (prior) { if (prior.role !== role || prior.fingerprint !== fingerprint) throw failure(409, '操作标识输入冲突'); return { ...clone(prior.result), replayed: true } }
  if (q.expectedVersion !== x.version) throw failure(409, '协同状态已变化，请刷新后重试')
  const now = new Date().toISOString(), id = 'dispatch-' + q.operationId
  const recipients = () => {
    source(d, 'equipment')
    if (!Array.isArray(q.deviceIds) || !q.deviceIds.length || q.deviceIds.length > 100 || new Set(q.deviceIds).size !== q.deviceIds.length) throw failure(400, '请选择1至100个不重复的有效对象')
    const all = contacts(d, q.siteId)
    return q.deviceIds.map(deviceId => { const c = all.find(c => c.deviceId === deviceId); if (!c) throw failure(404, '联系对象不可见'); return c })
  }
  let result = { changedEntities: ['dispatch', 'events', 'workbench'] }
  if (action === 'group') {
    if (typeof q.name !== 'string' || !q.name.trim() || q.name.length > 50) throw failure(400, '协助组名称需1至50字')
    x.groups.unshift({ id, siteId: q.siteId, name: q.name.trim(), deviceIds: recipients().map(c => c.deviceId), createdAt: now }); result.id = id
  } else if (action === 'start') {
    if (x.sessions.some(s => s.state === 'ACTIVE')) throw failure(409, '已有活动会话，请打开或明确结束后新建', 'ACTIVE_SESSION_EXISTS')
    if (!['VOICE', 'VIDEO'].includes(q.mode)) throw failure(400, '电话仅声明，号码和协议未接入')
    if (q.mode === 'VIDEO') source(d, 'video')
    const targets = recipients()
    if (targets.some(c => !c.modes.includes(q.mode))) throw failure(409, '所选对象能力未确认或隐私限制，不能本地会话就绪')
    if (q.eventId) { source(d, 'events'); object(d, 'events', 'eventId', q.eventId, q.siteId) }
    if (q.workId) { source(d, 'works'); object(d, 'works', 'workId', q.workId, q.siteId) }
    const s = { id, siteId: q.siteId, state: 'ACTIVE', mode: q.mode, kind: targets.length === 1 ? 'SINGLE' : 'GROUP', createdAt: now, endedAt: null, eventId: q.eventId || null, workId: q.workId || null, participants: targets.map(c => ({ ...c, state: 'RINGING' })), timeline: [{ time: now, title: '发起本地会话，未访问RTC或设备' }] }
    x.sessions.unshift(s); result.id = id
  } else if (action === 'participant' || action === 'end') {
    const s = x.sessions.find(s => s.id === q.sessionId && s.siteId === q.siteId)
    if (!s) throw failure(404, '会话不可见')
    if (s.state !== 'ACTIVE') throw failure(409, '会话已结束')
    if (action === 'end') closeActiveDispatch(d, '手动结束本地会话，事件仍按自身状态处理')
    else {
      const p = s.participants.find(p => p.deviceId === q.deviceId)
      if (!p) throw failure(404, '参与者不可见')
      const transitions = { RINGING: ['CONNECTED', 'REJECTED', 'TIMED_OUT', 'LEFT'], CONNECTED: ['LEFT'] }
      if (!transitions[p.state]?.includes(q.state)) throw failure(409, '参与者状态不可逆，请新建会话重试')
      p.state = q.state; s.timeline.unshift({ time: now, title: p.name + ' · ' + participantLabels[q.state] })
      if (s.participants.every(p => !['RINGING', 'CONNECTED'].includes(p.state))) closeActiveDispatch(d, '所有参与者已退出或未接通，本地会话结束')
    }
  } else if (action === 'broadcast') {
    if (typeof q.text !== 'string' || !q.text.trim() || [...q.text].length > 200) throw failure(400, '广播内容需1至200字')
    const targets = recipients()
    if (targets.some(c => !c.modes.includes('VOICE'))) throw failure(409, '所选对象本地语音能力不可用')
    x.broadcasts.unshift({ id, siteId: q.siteId, text: q.text.trim(), createdAt: now, recipients: targets.map(c => ({ deviceId: c.deviceId, name: c.name, state: 'PENDING', time: null })) }); result.id = id
  } else if (action === 'receipt') {
    const task = x.broadcasts.find(b => b.id === q.taskId && b.siteId === q.siteId), r = task?.recipients.find(r => r.deviceId === q.deviceId)
    if (!r) throw failure(404, '广播对象不可见')
    if (r.state !== 'PENDING' || !['SUCCESS', 'FAILED'].includes(q.state)) throw failure(409, '仅待回执对象可明确本地成功或失败')
    r.state = q.state; r.time = now
  } else if (action === 'sos') {
    source(d, 'events')
    const device = object(d, 'devices', 'deviceId', q.deviceId, q.siteId), eventId = 'sos-' + q.operationId
    const category = device.type + '_SOS'
    const location = d.entities.locations.find(l => l.siteId === q.siteId && l.deviceId === device.deviceId)
    d.relations.sosLocations ||= {}
    d.relations.sosLocations[eventId] = location ? clone(location.position) : null
    d.entities.events.unshift({ eventId, siteId: q.siteId, title: '本地SOS · ' + device.name, sourceSystem: 'FRONTEND_MOCK', sourceEventId: eventId, eventType: category, eventTypeName: '本地紧急求助', handlingStatus: 'UNHANDLED', deviceType: device.type, deviceName: device.name, handledBy: null, handledAt: null, handlingNote: null, deviceId: device.deviceId, deviceCode: device.deviceCode, occurredAt: now, receivedAt: now, sourceUpdatedAt: now, freshness: 'FRESH', person: missing('HISTORICAL_ATTRIBUTION_UNKNOWN'),  workId: null,  version: 1, deviceReport: { category, rawType: 'MOCK_SOS', rawLevel: null, source: 'MOCK_REQUIREMENT', model: device.model, description: '预置面板合成求助，不是设备上报；历史人员归属未知', recovery: 'UNKNOWN', localFeedback: '未发送设备指令', evidence: '纯本地，无厂家协议确认' } })
    d.relations.timeline.unshift({ id: eventId + '-fact', eventId, siteId: q.siteId, sequence: 1, title: '预置面板触发本地SOS；尚未创建协同会话', sourceTime: now, kind: 'MOCK_FACT', description: '不代表真实求助' })
    result.eventId = eventId
  } else throw failure(400, '未知协同操作')
  x.version++; result.version = x.version
  x.operations.push({ id: q.operationId, role, fingerprint, result: clone(result) })
  return result
}
