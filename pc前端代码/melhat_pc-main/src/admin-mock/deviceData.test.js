import { beforeEach, describe, expect, it } from 'vitest'
import { createAdminService } from './service'
import { createSeed } from './seed'
import { cleanDeviceQuery, deviceReturn, safeTarget, menuPath } from './navigation'
let service, sequence
function setup(seed = createSeed) { const map = new Map(); service = createAdminService({ storage: { getItem: k => map.get(k), setItem: (k, v) => map.set(k, v), removeItem: k => map.delete(k) }, seed, delay: 0 }); service.login('demo-system', 'Admin@2026') }
beforeEach(() => { sequence = 0; setup() })
const siteId = 'site-1'
const create = (data = {}, extra = {}) => service.execute('devices.create', { siteId, operationId: `test-${++sequence}`, data: { name: '预置新设备', code: 'EQ-NEW-' + sequence, type: 'HELMET', ...data }, ...extra })
const get = async id => (await service.query('device', { siteId, id })).data
const update = (row, data, extra = {}) => service.execute('devices.update', { siteId, id: row.id, expectedVersion: row.version, operationId: `test-${++sequence}`, relatedVersions: { 'area-1': 1 }, data, ...extra })
describe('A2 device inventory', () => {
  it('retains A0 baseline and supports long IDs, pagination and filters', async () => {
    expect((await service.query('overview', { siteId })).data.counts).toMatchObject({ assets: 36, available: 17, assigned: 12, maintenance: 3 })
    const list = (await service.query('devices', { siteId, pageNum: 2 })).data
    expect(list.rows.length).toBe(16); expect(typeof list.rows[0].id).toBe('string')
    expect((await service.query('devices', { siteId, keyword: 'sn-eq-1-001' })).data.total).toBe(1)
    expect((await service.query('devices', { siteId, type: 'WATCH' })).data.total).toBe(12)
  })
  it.each(['HELMET', 'BELT', 'WATCH'])('creates incomplete %s without observation or history', async type => {
    const d = (await create({ type })).data
    expect(d).toMatchObject({ lifecycle: 'STOCK', relation: 'UNASSIGNED', communication: 'NOT_CONNECTED', sourceTime: null, verification: 'UNCONFIRMED' })
    expect((await get(d.id)).identityComplete).toBe(false)
    expect((await service.query('deviceHistory', { siteId, id: d.id })).data.total).toBe(0)
    expect((await service.query('overview', { siteId })).data.counts).toMatchObject({ assets: 37, available: 18, assigned: 12 })
  })
  it('rejects case-insensitive global code and manufacturer/SN duplicates without leaking objects', async () => {
    await create({ code: ' UNIQUE ', manufacturer: ' Vendor ', sn: ' Serial ' })
    await expect(create({ code: 'unique' }, { siteId: 'site-2' })).rejects.toMatchObject({ code: 409, fields: { code: expect.any(String) } })
    await expect(create({ manufacturer: 'vendor', sn: 'serial' })).rejects.toMatchObject({ code: 409, fields: { sn: expect.any(String) } })
    await create({ manufacturer: 'vendor' }); await create({ manufacturer: 'vendor' })
  })
  it.each(['lifecycle', 'communication', 'sourceTime', 'verification', 'personId', 'siteId'])('rejects forged %s', async key => {
    await expect(create({ [key]: 'forged' })).rejects.toMatchObject({ errorCode: 'FIELD_NOT_ALLOWED' })
  })
  it('does not permit update type or removal', async () => {
    const d = (await create()).data
    await expect(update(d, { type: 'WATCH' })).rejects.toMatchObject({ errorCode: 'FIELD_NOT_ALLOWED' })
    await expect(service.execute('devices.delete', { siteId, id: d.id })).rejects.toMatchObject({ code: 400 })
  })
  it('requires area version and same-site enabled reference', async () => {
    await expect(create({ areaId: 'area-1' })).rejects.toMatchObject({ code: 409 })
    await expect(create({ areaId: 'area-2' }, { relatedVersions: { 'area-2': 1 } })).rejects.toMatchObject({ code: 400 })
    await create({ areaId: 'area-1' }, { relatedVersions: { 'area-1': 1 } })
  })
  it('locks identity in use but allows descriptive edits without changing history or source time', async () => {
    const d = await get('19007199254740993000')
    await expect(update(d, { code: 'CHANGED' })).rejects.toMatchObject({ errorCode: 'KEY_FIELDS_LOCKED' })
    const result = (await update(d, { name: '预置改名' })).data
    expect(result.sourceTime).toBe(d.sourceTime); expect(result.lifecycle).toBe(d.lifecycle)
    expect((await service.query('person', { siteId, id: 'person-1-0' })).data.equipment[0].name).toBe('预置改名')
  })
  it.each([31, 32, 33])('blocks scrapped or unknown/conflict device %s', async i => {
    const d = await get('19007199254740993' + String(i).padStart(3, '0'))
    await expect(update(d, { code: 'CHANGED' })).rejects.toMatchObject({ code: 409 })
  })
  it('blocks key edit if a stock device has active maintenance', async () => {
    setup(() => { const s = createSeed(); s.maintenanceOrders.push({ id: 'm', siteId, deviceId: s.devices[12].id, status: 'OPEN' }); return s })
    const d = await get('19007199254740993012'); await expect(update(d, { sn: 'NEW' })).rejects.toMatchObject({ errorCode: 'KEY_FIELDS_LOCKED' })
  })
  it('changes model with explicit confirmation and never verifies hardware', async () => {
    const d = (await create({ modelId: 'demo-helmet-plus', assemblies: { position: 'INSTALLED' } })).data
    await expect(update(d, { modelId: 'demo-helmet-basic' })).rejects.toMatchObject({ fields: { modelId: expect.any(String) } })
    const result = (await service.execute('devices.configure', { siteId, id: d.id, expectedVersion: 1, operationId: 'configure', data: { modelId: 'demo-helmet-basic', confirmModelChange: true } })).data
    expect(result.assemblies).toEqual({ camera: 'UNKNOWN' }); expect(result.verification).toBe('UNCONFIRMED')
    await expect(update(result, { assemblies: { position: 'INSTALLED' } })).rejects.toMatchObject({ code: 400 })
  })
  it('does not permit model/type mismatch or arbitrary watch sensors', async () => {
    await expect(create({ type: 'WATCH', modelId: 'demo-helmet-plus' })).rejects.toMatchObject({ code: 400 })
    await expect(create({ type: 'WATCH', assemblies: { heartRate: 'INSTALLED' } })).rejects.toMatchObject({ code: 400 })
  })
  it('idempotent create, stale version and failure preserve atomicity', async () => {
    const input = { siteId, operationId: 'repeat', data: { name: '预置', code: 'REPEAT', type: 'WATCH' } }
    const a = await service.execute('devices.create', input), b = await service.execute('devices.create', input)
    expect(a).toEqual(b)
    await expect(service.execute('devices.create', { ...input, data: { ...input.data, name: 'different' } })).rejects.toMatchObject({ code: 409 })
    await update(a.data, { name: 'updated' })
    await expect(update(a.data, { name: 'stale' })).rejects.toMatchObject({ errorCode: 'VERSION_CONFLICT' })
    expect((await service.query('deviceChanges', { siteId, id: a.data.id })).data.total).toBe(2)
    expect((await service.query('overview', { siteId })).data.counts.assets).toBe(37)
  })
  it('read-only and cross-site direct calls reject', async () => {
    service.login('demo-audit', 'Admin@2026'); await expect(create()).rejects.toMatchObject({ code: 403 })
    await expect(service.query('devices', { siteId: 'site-2' })).rejects.toMatchObject({ code: 403 })
    await expect(service.query('device', { siteId, id: '29007199254740993000' })).rejects.toMatchObject({ code: 404 })
  })
  it('area scope covers lists, details, options, metric and target edit; hides person and audit', async () => {
    setup(() => { const s = createSeed(); s.areas.push({ id: 'private', siteId, name: 'private', enabled: true, version: 1 }); s.devices[0].areaId = 'private'; s.roles.push({ id: 'limited', enabled: true, grants: [{ operations: ['overview:read', 'assets:read', 'assets:write'], siteIds: [siteId], areaIds: ['area-1'] }] }); s.accounts.push({ id: 'limited', name: 'limited', enabled: true, roleIds: ['limited'] }); return s })
    service.login('limited', 'Admin@2026')
    expect((await service.query('devices', { siteId })).data.total).toBe(35)
    expect((await service.query('overview', { siteId })).data.counts.assets).toBe(35)
    const d = await get('19007199254740993001'); expect(d.person).toBeNull()
    await expect(get('19007199254740993000')).rejects.toMatchObject({ code: 404 })
    await expect(service.query('deviceChanges', { siteId, id: d.id })).rejects.toMatchObject({ code: 403 })
    const stock = await get('19007199254740993012'); await expect(update(stock, { areaId: 'private' }, { relatedVersions: { private: 1 } })).rejects.toMatchObject({ code: 403 })
    await expect(create()).rejects.toMatchObject({ code: 403 })
    expect((await service.query('deviceOptions', { siteId })).data.areas.map(a => a.id)).toEqual(['area-1'])
  })
  it('cancellation and identity changes before commit leave no device', async () => {
    const controller = new AbortController(); const promise = create({}, { operationId: 'cancel' })
    service.logout(); await expect(promise).rejects.toMatchObject({ code: 401 }); service.login('demo-system', 'Admin@2026')
    controller.abort(); await expect(service.execute('devices.create', { siteId }, { signal: controller.signal })).rejects.toMatchObject({ name: 'AbortError' })
    expect((await service.query('overview', { siteId })).data.counts.assets).toBe(36)
  })
  it('rejects unsupported filters and preserves explicit source states', async () => {
    await expect(service.query('devices', { siteId, type: 'OTHER' })).rejects.toMatchObject({ code: 400 })
    service.setScenario({ target: 'devices', mode: 'unavailable' }); expect((await service.query('devices', { siteId })).data.availability).toBe('NOT_CONNECTED')
    service.setScenario({ target: 'device', mode: 'failure' }); await expect(get('19007199254740993000')).rejects.toMatchObject({ code: 503 })
  })
  it('safe return and login preserve legal equipment filters only', () => {
    expect(cleanDeviceQuery({ type: 'WATCH', lifecycle: 'OTHER', pageSize: 101 })).toEqual({ type: 'WATCH' })
    expect(deviceReturn('https://evil.example')).toBe('/admin/assets/devices')
    expect(deviceReturn('/admin/assets/devices/x')).toBe('/admin/assets/devices')
    expect(safeTarget('/admin/assets/devices/9007199254740993?siteId=new-site&returnTo=%2Fadmin%2Fassets%2Fdevices%3Ftype%3DWATCH')).toContain('returnTo=')
    expect(menuPath('/admin/assets/devices/x')).toBe('/admin/assets/devices')
  })
  it('idempotent retry rechecks permission after role revocation', async () => {
    setup(() => { const s = createSeed(); s.roles.push({ id: 'temporary', name: 'temporary', enabled: true, version: 1, grants: [{ operations: ['overview:read', 'assets:read', 'assets:write'], siteIds: [siteId], areaIds: '*' }] }); s.accounts.push({ id: 'temporary', name: 'temporary', enabled: true, roleIds: ['temporary'] }); return s })
    service.login('temporary', 'Admin@2026'); const input = { siteId, operationId: 'retry', data: { name: '预置', code: 'RETRY', type: 'BELT' } }
    await service.execute('devices.create', input); service.login('demo-system', 'Admin@2026')
    const revoke = { siteId, id: 'temporary', expectedVersion: 1, operationId: 'revoke', enabled: false }
    revoke.previewId = (await service.query('authorizationPreview', { siteId, type: 'roles.status', command: revoke })).data.previewId
    await service.execute('roles.status', revoke)
    service.login('temporary', 'Admin@2026'); await expect(service.execute('devices.create', input)).rejects.toMatchObject({ code: 403 })
  })
  it('history pagination uses frozen names rather than current owner; changes paginate separately', async () => {
    setup(() => { const s = createSeed(); for (let i = 0; i < 25; i++) s.history.push({ id: `h-${i}`, deviceId: s.devices[0].id, siteId, personId: 'person-1-0', personName: '预置历史名称', action: 'ISSUE', occurredAt: null }); return s })
    const d = await get('19007199254740993000')
    const history = (await service.query('deviceHistory', { siteId, id: d.id, pageNum: 2 })).data
    expect(history.rows).toHaveLength(5); expect(history.rows[0].personName).toBe('预置历史名称'); expect(history.rows[0].occurredAt).toBeNull()
    for (let i = 0; i < 21; i++) { const current = await get(d.id); await update(current, { name: `预置改名${i}` }) }
    expect((await service.query('deviceChanges', { siteId, id: d.id, pageNum: 2 })).data.rows).toHaveLength(1)
    expect((await service.query('deviceHistory', { siteId, id: d.id })).data.rows[0].personName).toBe('预置历史名称')
  })
  it('does not combine read/write rights from different role areas', async () => {
    setup(() => { const s = createSeed(); s.roles.push({ id: 'read-area', enabled: true, grants: [{ operations: ['overview:read', 'assets:read'], siteIds: [siteId], areaIds: ['area-1'] }] }, { id: 'write-other', enabled: true, grants: [{ operations: ['assets:write'], siteIds: [siteId], areaIds: ['other'] }] }); s.accounts.push({ id: 'split', enabled: true, roleIds: ['read-area', 'write-other'] }); return s })
    service.login('split', 'Admin@2026'); const d = await get('19007199254740993012'); await expect(update(d, { name: '不应成功' })).rejects.toMatchObject({ code: 403 })
  })
})
