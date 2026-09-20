import { requireValue, validateSection } from './portal-contract.js'
import { personIdPattern } from './portal-route.js'
import { phases, eventUtc } from './event-route.js'
export const phaseLabels = { UNCLAIMED: '待认领', PROCESSING: '处理中', AWAITING_VERIFICATION: '待现场核验', LOCAL_COMPLETED: '已完成本地跟进', UNKNOWN: '未知' }
export const deliveryLabels = { NOT_CONFIGURED: '未配置', PENDING: '待发送', SENDING: '发送中', SUCCESS: '成功', FAILED: '失败', UNKNOWN: '未知' }
export const verificationLabels = { DRAFT: '草稿', SUBMITTED: '已提交', UNKNOWN: '未知' }
export const conclusionLabels = { COMMUNICATION_ISSUE: '设备通信异常', ACTION_REQUIRED: '需现场处理', UNCONFIRMED: '无法确认' }
export function eventTime(v) { return eventUtc(v) ? v.replace('T', ' ').replace(/\.\d+Z$/, ' UTC').replace('Z', ' UTC') : '时间未知' }
export function noEventSecrets(value) { if (value && typeof value === 'object') for (const [k, v] of Object.entries(value)) { requireValue(!/url|path|token|credential|secret|rtc/i.test(k), '事件元数据不得包含地址或访问凭据'); noEventSecrets(v) } }
function id(v) { requireValue(typeof v === 'string' && personIdPattern.test(v)) }
function time(v) { requireValue(v == null || eventUtc(v), '事件时间格式异常') }
function evidenceProof(r, site) { id(r.id); requireValue(r.siteId === site && r.attribution === 'CONFIRMED' && typeof r.evidenceId === 'string' && !!r.evidenceId.trim()) }
export function validateEventRefs(s, site) { validateSection(s); if (s.state === 'AVAILABLE') { requireValue(Array.isArray(s.data)); for (const r of s.data) { evidenceProof(r, site); requireValue(typeof r.name === 'string' && ['UNKNOWN', 'HISTORICAL', 'CURRENT'].includes(r.snapshotKind)); time(r.sourceTime) } } return s }
export function validateEventFact(f, site, expected) {
  noEventSecrets(f); requireValue(!!f); id(f.eventId)
  requireValue(f.siteId === site && (!expected || expected === f.eventId) && typeof f.title === 'string' && typeof f.sourceSystem === 'string' && !!f.sourceSystem && typeof f.sourceEventId === 'string' && !!f.sourceEventId && phases.includes(f.phase))
  id(f.eventType); if (f.deviceId != null) id(f.deviceId)
  for (const k of ['occurredAt', 'receivedAt', 'sourceUpdatedAt']) time(f[k])
  requireValue(['FRESH', 'STALE', 'UNKNOWN', 'NOT_APPLICABLE'].includes(f.freshness) && (!['FRESH', 'STALE'].includes(f.freshness) || eventUtc(f.sourceUpdatedAt)))
  validateEventRefs(f.person, site); return f
}
export function uniqueEventOrigins(items) {
  const byId = new Map(), byOrigin = new Map()
  for (const f of items) {
    const origin = JSON.stringify([f.sourceSystem, f.sourceEventId]), prev = byId.get(f.eventId)
    requireValue(!byOrigin.has(origin) || byOrigin.get(origin) === f.eventId, '同一来源事件映射到多个平台标识')
    requireValue(!prev || prev.sourceSystem === f.sourceSystem && prev.sourceEventId === f.sourceEventId && prev.phase === f.phase, '事件身份冲突')
    byOrigin.set(origin, f.eventId); byId.set(f.eventId, f)
  }
  return [...byId.values()]
}
function page(p, q, eventId) {
  noEventSecrets(p); requireValue(p && ['AVAILABLE', 'NOT_INTEGRATED', 'UNAVAILABLE', 'FORBIDDEN'].includes(p.state) && Array.isArray(p.items) && p.scope?.siteId === q.siteId && (!eventId || p.scope.eventId === eventId))
  requireValue(p.pageNum === Number(q.pageNum || 1) && p.pageSize === Number(q.pageSize || 20) && p.items.length <= p.pageSize)
  requireValue(p.state === 'AVAILABLE' ? Number.isSafeInteger(p.total) && p.total >= p.items.length : p.total === null && !p.items.length && !!p.reasonCode)
}
export function validateEventPage(p, q) {
  page(p, q); p.items.forEach(f => validateEventFact(f, q.siteId)); requireValue(uniqueEventOrigins(p.items).length === p.items.length)
  requireValue(p.filters && ['keyword', 'timeRange', 'phase'].every(k => typeof p.filters[k] === 'boolean')); validateSection(p.filters.eventTypes)
  if (p.filters.eventTypes.state === 'AVAILABLE') { requireValue(Array.isArray(p.filters.eventTypes.data)); for (const o of p.filters.eventTypes.data) { id(o.value); requireValue(typeof o.label === 'string') } }
  return p
}
export function validateEventSummary(s) { noEventSecrets(s); validateSection(s); if (s.state === 'AVAILABLE') { requireValue(Number.isSafeInteger(s.data.total) && s.data.total >= 0 && phases.every(p => Number.isSafeInteger(s.data.counts?.[p]) && s.data.counts[p] >= 0) && phases.reduce((n, p) => n + s.data.counts[p], 0) === s.data.total); time(s.data.sourceTime) } return s }
export function validateEventEvidence(s, site) { validateSection(s); if (s.state === 'AVAILABLE') { requireValue(Array.isArray(s.data)); for (const e of s.data) { if (e.attribution === 'MANUAL_MOCK') { id(e.id); requireValue(e.siteId === site && e.associationSource === 'MANUAL_MOCK' && !!e.evidenceId) } else evidenceProof(e, site); requireValue(typeof e.name === 'string'); time(e.capturedAt); time(e.receivedAt) } } return s }
export function validateEventDetail(d, site, expected) {
  noEventSecrets(d); validateEventFact(d?.event, site, expected)
  for (const k of ['owner', 'equipment', 'works', 'video']) validateEventRefs(d[k], site)
  validateEventEvidence(d.materials, site); validateSection(d.location)
  if (d.location.state === 'AVAILABLE') { const p = d.location.data; evidenceProof(p, site); time(p.sourceTime); time(p.receivedAt); requireValue(!['FRESH', 'STALE'].includes(p.freshness) || eventUtc(p.sourceTime)) }
  for (const k of ['summaryDelivery', 'verificationDelivery']) { validateSection(d[k]); if (d[k].state === 'AVAILABLE') { requireValue(Object.hasOwn(deliveryLabels, d[k].data.state)); time(d[k].data.sourceTime) } }
  validateSection(d.originalSystem); if (d.originalSystem.state === 'AVAILABLE') time(d.originalSystem.data.sourceTime)
  return d
}
export function validateEventRecords(p, q, eventId, kind) {
  page(p, q, eventId); const ids = new Set()
  for (const r of p.items) { id(r.id); requireValue(!ids.has(r.id) && r.siteId === q.siteId && r.eventId === eventId); ids.add(r.id); time(r.sourceTime)
    if (kind === 'timeline') requireValue(typeof r.title === 'string' && typeof r.kind === 'string' && Number.isSafeInteger(r.sequence) && r.sequence >= 0)
    else { requireValue(Object.hasOwn(verificationLabels, r.state)); time(r.submittedAt); requireValue(r.state !== 'DRAFT' || r.submittedAt == null); validateEventEvidence(r.evidence, q.siteId) }
  } return p
}
