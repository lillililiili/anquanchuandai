import { describe, expect, it } from 'vitest'
import { createAdminService } from './service'
import { createLegacySeed } from './legacySeed'

const siteId = 'site-1', personId = 'person-1-4'
const deviceIds = [12, 13, 14].map(index => '19007199254740993' + String(index).padStart(3, '0'))
function service(initialState = createLegacySeed()) {
  const values = new Map()
  const api = createAdminService({ initialState, delay: 0, now: () => '2026-10-27T04:00:00.000Z', storage: { getItem: key => values.get(key), setItem: (key, value) => values.set(key, value), removeItem: key => values.delete(key) } })
  api.login('demo-system', 'Admin@2026')
  return api
}
const query = async (api, kind, input = {}) => (await api.query(kind, { siteId, ...input })).data
const execute = async (api, type, input) => (await api.execute(type, { siteId, acknowledged: true, ...input })).data

async function returnOne(api, targetPersonId, deviceId, operationId = 'return-one') {
  const selection = await query(api, 'assignmentCandidates', { resource: 'selection', personId: targetPersonId })
  const current = selection.current.find(row => row.deviceId === deviceId)
  return execute(api, 'assignments.return', { personId: targetPersonId, personVersion: selection.person.version, operationId, items: [{ deviceId, deviceVersion: current.deviceVersion, assignmentId: current.id, assignmentVersion: current.version, condition: 'GOOD' }] })
}

describe('person detail histories and account association', () => {
  it('restores per-item issuance and returns after reload with immutable display snapshots and consistent pagination', async () => {
    const api = service()
    const original = await query(api, 'person', { id: personId })
    const issued = await execute(api, 'assignments.issue', { personId, personVersion: original.version, operationId: 'issue-three', items: deviceIds.map(deviceId => ({ deviceId, deviceVersion: 1 })) })
    expect(issued.history).toHaveLength(3)
    for (const history of issued.history) {
      const device = api.exportState().devices.find(row => row.id === history.deviceId)
      expect(history).toMatchObject({ batchId: issued.batchId, assignmentId: expect.any(String), action: 'ISSUE', personName: original.name, personCode: original.code, deviceCode: device.code, deviceName: device.name, type: device.type, actorName: '系统管理员', occurredAt: '2026-10-27T04:00:00.000Z', startedAt: '2026-10-27T04:00:00.000Z', condition: null })
    }
    await api.execute('people.update', { siteId, id: personId, expectedVersion: original.version + 1, operationId: 'rename-person', relatedVersions: { [original.organizationId]: 1 }, data: { name: '归还时姓名', code: original.code, organizationId: original.organizationId } })
    const returned = await returnOne(api, personId, deviceIds[1])
    expect(returned.history).toEqual([expect.objectContaining({ action: 'RETURN', personName: '归还时姓名', deviceId: deviceIds[1], condition: 'GOOD', startedAt: issued.history[1].startedAt })])
    const beforeReload = await query(api, 'assignmentHistory', { personId, pageSize: 100 })
    expect(beforeReload.total).toBe(4)
    expect(beforeReload.rows.filter(row => row.action === 'ISSUE').map(row => row.personName)).toEqual([original.name, original.name, original.name])
    const reloaded = service(api.exportState())
    expect(await query(reloaded, 'assignmentHistory', { personId, pageSize: 100 })).toEqual(beforeReload)
    expect((await query(reloaded, 'person', { id: personId })).history).toEqual(beforeReload.rows)
    const first = await query(reloaded, 'assignmentHistory', { personId, pageSize: 2, pageNum: 1 })
    const second = await query(reloaded, 'assignmentHistory', { personId, pageSize: 2, pageNum: 2 })
    expect(first.total).toBe(4); expect(second.total).toBe(4)
    expect([...first.rows, ...second.rows].map(row => row.id)).toEqual(beforeReload.rows.map(row => row.id))
    expect(new Set([...first.rows, ...second.rows].map(row => row.id)).size).toBe(4)
    const deviceHistory = await query(reloaded, 'deviceHistory', { id: deviceIds[1], pageSize: 100 })
    expect(deviceHistory.rows).toEqual(beforeReload.rows.filter(row => row.deviceId === deviceIds[1]))
    expect((await query(reloaded, 'assignmentHistory', { personId, action: 'RETURN', type: 'BELT' })).rows).toMatchObject(returned.history)
  })

  it('does not invent issuance history from an initial binding, including after a real return and reload', async () => {
    const api = service(), originalPersonId = 'person-1-0'
    const selection = await query(api, 'assignmentCandidates', { resource: 'selection', personId: originalPersonId })
    expect(selection.current.length).toBeGreaterThan(0)
    expect((await query(api, 'assignmentHistory', { personId: originalPersonId })).total).toBe(0)
    expect((await query(api, 'person', { id: originalPersonId })).history).toEqual([])
    const returned = await returnOne(api, originalPersonId, selection.current[0].deviceId)
    expect(returned.history).toEqual([expect.objectContaining({ action: 'RETURN', startedAt: null })])
    const restored = service(api.exportState())
    const history = await query(restored, 'assignmentHistory', { personId: originalPersonId })
    expect(history.total).toBe(1)
    expect(history.rows.map(row => row.action)).toEqual(['RETURN'])
  })

  it.each(['account-to-person', 'person-to-account'])('resolves %s account names only through visible accounts', async direction => {
    const state = createLegacySeed(), target = state.people.find(row => row.id === personId)
    const account = { id: 'linked-history-account', name: '历史关联账号', loginName: 'linked-history-account', siteId, enabled: false, roleIds: [], credentialVersion: 1 }
    if (direction === 'account-to-person') account.personId = personId
    else target.accountId = account.id
    state.accounts.push(account)
    state.roles.push({ id: 'person-details-only-role', enabled: true, grants: [{ siteIds: [siteId], operations: ['overview:read', 'people:read', 'assets:read'] }] })
    state.accounts.push({ id: 'person-details-only', enabled: true, roleIds: ['person-details-only-role'], credentialVersion: 1 })
    const api = service(state)
    expect((await query(api, 'person', { id: personId })).accountName).toBe(account.name)
    api.login('person-details-only', 'Admin@2026')
    expect((await query(api, 'person', { id: personId })).accountName).toBeNull()
  })
})
