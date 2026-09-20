import { identities } from './seed.js'
import { projectDataset, equipmentDevice } from './assignment-model.js'
import { workSummary } from './work-model.js'
import { failure } from './errors.js'
import { inInterval } from '../utils/statistics.js'
import { validUtc } from '../utils/work-route.js'
import { phaseLabels } from '../utils/event-contract.js'
const unique = (rows, key) => [...new Map(rows.map(r => [r[key], r])).values()]
export function distinctEvents(rows) {
  const ids = new Set(), sources = new Set()
  return rows.filter(e => {
    const source = e.sourceSystem && e.sourceEventId ? JSON.stringify([e.siteId, e.sourceSystem, e.sourceEventId]) : null
    const duplicate = ids.has(e.eventId) || source && sources.has(source)
    ids.add(e.eventId); if (source) sources.add(source)
    return !duplicate
  })
}
export function buildStatistics(input, role, q, now = new Date().toISOString()) {
  const identity = identities.find(i => i.id === role)
  if (!identity) throw failure(401, '本地会话失效')
  if (!identity.sites.includes(q.siteId)) throw failure(403, '厂站不可见')
  if (Object.keys(q).some(k => !['siteId', 'from', 'to'].includes(k))) throw failure(400, '统计筛选不受支持')
  const from = q.from || new Date(Date.parse(input.meta.baseTime) - 7 * 86400000).toISOString()
  const to = q.to || new Date(Math.max(Date.parse(input.meta.baseTime), Date.parse(now)) + 86400000).toISOString()
  if (!validUtc(from) || !validUtc(to) || Date.parse(from) >= Date.parse(to)) throw failure(400, '请提供有效 UTC 区间 [from,to)')
  if (!!q.from !== !!q.to) throw failure(400, '起止时间必须同时提供')
  const d = projectDataset(input), site = d.entities.sites.find(s => s.siteId === q.siteId)
  const scoped = name => d.entities[name].filter(r => r.siteId === q.siteId)
  let timeZone = site.timeZone || 'UTC'
  try { new Intl.DateTimeFormat('en', { timeZone }).format() } catch { timeZone = 'UTC' }
  const people = unique(scoped('people'), 'personId'), devices = unique(scoped('devices'), 'deviceId').map(v => equipmentDevice(d, v))
  const works = unique(scoped('works'), 'workId').map(w => workSummary(d, w)), events = distinctEvents(scoped('events'))
  const materials = unique(scoped('materials'), 'id'), metrics = []
  const personRow = p => ({ id: p.personId, name: p.name, state: { ON_DUTY: '名册当班', OFF_DUTY: '非当班' }[p.duty.data?.state] || '未知', path: '/personnel/' + p.personId })
  const deviceRow = v => ({ id: v.deviceId, name: v.name, state: `${{ HELMET:'安全帽', BELT:'安全带', WATCH:'手表' }[v.type]} · ${v.model} · ${{ ASSIGNED:'已领用', UNASSIGNED:'未领用', UNKNOWN:'未知', CONFLICT:'冲突' }[v.assignmentState]}`, path: '/equipment/' + v.deviceId, time: v.communication?.sourceTime || null })
  const eventRow = e => ({ id: e.eventId, name: e.title, state: phaseLabels[e.phase] || '未知', time: e.occurredAt, path: '/alarms/' + e.eventId + '/verification' })
  const add = (id, label, module, tab, kind, rows, note) => {
    const mode = d.config.module === module ? d.config.mode : 'normal'
    const state = ({ failure: 'ERROR', forbidden: 'FORBIDDEN', 'not-integrated': 'NOT_INTEGRATED' })[mode] || 'AVAILABLE'
    metrics.push({ id, label, module, tab, kind, state, count: state === 'AVAILABLE' ? rows.length : null, rows: state === 'AVAILABLE' ? rows : [], note })
  }
  add('duty', '当班人数', 'people', 'people', 'snapshot', people.filter(p => p.duty.state === 'AVAILABLE' && p.duty.data.state === 'ON_DUTY').map(personRow), '当前名册按 personId 去重；不是在线人数，也不是历史出勤。')
  add('rosterUnknown', '名册状态未知', 'people', 'people', 'snapshot', people.filter(p => p.duty.state !== 'AVAILABLE' || !['ON_DUTY', 'OFF_DUTY'].includes(p.duty.data?.state)).map(personRow), '未知不计入当班人数。')
  for (const [state, label] of Object.entries({ ASSIGNED: '已领用装备', UNASSIGNED: '明确未领用', UNKNOWN: '领用关系未知', CONFLICT: '领用关系冲突' })) add('assignment-' + state, label, 'equipment', 'equipment', 'snapshot', devices.filter(v => v.assignmentState === state).map(deviceRow), '按 deviceId 去重；领用率分母只包含已领用和明确未领用，未知与冲突单列。')
  for (const type of ['HELMET', 'BELT', 'WATCH']) add('type-' + type, { HELMET: '安全帽', BELT: '安全带', WATCH: '手表' }[type], 'equipment', 'equipment', 'snapshot', devices.filter(v => v.type === type).map(deviceRow), '设备类型分布；带表合成公共能力不代表厂家协议。')
  for (const model of d.config.module === 'equipment' && d.config.mode !== 'normal' ? [] : [...new Set(devices.map(v => v.model || '型号未知'))]) add('model-' + model, model, 'equipment', 'equipment', 'snapshot', devices.filter(v => (v.model || '型号未知') === model).map(deviceRow), '型号按预置配置分组；文档选配声明不是实例装配证明。')
  for (const state of ['PRESENT', 'ABSENT', 'UNKNOWN']) add('video-' + state, { PRESENT: '视频装配已配置', ABSENT: '视频明确未装配', UNKNOWN: '视频装配待确认' }[state], 'video', 'equipment', 'snapshot', devices.filter(v => (v.profile?.capabilities.video?.installation || 'UNKNOWN') === state).map(deviceRow), '装配状态独立于在线和播放状态；不计算真实视频可用率。')
  for (const state of ['ONLINE', 'OFFLINE', 'UNKNOWN']) add('communication-' + state, { ONLINE:'通信在线', OFFLINE:'通信离线', UNKNOWN:'通信未知' }[state], 'equipment', 'equipment', 'snapshot', devices.filter(v => (v.communication?.state || 'UNKNOWN') === state).map(deviceRow), '仅来源通信状态，在线不代表视频可用或人员健康。')
  for (const state of ['FRESH', 'STALE', 'UNKNOWN']) add('freshness-' + state, { FRESH:'通信数据新鲜', STALE:'通信数据过期', UNKNOWN:'通信新鲜度未知' }[state], 'equipment', 'equipment', 'snapshot', devices.filter(v => (v.communication?.freshness || 'UNKNOWN') === state).map(deviceRow), '采用来源新鲜度；不自行设置阈值，过期不转换为离线。')
  for (const state of ['PENDING', 'ACTIVE', 'PAUSED', 'ENDED']) add('work-' + state, { PENDING: '监护待开始', ACTIVE: '监护中', PAUSED: '监护暂停', ENDED: '监护已结束' }[state], 'works', 'tasks', 'snapshot', works.filter(w => w.monitorState === state).map(w => ({ id: w.workId, name: w.name, state, path: '/supervision/' + w.workId })), '当前本地监护状态，不是工作票许可或历史工时。')
  const intervalEvents = events.filter(e => inInterval(e.occurredAt, from, to))
  add('occurred', '区间发生事件', 'events', 'events', 'history', intervalEvents.map(eventRow), '发生时间在 [from,to) 内；按平台 ID 与来源系统/事件 ID 去重，未知时间另列。')
  add('unknownTime', '发生时间未知', 'events', 'events', 'snapshot', events.filter(e => !validUtc(e.occurredAt)).map(eventRow), '全厂站未知时间，无法放入任一历史日期。')
  for (const phase of ['UNCLAIMED', 'PROCESSING', 'AWAITING_VERIFICATION', 'LOCAL_COMPLETED', 'UNKNOWN']) add('phase-' + phase, { UNCLAIMED: '待认领', PROCESSING: '处理中', AWAITING_VERIFICATION: '待现场核验', LOCAL_COMPLETED: '来源标记本地完成', UNKNOWN: '阶段未知' }[phase], 'events', 'events', 'snapshot', events.filter(e => e.phase === phase).map(eventRow), '当前跟进阶段；来源标记完成不代表本次预置有显式完成记录，也不是外部结案。')
  const completed = unique(d.relations.timeline.filter(t => t.siteId === q.siteId && t.action === 'complete' && inInterval(t.sourceTime, from, to)), 'eventId')
  add('completed', '区间显式完成跟进', 'events', 'events', 'history', completed.flatMap(t => { const e = events.find(e => e.eventId === t.eventId); return e ? [{ ...eventRow(e), time: t.sourceTime }] : [] }), '只计独立 complete 操作时间；草稿、提交、回执成功及种子完成快照不计入。')
  for (const [key, label] of [['capturedAt', '区间采集资料'], ['receivedAt', '区间接收资料']]) add(key, label, 'materials', 'comprehensive', 'history', materials.filter(m => inInterval(m[key], from, to)).map(m => ({ id: m.id, name: m.name, state: m.type, time: m[key], path: '/materials', selectedId: m.id })), `${key === 'capturedAt' ? '采集' : '接收'}时间独立统计；未知不补齐，不以当前绑定推断归属。`)
  add('captureUnknown', '采集时间未知资料', 'materials', 'comprehensive', 'snapshot', materials.filter(m => !validUtc(m.capturedAt)).map(m => ({ id: m.id, name: m.name, state: m.type, path: '/materials', selectedId: m.id })), '未知采集时间不等同接收时间。')
  const date = new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' })
  if (d.config.module === 'events' && d.config.mode !== 'normal') add('day-unavailable', '按日统计来源不可用', 'events', 'events', 'history', [], '恢复事件来源后查看，未返回日期分组。')
  else for (const day of [...new Set(intervalEvents.map(e => date.format(new Date(e.occurredAt))))].sort()) add('day-' + day, day, 'events', 'events', 'history', intervalEvents.filter(e => date.format(new Date(e.occurredAt)) === day).map(eventRow), '按厂站时区分日；仅显示有发生记录的日期，不补造未知日期。')
  const assigned = metrics.find(m => m.id === 'assignment-ASSIGNED'), unassigned = metrics.find(m => m.id === 'assignment-UNASSIGNED')
  const denominator = assigned.count === null ? null : assigned.count + unassigned.count
  return { siteId: q.siteId, siteName: site.name, source: 'MOCK', readAt: now, from, to, timeZone, metrics, assignmentRate: denominator ? assigned.count / denominator : null, assignmentDenominator: denominator }
}
