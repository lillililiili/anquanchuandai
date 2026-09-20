export const personIdPattern = /^[A-Za-z0-9_-]{1,64}$/
export function personnelQuery(query = {}) {
  const result = {}
  for (const k of ['siteId', 'shiftId', 'teamId', 'selectedPersonId']) if (typeof query[k] === 'string' && personIdPattern.test(query[k])) result[k] = query[k]
  if (typeof query.keyword === 'string' && query.keyword.trim()) result.keyword = query.keyword.trim().slice(0, 100)
  if (['WORKING', 'IDLE', 'UNKNOWN'].includes(query.workState)) result.workState = query.workState
  for (const [k, max] of [['pageNum', 2147483647], ['pageSize', 100]]) {
    const n = Number(query[k])
    if (Number.isInteger(n) && n > 0 && n <= max) result[k] = String(n)
  }
  return result
}
export function safePersonnelReturn(value) {
  if (typeof value !== 'string' || !/^\/personnel(?:\?|$)/.test(value) || value.includes('\\') || [...value].some(c => c.charCodeAt(0) < 32)) return '/personnel'
  const url = new URL(value, 'https://portal.invalid')
  if (url.pathname !== '/personnel' || url.hash) return '/personnel'
  const q = new URLSearchParams(personnelQuery(Object.fromEntries(url.searchParams))).toString()
  return '/personnel' + (q ? '?' + q : '')
}
