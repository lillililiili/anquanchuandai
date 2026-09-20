import { personIdPattern } from './portal-route.js'
export function dispatchQuery(q = {}) {
  const result = {}
  for (const key of ['siteId', 'personId', 'deviceId', 'workId', 'eventId']) if (typeof q[key] === 'string' && personIdPattern.test(q[key])) result[key] = q[key]
  if (typeof q.keyword === 'string' && q.keyword.length <= 100) result.keyword = q.keyword
  for (const key of ['pageNum', 'pageSize']) if (/^[1-9]\d*$/.test(q[key] || '') && Number(q[key]) <= (key === 'pageSize' ? 100 : 2147483647)) result[key] = String(q[key])
  return result
}
export function safeDispatchReturn(value) {
  if (typeof value !== 'string' || !/^\/dispatch(?:\?|$|\/sos\/)/.test(value) || value.includes('\\') || [...value].some(c => c.charCodeAt(0) < 32)) return '/dispatch'
  try {
    const u = new URL(value, 'https://portal.invalid')
    if (u.origin !== 'https://portal.invalid' || u.hash || u.pathname !== '/dispatch' && !/^\/dispatch\/sos\/[\w-]+$/.test(u.pathname)) return '/dispatch'
    const query = new URLSearchParams(dispatchQuery(Object.fromEntries(u.searchParams))).toString()
    return u.pathname + (query ? '?' + query : '')
  } catch { return '/dispatch' }
}
