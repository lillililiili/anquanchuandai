import { describe, it, expect } from 'vitest'
import { queryAudit, redactAudit, auditCsvCell, AUDIT_RESULTS } from './auditData'
import { createAdminService } from './service'
import { createSeed } from './seed'
import { safeTarget, cleanIntegrationQuery, integrationReturn, menuPath } from './navigation'

function setup() {
  const state = { sites: [{ id: 's', enabled: true }, { id: 'other', enabled: true }], areas: [{ id: 'a', siteId: 's', enabled: true }], roles: [{ id: 'reader', grants: [{ operations: ['audit:read'], siteIds: ['s'], areaIds: ['a'] }] }], audit: [] }
  const actor = { id: 'reader', enabled: true, roleIds: ['reader'] }
  state.audit = Array.from({ length: 25 }, (_, i) => ({ id: `r-${i}`, siteId: 's', areaId: 'a', actorName: '历史账号', objectId: 'deleted-person', action: 'people.update', result: 'SUCCESS', occurredAt: '2026-09-20T12:00:00.000Z', before: { name: '旧名称' }, after: { name: '新名称' }, source: '本地模拟', requestId: 'request-1', operationId: 'operation-1' }))
  state.audit.push({ ...state.audit[0], id: 'hidden', areaId: 'b', actorName: '不可见账号', objectId: '不可见对象' })
  const fail = (code, errorCode, message) => Object.assign(new Error(message), { code, errorCode })
  const page = (rows, { pageNum = 1, pageSize = 20 }) => ({ rows: rows.slice((pageNum - 1) * pageSize, pageNum * pageSize), total: rows.length, pageNum, pageSize })
  const q = (kind = 'audit', input = {}) => queryAudit(state, actor, kind, { siteId: 's', ...input }, { fail, page, now: '2026-09-21T00:00:00.000Z' })
  return { state, actor, q }
}
describe('A6 audit snapshots and local CSV', () => {
  it.each(['SOURCE_FAILURE', 'BUSINESS_REJECTED'])('exposes actual integration result %s as a filter option', result => {
    const { q, state } = setup(); state.audit[0].result = result
    expect(AUDIT_RESULTS[result]).toBeTruthy()
    expect(q('audit', { result }).rows.map(r => r.id)).toEqual(['r-0'])
    expect(q('auditExport', { result }).total).toBe(1)
  })
  it('filters before paging and exports all authorized results', () => {
    const { q } = setup()
    expect(q('audit', { pageNum: 2, pageSize: 10, keyword: '历史账号' })).toMatchObject({ total: 25, rows: expect.any(Array) })
    expect(q('audit', { pageNum: 2, pageSize: 10 }).rows).toHaveLength(10)
    const csv = q('auditExport', { pageNum: 2, pageSize: 1 })
    expect(csv.total).toBe(25); expect(csv.csv.startsWith('\uFEFF')).toBe(true)
    expect(csv.csv).toContain('模拟数据'); expect(csv.csv).toContain('筛选条件'); expect(csv.csv).not.toContain('不可见')
    expect(csv.filename).toMatch(/^mock-audit-\d+\.csv$/)
  })
  it('returns immutable historical name snapshots even without live targets', () => {
    const { q, state } = setup(), row = q('auditDetail', { id: 'r-0' })
    expect(row.before.name).toBe('旧名称'); row.before.name = '修改返回值'
    expect(state.audit[0].before.name).toBe('旧名称')
    expect(() => q('auditDetail', { id: 'hidden' })).toThrow('不存在或不可见')
  })
  it('rechecks dynamic row and site permissions', () => {
    const { q, state } = setup()
    state.areas.push({ id: 'b', siteId: 's', enabled: true }); state.roles[0].grants[0].areaIds = ['b']
    expect(q().rows.map(r => r.id)).toEqual(['hidden'])
    expect(() => q('auditDetail', { id: 'r-0' })).toThrow()
    expect(() => q('auditExport', { siteId: 'other' })).toThrow()
    state.roles[0].enabled = false; expect(() => q()).toThrow()
  })
  it('combines UTC date/account/object/action/result filters, validates calendar dates', () => {
    const { q } = setup()
    expect(q('audit', { dateFrom: '2026-09-20', dateTo: '2026-09-20', actorName: '历史账号', objectId: 'deleted-person', action: 'people.update', result: 'SUCCESS' }).total).toBe(25)
    expect(q('audit', { dateFrom: '2026-09-21' }).total).toBe(0)
    expect(() => q('audit', { dateFrom: '2026-02-30' })).toThrow()
    expect(() => q('audit', { dateFrom: '2026-09-22', dateTo: '2026-09-20' })).toThrow()
    expect(() => q('audit', { dateFrom: '2026-09-20T12:00:00+08:00' })).toThrow()
  })
  it('redacts nested secret fields, duplicated secret values and URL/free-text credentials', () => {
    const value = { password: 'privatepass', token: 'unique-token', note: 'privatepass unique-token https://internal/a token=abcdef Bearer abc', nested: [{ url: 'http://internal', name: '保留名称' }] }
    const result = JSON.stringify(redactAudit(value))
    for (const secret of ['privatepass', 'unique-token', 'https://', 'http://', 'abcdef', 'Bearer abc']) expect(result).not.toContain(secret)
    expect(result).toContain('保留名称')
    const { q, state } = setup(); state.audit[0].after = value
    expect(q('auditExport', { keyword: 'https://internal/a' }).csv).not.toContain('https://')
    expect(JSON.stringify(q('auditDetail', { id: 'r-0' }))).not.toContain('privatepass')
  })
  it('quotes commas, quotes and newlines; guards spreadsheet formulas with leading whitespace/control', () => {
    expect(auditCsvCell('a,"b"\nc')).toBe('"a,""b""\nc"')
    for (const value of ['=1+1', '+1', '-1', '@SUM(A1)', ' \t\r=1', '\u0000\u007f+1', '\uFEFF@x']) expect(auditCsvCell(value)).toBe('"\'' + value + '"')
    expect(auditCsvCell('普通名称')).toBe('"普通名称"')
  })
  it('service dispatch protects all audit kinds and returns full filtered export', async () => {
    const values = new Map(), storage = { getItem: key => values.get(key), setItem: (key, value) => values.set(key, value), removeItem: key => values.delete(key) }
    const api = createAdminService({ storage, delay: 0, seed: () => { const state = createSeed(); state.audit = setup().state.audit.slice(0, 25).map(r => ({ ...r, siteId: 'site-1', areaId: null })); return state } })
    api.login('demo-audit', 'Admin@2026')
    const input = { siteId: 'site-1', keyword: '历史账号', pageSize: 1 }
    expect((await api.query('audit', input)).data.rows).toHaveLength(1)
    expect((await api.query('auditExport', input)).data.total).toBe(25)
    expect((await api.query('auditDetail', { siteId: 'site-1', id: 'r-0' })).data.before.name).toBe('旧名称')
    await expect(api.query('auditExport', { siteId: 'site-2' })).rejects.toMatchObject({ code: 403 })
    const controller = new AbortController(); controller.abort()
    await expect(api.query('auditExport', input, { signal: controller.signal })).rejects.toMatchObject({ name: 'AbortError' })
    api.logout(); await expect(api.query('auditDetail', { siteId: 'site-1', id: 'r-0' })).rejects.toMatchObject({ code: 401 })
  })
})

