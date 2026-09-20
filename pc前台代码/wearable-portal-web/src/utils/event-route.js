import { safeDispatchReturn } from './dispatch-route.js'
import { safeWorkReturn } from './work-route.js'
import { personIdPattern } from './portal-route.js'
export const phases = ['UNCLAIMED', 'PROCESSING', 'AWAITING_VERIFICATION', 'LOCAL_COMPLETED', 'UNKNOWN']
export const eventUtc = v => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}T.*Z$/.test(v) && Number.isFinite(Date.parse(v))
export function eventQuery(raw = {}, detail = false) {
  const q = {}
  for (const k of detail ? ['siteId'] : ['siteId', 'selectedId', 'eventType']) if (typeof raw[k] === 'string' && personIdPattern.test(raw[k])) q[k] = raw[k]
  if (!detail) {
    if (raw.mine === 'true') q.mine = 'true'
    if (typeof raw.keyword === 'string' && raw.keyword.trim()) q.keyword = raw.keyword.trim().slice(0, 100)
    if (phases.includes(raw.phase)) q.phase = raw.phase
    if (eventUtc(raw.from) && eventUtc(raw.to) && Date.parse(raw.from) < Date.parse(raw.to)) { q.from = raw.from; q.to = raw.to }
    for (const [k, max] of [['pageNum', 2147483647], ['pageSize', 100]]) { const n = Number(raw[k]); if (Number.isInteger(n) && n > 0 && n <= max) q[k] = String(n) }
  }
  return q
}
export function safeEventReturn(value, allowDetail = false) {
  if (typeof value !== 'string' || !value.startsWith('/') || value.startsWith('//') || value.includes('\\') || [...value].some(c => c.charCodeAt(0) < 32)) return '/alarms'
  try {
    const u = new URL(value, 'https://portal.invalid'), detail = /^\/alarms\/[A-Za-z0-9_-]{1,64}\/verification$/.test(u.pathname)
    if (!u.hash && /^\/dispatch(?:\/sos\/[\w-]+)?$/.test(u.pathname)) return safeDispatchReturn(value)
    if (!u.hash && /^\/supervision(?:\/[A-Za-z0-9_-]{1,64})?$/.test(u.pathname)) return safeWorkReturn(value, true)
    if (u.hash || u.pathname !== '/alarms' && !(allowDetail && detail)) return '/alarms'
    const raw = Object.fromEntries(u.searchParams), q = eventQuery(raw, detail)
    if (detail && raw.returnTo) q.returnTo = safeEventReturn(raw.returnTo)
    const search = new URLSearchParams(q).toString(); return u.pathname + (search ? '?' + search : '')
  } catch { return '/alarms' }
}
export function eventTimeZone(zone) { try { new Intl.DateTimeFormat('en', { timeZone: zone || 'UTC' }).format(); return zone || 'UTC' } catch { return 'UTC' } }
function parts(at, zone) {
  const values = Object.fromEntries(new Intl.DateTimeFormat('en-GB', { timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' }).formatToParts(new Date(at)).map(p => [p.type, p.value]))
  return `${values.year}-${values.month}-${values.day}T${values.hour}:${values.minute}:${values.second}`
}
export function eventLocalTime(utc, zone) { return eventUtc(utc) ? parts(Date.parse(utc), eventTimeZone(zone)) : '' }
// Search possible zone offsets, then round-trip. DST gaps/folds are rejected rather than guessed.
export function eventLocalToUtc(local, zone) {
  if (!local) return null
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/.test(local)) throw new Error('请输入有效日期时间')
  const normalized = local.length === 16 ? local + ':00' : local, base = Date.parse(normalized + 'Z')
  if (!Number.isFinite(base) || new Date(base).toISOString().slice(0, 19) !== normalized) throw new Error('请输入有效日期时间')
  const tz = eventTimeZone(zone), offsets = new Set(), matches = new Set()
  for (let h = -36; h <= 36; h += 6) { const at = base + h * 3600000; offsets.add(Date.parse(parts(at, tz) + 'Z') - at) }
  for (const offset of offsets) { const at = base - offset; if (parts(at, tz) === normalized) matches.add(at) }
  if (matches.size !== 1) throw new Error('该厂站时区的此时间不存在或存在夏令时歧义，请选择明确的时间')
  return new Date([...matches][0]).toISOString()
}
