import { beforeEach, describe, expect, it } from 'vitest'
import { createAdminService } from './service'
import { createLegacySeed } from './legacySeed'

let api, serial
const siteId = 'site-1'
function setup(seed = createLegacySeed) {
  const values = new Map()
  api = createAdminService({ delay: 0, seed, storage: { getItem: key => values.get(key), setItem: (key, value) => values.set(key, value), removeItem: key => values.delete(key) } })
  api.login('demo-system', 'Admin@2026')
  serial = 0
}
beforeEach(() => setup())
const query = async (kind, input = {}) => (await api.query(kind, { siteId, ...input })).data
const execute = async (type, input) => (await api.execute(type, { siteId, operationId: `inherit-${++serial}`, ...input })).data
const createAccount = (loginName, role, extra = {}) => execute('accounts.create', { relatedVersions: role ? { [role.id]: role.version } : {}, data: { name: loginName, loginName, bindings: role ? [{ roleId: role.id }] : [], ...extra } })
async function checkSites(account, sites) {
  api.login(account.id, 'Admin@2026')
  expect((await query('context')).sites.map(site => site.id)).toEqual(sites)
}

describe('accounts inherit the complete current role grants', () => {
  it('previews and applies role site additions and removals to every bound account', async () => {
    let role = await execute('roles.create', { data: { name: '共享角色', operations: ['people:read'], siteIds: [siteId] } })
    const accounts = [await createAccount('inherit-first', role), await createAccount('inherit-second', role)]
    for (const account of accounts) {
      expect(account).not.toHaveProperty('roleScopes')
      await checkSites(account, [siteId])
    }
    api.login('demo-system', 'Admin@2026')
    for (const sites of [[siteId, 'site-2'], ['site-2']]) {
      const input = { siteId, id: role.id, expectedVersion: role.version, operationId: `role-sites-${role.version}`, data: { name: role.name, operations: ['people:read'], siteIds: sites } }
      const preview = await query('authorizationPreview', { type: 'roles.update', command: input })
      expect(preview.required).toBe(true)
      expect(preview.accounts.map(account => account.id).sort()).toEqual(accounts.map(account => account.id).sort())
      for (const effect of preview.accounts) {
        if (sites.length === 2) expect(effect.added).toEqual(expect.arrayContaining([expect.objectContaining({ siteId: 'site-2', operation: 'people:read' })]))
        else {
          expect(effect.removed).toEqual(expect.arrayContaining([expect.objectContaining({ siteId, operation: 'people:read' })]))
          expect(effect.lostSites).toEqual([expect.objectContaining({ id: siteId })])
        }
      }
      role = await execute('roles.update', { ...input, previewId: preview.previewId })
      for (const account of accounts) await checkSites(account, sites)
      api.login('demo-system', 'Admin@2026')
      for (const account of accounts) expect((await query('record', { entity: 'accounts', id: account.id })).version).toBe(account.version)
    }
  })

  it('ignores legacy account scopes and removes them on a normal same-role save', async () => {
    setup(() => {
      const state = createLegacySeed()
      state.accounts.push({ id: 'legacy-scope-user', name: '旧范围账号', loginName: 'legacy-scope-user', siteId, enabled: true, version: 1, credentialVersion: 1, roleIds: ['viewer'], roleScopes: { viewer: { siteIds: [siteId] } } })
      return state
    })
    const account = await query('record', { entity: 'accounts', id: 'legacy-scope-user' })
    await checkSites(account, [siteId, 'site-2', 'site-empty'])
    api.login('demo-system', 'Admin@2026')
    const input = { siteId, id: account.id, expectedVersion: account.version, relatedVersions: { viewer: 1 }, data: { name: '旧账号更名', loginName: account.loginName, bindings: [{ roleId: 'viewer' }] } }
    const preview = await query('authorizationPreview', { type: 'accounts.update', command: input })
    expect(preview.required).toBe(false)
    expect(preview.accounts[0]).toMatchObject({ added: [], removed: [], lostSites: [] })
    const saved = await execute('accounts.update', input)
    expect(saved).not.toHaveProperty('roleScopes')
    await checkSites(saved, [siteId, 'site-2', 'site-empty'])
  })

  it('ignores client-supplied account scope fields instead of persisting them', async () => {
    const role = await execute('roles.create', { data: { name: '角色决定厂站', operations: ['people:read'], siteIds: ['site-2'] } })
    const account = await createAccount('legacy-payload', role, { bindings: [{ roleId: role.id, siteIds: ['not-a-site'], areaIds: [] }], roleScopes: { [role.id]: { siteIds: [siteId] } } })
    expect(account.roleIds).toEqual([role.id])
    expect(account).not.toHaveProperty('roleScopes')
    await checkSites(account, ['site-2'])
    expect(api.can('people:read', siteId)).toBe(false)
  })

  it('rejects delegation outside any role site even when the request supplies a narrower scope', async () => {
    const target = await createAccount('delegation-target')
    api.login('demo-site', 'Admin@2026')
    for (const binding of [{ roleId: 'viewer' }, { roleId: 'viewer', siteIds: [siteId] }, { roleId: 'viewer', siteIds: [] }]) {
      const data = { name: '禁止越权', loginName: 'narrowed-delegation', bindings: [binding] }
      await expect(execute('accounts.create', { relatedVersions: { viewer: 1 }, data })).rejects.toMatchObject({ fields: { bindings: expect.any(String) } })
      await expect(query('authorizationPreview', { type: 'accounts.update', command: { siteId, id: target.id, expectedVersion: target.version, relatedVersions: { viewer: 1 }, data: { ...data, loginName: target.loginName } } })).rejects.toMatchObject({ fields: { bindings: expect.any(String) } })
    }
    expect((await query('record', { entity: 'accounts', id: target.id })).roleIds).toEqual([])
  })

  it('checks every grant operation and site when delegating a role', async () => {
    setup(() => {
      const state = createLegacySeed()
      state.roles.find(role => role.id === 'site').grants.push({ operations: ['overview:read', 'access:read', 'accounts:write'], siteIds: ['site-2'] })
      state.roles.find(role => role.id === 'viewer').grants = [
        { operations: ['overview:read'], siteIds: [siteId] },
        { operations: ['assets:write'], siteIds: ['site-2'] }
      ]
      return state
    })
    api.login('demo-site', 'Admin@2026')
    await expect(execute('accounts.create', { relatedVersions: { viewer: 1 }, data: { name: '不能转授设备写权限', loginName: 'grant-operation-check', bindings: [{ roleId: 'viewer', siteIds: [siteId] }] } })).rejects.toMatchObject({ fields: { bindings: expect.any(String) } })
  })

  it('does not let legacy account scopes conceal stronger role permissions during management', async () => {
    setup(() => {
      const state = createLegacySeed()
      state.accounts.push({ id: 'legacy-stronger', name: '完整角色超出范围', loginName: 'legacy-stronger', siteId, enabled: true, version: 1, roleIds: ['viewer'], roleScopes: { viewer: { siteIds: [siteId] } } })
      return state
    })
    api.login('demo-site', 'Admin@2026')
    for (const type of ['accounts.update', 'accounts.delete', 'accounts.status']) {
      await expect(execute(type, { id: 'legacy-stronger', expectedVersion: 1, enabled: false, data: { name: '尝试更名', loginName: 'legacy-stronger', bindings: [] } })).rejects.toMatchObject({ code: 404 })
    }
  })
})