describe('A6 navigation sanitization', () => {
  it('preserves integration workspace filters and known detail/settings paths', () => {
    const query = { siteId: 'site-1', tab: 'jobs', status: 'CONFLICT', connectorId: 'integration-site-1-DEVICE', keyword: 'source', pageNum: '2', pageSize: '50' }
    expect(cleanIntegrationQuery(query)).toEqual(query)
    for (const path of ['/admin/integrations', '/admin/integrations/settings', '/admin/integrations/integration-site-1-DEVICE', '/admin/integrations/jobs/integration-job-1']) {
      const target = safeTarget(path + '?' + new URLSearchParams(query))
      expect(target.split('?')[0]).toBe(path)
      expect(Object.fromEntries(new URLSearchParams(target.split('?')[1]))).toEqual(query)
      expect(menuPath(path)).toBe('/admin/integrations')
    }
  })
  it('drops unsafe and unsupported integration filters', () => {
    expect(cleanIntegrationQuery({ siteId: '../site', tab: 'unknown', status: 'SUCCESS', connectorId: '../../other', keyword: 'x'.repeat(150), pageNum: '0', pageSize: '101', token: 'secret', endpoint: 'https://remote.invalid', returnTo: '//remote.invalid' })).toEqual({ keyword: 'x'.repeat(100) })
    expect(cleanIntegrationQuery({ siteId: ['site-1', 'site-2'], tab: ['jobs'], status: ['PREVIEW'], connectorId: ['integration-1'] })).toEqual({})
    expect(safeTarget('/admin/audit?siteId=site-1&token=hidden&url=https%3A%2F%2Fremote.invalid')).toBe('/admin/audit?siteId=site-1')
  })
  it.each(['https://remote.invalid/admin/integrations', '//remote.invalid/admin/integrations', 'javascript:alert(1)', '/admin/integrations\\evil', '/admin/integrations#evil', '/admin/integrations/jobs/id/extra', '/admin/integrations/%2Fremote', '/admin/integrations/jobs/' + 'x'.repeat(101)])('rejects unsafe target %s', value => {
    expect(safeTarget(value)).toBe('/admin/overview')
    expect(integrationReturn(value)).toBe('/admin/integrations')
  })
  it('limits return paths to the filtered integration list and strips nested secrets', () => {
    const back = '/admin/integrations?siteId=site-1&tab=jobs&status=FAILED&token=secret'
    const result = safeTarget('/admin/integrations/jobs/job-1?' + new URLSearchParams({ siteId: 'site-1', returnTo: back, token: 'secret' }))
    expect(new URLSearchParams(result.split('?')[1]).get('returnTo')).toBe('/admin/integrations?siteId=site-1&tab=jobs&status=FAILED')
    expect(result).not.toContain('secret')
    for (const value of ['/admin/access/accounts', '/admin/integrations/settings', '/admin/integrations/jobs/job-2']) expect(integrationReturn(value)).toBe('/admin/integrations')
  })
})
