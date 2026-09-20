import { personIdPattern } from './portal-route.js'
export const monitorLabels = { PENDING: '待开始', ACTIVE: '监护中', PAUSED: '暂停', ENDED: '已结束' }
export const sourceLabels = { PLANNED: '来源计划中', EXECUTING: '来源执行中', UNKNOWN: '来源状态未知' }
export function workQuery(raw = {}) {
  const q = {}
  for (const k of ['siteId', 'selectedId', 'areaId']) if (typeof raw[k] === 'string' && personIdPattern.test(raw[k])) q[k] = raw[k]
  if (typeof raw.keyword === 'string' && raw.keyword.trim()) q.keyword = raw.keyword.trim().slice(0, 100)
  if (Object.hasOwn(monitorLabels, raw.state)) q.state = raw.state
  if (Object.hasOwn(sourceLabels, raw.sourceStatus)) q.sourceStatus = raw.sourceStatus
  for (const [k, max] of [['pageNum', 2147483647], ['pageSize', 100]]) if (/^\d+$/.test(String(raw[k])) && Number(raw[k]) > 0 && Number(raw[k]) <= max) q[k] = String(Number(raw[k]))
  if (validUtc(raw.from) && validUtc(raw.to) && Date.parse(raw.from) < Date.parse(raw.to)) { q.from = raw.from; q.to = raw.to }
  return q
}
export function validUtc(v) { return typeof v === 'string' && /^\d{4}-\d\d-\d\dT.*Z$/.test(v) && Number.isFinite(Date.parse(v)) }
export function safeWorkReturn(value, detail = false) {
  if (typeof value !== 'string' || !value.startsWith('/') || value.startsWith('//') || value.includes('\\') || [...value].some(c => c.charCodeAt(0) < 32)) return '/supervision'
  try {
    const u = new URL(value, 'https://portal.invalid')
    if (u.hash || u.pathname !== '/supervision' && !(detail && /^\/supervision\/[A-Za-z0-9_-]{1,64}$/.test(u.pathname))) return '/supervision'
    const raw = Object.fromEntries(u.searchParams), q = workQuery(raw)
    if (u.pathname !== '/supervision' && raw.returnTo) q.returnTo = safeWorkReturn(raw.returnTo)
    const search = new URLSearchParams(q).toString()
    return u.pathname + (search ? '?' + search : '')
  } catch { return '/supervision' }
}
