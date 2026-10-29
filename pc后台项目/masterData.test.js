import { beforeEach, describe, expect, it, vi } from 'vitest'
import { createAdminService } from './service'
import { localTime, toUtc } from './time'
import { createLegacySeed as createSeed } from './legacySeed'
import { safeTarget, peopleReturn } from './navigation'
let api, serial
const siteId = 'site-empty'
function resetService(seed = createSeed) {
  const items = new Map()
  api = createAdminService({ delay: 0, now: () => '2026-09-19T08:00:00Z', seed, storage: { getItem: k => items.get(k), setItem: (k, v) => items.set(k, v), removeItem: k => items.delete(k) } })
  api.login('demo-system', 'Admin@2026'); serial = 0
}
beforeEach(() => resetService())
const query = async (entity, extra = {}) => (await api.query('master', { entity, siteId, pageSize: 100, ...extra })).data
const command = async (entity, action, data, extra = {}) => {
  const choices = (await api.query('options', { siteId: extra.siteId || siteId })).data
  const relatedVersions = Object.fromEntries(Object.values(choices).flat().map(r => [r.id, r.version]))
  const type = `${entity}.${action}`, input = { siteId, operationId: `test-${++serial}`, relatedVersions, data, ...extra }
  if (['accounts.update', 'roles.update', 'roles.status'].includes(type)) input.previewId = (await api.query('authorizationPreview', { siteId: input.siteId, type, command: input })).data.previewId
  return (await api.execute(type, input)).data
}
const create = (entity, data, extra) => command(entity, 'create', data, extra)
const update = (entity, row, data, extra) => command(entity, 'update', data, { id: row.id, expectedVersion: row.version, ...extra })
const status = (entity, row, enabled, extra) => command(entity, 'status', null, { id: row.id, expectedVersion: row.version, enabled, ...extra })
const person = (code = 'TEST-P') => create('people', { name: '预置同名人员', code })
const account = () => create('accounts', { name: '预置自定义账号', loginName: `test-${serial}` })
const scope = (roleId, sid = siteId, areaIds = '*') => ({ roleId, siteIds: [sid], areaIds })
async function grant(row, roleId = 'viewer', sid = siteId, areaIds = '*') {
  return update('accounts', row, { ...row, bindings: [scope(roleId, sid, areaIds)] }, { relatedVersions: { [roleId]: 1 }, siteId: row.siteId })
}
describe('A1 master data', () => {
  it('retires area maintenance and filters while preserving organization management', async () => {
    await expect(query('areas')).rejects.toMatchObject({ code: 400 })
    await expect(create('areas', { name: '旧区域', code: 'OLD' })).rejects.toMatchObject({ code: 400 })
    const options = (await api.query('options', { siteId })).data
    expect(options).not.toHaveProperty('areas')
    expect(options).not.toHaveProperty('scopeAreas')
    const org = await create('organizations', { name: '检修班', code: 'ORG' })
    const p = await create('people', { name: '检修人员', code: 'P', organizationId: org.id, areaId: 'retired-area' })
    expect(p.organizationId).toBe(org.id)
    expect(p).not.toHaveProperty('areaId')
    expect((await query('people', { areaId: 'unrelated-area' })).total).toBe(1)
  })
  it('creates a new site without granting other roles', async () => {
    const row = await create('sites', { name: '预置新厂站', code: 'NEW', timezone: 'Asia/Shanghai' })
    expect((await api.query('context')).data.sites.some(s => s.id === row.id)).toBe(true)
    await person(); api.login('demo-site', 'Admin@2026')
    expect((await api.query('context')).data.sites).toHaveLength(1)
  })
  it('preserves equipment baseline when adding independent people', async () => {
    await person(); expect((await query('people')).total).toBe(1)
    expect((await api.query('devices', { siteId: 'site-1' })).data.total).toBe(36)
  })
  it('allows duplicate names but not identifiers', async () => {
    await person('ONE'); await person('TWO'); await expect(person('one')).rejects.toMatchObject({ code: 409, fields: { code: expect.any(String) } })
  })
  it('rejects cross-site references without partial changes', async () => {
    await expect(create('people', { name: '预置', code: 'P', organizationId: 'organization-1' })).rejects.toMatchObject({ code: 400 })
    expect((await query('people')).total).toBe(0); expect((await api.query('audit', { siteId })).data.total).toBe(0)
  })
  it('rejects tree cycles and referenced nodes', async () => {
    const root = await create('organizations', { name: '预置根', code: 'ROOT' })
    const child = await create('organizations', { name: '预置叶', code: 'LEAF', parentId: root.id })
    await expect(update('organizations', root, { ...root, parentId: child.id })).rejects.toMatchObject({ fields: { parentId: expect.any(String) } })
    await expect(command('organizations', 'delete', null, { id: root.id, expectedVersion: root.version })).rejects.toMatchObject({ code: 409, impacts: expect.any(Array) })
  })
  it('deletes only an unreferenced leaf while retaining audit snapshots', async () => {
    const leaf = await create('organizations', { name: '预置可删除叶', code: 'LEAF' })
    await command('organizations', 'delete', null, { id: leaf.id, expectedVersion: leaf.version })
    expect((await query('organizations')).total).toBe(0)
    expect((await api.query('audit', { siteId })).data.total).toBe(2)
  })
  it('reference version changes reject an otherwise valid new person', async () => {
    const area = await create('organizations', { name: '预置区域', code: 'AREA' })
    await update('organizations', area, { ...area, name: '已变化' })
    await expect(create('people', { name: '预置', code: 'V', organizationId: area.id }, { relatedVersions: { [area.id]: 1 } })).rejects.toMatchObject({ errorCode: 'VERSION_CONFLICT' })
    expect((await query('people')).total).toBe(0)
  })
  it('protects persons with active assignments, including conflict links', async () => {
    for (const id of ['person-1-0', 'person-1-20']) await expect(command('people', 'status', null, { id, siteId: 'site-1', expectedVersion: 1, enabled: false })).rejects.toMatchObject({ code: 409 })
  })
  it('future duty blocks stopping members; cancelling releases dependency', async () => {
    const p = await person()
    const shift = await create('dutyShifts', { name: '预置未来班', startsAt: '2027-01-01T00:00:00Z', endsAt: '2027-01-01T08:00:00Z', personIds: [p.id] })
    await expect(status('people', p, false)).rejects.toMatchObject({ code: 409 })
    await status('dutyShifts', shift, false); expect((await status('people', p, false)).enabled).toBe(false)
  })
  it('rejects duplicate members and invalid duty time', async () => {
    const p = await person(), data = { name: '预置', startsAt: '2027-01-01T00:00:00Z', endsAt: '2027-01-01T08:00:00Z', personIds: [p.id, p.id] }
    await expect(create('dutyShifts', data)).rejects.toMatchObject({ code: 400 })
    await expect(create('dutyShifts', { ...data, personIds: [p.id], endsAt: data.startsAt })).rejects.toMatchObject({ code: 400 })
  })
  it('started shift cannot be edited or cancelled', async () => {
    const row = (await query('dutyShifts', { siteId: 'site-1' })).rows[0]
    await expect(update('dutyShifts', row, row, { siteId: 'site-1' })).rejects.toMatchObject({ code: 409 })
    await expect(status('dutyShifts', row, false, { siteId: 'site-1' })).rejects.toMatchObject({ code: 409 })
  })
  it('historical audit snapshots do not change on rename', async () => {
    const row = await person(); await update('people', row, { ...row, name: '新名字' })
    const audit = (await api.query('audit', { siteId })).data.rows
    expect(audit.find(a => a.action === 'people.create').after.name).toBe('预置同名人员')
  })
  it('new command idempotency and changed input conflict', async () => {
    const input = { siteId, operationId: 'once', data: { name: '预置', code: 'ONCE' } }
    const first = await api.execute('people.create', input)
    expect(await api.execute('people.create', input)).toEqual(first)
    await expect(api.execute('people.create', { ...input, data: { name: '其他', code: 'OTHER' } })).rejects.toMatchObject({ code: 409 })
    expect((await query('people')).total).toBe(1)
  })
  it('old version and cancellation cannot append audit', async () => {
    const p = await person(); await update('people', p, { ...p, name: '新' })
    await expect(update('people', p, p)).rejects.toMatchObject({ errorCode: 'VERSION_CONFLICT' })
    const c = new AbortController(); c.abort()
    await expect(api.execute('people.create', { siteId, operationId: 'abort' }, { signal: c.signal })).rejects.toMatchObject({ name: 'AbortError' })
    expect((await api.query('audit', { siteId })).data.total).toBe(2)
  })
  it('notification exception never turns committed change into failure', async () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    api.subscribe(() => { throw new Error('observer failure') })
    expect((await person()).id).toBeTruthy(); expect((await query('people')).total).toBe(1); spy.mockRestore()
  })
})
describe('A1 accounts and authorization', () => {
  it('new account starts without authorization and is selectable', async () => {
    const a = await account(); expect(api.identities().some(x => x.id === a.id)).toBe(true)
    api.login(a.id, 'Admin@2026'); expect((await api.query('context')).data.sites).toEqual([])
  })
  it('creates an account with one role and lets multiple users share that role', async () => {
    const bindings = [{ roleId: 'people-editor' }]
    const first = await create('accounts', { name: '人员维护甲', loginName: 'shared-role-first', bindings })
    const second = await create('accounts', { name: '人员维护乙', loginName: 'shared-role-second', bindings })
    for (const row of [first, second]) {
      expect(row.roleIds).toEqual(['people-editor'])
      expect(row).not.toHaveProperty('roleScopes')
      api.login(row.id, 'Admin@2026')
      expect(api.can('people:write', siteId)).toBe(true)
      expect((await api.query('context')).data.sites.map(site => site.id)).toEqual(['site-1', 'site-2', siteId])
    }
  })
  it('replaces a users role instead of accumulating roles and allows clearing it', async () => {
    const first = await create('accounts', { name: '可改绑用户', loginName: 'replace-role', bindings: [scope('people-editor')] })
    const replacement = await grant(first, 'viewer')
    expect(replacement.roleIds).toEqual(['viewer'])
    expect(replacement).not.toHaveProperty('roleScopes')
    api.login(replacement.id, 'Admin@2026')
    expect(api.can('people:write', siteId)).toBe(false)
    api.login('demo-system', 'Admin@2026')
    const cleared = await update('accounts', replacement, { ...replacement, bindings: [] })
    expect(cleared.roleIds).toEqual([])
    expect(cleared).not.toHaveProperty('roleScopes')
    api.login(cleared.id, 'Admin@2026')
    expect((await api.query('context')).data.sites).toEqual([])
  })
  it('rejects multiple roles on create and update without changing existing authorization', async () => {
    const bindings = [scope('viewer'), scope('people-editor')]
    await expect(create('accounts', { name: '无效多角色', loginName: 'too-many-create', bindings })).rejects.toMatchObject({ errorCode: 'VALIDATION_ERROR', fields: { bindings: '每个用户最多只能绑定一个角色' } })
    expect((await query('accounts')).total).toBe(0)
    const existing = await create('accounts', { name: '现有单角色', loginName: 'too-many-update', bindings: [scope('viewer')] })
    await expect(update('accounts', existing, { ...existing, bindings })).rejects.toMatchObject({ errorCode: 'VALIDATION_ERROR', fields: { bindings: '每个用户最多只能绑定一个角色' } })
    expect((await query('accounts')).rows).toEqual([existing])
    expect((await api.query('audit', { siteId })).data.total).toBe(1)
  })
  it('rejects malformed role binding values with a field error', async () => {
    const existing = await account()
    for (const bindings of [null, false, '', {}, [null], ['viewer'], [[]], [{}], [{ roleId: 1 }], [{ roleId: '' }]]) {
      await expect(create('accounts', { name: '格式错误', loginName: 'malformed-create', bindings })).rejects.toMatchObject({ errorCode: 'VALIDATION_ERROR', fields: { bindings: expect.any(String) } })
      await expect(update('accounts', existing, { ...existing, bindings })).rejects.toMatchObject({ errorCode: 'VALIDATION_ERROR', fields: { bindings: expect.any(String) } })
    }
    expect((await query('accounts')).rows).toEqual([existing])
  })
  it('keeps role version, scope and delegation checks when assigning during creation', async () => {
    resetService(() => { const state = createSeed(); state.roles.find(role => role.id === 'viewer').grants[0].siteIds = ['site-1']; return state })
    const data = { name: '创建授权检查', loginName: 'create-role-check', bindings: [scope('viewer')] }
    await expect(create('accounts', data, { relatedVersions: { viewer: 0 } })).rejects.toMatchObject({ errorCode: 'VERSION_CONFLICT' })
    await expect(create('accounts', { ...data, bindings: [scope('system')] })).rejects.toMatchObject({ fields: { bindings: expect.any(String) } })
    api.login('demo-site', 'Admin@2026')
    const delegated = await create('accounts', { ...data, bindings: [scope('viewer', 'site-1')] }, { siteId: 'site-1' })
    expect(delegated.roleIds).toEqual(['viewer'])
    await expect(create('accounts', { ...data, loginName: 'create-role-too-high', bindings: [scope('site', 'site-1')] }, { siteId: 'site-1' })).rejects.toMatchObject({ fields: { bindings: expect.any(String) } })
    await expect(create('accounts', { ...data, loginName: 'create-role-outside', bindings: [scope('people-editor', 'site-1')] }, { siteId: 'site-1' })).rejects.toMatchObject({ fields: { bindings: expect.any(String) } })
  })
  it('optional association is one-to-one and stopping account preserves person', async () => {
    let p = await person(), a = await account()
    a = await update('accounts', a, { ...a, personId: p.id }, { relatedVersions: { [p.id]: p.version } })
    p = (await query('people')).rows[0]; expect(p.accountId).toBe(a.id)
    const other = await account()
    await expect(update('accounts', other, { ...other, personId: p.id }, { relatedVersions: { [p.id]: p.version } })).rejects.toMatchObject({ code: 409 })
    await status('accounts', a, false); expect((await query('people')).rows[0].enabled).toBe(true)
  })
  it('association version conflict rolls back both sides', async () => {
    const p = await person(), a = await account()
    await expect(update('accounts', a, { ...a, personId: p.id }, { relatedVersions: { [p.id]: 0 } })).rejects.toMatchObject({ code: 409 })
    expect((await query('people')).rows[0].accountId).toBe(null)
  })
  it('deletes a linked account while retaining the person, equipment, roles and audit snapshots', async () => {
    const currentSite = 'site-1'
    const p = (await query('people', { siteId: currentSite })).rows[0]
    let a = await create('accounts', { name: '待删除用户', loginName: 'remove-linked' }, { siteId: currentSite })
    a = await update('accounts', a, { ...a, personId: p.id, bindings: [scope('viewer', currentSite)] }, { siteId: currentSite })
    const before = (await api.query('person', { siteId: currentSite, id: p.id })).data
    const roles = (await query('roles', { siteId: currentSite })).rows
    const removed = await command('accounts', 'delete', null, { siteId: currentSite, id: a.id, expectedVersion: a.version })
    expect(removed).toMatchObject({ id: a.id, deleted: true })
    expect(api.identities().some(row => row.id === a.id)).toBe(false)
    expect(() => api.login(a.id, 'Admin@2026')).toThrow()
    const after = (await api.query('person', { siteId: currentSite, id: p.id })).data
    expect(after).toMatchObject({ id: p.id, enabled: before.enabled, accountId: null, version: before.version + 1, equipment: before.equipment })
    expect((await query('roles', { siteId: currentSite })).rows).toEqual(roles)
    const audit = (await api.query('audit', { siteId: currentSite })).data.rows
    expect(audit.find(row => row.action === 'accounts.create' && row.objectId === a.id).after.name).toBe(a.name)
    expect(audit.find(row => row.action === 'accounts.delete' && row.objectId === a.id)).toMatchObject({ before: { id: a.id }, after: { id: a.id, deleted: true } })
  })
  it('rejects stale deletion and replays a successful delete only once', async () => {
    const a = await account()
    const current = await update('accounts', a, { ...a, name: '删除前已更新' })
    await expect(command('accounts', 'delete', null, { id: a.id, expectedVersion: a.version })).rejects.toMatchObject({ errorCode: 'VERSION_CONFLICT' })
    expect((await query('accounts')).rows).toHaveLength(1)
    const input = { siteId, id: current.id, expectedVersion: current.version, operationId: 'delete-once' }
    const result = await api.execute('accounts.delete', input)
    expect(await api.execute('accounts.delete', input)).toEqual(result)
    await expect(api.execute('accounts.delete', { ...input, expectedVersion: a.version })).rejects.toMatchObject({ errorCode: 'IDEMPOTENCY_CONFLICT' })
    expect((await api.query('audit', { siteId })).data.rows.filter(row => row.action === 'accounts.delete')).toHaveLength(1)
  })
  it('blocks deletion for open repairs and preserves closed repair history', async () => {
    for (const orderStatus of ['OPEN', 'CLOSED']) {
      const state = createSeed()
      state.maintenanceOrders.push({ id: 'account-repair', siteId: 'site-1', deviceId: state.devices[0].id, areaId: state.devices[0].areaId, status: orderStatus, handlerId: 'demo-asset', handlerName: '资产管理员', version: 1 })
      resetService(() => state)
      const input = { siteId: 'site-1', id: 'demo-asset', expectedVersion: 1 }
      const refs = (await api.query('impacts', { ...input, entity: 'accounts', all: true })).data.rows
      if (orderStatus === 'OPEN') {
        expect(refs).toEqual([expect.objectContaining({ id: 'account-repair' })])
        await expect(command('accounts', 'delete', null, input)).rejects.toMatchObject({ errorCode: 'REFERENCED', impacts: refs })
        expect(api.identities().some(row => row.id === 'demo-asset')).toBe(true)
      } else {
        expect(refs).toEqual([])
        await command('accounts', 'delete', null, input)
        expect(api.identities().some(row => row.id === 'demo-asset')).toBe(false)
      }
      const retainedOrder = (await api.query('maintenanceOrder', { siteId: 'site-1', id: 'account-repair' })).data
      expect(retainedOrder).toMatchObject({ status: orderStatus, handlerId: 'demo-asset', handlerName: '资产管理员' })
    }
  })
  it('protects system, current, stronger and out-of-scope accounts from deletion', async () => {
    await expect(command('accounts', 'delete', null, { siteId: 'site-1', id: 'demo-system', expectedVersion: 1 })).rejects.toMatchObject({ errorCode: 'BUILTIN_PROTECTED' })
    const a = await account()
    api.login('demo-site', 'Admin@2026')
    await expect(command('accounts', 'delete', null, { siteId: 'site-1', id: 'demo-site', expectedVersion: 1 })).rejects.toMatchObject({ code: 403 })
    await expect(command('accounts', 'delete', null, { siteId: 'site-1', id: 'demo-asset', expectedVersion: 1 })).rejects.toMatchObject({ code: 404 })
    await expect(api.execute('accounts.delete', { siteId, id: a.id, expectedVersion: a.version, operationId: 'outside' })).rejects.toMatchObject({ code: 403 })
    api.login('demo-audit', 'Admin@2026')
    await expect(api.execute('accounts.delete', { siteId, id: a.id, expectedVersion: a.version, operationId: 'readonly' })).rejects.toMatchObject({ code: 404 })
  })
  it('rechecks delegated write permission before replaying a deleted account', async () => {
    let manager = await create('accounts', { name: '临时管理用户', loginName: 'delete-manager' }, { siteId: 'site-1' })
    manager = await grant(manager, 'site', 'site-1')
    const target = await create('accounts', { name: '委派删除目标', loginName: 'delete-target' }, { siteId: 'site-1' })
    api.login(manager.id, 'Admin@2026')
    const input = { siteId: 'site-1', id: target.id, expectedVersion: target.version, operationId: 'delegated-delete' }
    await api.execute('accounts.delete', input)
    api.login('demo-system', 'Admin@2026')
    await grant(manager, 'viewer', 'site-1')
    api.login(manager.id, 'Admin@2026')
    await expect(api.execute('accounts.delete', input)).rejects.toMatchObject({ code: 404 })
  })
  it('invalid role after association validation rolls back the person change', async () => {
    const p = await person(), a = await account()
    await expect(update('accounts', a, { ...a, personId: p.id, bindings: [scope('system')] }, { relatedVersions: { [p.id]: p.version, system: 1 } })).rejects.toMatchObject({ code: 400 })
    const unchanged = (await query('people')).rows[0]
    expect(unchanged.accountId).toBe(null); expect(unchanged.version).toBe(p.version)
  })
  it('built-in system and roles cannot be edited', async () => {
    await expect(command('accounts', 'status', null, { siteId: 'site-1', id: 'demo-system', expectedVersion: 1, enabled: false })).rejects.toMatchObject({ code: 403 })
    await expect(command('roles', 'status', null, { id: 'site', expectedVersion: 1, enabled: false })).rejects.toMatchObject({ code: 403 })
  })
  it('site administrator delegates only predefined roles within its full scope', async () => {
    resetService(() => { const state = createSeed(); state.roles.find(role => role.id === 'viewer').grants[0].siteIds = ['site-1']; return state })
    api.login('demo-site', 'Admin@2026')
    const a = await create('accounts', { name: '预置站员', loginName: 'delegated' }, { siteId: 'site-1' })
    await grant(a, 'viewer', 'site-1')
    await expect(grant({ ...a, version: 2 }, 'people-editor', 'site-1')).rejects.toMatchObject({ code: 400 })
    await expect(grant({ ...a, version: 2 }, 'site', 'site-1')).rejects.toMatchObject({ code: 400 })
  })
  it('site administrator cannot remove roles to take over stronger account', async () => {
    let a = await create('accounts', { name: '高权限本地', loginName: 'higher' }, { siteId: 'site-1' })
    a = await grant(a, 'site', 'site-1'); api.login('demo-site', 'Admin@2026')
    await expect(update('accounts', a, { ...a, bindings: [] }, { siteId: 'site-1' })).rejects.toMatchObject({ code: 404 })
  })
  it('legacy area bindings use the assigned site without granting other sites', async () => {
    const role = await create('roles', { name: '预置区域只读', operations: ['overview:read', 'assets:read', 'people:read', 'organization:read'], siteIds: ['site-1'], areaIds: ['area-1'] })
    let a = await account(); a = await grant(a, role.id, 'site-1', ['area-1'])
    api.login(a.id, 'Admin@2026')
    expect((await api.query('context')).data.sites).toHaveLength(1)
    expect((await api.query('devices', { siteId: 'site-1' })).data.total).toBe(36)
    await expect(api.query('devices', { siteId: 'site-2' })).rejects.toMatchObject({ code: 403 })
  })
  it('role disable immediately removes authorization', async () => {
    const role = await create('roles', { name: '预置角色', operations: ['people:read'], siteIds: [siteId], areaIds: '*' })
    let a = await account(); a = await grant(a, role.id)
    await status('roles', role, false); api.login(a.id, 'Admin@2026')
    expect((await api.query('context')).data.sites).toHaveLength(0)
  })
  it('readonly account cannot write', async () => {
    api.login('demo-audit', 'Admin@2026'); await expect(person()).rejects.toMatchObject({ code: 403 })
  })
  it('legacy area scope no longer hides same-site records or permits other sites', async () => {
    const state = createSeed()
    state.areas.push({ id: 'other-area', siteId: 'site-1', enabled: true, version: 1 })
    state.devices[0].areaId = 'other-area'; state.devices[1].areaId = null
    state.people[0].areaId = 'other-area'; state.people[1].areaId = null
    state.roles.push({ id: 'scoped', enabled: true, grants: [{ operations: ['overview:read', 'assets:read', 'people:read'], siteIds: ['site-1'], areaIds: ['area-1'] }] })
    state.accounts.push({ id: 'scoped-user', enabled: true, roleIds: ['scoped'] })
    const scoped = createAdminService({ seed: () => state, delay: 0, storage: { getItem: key => key.endsWith('Session-Version') ? '1' : 'scoped-user', removeItem: () => {} } })
    expect((await scoped.query('devices', { siteId: 'site-1' })).data.total).toBe(36)
    expect((await scoped.query('master', { entity: 'people', siteId: 'site-1' })).data.total).toBe(25)
    expect((await scoped.query('person', { siteId: 'site-1', id: 'person-1-0' })).data.id).toBe('person-1-0')
    expect((await scoped.query('person', { siteId: 'site-1', id: 'person-1-1' })).data.id).toBe('person-1-1')
    await expect(scoped.query('person', { siteId: 'site-2', id: 'person-2-0' })).rejects.toMatchObject({ code: 403 })
  })
  it('unknown identity after refresh returns login state', async () => {
    const a = await account()
    const fresh = createAdminService({ delay: 0, storage: { getItem: () => a.id, removeItem: () => {} } })
    expect(fresh.identity()).toBe(null)
  })
})
describe('explicit timezone', () => {
  it('converts Shanghai independently of browser timezone', () => { expect(toUtc('2027-01-01T08:00', 'Asia/Shanghai')).toBe('2027-01-01T00:00:00.000Z'); expect(localTime('2027-01-01T00:00:00Z', 'Asia/Shanghai')).toBe('2027-01-01T08:00') })
  it('rejects DST ambiguous and nonexistent local time', () => { expect(() => toUtc('2027-03-14T02:30', 'America/New_York')).toThrow(); expect(() => toUtc('2027-11-07T01:30', 'America/New_York')).toThrow() })
  it('restores long person/site IDs and safe list filters only', () => {
    expect(safeTarget('/people/19007199254740993000?siteId=sites-19007199254740993-1&token=secret')).toBe('/people/19007199254740993000?siteId=sites-19007199254740993-1')
    expect(peopleReturn('https://evil.invalid')).toBe('/people')
    expect(peopleReturn('/people?siteId=site-1&pageNum=2')).toContain('pageNum=2')
  })
})
