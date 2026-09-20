import { requireValue, validateSection } from './portal-contract.js'
import { personIdPattern } from './portal-route.js'
const utc = v => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}T.*Z$/.test(v) && Number.isFinite(Date.parse(v))
export const videoLabels = { UNKNOWN: '未知', ONLINE: '通信在线', OFFLINE: '通信离线', NOT_INTEGRATED: '未接入', SUPPORTED: '支持', UNSUPPORTED: '不支持', VERIFIED: '已验证', UNVERIFIED: '待验证', NOT_STARTED: '来源报告未开启', REPORTED_ACTIVE: '来源报告有流（非播放证明）', INTERRUPTED: '来源报告中断', HELMET: '安全帽', BELT: '安全带', WATCH: '手表' }
function time(v) { requireValue(v == null || utc(v), '视频时间格式异常') }
function secrets(value) {
  if (!value || typeof value !== 'object') return
  for (const [k, v] of Object.entries(value)) { requireValue(!/url|token|credential|secret|path|rtc/i.test(k), '视频元数据不能包含媒体地址或凭据'); secrets(v) }
}
export function uniqueDevices(items) { return [...new Map(items.map(d => [d.deviceId, d])).values()] }
export function validateVideoDevice(d, site, id) {
  secrets(d)
  requireValue(d && typeof d.deviceId === 'string' && personIdPattern.test(d.deviceId) && d.siteId === site && (!id || d.deviceId === id) && typeof d.name === 'string')
  requireValue(['HELMET', 'BELT', 'WATCH'].includes(d.type) && ['ONLINE', 'OFFLINE', 'UNKNOWN', 'NOT_INTEGRATED'].includes(d.communication?.state))
  requireValue(['SUPPORTED', 'UNSUPPORTED', 'UNKNOWN'].includes(d.video?.state) && ['VERIFIED', 'UNVERIFIED'].includes(d.video.verification))
  requireValue(['UNKNOWN', 'NOT_STARTED', 'REPORTED_ACTIVE', 'INTERRUPTED'].includes(d.streamState) && ['FRESH', 'STALE', 'UNKNOWN', 'NOT_APPLICABLE'].includes(d.freshness))
  time(d.sourceTime); time(d.communication.sourceTime); time(d.communication.receivedAt)
  requireValue(!['FRESH', 'STALE'].includes(d.freshness) || utc(d.sourceTime))
  requireValue(d.communication.sourceKind !== 'LEGACY_SNAPSHOT' || d.communication.state === 'UNKNOWN')
  requireValue(typeof d.unavailableReason === 'string')
  return d
}
export function validateVideoPage(p, q) {
  secrets(p)
  requireValue(p && ['AVAILABLE', 'NOT_INTEGRATED', 'FORBIDDEN', 'UNAVAILABLE'].includes(p.state) && p.scope?.siteId === q.siteId && Array.isArray(p.items))
  requireValue(p.pageNum === Number(q.pageNum || 1) && p.pageSize === Number(q.pageSize || 8) && p.items.length <= p.pageSize)
  requireValue(p.state === 'AVAILABLE' ? Number.isSafeInteger(p.total) && p.total >= p.items.length : p.total === null && p.items.length === 0 && !!p.reasonCode)
  p.items.forEach(d => validateVideoDevice(d, q.siteId))
  requireValue(uniqueDevices(p.items).length === p.items.length)
  for (const k of ['areas', 'works']) { const s = validateSection(p.filters?.[k]); if (s.state === 'AVAILABLE') requireValue(Array.isArray(s.data) && s.data.every(o => typeof o.id === 'string' && personIdPattern.test(o.id) && typeof o.name === 'string')) }
  validateSection(p.statistics)
  if (p.statistics.state === 'AVAILABLE') { const s = p.statistics.data; requireValue(['devices', 'available', 'interrupted', 'notStarted'].every(k => Number.isSafeInteger(s[k]) && s[k] >= 0) && s.devices === p.total && s.available + s.interrupted + s.notStarted <= s.devices); time(s.sourceTime) }
  return p
}
export function validateVideoDetail(d, site, id) {
  secrets(d); validateVideoDevice(d?.device, site, id)
  for (const key of ['person', 'equipment', 'works', 'location', 'events', 'materials']) {
    const s = validateSection(d[key])
    if (s.state === 'AVAILABLE') {
      requireValue(Array.isArray(s.data))
      for (const r of s.data) { requireValue(typeof r.id === 'string' && personIdPattern.test(r.id) && r.siteId === site && typeof r.name === 'string' && r.attribution === 'CONFIRMED' && !!r.evidenceId); time(r.sourceTime); time(r.receivedAt) }
    }
  }
  return d
}
export function wallSlots(items, selectedId, layout) {
  const rows = uniqueDevices(items), main = selectedId ? rows.find(d => d.deviceId === selectedId) : rows[0]
  const ordered = main ? [main, ...rows.filter(d => d !== main)] : []
  return Array.from({ length: layout === '3x3' ? 9 : 8 }, (_, i) => ordered[i] || null)
}
