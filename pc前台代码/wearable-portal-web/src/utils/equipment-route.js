import { personIdPattern } from './portal-route.js'
export const equipmentTypes = { HELMET: '安全帽', BELT: '安全带', WATCH: '手表' }
export const assignmentLabels = { ASSIGNED: '已领用', UNASSIGNED: '未领用', UNKNOWN: '关系未知', CONFLICT: '关系冲突' }
export function equipmentQuery(raw = {}, detail = false) {
  const q = {}
  if (typeof raw.siteId === 'string' && personIdPattern.test(raw.siteId)) q.siteId = raw.siteId
  if (!detail) {
    if (typeof raw.keyword === 'string' && raw.keyword.trim()) q.keyword = raw.keyword.trim().slice(0, 100)
    if (Object.hasOwn(equipmentTypes, raw.type)) q.type = raw.type
    if (Object.hasOwn(assignmentLabels, raw.assignmentState)) q.assignmentState = raw.assignmentState
    for (const [key, max] of [['pageNum', 2147483647], ['pageSize', 100]]) { const n = Number(raw[key]); if (Number.isInteger(n) && n > 0 && n <= max) q[key] = String(n) }
  }
  return q
}
export function safeEquipmentReturn(value, detail = false) {
  if (typeof value !== 'string' || !value.startsWith('/') || value.startsWith('//') || value.includes('\\') || [...value].some(c => c.charCodeAt(0) < 32)) return '/equipment'
  try {
    const u = new URL(value, 'https://portal.invalid'), isDetail = /^\/equipment\/[A-Za-z0-9_-]{1,64}$/.test(u.pathname)
    if (u.hash || u.pathname !== '/equipment' && !(detail && isDetail)) return '/equipment'
    const raw = Object.fromEntries(u.searchParams), q = equipmentQuery(raw, isDetail)
    if (isDetail && raw.returnTo) q.returnTo = safeEquipmentReturn(raw.returnTo)
    const search = new URLSearchParams(q).toString()
    return u.pathname + (search ? '?' + search : '')
  } catch { return '/equipment' }
}
