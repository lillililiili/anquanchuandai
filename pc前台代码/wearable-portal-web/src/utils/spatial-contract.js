import { requireValue, validateSection, sectionStates } from './portal-contract.js'
import { personIdPattern, safePersonnelReturn } from './portal-route.js'
import { safeVideoReturn } from './video-route.js'
import { safeEventReturn } from './event-route.js'
import { safeWorkReturn } from './work-route.js'
import { safeEquipmentReturn } from './equipment-route.js'

export const spatialLabels = { PHOTO: '图片', VIDEO: '视频', AUDIO: '音频', ENABLED: '启用', DISABLED: '停用', UNKNOWN: '未知', CONFIRMED: '已确认', HELMET: '安全帽', BELT: '安全带', WATCH: '手表' }
export function utc(value) { return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T.*Z$/.test(value) && Number.isFinite(Date.parse(value)) }
export function reliablePosition(p) {
  return !!p && p.coordinateSystem === 'WGS84' && p.quality === 'VALID' && Number.isFinite(p.longitude) && Number.isFinite(p.latitude) && Math.abs(p.longitude) <= 180 && Math.abs(p.latitude) <= 85.0511287798
}
export function positionReason(p) {
  if (!p) return '位置数据待接入'
  if (p.coordinateSystem !== 'WGS84') return '坐标系未知或暂不支持，未落点'
  if (!reliablePosition(p)) return '无可靠位置，待核验'
  if (p.freshness === 'STALE') return '位置数据已过期，请现场核验'
  return utc(p.sourceTime) ? '最近位置快照（非实时连接）' : '源时间未知，时效待确认'
}
export function s2Query(kind, query = {}) {
  const q = {}
  const keys = ['siteId', ...(kind === 'live' ? ['selectedId'] : kind === 'tracks' ? ['deviceId', 'personId'] : kind === 'fences' ? ['selectedId'] : ['deviceId', 'personId', 'selectedId'])]
  for (const k of keys) if (typeof query[k] === 'string' && personIdPattern.test(query[k])) q[k] = query[k]
  if (kind !== 'tracks') {
    if (typeof query.keyword === 'string' && query.keyword.trim()) q.keyword = query.keyword.trim().slice(0, 100)
    for (const [k, max] of [['pageNum', 2147483647], ['pageSize', 100]]) { const n = Number(query[k]); if (Number.isInteger(n) && n > 0 && n <= max) q[k] = String(n) }
  }
  if (['tracks', 'materials'].includes(kind) && utc(query.from) && utc(query.to) && Date.parse(query.from) < Date.parse(query.to)) { q.from = query.from; q.to = query.to }
  if (kind === 'materials' && ['PHOTO', 'VIDEO', 'AUDIO'].includes(query.type)) q.type = query.type
  if (kind === 'fences' && ['ENABLED', 'DISABLED', 'UNKNOWN'].includes(query.status)) q.status = query.status
  return q
}
export function safeWorkspaceReturn(value) {
  if (typeof value !== 'string' || !value.startsWith('/') || value.startsWith('//') || value.includes('\\') || [...value].some(c => c.charCodeAt(0) < 32)) return '/personnel'
  try {
    const u = new URL(value, 'https://portal.invalid')
    if (u.hash) return '/personnel'
    if (u.pathname === '/supervision' || /^\/supervision\/[A-Za-z0-9_-]{1,64}$/.test(u.pathname)) return safeWorkReturn(value, true)
    if (u.pathname === '/equipment' || /^\/equipment\/[A-Za-z0-9_-]{1,64}$/.test(u.pathname)) return safeEquipmentReturn(value, true)
    if (u.pathname === '/alarms' || /^\/alarms\/[A-Za-z0-9_-]{1,64}\/verification$/.test(u.pathname)) return safeEventReturn(value, true)
    if (u.pathname === '/video' || /^\/video\/[A-Za-z0-9_-]{1,64}$/.test(u.pathname)) return safeVideoReturn(value, true)
    if (u.pathname === '/personnel') return safePersonnelReturn(value)
    const raw = Object.fromEntries(u.searchParams)
    if (['/overview', '/statistics', '/supervision', '/dispatch'].includes(u.pathname)) {
      const query = typeof raw.siteId === 'string' && personIdPattern.test(raw.siteId) ? '?' + new URLSearchParams({ siteId: raw.siteId }) : ''
      return u.pathname + query
    }
    if (u.pathname === '/location') {
      const tab = ['live', 'tracks', 'fences'].includes(raw.tab) ? raw.tab : 'live'
      return '/location?' + new URLSearchParams({ tab, ...s2Query(tab, raw) })
    }
    if (u.pathname === '/materials') { const q = new URLSearchParams(s2Query('materials', raw)).toString(); return '/materials' + (q ? '?' + q : '') }
  } catch { /* fail closed */ }
  return '/personnel'
}
export function validateItem(item, siteId, id) {
  requireValue(item && typeof item.id === 'string' && personIdPattern.test(item.id) && item.siteId === siteId && typeof item.name === 'string' && (!id || item.id === id), '数据与请求对象或厂站不一致')
  return item
}
function time(value) { requireValue(value == null || utc(value), '数据时间格式异常') }
function position(p) {
  if (p == null) return
  requireValue(typeof p === 'object' && ['FRESH', 'STALE', 'UNKNOWN', 'NOT_APPLICABLE'].includes(p.freshness))
  time(p.sourceTime); time(p.receivedAt)
  requireValue(!['FRESH', 'STALE'].includes(p.freshness) || utc(p.sourceTime), '无源时间不能判定时效')
}
export function validateS2Item(item, kind, siteId, id) {
  validateItem(item, siteId, id)
  if (kind === 'devices') requireValue(['HELMET', 'BELT', 'WATCH'].includes(item.type))
  if (kind === 'locations') {
    requireValue(typeof item.deviceId === 'string' && personIdPattern.test(item.deviceId))
    position(item.position)
    requireValue(!item.personId || item.attribution === 'CONFIRMED', '人员归属缺少证据')
  }
  if (kind === 'fences') {
    requireValue(['ENABLED', 'DISABLED', 'UNKNOWN'].includes(item.status) && Array.isArray(item.ring)); time(item.sourceTime); time(item.effectiveAt)
  }
  if (kind === 'materials') {
    requireValue(['PHOTO', 'VIDEO', 'AUDIO'].includes(item.type)); time(item.capturedAt); time(item.receivedAt)
    requireValue(!item.personId || ['CONFIRMED', 'MANUAL_MOCK'].includes(item.attribution), '历史人员归属缺少证据')
    requireValue(!item.workId || ['CONFIRMED', 'MANUAL_MOCK'].includes(item.workAttribution), '作业关联缺少证据')
    requireValue(!item.eventId || ['CONFIRMED', 'MANUAL_MOCK'].includes(item.eventAttribution), '事件关联缺少证据')
    requireValue(!Object.keys(item).some(k => /url|path|token/i.test(k)), '资料接口不得返回文件地址或访问凭据')
  }
  return item
}
export function validateS2Page(data, kind, params) {
  requireValue(data && sectionStates.includes(data.state) && Array.isArray(data.items) && data.scope?.siteId === params.siteId)
  requireValue(data.pageNum === Number(params.pageNum || 1) && data.pageSize === Number(params.pageSize || 20))
  requireValue(data.state === 'AVAILABLE' ? Number.isSafeInteger(data.total) && data.total >= data.items.length : data.total === null && !data.items.length && !!data.reasonCode)
  requireValue(data.items.length <= data.pageSize && new Set(data.items.map(i => i.id)).size === data.items.length)
  data.items.forEach(i => validateS2Item(i, kind, params.siteId))
  return data
}
export function validateTrack(section, params) {
  validateSection(section)
  if (section.state !== 'AVAILABLE') return section
  const t = section.data
  validateItem(t, params.siteId)
  requireValue(t.deviceId === params.deviceId && t.from === params.from && t.to === params.to && Array.isArray(t.segments) && Array.isArray(t.gaps))
  requireValue(typeof t.complete === 'boolean' && (t.complete || typeof t.incompleteReason === 'string'))
  requireValue(!t.personId || t.attribution === 'CONFIRMED')
  requireValue(!params.personId || t.personId === params.personId, '轨迹历史归属不一致')
  let previous = -Infinity, count = 0
  for (const s of t.segments) {
    requireValue(s && personIdPattern.test(s.segmentId) && ['CONFIRMED', 'UNKNOWN'].includes(s.continuity) && Array.isArray(s.points))
    for (const p of s.points) {
      requireValue(!!p); position(p); count++
      if (p.sourceTime) { const at = Date.parse(p.sourceTime); requireValue(at >= previous && at >= Date.parse(t.from) && at <= Date.parse(t.to)); previous = at }
    }
  }
  requireValue(count <= 10000)
  for (const g of t.gaps) requireValue(utc(g.from) && utc(g.to) && Date.parse(g.from) < Date.parse(g.to) && Date.parse(g.from) >= Date.parse(t.from) && Date.parse(g.to) <= Date.parse(t.to))
  return section
}
// Break at every invalid point, unknown timestamp or declared gap; never bridge segments.
export function trackGeometry(track) {
  const points = [], lines = []
  for (const s of track?.segments || []) {
    let run = []
    const flush = () => { if (run.length > 1 && s.continuity === 'CONFIRMED') lines.push(run); run = [] }
    for (const p of s.points) {
      if (!reliablePosition(p)) { flush(); continue }
      points.push(p)
      if (!utc(p.sourceTime)) { flush(); continue }
      const prev = run.at(-1)
      if (prev && track.gaps.some(g => Date.parse(g.from) < Date.parse(p.sourceTime) && Date.parse(g.to) > Date.parse(prev.sourceTime))) flush()
      run.push(p)
    }
    flush()
  }
  return { points, lines }
}
export function validRing(fence) {
  const ring = fence?.ring
  return fence?.coordinateSystem === 'WGS84' && Array.isArray(ring) && ring.length >= 4 && ring.every(p => Array.isArray(p) && p.length === 2 && reliablePosition({ longitude: p[0], latitude: p[1], coordinateSystem: 'WGS84', quality: 'VALID' })) && ring[0][0] === ring.at(-1)[0] && ring[0][1] === ring.at(-1)[1]
}
