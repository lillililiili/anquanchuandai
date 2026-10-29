import { beforeEach, describe, expect, it } from 'vitest'
import { createAdminService } from './service'
import { createLegacySeed } from './legacySeed'

const siteId = 'site-empty'
let api, serial
const organization = (id, extra = {}) => ({ id, code: id, name: id, siteId, parentId: null, enabled: false, version: 1, ...extra })
function seed() {
  const state = createLegacySeed()
  state.organizations.push(organization('legacy-root'), organization('legacy-child', { parentId: 'legacy-root' }), organization('legacy-free'))
  state.people.push({ id: 'legacy-person', code: 'legacy-person', name: '旧组织人员', siteId, organizationId: 'legacy-root', enabled: false, version: 1 })
  return state
}
beforeEach(() => {
  const values = new Map()
  api = createAdminService({ delay: 0, seed, storage: { getItem: key => values.get(key), setItem: (key, value) => values.set(key, value), removeItem: key => values.delete(key) } })
  api.login('demo-system', 'Admin@2026'); serial = 0
})
const query = async (entity, extra = {}) => (await api.query('master', { entity, siteId, pageSize: 100, ...extra })).data
const record = async (entity, id) => (await api.query('record', { entity, siteId, id })).data
async function execute(entity, action, input = {}) {
  const options = (await api.query('options', { siteId })).data
  const relatedVersions = Object.fromEntries(Object.values(options).flat().map(row => [row.id, row.version]))
  return (await api.execute(`${entity}.${action}`, { siteId, operationId: `org-lifecycle-${++serial}`, relatedVersions, ...input })).data
}

describe('organizations without enable-disable lifecycle', () => {
  it('rejects both status commands without changing records or appending audit', async () => {
    const auditBefore = (await api.query('audit', { siteId })).data.total
    for (const enabled of [false, true]) await expect(execute('organizations', 'status', { id: 'legacy-root', expectedVersion: 1, enabled })).rejects.toMatchObject({ code: 400, errorCode: 'UNKNOWN_COMMAND' })
    expect(await record('organizations', 'legacy-root')).toMatchObject({ enabled: false, version: 1 })
    expect((await api.query('audit', { siteId })).data.total).toBe(auditBefore)
  })

  it('ignores legacy organization status in options and list filters without changing personnel status', async () => {
    const choices = (await api.query('options', { siteId })).data
    expect(choices.organizations.map(row => row.id)).toEqual(['legacy-root', 'legacy-child', 'legacy-free'])
    for (const status of [undefined, 'enabled', 'disabled', 'obsolete']) expect((await query('organizations', { status })).rows.map(row => row.id)).toEqual(['legacy-root', 'legacy-child', 'legacy-free'])
    expect((await query('people', { status: 'enabled' })).rows).toEqual([])
    expect((await query('people', { status: 'disabled' })).rows.map(row => row.id)).toEqual(['legacy-person'])
    await expect(query('people', { status: 'obsolete' })).rejects.toMatchObject({ errorCode: 'INVALID_FILTER' })
  })

  it('allows child creation, personnel assignment and personnel reactivation under legacy organizations', async () => {
    const child = await execute('organizations', 'create', { data: { name: '新下级', code: 'new-child', parentId: 'legacy-root', enabled: false } })
    expect(child.parentId).toBe('legacy-root'); expect(child).not.toHaveProperty('enabled')
    const person = await execute('people', 'create', { data: { name: '新人员', code: 'new-person', organizationId: 'legacy-child' } })
    expect(person.organizationId).toBe('legacy-child'); expect(person.enabled).toBe(true)
    const updated = await execute('people', 'update', { id: person.id, expectedVersion: person.version, data: { ...person, organizationId: 'legacy-root' } })
    expect(updated.organizationId).toBe('legacy-root')
    const enabledPerson = await execute('people', 'status', { id: 'legacy-person', expectedVersion: 1, enabled: true })
    expect(enabledPerson.enabled).toBe(true)
  })

  it('removes the old state on organization edits and preserves hierarchy, versions and site checks', async () => {
    const root = await record('organizations', 'legacy-root')
    await expect(execute('organizations', 'update', { id: root.id, expectedVersion: root.version, data: { ...root, parentId: 'legacy-child' } })).rejects.toMatchObject({ fields: { parentId: expect.any(String) } })
    await expect(execute('organizations', 'create', { data: { name: '跨站', code: 'foreign-child', parentId: 'organization-1' } })).rejects.toMatchObject({ fields: { parentId: expect.any(String) } })
    const updated = await execute('organizations', 'update', { id: root.id, expectedVersion: root.version, data: { ...root, name: '改名', enabled: false } })
    expect(updated).not.toHaveProperty('enabled'); expect(updated.version).toBe(2)
    await expect(execute('organizations', 'update', { id: root.id, expectedVersion: root.version, data: root })).rejects.toMatchObject({ errorCode: 'VERSION_CONFLICT' })
  })

  it('still blocks referenced organization deletion and counts all organizations against site disable', async () => {
    const impacts = (await api.query('impacts', { siteId, entity: 'organizations', id: 'legacy-root' })).data.rows
    expect(impacts.map(row => row.id)).toEqual(['legacy-child', 'legacy-person'])
    await expect(execute('organizations', 'delete', { id: 'legacy-root', expectedVersion: 1 })).rejects.toMatchObject({ errorCode: 'REFERENCED' })
    const site = await record('sites', siteId)
    await expect(execute('sites', 'status', { id: siteId, expectedVersion: site.version, enabled: false })).rejects.toMatchObject({ errorCode: 'REFERENCED', impacts: expect.arrayContaining([expect.objectContaining({ id: 'legacy-root', label: 'organizations引用' })]) })
    await execute('organizations', 'delete', { id: 'legacy-free', expectedVersion: 1 })
    expect((await query('organizations')).rows.map(row => row.id)).toEqual(['legacy-root', 'legacy-child'])
  })
})
