import { beforeEach, describe, expect, it } from 'vitest'
import { createAdminService } from './service'
import { createLegacySeed } from './legacySeed'

const siteId = 'site-1'
let api, serial, currentTime
function setup(seed = createLegacySeed) {
  const values = new Map()
  serial = 0
  currentTime = '2026-10-27T03:00:00.000Z'
  api = createAdminService({ delay: 0, now: () => currentTime, seed, storage: { getItem: key => values.get(key), setItem: (key, value) => values.set(key, value), removeItem: key => values.delete(key) } })
  api.login('demo-system', 'Admin@2026')
}
beforeEach(() => setup())
const query = async (kind, input = {}) => (await api.query(kind, { siteId, ...input })).data
async function execute(type, input) {
  const command = { siteId, operationId: `role-lifecycle-${++serial}`, ...input }
  if (['roles.update', 'roles.status'].includes(type)) command.previewId = (await query('authorizationPreview', { type, command })).previewId
  return (await api.execute(type, command)).data
}
const createRole = () => execute('roles.create', { data: { name: '可维护角色', operations: ['people:read'], siteIds: [siteId] } })
const updateRole = (role, data = {}) => execute('roles.update', { id: role.id, expectedVersion: role.version, data: { name: role.name, operations: role.grants[0].operations, siteIds: role.grants[0].siteIds, ...data } })

describe('role deletion and recorded times', () => {
  it('records creation and updates the modification time for edits and status changes', async () => {
    const created = await createRole()
    expect(created).toMatchObject({ createdAt: currentTime, updatedAt: currentTime })
    currentTime = '2026-10-27T04:00:00.000Z'
    const updated = await updateRole(created, { name: '已更名角色', createdAt: '2000-01-01T00:00:00.000Z', updatedAt: '2000-01-01T00:00:00.000Z' })
    expect(updated).toMatchObject({ createdAt: created.createdAt, updatedAt: currentTime, version: created.version + 1 })
    currentTime = '2026-10-27T05:00:00.000Z'
    const disabled = await execute('roles.status', { id: updated.id, expectedVersion: updated.version, enabled: false })
    expect(disabled).toMatchObject({ enabled: false, createdAt: created.createdAt, updatedAt: currentTime })
    currentTime = '2026-10-27T06:00:00.000Z'
    const enabled = await execute('roles.status', { id: disabled.id, expectedVersion: disabled.version, enabled: true })
    expect(enabled).toMatchObject({ enabled: true, createdAt: created.createdAt, updatedAt: currentTime })
  })

  it('leaves unknown legacy creation times absent when editing and changing status', async () => {
    setup(() => {
      const state = createLegacySeed()
      state.roles.push({ id: 'legacy-custom-role', name: '旧角色', enabled: true, version: 1, grants: [{ operations: ['overview:read', 'people:read'], siteIds: [siteId] }] })
      return state
    })
    const legacy = await query('record', { entity: 'roles', id: 'legacy-custom-role' })
    expect(legacy).not.toHaveProperty('createdAt')
    expect(legacy).not.toHaveProperty('updatedAt')
    const updated = await updateRole(legacy, { name: '旧角色更名', createdAt: currentTime })
    expect(updated).not.toHaveProperty('createdAt')
    expect(updated.updatedAt).toBe(currentTime)
    currentTime = '2026-10-27T04:00:00.000Z'
    const disabled = await execute('roles.status', { id: updated.id, expectedVersion: updated.version, enabled: false })
    expect(disabled).not.toHaveProperty('createdAt')
    expect(disabled.updatedAt).toBe(currentTime)
  })

  it('deletes an unreferenced custom role with version checking, idempotency and audit snapshots', async () => {
    const created = await createRole()
    const updated = await updateRole(created, { name: '删除前更名' })
    await expect(execute('roles.delete', { id: created.id, expectedVersion: created.version })).rejects.toMatchObject({ errorCode: 'VERSION_CONFLICT' })
    const input = { siteId, id: updated.id, expectedVersion: updated.version, operationId: 'role-delete-once' }
    const deleted = await api.execute('roles.delete', input)
    expect(deleted.data).toMatchObject({ id: updated.id, name: updated.name, deleted: true })
    expect(await api.execute('roles.delete', input)).toEqual(deleted)
    await expect(api.execute('roles.delete', { ...input, expectedVersion: created.version })).rejects.toMatchObject({ errorCode: 'IDEMPOTENCY_CONFLICT' })
    await expect(query('record', { entity: 'roles', id: updated.id })).rejects.toMatchObject({ code: 404 })
    expect((await query('options')).roles.some(role => role.id === updated.id)).toBe(false)
    const audit = (await query('audit')).rows
    expect(audit.find(row => row.action === 'roles.create' && row.objectId === created.id).after.name).toBe(created.name)
    expect(audit.filter(row => row.action === 'roles.delete' && row.objectId === created.id)).toEqual([expect.objectContaining({ before: expect.objectContaining({ id: created.id, name: updated.name }), after: expect.objectContaining({ id: created.id, deleted: true }) })])
    api.login('demo-site', 'Admin@2026')
    await expect(api.execute('roles.delete', input)).rejects.toMatchObject({ code: 404 })
  })

  it('blocks deletion for enabled and disabled account references without cascading changes', async () => {
    const role = await createRole()
    const accounts = []
    for (const loginName of ['active-role-reference', 'disabled-role-reference']) accounts.push(await execute('accounts.create', { relatedVersions: { [role.id]: role.version }, data: { name: loginName, loginName, bindings: [{ roleId: role.id }] } }))
    accounts[1] = await execute('accounts.status', { id: accounts[1].id, expectedVersion: accounts[1].version, enabled: false })
    const impacts = await query('impacts', { entity: 'roles', id: role.id, all: true })
    expect(impacts.rows.map(row => row.id).sort()).toEqual(accounts.map(row => row.id).sort())
    expect((await query('impacts', { entity: 'roles', id: role.id })).rows).toEqual([])
    await expect(execute('roles.delete', { id: role.id, expectedVersion: role.version })).rejects.toMatchObject({ errorCode: 'REFERENCED', impacts: impacts.rows })
    expect(await query('record', { entity: 'roles', id: role.id })).toEqual(role)
    for (const account of accounts) expect(await query('record', { entity: 'accounts', id: account.id })).toEqual(account)
    expect((await query('audit')).rows.some(row => row.action === 'roles.delete')).toBe(false)
  })

  it('protects built-in roles and restricts custom role deletion to the system administrator', async () => {
    const role = await createRole()
    await expect(execute('roles.delete', { id: 'viewer', expectedVersion: 1 })).rejects.toMatchObject({ errorCode: 'BUILTIN_PROTECTED' })
    api.login('demo-site', 'Admin@2026')
    await expect(execute('roles.delete', { id: 'viewer', expectedVersion: 1 })).rejects.toMatchObject({ code: 403 })
    await expect(execute('roles.delete', { id: role.id, expectedVersion: role.version })).rejects.toMatchObject({ code: 404 })
    api.login('demo-system', 'Admin@2026')
    expect((await query('record', { entity: 'roles', id: role.id })).id).toBe(role.id)
  })
})
