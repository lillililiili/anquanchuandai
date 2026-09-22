import { beforeEach, describe, expect, it } from 'vitest'
import { createAdminService } from './service'
import { createSeed } from './seed'
import { cleanAssignmentQuery, assignmentReturn, safeTarget } from './navigation'
let service, sequence
const siteId = 'site-1', personId = 'person-1-4', ids = [12, 13, 14].map(i => '19007199254740993' + String(i).padStart(3, '0'))
function setup(change = () => {}, delay = 0) { const map = new Map(); service = createAdminService({ storage: { getItem: k => map.get(k), setItem: (k, v) => map.set(k, v), removeItem: k => map.delete(k) }, delay, seed: () => { const s = createSeed(); change(s); return s }, now: () => '2026-09-20T08:00:00Z' }); service.login('demo-system', 'Admin@2026') }
beforeEach(() => { sequence = 0; setup() })
const query = async (kind, input = {}) => (await service.query(kind, { siteId, ...input })).data
const issue = (extra = {}) => ({ siteId, personId, personVersion: 1, acknowledged: true, operationId: `issue-${++sequence}`, items: ids.map(deviceId => ({ deviceId, deviceVersion: 1 })), ...extra })
async function returnInput(extra = {}) { const s = await query('assignmentCandidates', { resource: 'selection', personId: extra.personId || personId }); return { siteId, personId: s.person.id, personVersion: s.person.version, acknowledged: true, operationId: `return-${++sequence}`, items: s.current.map(r => ({ deviceId: r.deviceId, deviceVersion: r.deviceVersion, assignmentId: r.id, assignmentVersion: r.version, condition: 'GOOD' })), ...extra } }
const counts = async () => (await query('overview')).counts
describe('A3 atomic assignment transactions', () => {
  it('three types, partial and mixed return update one source with one order', async () => {
    const result = (await service.execute('assignments.issue', issue())).data
    expect(new Set(result.history.map(h => h.batchId)).size).toBe(1); expect(result.history).toHaveLength(3)
    expect(await counts()).toMatchObject({ available: 14, assigned: 15, maintenance: 3 })
    const first = await returnInput(); first.items = first.items.slice(0, 1); await service.execute('assignments.return', first)
    expect(await counts()).toMatchObject({ available: 15, assigned: 14, maintenance: 3 })
    const rest = await returnInput(); rest.items[1] = { ...rest.items[1], condition: 'REPAIR', reason: '预置外壳破损', handlerId: 'demo-asset', handlerVersion: 1 }
    const returned = (await service.execute('assignments.return', rest)).data
    expect(await counts()).toMatchObject({ available: 16, assigned: 12, maintenance: 4 })
    expect((await query('maintenanceSummary', { id: returned.maintenanceOrderIds[0] }))).toMatchObject({ batchId: returned.batchId, handlerName: '资产管理员', status: 'OPEN' })
    expect((await query('assignmentHistory', { personId })).total).toBe(6)
    expect((await query('assignmentCandidates', { resource: 'devices', personId })).rows.some(d => d.id === ids[2])).toBe(false)
  })
  it('baseline metrics and explicit unknown slots remain unchanged', async () => {
    expect(await counts()).toMatchObject({ assets: 36, available: 17, assigned: 12, maintenance: 3 })
    expect((await query('assignmentCandidates', { resource: 'selection', personId: 'person-1-22' })).slots.BELT).toBe('UNKNOWN')
    expect((await query('assignmentCandidates', { resource: 'selection', personId: 'person-1-20' })).slots.HELMET).toBe('CONFLICT')
  })
  it('idempotent issue and return do not duplicate histories, orders or revision', async () => {
    const command = issue(), first = await service.execute('assignments.issue', command)
    expect(await service.execute('assignments.issue', command)).toEqual(first)
    await expect(service.execute('assignments.issue', { ...command, acknowledged: false })).rejects.toMatchObject({ code: 409 })
    const ret = await returnInput(); ret.items[0] = { ...ret.items[0], condition: 'REPAIR', reason: '预置', handlerId: 'demo-system', handlerVersion: 1 }
    const returned = await service.execute('assignments.return', ret)
    expect(await service.execute('assignments.return', ret)).toEqual(returned)
    expect((await query('assignmentHistory', { personId })).total).toBe(6); expect((await counts()).maintenance).toBe(4)
  })
  it('one stale item fails whole issue without mutation or audit', async () => {
    const command = issue(); command.items[2].deviceVersion = 99
    await expect(service.execute('assignments.issue', command)).rejects.toMatchObject({ code: 409 })
    expect((await counts()).assigned).toBe(12); expect((await query('assignmentHistory')).total).toBe(0); expect((await query('audit')).total).toBe(0)
  })
  it.each(['duplicate-device', 'duplicate-type', 'empty', 'too-many', 'unacknowledged', 'forged'])('rejects %s', async mode => {
    const command = issue()
    if (mode === 'duplicate-device') command.items[1] = command.items[0]
    if (mode === 'duplicate-type') command.items[1].deviceId = '19007199254740993015'
    if (mode === 'empty') command.items = []
    if (mode === 'too-many') command.items.push(command.items[0])
    if (mode === 'unacknowledged') command.acknowledged = false
    if (mode === 'forged') command.items[0].sourceTime = 'forged'
    await expect(service.execute('assignments.issue', command)).rejects.toHaveProperty('errorCode')
    expect((await query('assignmentHistory')).total).toBe(0)
  })
  it.each(['UNKNOWN', 'CONFLICT', 'MAINTENANCE', 'SCRAPPED'])('rejects device %s', async state => {
    setup(s => { const d = s.devices.find(d => d.id === ids[0]); if (['UNKNOWN', 'CONFLICT'].includes(state)) d.relation = state; else d.lifecycle = state })
    await expect(service.execute('assignments.issue', issue())).rejects.toMatchObject({ code: 409 })
  })
  it('offline stale incomplete capability devices remain issuable with warnings', async () => {
    const candidates = await query('assignmentCandidates', { resource: 'devices', personId })
    expect(candidates.rows.find(d => d.id === ids[0]).warnings.length).toBeGreaterThan(0)
    const d = await query('device', { id: ids[0] }); await service.execute('assignments.issue', issue())
    expect(await query('device', { id: ids[0] })).toMatchObject({ sourceTime: d.sourceTime, communication: d.communication, verification: d.verification })
  })
  it('disabled person cannot issue but can return a normal old binding with unknown start', async () => {
    setup(s => { s.people.find(p => p.id === personId).enabled = false; s.people[0].enabled = false })
    await expect(service.execute('assignments.issue', issue())).rejects.toMatchObject({ code: 409 })
    const ret = await returnInput({ personId: 'person-1-0' }); const result = (await service.execute('assignments.return', ret)).data
    expect(result.history.every(h => h.startedAt === null)).toBe(true)
    expect((await query('assignmentHistory', { personId: 'person-1-0' })).rows.every(h => h.action === 'RETURN')).toBe(true)
  })
  it('unknown person slot cannot be inferred empty', async () => {
    await expect(service.execute('assignments.issue', issue({ personId: 'person-1-22', items: [{ deviceId: ids[1], deviceVersion: 1 }] }))).rejects.toMatchObject({ code: 409 })
  })
  it.each(['missing-reason', 'disabled-handler', 'revoked-handler', 'stale-handler', 'stale-relation'])('mixed return %s is atomic', async mode => {
    if (mode === 'disabled-handler') setup(s => { s.accounts.find(a => a.id === 'demo-asset').enabled = false })
    if (mode === 'revoked-handler') setup(s => { s.roles.find(r => r.id === 'asset').grants[0].operations = ['assets:read', 'overview:read'] })
    await service.execute('assignments.issue', issue()); const ret = await returnInput()
    ret.items[2] = { ...ret.items[2], condition: 'REPAIR', reason: mode === 'missing-reason' ? '' : '本地损坏', handlerId: 'demo-asset', handlerVersion: mode === 'stale-handler' ? 99 : 1 }
    if (mode === 'stale-relation') ret.items[2].assignmentVersion = 99
    await expect(service.execute('assignments.return', ret)).rejects.toHaveProperty('errorCode')
    expect(await counts()).toMatchObject({ assigned: 15, maintenance: 3 }); expect((await query('assignmentHistory')).total).toBe(3)
  })
  it('readonly actor cannot write or enumerate handlers', async () => {
    service.login('demo-audit', 'Admin@2026')
    await expect(service.execute('assignments.issue', issue())).rejects.toMatchObject({ code: 403 })
    await expect(query('repairAssignees', { deviceId: ids[0] })).rejects.toMatchObject({ code: 403 })
  })
  it('cross-site object is invisible and unauthorized site rejected', async () => {
    service.login('demo-asset', 'Admin@2026')
    await expect(service.execute('assignments.issue', issue({ personId: 'person-2-4' }))).rejects.toMatchObject({ code: 404 })
    await expect(query('assignments', { siteId: 'site-2' })).rejects.toMatchObject({ code: 403 })
  })
  it('area and paired role grants cannot be stitched into write privilege', async () => {
    setup(s => { s.areas.push({ id: 'restricted', siteId, enabled: true }); s.people.find(p => p.id === personId).areaId = 'restricted'; s.roles.find(r => r.id === 'asset').grants = [{ operations: ['assets:write', 'assets:read', 'people:read', 'overview:read'], siteIds: [siteId], areaIds: ['area-1'] }, { operations: ['people:read', 'assets:read', 'overview:read'], siteIds: [siteId], areaIds: ['restricted'] }] })
    service.login('demo-asset', 'Admin@2026'); await expect(service.execute('assignments.issue', issue())).rejects.toMatchObject({ code: 403 })
  })
  it('abort and context changes before commit leave no history', async () => {
    setup(() => {}, 10); const controller = new AbortController(), pending = service.execute('assignments.issue', issue(), { signal: controller.signal }); controller.abort()
    await expect(pending).rejects.toMatchObject({ name: 'AbortError' })
    const switched = service.execute('assignments.issue', issue()); service.changeContext(); await expect(switched).rejects.toMatchObject({ name: 'AbortError' })
    expect((await query('assignmentHistory')).total).toBe(0)
  })
  it('simultaneous issue accepts exactly one operation', async () => {
    const result = await Promise.allSettled([service.execute('assignments.issue', issue()), service.execute('assignments.issue', issue())])
    expect(result.filter(r => r.status === 'fulfilled')).toHaveLength(1); expect((await query('assignmentHistory')).total).toBe(3)
  })
  it('history freezes names and is compatible across person/device detail', async () => {
    const result = (await service.execute('assignments.issue', issue())).data
    const p = await query('person', { id: personId })
    await service.execute('people.update', { siteId, id: personId, operationId: 'rename', expectedVersion: 2, relatedVersions: { 'area-1': 1, 'org-1': 1 }, data: { name: '预置改名后', code: p.code, areaId: p.areaId, organizationId: p.organizationId } })
    expect((await query('assignments', { personId })).rows[0].personName).toBe('预置改名后')
    const history = await query('assignmentHistory', { personId, batchId: result.batchId, pageSize: 1, pageNum: 2 })
    expect(history.total).toBe(3); expect(history.rows[0].personName).not.toBe('预置改名后')
    expect((await query('deviceHistory', { id: ids[0] })).rows[0].personName).toBe(result.history[0].personName)
    expect((await query('person', { id: personId })).history).toHaveLength(3)
  })
  it('handler response contains no role or account credentials', async () => {
    const handlers = await query('repairAssignees', { deviceId: ids[0] }); expect(handlers.rows.length).toBeGreaterThan(0)
    expect(Object.keys(handlers.rows[0]).sort()).toEqual(['id', 'name', 'version'])
  })
  it('no device/history leakage without its area scope', async () => {
    setup(s => { s.areas.push({ id: 'area-other', siteId, enabled: true }); s.roles.find(r => r.id === 'asset').grants[0].areaIds = ['area-other'] })
    service.login('demo-asset', 'Admin@2026'); expect((await query('assignments')).total).toBe(0)
    await expect(query('assignmentHistory', { deviceId: ids[0] })).rejects.toMatchObject({ code: 404 })
  })
  it('stock device with active maintenance is excluded from metric and candidates', async () => {
    setup(s => { s.maintenanceOrders.push({ id: 'anomaly', siteId, deviceId: ids[0], status: 'OPEN' }) })
    expect((await counts()).available).toBe(16)
    expect((await query('assignmentCandidates', { resource: 'devices', personId })).rows.some(d => d.id === ids[0])).toBe(false)
  })
  it('safe routes preserve only legal assignment filters and maintenance target', () => {
    expect(cleanAssignmentQuery({ tab: 'returns', type: 'BELT', pageSize: '101', deviceId: ids[0], url: 'evil' })).toEqual({ tab: 'returns', type: 'BELT', deviceId: ids[0] })
    expect(assignmentReturn('https://evil.test')).toBe('/admin/assets/assignments')
    expect(safeTarget('/admin/assets/maintenance/repair-1?siteId=site-new')).toBe('/admin/assets/maintenance/repair-1?siteId=site-new')
  })
  it('history paginates beyond twenty and filters by device/type/action/batch', async () => {
    for (let i = 0; i < 11; i++) {
      const selection = await query('assignmentCandidates', { resource: 'selection', personId }), d = await query('device', { id: ids[0] })
      await service.execute('assignments.issue', issue({ personVersion: selection.person.version, items: [{ deviceId: d.id, deviceVersion: d.version }] }))
      await service.execute('assignments.return', await returnInput())
    }
    expect((await query('assignmentHistory', { personId, pageNum: 2 })).rows).toHaveLength(2)
    expect((await query('deviceHistory', { id: ids[0], pageNum: 2 })).rows).toHaveLength(2)
    expect((await query('assignmentHistory', { deviceId: ids[0], type: 'HELMET', action: 'RETURN' })).total).toBe(11)
    expect((await query('assignmentHistory', { keyword: 'does-not-exist' })).total).toBe(0)
    await expect(query('assignmentHistory', { pageSize: 101 })).rejects.toMatchObject({ code: 400 })
  })
  it('history hides personnel snapshots and audit contains no personnel payload when people read revoked', async () => {
    setup(s => { s.roles.push({ id: 'no-people', enabled: true, grants: [{ siteIds: [siteId], areaIds: '*', operations: ['overview:read', 'assets:read', 'audit:read'] }] }); s.accounts.push({ id: 'no-people', name: '预置设备查看员', enabled: true, roleIds: ['no-people'] }) })
    await service.execute('assignments.issue', issue()); service.login('no-people', 'Admin@2026')
    const h = (await query('assignmentHistory')).rows[0]
    expect(h.personId).toBeNull(); expect(h.personName).toBeNull()
    expect(JSON.stringify((await query('audit')).rows)).not.toContain('person-1-4')
    await expect(query('assignmentHistory', { personId })).rejects.toMatchObject({ code: 404 })
  })
  it('same person type conflict prevents new device while other known slots remain available', async () => {
    await service.execute('assignments.issue', issue({ items: [issue().items[0]] }))
    await expect(service.execute('assignments.issue', issue({ personVersion: 2, items: [{ deviceId: '19007199254740993015', deviceVersion: 1 }] }))).rejects.toMatchObject({ code: 409 })
    const unknown = issue({ personId: 'person-1-22', items: [{ deviceId: ids[0], deviceVersion: 2 }] })
    await expect(service.execute('assignments.issue', unknown)).rejects.toMatchObject({ code: 409 })
    await service.execute('assignments.issue', issue({ personId: 'person-1-22', items: [{ deviceId: ids[2], deviceVersion: 1 }] }))
  })
  it('identity change during submission does not commit into a new identity', async () => {
    setup(() => {}, 10); const pending = service.execute('assignments.issue', issue()); service.login('demo-asset', 'Admin@2026')
    await expect(pending).rejects.toMatchObject({ code: 401 }); expect((await query('assignmentHistory')).total).toBe(0)
  })
  it('idempotent replay rechecks current permission', async () => {
    const command = issue(); await service.execute('assignments.issue', command); service.login('demo-audit', 'Admin@2026')
    await expect(service.execute('assignments.issue', command)).rejects.toMatchObject({ code: 403 })
  })
  it('old relationship cannot return twice under another operation', async () => {
    const ret = await returnInput({ personId: 'person-1-0' }); await service.execute('assignments.return', ret)
    await expect(service.execute('assignments.return', { ...ret, operationId: 'second-return' })).rejects.toMatchObject({ code: 409 })
    expect((await query('assignmentHistory')).total).toBe(3)
  })
  it('failed observer cannot report committed issuance as a transaction failure', async () => {
    const stop = service.subscribe(() => { throw new Error('test observer failure') })
    await expect(service.execute('assignments.issue', issue())).resolves.toMatchObject({ code: 200 }); stop()
    expect((await counts()).assigned).toBe(15)
  })
})
