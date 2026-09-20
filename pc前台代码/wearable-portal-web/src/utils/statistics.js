import { personIdPattern } from './portal-route.js'
import { validUtc } from './work-route.js'
export const statisticTabs = { comprehensive: '综合', people: '人员', equipment: '装备', tasks: '任务', events: '事件' }
export function statisticsQuery(raw = {}) {
  const q = {}
  if (typeof raw.siteId === 'string' && personIdPattern.test(raw.siteId)) q.siteId = raw.siteId
  if (Object.hasOwn(statisticTabs, raw.tab)) q.tab = raw.tab
  if (validUtc(raw.from) && validUtc(raw.to) && Date.parse(raw.from) < Date.parse(raw.to)) { q.from = raw.from; q.to = raw.to }
  return q
}
export function safeStatisticsReturn(value) {
  try {
    if (typeof value !== 'string' || !value.startsWith('/statistics') || value.includes('\\') || [...value].some(c => c.charCodeAt(0) < 32)) return '/statistics'
    const u = new URL(value, 'https://portal.invalid')
    if (u.origin !== 'https://portal.invalid' || u.pathname !== '/statistics' || u.hash) return '/statistics'
    const search = new URLSearchParams(statisticsQuery(Object.fromEntries(u.searchParams))).toString()
    return '/statistics' + (search ? '?' + search : '')
  } catch { return '/statistics' }
}
export const inInterval = (value, from, to) => validUtc(value) && Date.parse(value) >= Date.parse(from) && Date.parse(value) < Date.parse(to)
// Quote every cell and neutralize formulas even after leading whitespace/control bytes.
export function csvCell(value) {
  let text = String(value ?? '')
  const significant = [...text].filter(c => c.charCodeAt(0) >= 32).join('').trimStart()
  if (/^[=+@-]/.test(significant) || /^[\t\r\n]/.test(text)) text = "'" + text
  return '"' + text.replaceAll('"', '""') + '"'
}
export function statisticsCsv(report, metric, exportedAt = new Date().toISOString()) {
  if (metric.state !== 'AVAILABLE') throw new Error('来源不可用，不能导出')
  const lines = [
    ['服务未接入 · 本地工作空间 · 非正式报表'], ['厂站', report.siteName, report.siteId], ['导出时间 UTC', exportedAt],
    ['快照读取时间 UTC（非设备上报）', report.readAt], ['历史区间 [from,to)', report.from, report.to], ['日分组时区', report.timeZone],
    ['统计项', metric.label, '口径', metric.note], ['范围', metric.kind === 'snapshot' ? '当前快照，不受历史区间过滤' : '历史区间'],
    ['标识', '名称', '状态 / 说明', '源时间（未知留空）'], ...metric.rows.map(r => [r.id, r.name, r.state, r.time])
  ]
  return '\ufeff' + lines.map(row => row.map(csvCell).join(',')).join('\r\n')
}
