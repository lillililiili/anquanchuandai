import { beforeEach, describe, expect, it } from 'vitest'
import { createAdminService } from './service'
import { createLegacySeed } from './legacySeed'

const siteId = 'site-empty', personId = 'deletion-person'
let api
const person = () => ({ id: personId, siteId, code: 'DELETE-P', name: '可删除人员', organizationId: null, accountId: null, enabled: true, version: 1 })
function setup(change = () => {}) {
  const values = new Map()
  api = createAdminService({ delay: 0, now: () => '2026-10-27T04:00:00.000Z', seed: () => {
    const state = createLegacySeed(); state.people.push(person()); change(state); return state
  }, storage: { getItem: key => values.get(key), setItem: (key, value) => values.set(key, value), removeItem: key => values.delete(key) } })
  api.login('demo-system', 'Admin@2026')
}
beforeEach(() => setup())
const input = () => ({ siteId, id: personId, expectedVersion: 1, operationId: 'delete-person-once' })
const query = async (kind, extra = {}) => (await api.query(kind, { siteId, ...extra })).data

const references = [
  ['活动领用', state => state.assignments.push({ id: 'live-assignment', siteId, personId, deviceId: 'test-device', active: true }), 'live-assignment'],
  ['已停用历史名册', state => state.dutyShifts.push({ id: 'old-roster', siteId, name: '旧名册', enabled: false, startsAt: '2020-01-01T00:00:00Z', endsAt: '2020-01-02T00:00:00Z', personIds: [personId] }), 'old-roster'],
  ['已停用组成员', state => state.groups.push({ id: 'old-group', siteId, enabled: false, personIds: [personId] }), 'old-group'],
  ['已停用组长', state => state.groups.push({ id: 'old-leader-group', siteId, enabled: false, personIds: [], leaderId: personId }), 'old-leader-group'],
  ['账号人员关联', state => state.accounts.push({ id: 'linked-account', siteId, name: '关联账号', enabled: false, roleIds: [], personId }), 'linked-account'],
  ['人员账号关联', state => { state.people.find(row => row.id === personId).accountId = 'reverse-account'; state.accounts.push({ id: 'reverse-account', siteId, name: '反向关联账号', enabled: false, roleIds: [] }) }, 'reverse-account'],
  ['设备直接人员关联', state => state.devices.push({ id: 'direct-device', siteId, personId, enabled: false, lifecycle: 'DISABLED' }), 'direct-device'],
]

describe('personnel deletion', () => {
  it.each(references)('blocks %s without deleting or changing related data', async (_label, change, referenceId) => {
    setup(change)
    const before = api.exportState()
    const impacts = (await query('impacts', { entity: 'people', id: personId, all: true })).rows
    expect(impacts.map(row => row.id)).toContain(referenceId)
    await expect(api.execute('people.delete', input())).rejects.toMatchObject({ code: 409, errorCode: 'REFERENCED', impacts })
    expect(api.exportState()).toEqual(before)
  })

  it('deletes only the person, retaining returned equipment and immutable history, with one audit on replay', async () => {
    setup(state => {
      state.devices.push({ id: 'returned-device', code: 'RETURNED', siteId, type: 'WATCH', lifecycle: 'STOCK', version: 1 })
      state.assignments.push({ id: 'returned-assignment', siteId, personId, deviceId: 'returned-device', active: false, startedAt: '2026-01-01T00:00:00Z', endedAt: '2026-01-02T00:00:00Z' })
      state.history.push({ id: 'returned-history', siteId, personId, personName: '历史人员姓名', deviceId: 'returned-device', action: 'RETURN', occurredAt: '2026-01-02T00:00:00Z' })
      state.audit.push({ id: 'previous-person-audit', siteId, action: 'people.update', objectId: personId, before: { name: '历史人员姓名' }, after: { name: '可删除人员' }, occurredAt: '2026-01-01T00:00:00Z', result: 'SUCCESS' })
    })
    const before = api.exportState(), command = input()
    expect((await query('impacts', { entity: 'people', id: personId, all: true })).rows).toEqual([])
    const removed = await api.execute('people.delete', command)
    expect(removed.data).toMatchObject({ id: personId, deleted: true })
    expect(await api.execute('people.delete', command)).toEqual(removed)
    await expect(api.execute('people.delete', { ...command, expectedVersion: 0 })).rejects.toMatchObject({ errorCode: 'IDEMPOTENCY_CONFLICT' })
    const after = api.exportState()
    expect(after.people.some(row => row.id === personId)).toBe(false)
    for (const key of ['accounts', 'devices', 'assignments', 'history', 'organizations']) expect(after[key]).toEqual(before[key])
    expect(after.audit.find(row => row.id === 'previous-person-audit')).toEqual(before.audit.find(row => row.id === 'previous-person-audit'))
    expect(after.audit.filter(row => row.action === 'people.delete')).toEqual([expect.objectContaining({ objectId: personId, before: expect.objectContaining({ name: '可删除人员' }), after: expect.objectContaining({ deleted: true }) })])
    expect((await query('options')).people.some(row => row.id === personId)).toBe(false)
    await expect(query('record', { entity: 'people', id: personId })).rejects.toMatchObject({ code: 404 })
  })

  it('rejects stale versions, readonly users, and wrong sites before deletion', async () => {
    await api.execute('people.update', { siteId, id: personId, expectedVersion: 1, operationId: 'person-change', data: { name: '改名', code: 'DELETE-P' } })
    await expect(api.execute('people.delete', input())).rejects.toMatchObject({ errorCode: 'VERSION_CONFLICT' })
    await expect(api.execute('people.delete', { ...input(), siteId: 'site-1', expectedVersion: 2 })).rejects.toMatchObject({ code: 404 })
    api.login('demo-audit', 'Admin@2026')
    await expect(api.execute('people.delete', { ...input(), expectedVersion: 2 })).rejects.toMatchObject({ code: 403 })
    api.login('demo-site', 'Admin@2026')
    await expect(api.execute('people.delete', { ...input(), expectedVersion: 2 })).rejects.toMatchObject({ code: 403 })
    api.login('demo-system', 'Admin@2026')
    expect((await query('record', { entity: 'people', id: personId })).name).toBe('改名')
    expect(api.exportState().audit.some(row => row.action === 'people.delete')).toBe(false)
  })

  it('rechecks current write permission when replaying a completed deletion', async () => {
    setup(state => {
      state.roles.push({ id: 'delete-manager-role', enabled: true, grants: [{ siteIds: [siteId], operations: ['overview:read', 'people:read', 'people:write'] }] })
      state.accounts.push({ id: 'delete-manager', loginName: 'delete-manager', enabled: true, credentialVersion: 1, roleIds: ['delete-manager-role'] })
    })
    api.login('delete-manager', 'Admin@2026')
    const command = input()
    await api.execute('people.delete', command)
    const state = api.exportState()
    state.roles.find(row => row.id === 'delete-manager-role').grants[0].operations = ['overview:read', 'people:read']
    api.replaceState(state)
    await expect(api.execute('people.delete', command)).rejects.toMatchObject({ code: 403 })
    expect(api.exportState().audit.filter(row => row.action === 'people.delete')).toHaveLength(1)
  })
})
