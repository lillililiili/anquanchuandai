import { can, hasSite } from './access'

export const AUDIT_QUERIES = ['audit', 'auditDetail', 'auditExport']
export const AUDIT_RESULTS = { SUCCESS: '成功', SOURCE_FAILURE: '来源失败', BUSINESS_REJECTED: '业务拒绝', FAILED: '失败', FAILURE: '失败（FAILURE）', DENIED: '拒绝' }
const HIDDEN = '[已脱敏]'
const sensitiveKey = /password|passwd|token|secret|credential|authorization|cookie|url|address|api.?key|access.?key|private.?key|密码|密钥|令牌/i

// Redact both structured fields and free text; never mutate historical snapshots.
export function redactAudit(value) {
  const secrets = new Set()
  function collect(v) {
    if (!v || typeof v !== 'object') return
    for (const [key, item] of Object.entries(v)) {
      if (sensitiveKey.test(key) && typeof item === 'string' && item && item !== HIDDEN) secrets.add(item)
      collect(item)
    }
  }
  collect(value)
  function clean(v) {
    if (Array.isArray(v)) return v.map(clean)
    if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, item]) => [clean(k), sensitiveKey.test(k) ? HIDDEN : clean(item)]))
    if (typeof v !== 'string') return v
    let text = v
    for (const secret of secrets) text = text.split(secret).join(HIDDEN)
    return text.replace(/\b[a-z][a-z0-9+.-]*:\/\/[^\s<>"']+|\bwww\.[^\s<>"']+/gi, HIDDEN)
      .replace(/\bBearer\s+[^\s,;]+/gi, HIDDEN)
      .replace(/\b(?:password|passwd|token|secret|credential|authorization|cookie)\s*[:=]\s*[^\s,;]+/gi, HIDDEN)
      .replace(/\beyJ[\w-]+\.[\w-]+\.[\w-]+\b/g, HIDDEN)
  }
  return clean(value)
}

function filtersFor(input, fail) {
  const filters = {}
  for (const key of ['keyword', 'actorName', 'objectId', 'action', 'result', 'dateFrom', 'dateTo']) {
    const value = input[key] ?? ''
    if (typeof value !== 'string' || value.length > 100) throw fail(400, 'INVALID_FILTER', '筛选条件最多100字')
    filters[key] = value.trim()
  }
  const dates = {}
  for (const key of ['dateFrom', 'dateTo']) {
    if (!filters[key]) continue
    const value = filters[key], day = /^\d{4}-\d{2}-\d{2}$/.test(value)
    if (!day && !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(value)) throw fail(400, 'INVALID_DATE', '日期须为UTC日期或带Z的UTC时间')
    const time = Date.parse(day ? value + (key === 'dateTo' ? 'T23:59:59.999Z' : 'T00:00:00.000Z') : value)
    if (!Number.isFinite(time) || new Date(time).toISOString().slice(0, 10) !== value.slice(0, 10)) throw fail(400, 'INVALID_DATE', '日期无效')
    dates[key] = time
  }
  if (dates.dateFrom > dates.dateTo) throw fail(400, 'INVALID_DATE_RANGE', '开始日期不得晚于结束日期')
  return { filters, dates }
}

export function auditCsvCell(value) {
  let text = value == null ? '' : typeof value === 'object' ? JSON.stringify(value) : String(value)
  // Control prefixes are intentionally included because spreadsheet import can discard them.
  // eslint-disable-next-line no-control-regex
  if (/^[\s\u0000-\u001f\u007f-\u009f]*[=+\-@]/u.test(text)) text = "'" + text
  return '"' + text.replace(/"/g, '""') + '"'
}

export function queryAudit(state, actor, kind, input, { fail, page, now, redact = redactAudit }) {
  if (!AUDIT_QUERIES.includes(kind)) throw fail(400, 'INVALID_QUERY', '不支持的审计查询')
  if (!hasSite(state, actor, input.siteId, 'audit:read')) throw fail(403, 'PERMISSION_DENIED', '无权查看此厂站审计')
  const safe = value => redactAudit(redact(redactAudit(value)))
  const authorized = state.audit.filter(row => row.siteId === input.siteId && can(state, actor, 'audit:read', row))
  if (kind === 'auditDetail') {
    const row = authorized.find(r => r.id === input.id)
    if (!row) throw fail(404, 'AUDIT_NOT_FOUND', '审计记录不存在或不可见')
    return { availability: 'AVAILABLE', ...safe(row) }
  }
  const { filters, dates } = filtersFor(input, fail)
  const rows = authorized.map(safe).filter(row => {
    const time = Date.parse(row.occurredAt)
    if ((dates.dateFrom != null || dates.dateTo != null) && !Number.isFinite(time)) return false
    if (dates.dateFrom != null && time < dates.dateFrom || dates.dateTo != null && time > dates.dateTo) return false
    if (['actorName', 'objectId', 'action', 'result'].some(k => filters[k] && String(row[k] || '') !== filters[k])) return false
    return [row.id, row.actorName, row.objectId, row.action, row.result, row.requestId, row.operationId].join(' ').toLowerCase().includes(filters.keyword.toLowerCase())
  }).sort((a, b) => String(b.occurredAt).localeCompare(String(a.occurredAt)) || String(b.id).localeCompare(String(a.id)))
  if (kind === 'audit') return { availability: 'AVAILABLE', ...page(rows, { ...input, keyword: '' }) }
  const exportedAt = typeof now === 'function' ? now() : now || new Date().toISOString()
  const columns = ['id', 'siteId', 'areaId', 'actorName', 'action', 'objectId', 'occurredAt', 'result', 'requestId', 'operationId', 'before', 'after', 'source']
  const csvRows = [
    ['模拟数据', '前端内存本地审计；非生产审计'], ['厂站', safe(input.siteId)],
    ['筛选条件', safe(filters)], ['导出时间（UTC）', safe(exportedAt)], ['记录数', rows.length], columns,
    ...rows.map(row => columns.map(key => row[key]))
  ]
  return { filename: `mock-audit-${new Date(exportedAt).toISOString().replace(/\D/g, '').slice(0, 17)}.csv`, csv: '\uFEFF' + csvRows.map(row => row.map(auditCsvCell).join(',')).join('\r\n'), total: rows.length, exportedAt }
}
