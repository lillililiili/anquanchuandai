import { beforeEach, describe, expect, it } from 'vitest'
import { createAdminService } from './service'
import { createLegacySeed } from './legacySeed'

const siteId = 'site-1', id = 'person-1-0', now = '2026-10-27T08:00:00.000Z'
let api, serial
function setup(change = () => {}, initialState = null) {
  const values = new Map()
  api = createAdminService({ delay: 0, now: () => now, initialState, seed: () => {
    const state = createLegacySeed(); change(state); return state
  }, storage: { getItem: key => values.get(key), setItem: (key, value) => values.set(key, value), removeItem: key => values.delete(key) } })
  api.login('demo-system', 'Admin@2026'); serial = 0
}
beforeEach(() => setup())
const query = async (kind, extra = {}) => (await api.query(kind, { siteId, entity: 'people', ...extra })).data
const command = (extra = {}) => ({ siteId, id, expectedVersion: 1, operationId: `duty-${++serial}`, dutyStatus: 'OFF_DUTY', ...extra })

describe('manual person duty status', () => {
  it('legacy enabled and disabled records remain unknown until maintained', async () => {
    setup(state => { state.people.find(person => person.id === id).enabled = false })
    expect((await query('record', { id })).dutyStatus).toBe('UNKNOWN')
    const rows = await query('master', { dutyStatus: 'UNKNOWN', pageSize: 100 })
    expect(rows.rows.find(person => person.id === id)).toMatchObject({ enabled: false, dutyStatus: 'UNKNOWN' })
    expect(rows.rows.find(person => person.id === 'person-1-1')).toMatchObject({ enabled: true, dutyStatus: 'UNKNOWN' })
  })

  it('allows off duty with held equipment, saves provenance, and replays without duplicate audit', async () => {
    const before = api.exportState(), input = command()
    expect(before.assignments.some(assignment => assignment.personId === id && assignment.active)).toBe(true)
    const result = await api.execute('people.dutyStatus', input)
    expect(result.data).toMatchObject({ id, enabled: true, dutyStatus: 'OFF_DUTY', version: 2, dutyStatusSource: 'MANUAL', dutyStatusUpdatedAt: now, dutyStatusUpdatedBy: '系统管理员' })
    expect(await api.execute('people.dutyStatus', input)).toEqual(result)
    const after = api.exportState()
    for (const key of ['devices', 'assignments', 'history', 'accounts', 'dutyShifts']) expect(after[key]).toEqual(before[key])
    expect(after.audit.filter(row => row.action === 'people.dutyStatus')).toHaveLength(1)
    expect(after.audit.at(-1)).toMatchObject({ before: { enabled: true }, after: { enabled: true, dutyStatus: 'OFF_DUTY' } })
    setup(() => {}, after)
    expect(await query('person', { id })).toMatchObject({ dutyStatus: 'OFF_DUTY', enabled: true, dutyStatusUpdatedAt: now })
    await api.execute('people.dutyStatus', command({ expectedVersion: 2, operationId: 'back-on-duty', dutyStatus: 'ON_DUTY' }))
    expect((await query('person', { id })).dutyStatus).toBe('ON_DUTY')
  })

  it('filters all three duty states independently of archive enablement', async () => {
    setup(state => {
      Object.assign(state.people.find(person => person.id === id), { dutyStatus: 'OFF_DUTY', enabled: true })
      Object.assign(state.people.find(person => person.id === 'person-1-1'), { dutyStatus: 'ON_DUTY', enabled: false })
    })
    expect((await query('master', { dutyStatus: 'OFF_DUTY' })).rows.map(row => row.id)).toEqual([id])
    expect((await query('master', { dutyStatus: 'ON_DUTY' })).rows.map(row => row.id)).toEqual(['person-1-1'])
    expect((await query('master', { dutyStatus: 'UNKNOWN', pageSize: 100 })).rows.every(row => ![id, 'person-1-1'].includes(row.id))).toBe(true)
    await expect(query('master', { dutyStatus: 'enabled' })).rejects.toMatchObject({ errorCode: 'INVALID_FILTER' })
  })

  it.each(['UNKNOWN', 'enabled', '', null])('rejects unsupported manual state %s atomically', async dutyStatus => {
    const before = api.exportState()
    await expect(api.execute('people.dutyStatus', command({ dutyStatus }))).rejects.toMatchObject({ code: 400, fields: { dutyStatus: expect.any(String) } })
    expect(api.exportState()).toEqual(before)
  })

  it('rejects hidden enablement changes, stale records, readonly accounts and wrong sites', async () => {
    const before = api.exportState()
    await expect(api.execute('people.dutyStatus', command({ enabled: false }))).rejects.toMatchObject({ code: 400 })
    await expect(api.execute('people.dutyStatus', command({ expectedVersion: 99 }))).rejects.toMatchObject({ errorCode: 'VERSION_CONFLICT' })
    await expect(api.execute('people.dutyStatus', command({ siteId: 'site-2' }))).rejects.toMatchObject({ code: 404 })
    api.login('demo-audit', 'Admin@2026')
    await expect(api.execute('people.dutyStatus', command())).rejects.toMatchObject({ code: 403 })
    expect(api.exportState()).toEqual(before)
  })

  it('new people stay unknown and ordinary profile edits cannot overwrite manual duty state', async () => {
    const created = (await api.execute('people.create', { siteId, operationId: 'new-person', data: { code: 'DUTY-NEW', name: '新人员', dutyStatus: 'ON_DUTY' } })).data
    expect(created.dutyStatus).toBe('UNKNOWN')
    await api.execute('people.dutyStatus', command())
    const row = await query('record', { id })
    const options = await query('options')
    const relatedVersions = Object.fromEntries(Object.values(options).flat().map(item => [item.id, item.version]))
    const result = await api.execute('people.update', { siteId, id, expectedVersion: row.version, operationId: 'edit-profile', relatedVersions, data: { ...row, name: '修改姓名', dutyStatus: 'ON_DUTY' } })
    expect(result.data).toMatchObject({ name: '修改姓名', dutyStatus: 'OFF_DUTY', dutyStatusUpdatedAt: now, dutyStatusSource: 'MANUAL' })
  })
})
