export function parseLocal(value) {
  const m = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2}))?)?$/.exec(value || '')
  if (!m) return null
  const [year, month, day, hour = 0, minute = 0, second = 0] = m.slice(1).map(n => n === undefined ? undefined : Number(n))
  const date = new Date(0); date.setFullYear(year, month - 1, day)
  return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day && hour < 24 && minute < 60 && second < 60 ? { year, month, day, hour, minute, second } : null
}
export const pad = n => String(n).padStart(2, '0')
export function localString(p, time = false, seconds = false) { return `${String(p.year).padStart(4,'0')}-${pad(p.month)}-${pad(p.day)}${time ? `T${pad(p.hour || 0)}:${pad(p.minute || 0)}${seconds ? ':' + pad(p.second || 0) : ''}` : ''}` }
export function monthDays(year, month) {
  const first = new Date(0); first.setFullYear(year, month - 1, 1)
  const end = new Date(0); end.setFullYear(year, month, 0)
  const offset = first.getDay(), length = Math.max(35,Math.ceil((offset+end.getDate())/7)*7)
  return Array.from({ length }, (_, i) => { const d = new Date(0); d.setFullYear(year, month - 1, i - offset + 1); return { year:d.getFullYear(), month:d.getMonth()+1, day:d.getDate() } })
}
export function withinRange(value, min, max) {
  const normalize = v => { const p=parseLocal(v); return p ? localString(p, v.includes('T'), v.includes('T')) : v }
  const v=normalize(value); return (!min || v >= normalize(min)) && (!max || v <= normalize(max))
}
