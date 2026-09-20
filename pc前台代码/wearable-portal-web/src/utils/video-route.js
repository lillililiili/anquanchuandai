import { safeDispatchReturn } from './dispatch-route.js'
import { safeWorkReturn } from './work-route.js'
import { personIdPattern } from './portal-route.js'
export const layouts = ['1+7', '2x4', '3x3']
export function videoQuery(raw = {}, detail = false) {
  const q = {}
  for (const k of detail ? ['siteId'] : ['siteId', 'selectedId', 'areaId', 'workId']) if (typeof raw[k] === 'string' && personIdPattern.test(raw[k])) q[k] = raw[k]
  if (!detail) {
    if (typeof raw.keyword === 'string' && raw.keyword.trim()) q.keyword = raw.keyword.trim().slice(0, 100)
    if (layouts.includes(raw.layout)) q.layout = raw.layout
    for (const [k, max] of [['pageNum', 2147483647], ['pageSize', 100]]) { const n = Number(raw[k]); if (Number.isInteger(n) && n > 0 && n <= max) q[k] = String(n) }
  }
  return q
}
export function safeVideoReturn(value, allowDetail = false) {
  if (typeof value !== 'string' || !value.startsWith('/') || value.startsWith('//') || value.includes('\\') || [...value].some(c => c.charCodeAt(0) < 32)) return '/video'
  try {
    const u = new URL(value, 'https://portal.invalid'), detail = /^\/video\/[A-Za-z0-9_-]{1,64}$/.test(u.pathname)
    if (!u.hash && /^\/dispatch(?:\/sos\/[\w-]+)?$/.test(u.pathname)) return safeDispatchReturn(value)
    if (!u.hash && /^\/supervision(?:\/[A-Za-z0-9_-]{1,64})?$/.test(u.pathname)) return safeWorkReturn(value, true)
    if (u.hash || (u.pathname !== '/video' && !(allowDetail && detail))) return '/video'
    const raw = Object.fromEntries(u.searchParams), q = videoQuery(raw, detail)
    if (detail && raw.returnTo) q.returnTo = safeVideoReturn(raw.returnTo)
    const search = new URLSearchParams(q).toString()
    return u.pathname + (search ? '?' + search : '')
  } catch { return '/video' }
}
