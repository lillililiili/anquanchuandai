export function localTime(utc, timezone = 'UTC') {
  if (!utc || !Number.isFinite(Date.parse(utc))) return ''
  const parts = new Intl.DateTimeFormat('sv-SE', { timeZone: timezone || 'UTC', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(new Date(utc))
  const p = Object.fromEntries(parts.map(x => [x.type, x.value]))
  return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`
}
export function toUtc(local, timezone = 'UTC') {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(local)) throw new Error('请输入完整日期和时间')
  const guess = Date.parse(local + ':00Z'), matches = []
  // Enumerating valid timezone offsets also detects DST gaps and ambiguous times.
  for (let minutes = -14 * 60; minutes <= 14 * 60; minutes += 15) {
    const candidate = new Date(guess + minutes * 60000).toISOString()
    if (localTime(candidate, timezone) === local) matches.push(candidate)
  }
  if (matches.length !== 1) throw new Error('该时区时间不存在或存在夏令时歧义，请选择其他时间')
  return matches[0]
}
