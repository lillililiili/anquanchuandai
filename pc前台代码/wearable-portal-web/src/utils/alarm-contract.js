import { requireValue, validateSection } from './portal-contract.js'
import { noEventSecrets, validateEventRefs, validateEventEvidence } from './event-contract.js'
export const alarmStatuses = { UNHANDLED: '未处理', HANDLED: '已处理', UNKNOWN: '未知' }
export const deviceTypes = { HELMET: '安全帽', BELT: '安全带', WATCH: '手表' }
export const alarmStatus = e => alarmStatuses[e?.handlingStatus] ? e.handlingStatus : 'UNKNOWN'
export const alarmLabel = e => alarmStatuses[alarmStatus(e)]
const utc = value => typeof value === 'string' && /^\d{4}-\d\d-\d\dT.*Z$/.test(value) && Number.isFinite(Date.parse(value))
export function validateAlarm(e, siteId, id) {
  noEventSecrets(e)
  requireValue(e && e.siteId === siteId && typeof e.eventId === 'string' && /^[\w-]{1,64}$/.test(e.eventId) && (!id || e.eventId === id), '告警标识或范围异常')
  requireValue(['UNHANDLED', 'HANDLED'].includes(e.handlingStatus) && Object.hasOwn(deviceTypes, e.deviceType) && typeof e.eventType === 'string' && typeof e.title === 'string' && Number.isSafeInteger(e.version) && e.version > 0, '告警类型或状态异常')
  validateEventRefs(e.person, siteId)
  for (const time of ['occurredAt', 'receivedAt', 'sourceUpdatedAt']) requireValue(e[time] == null || utc(e[time]), '告警时间异常')
  if (e.handlingStatus === 'HANDLED') requireValue(!!e.handledBy?.name && typeof e.handlingNote === 'string' && !!e.handlingNote.trim() && [...e.handlingNote.trim()].length <= 1000 && utc(e.handledAt), '告警处理记录不完整')
  else requireValue(e.handledBy == null && e.handledAt == null && e.handlingNote == null, '未处理告警不能包含处理记录')
  return e
}
export function validateAlarmPage(p, q) {
  requireValue(p && p.scope?.siteId === q.siteId && p.pageNum === Number(q.pageNum || 1) && p.pageSize === Number(q.pageSize || 20) && Array.isArray(p.items), '告警分页范围异常')
  requireValue(p.state === 'AVAILABLE' ? Number.isSafeInteger(p.total) && p.total >= p.items.length && p.items.length <= p.pageSize : p.state === 'NOT_INTEGRATED' && p.total === null && p.items.length === 0, '告警分页数据异常')
  p.items.forEach(e => validateAlarm(e, q.siteId))
  requireValue(new Set(p.items.map(e => e.eventId)).size === p.items.length, '告警标识重复')
  validateSection(p.filters.eventTypes)
  return p
}
export function validateAlarmSummary(s) {
  validateSection(s)
  if (s.state === 'AVAILABLE') requireValue(['UNHANDLED', 'HANDLED'].every(k => Number.isSafeInteger(s.data.counts[k]) && s.data.counts[k] >= 0) && s.data.total === s.data.counts.UNHANDLED + s.data.counts.HANDLED, '告警统计异常')
  return s
}
export function validateAlarmDetail(d, siteId, id) {
  if (d.state === 'NOT_INTEGRATED' && d.event === null) return d
  validateAlarm(d.event, siteId, id); validateSection(d.location); validateEventRefs(d.video, siteId)
  if (d.materials) validateEventEvidence(d.materials, siteId)
  return d
}
// Never infer device alarm handling from the legacy workflow phase.
export const legacyAlarm = e => ({ ...e, handlingStatus: 'UNKNOWN', handledBy: null, handledAt: null, handlingNote: null })
