import { beforeEach, describe, expect, it } from 'vitest'
import { createAdminService } from './service'
import { createLegacySeed } from './legacySeed'

const siteId = 'site-1'
let api
function seedOrganizationTree() {
  const state = createLegacySeed()
  state.organizations = [
    { id: 'root', parentId: null },
    { id: 'child', parentId: 'root' },
    { id: 'grandchild', parentId: 'child' },
    { id: 'disabled-child', parentId: 'root', enabled: false },
    { id: 'other-root', parentId: null },
    { id: 'foreign-child', parentId: 'root', siteId: 'site-2' },
    { id: 'invalid-bridge', parentId: 'foreign-child' },
    { id: 'cycle-a', parentId: 'cycle-b' },
    { id: 'cycle-b', parentId: 'cycle-a' }
  ].map(organization => ({ name: organization.id, code: organization.id, siteId, enabled: true, version: 1, ...organization }))
  state.people = [
    { id: 'person-root', organizationId: 'root' },
    { id: 'person-child', organizationId: 'child' },
    { id: 'person-grandchild', organizationId: 'grandchild', name: '孙级人员' },
    { id: 'person-disabled', organizationId: 'disabled-child', enabled: false },
    { id: 'person-other', organizationId: 'other-root' },
    { id: 'person-foreign', organizationId: 'foreign-child', siteId: 'site-2' },
    { id: 'person-foreign-root-link', organizationId: 'root', siteId: 'site-2' },
    { id: 'person-bridge', organizationId: 'invalid-bridge' },
    { id: 'person-cycle-a', organizationId: 'cycle-a' },
    { id: 'person-cycle-b', organizationId: 'cycle-b' },
    { id: 'person-unassigned', organizationId: null }
  ].map(person => ({ name: person.id, code: person.id, siteId, enabled: true, version: 1, ...person }))
  return state
}
function setup(seed = seedOrganizationTree) {
  const values = new Map()
  api = createAdminService({ delay: 0, seed, storage: { getItem: key => values.get(key), setItem: (key, value) => values.set(key, value), removeItem: key => values.delete(key) } })
  api.login('demo-system', 'Admin@2026')
}
beforeEach(() => setup())
const people = async (input = {}) => (await api.query('master', { siteId, entity: 'people', pageSize: 100, ...input })).data
const ids = result => result.rows.map(row => row.id)

describe('organization subtree personnel queries', () => {
  it('preserves exact matching unless includeDescendants is explicitly true', async () => {
    for (const input of [{}, { includeDescendants: false }, { includeDescendants: 'true' }]) expect(ids(await people({ organizationId: 'root', ...input }))).toEqual(['person-root'])
    expect(ids(await people({ organizationId: 'root', includeDescendants: true }))).toEqual(['person-root', 'person-child', 'person-grandchild', 'person-disabled'])
    expect(ids(await people({ organizationId: 'child', includeDescendants: true }))).toEqual(['person-child', 'person-grandchild'])
  })

  it('keeps status, keyword and pagination filters within the selected subtree', async () => {
    const input = { organizationId: 'root', includeDescendants: true }
    expect(ids(await people({ ...input, status: 'enabled' }))).toEqual(['person-root', 'person-child', 'person-grandchild'])
    expect(ids(await people({ ...input, status: 'disabled' }))).toEqual(['person-disabled'])
    expect(ids(await people({ ...input, keyword: '孙级' }))).toEqual(['person-grandchild'])
    const secondPage = await people({ ...input, pageSize: 2, pageNum: 2 })
    expect(secondPage.total).toBe(4)
    expect(ids(secondPage)).toEqual(['person-grandchild', 'person-disabled'])
  })

  it('never crosses sites through malformed organization or personnel references', async () => {
    const input = { includeDescendants: true }
    expect(ids(await people({ ...input, organizationId: 'root' }))).toEqual(['person-root', 'person-child', 'person-grandchild', 'person-disabled'])
    expect(ids(await people({ ...input, organizationId: 'foreign-child' }))).toEqual([])
    expect(ids(await people({ ...input, organizationId: 'missing-root' }))).toEqual([])
    api.login('demo-site', 'Admin@2026')
    await expect(people({ ...input, siteId: 'site-2', organizationId: 'foreign-child' })).rejects.toMatchObject({ code: 403 })
  })

  it('does not traverse organizations the actor cannot read', async () => {
    setup(() => {
      const state = seedOrganizationTree()
      state.roles.push({ id: 'people-only', enabled: true, grants: [{ operations: ['overview:read', 'people:read'], siteIds: [siteId] }] })
      state.accounts.push({ id: 'people-only-user', loginName: 'people-only-user', enabled: true, credentialVersion: 1, roleIds: ['people-only'] })
      return state
    })
    api.login('people-only-user', 'Admin@2026')
    expect(ids(await people({ organizationId: 'root', includeDescendants: true }))).toEqual([])
    expect(ids(await people({ organizationId: 'root' }))).toEqual(['person-root'])
  })

  it('terminates safely and returns each person once for a cyclic legacy tree', async () => {
    expect(ids(await people({ organizationId: 'cycle-a', includeDescendants: true }))).toEqual(['person-cycle-a', 'person-cycle-b'])
    expect(ids(await people({ organizationId: 'cycle-b', includeDescendants: true }))).toEqual(['person-cycle-a', 'person-cycle-b'])
  })
})
