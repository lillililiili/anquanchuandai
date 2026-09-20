import { beforeEach, describe, expect, it, vi } from 'vitest'
import { createAdminService } from './service'
import { localTime, toUtc } from './time'
import { createSeed } from './seed'
import { safeTarget, peopleReturn } from './navigation'
let api, serial
const siteId = 'site-empty'
beforeEach(() => {
  const items = new Map()
  api = createAdminService({ delay: 0, now: () => '2026-09-19T08:00:00Z', storage: { getItem: k => items.get(k), setItem: (k, v) => items.set(k, v), removeItem: k => items.delete(k) } })
  api.login('demo-system', 'Admin@2026'); serial = 0
})
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
  it('creates a new site without granting other roles', async () => {
    const row = await create('sites', { name: '预置新厂站', code: 'NEW', timezone: 'Asia/Shanghai' })
    expect((await api.query('context')).data.sites.some(s => s.id === row.id)).toBe(true)
    await person(); api.login('demo-site', 'Admin@2026')
    expect((await api.query('context')).data.sites).toHaveLength(1)
  })
  it('preserves equipment baseline when adding independent people', async () => {
    await person(); expect((await query('people')).total).toBe(1)
    expect((await api.query('overview', { siteId: 'site-1' })).data.counts.assets).toBe(36)
  })
  it('allows duplicate names but not identifiers', async () => {
    await person('ONE'); await person('TWO'); await expect(person('one')).rejects.toMatchObject({ code: 409, fields: { code: expect.any(String) } })
  })
  it('rejects cross-site references without partial changes', async () => {
    await expect(create('people', { name: '预置', code: 'P', areaId: 'area-1' })).rejects.toMatchObject({ code: 400 })
    expect((await query('people')).total).toBe(0); expect((await api.query('audit', { siteId })).data.total).toBe(0)
  })
  it('rejects tree cycles and referenced nodes', async () => {
    const root = await create('areas', { name: '预置根', code: 'ROOT' })
    const child = await create('areas', { name: '预置叶', code: 'LEAF', parentId: root.id })
    await expect(update('areas', root, { ...root, parentId: child.id })).rejects.toMatchObject({ fields: { parentId: expect.any(String) } })
    await expect(status('areas', root, false)).rejects.toMatchObject({ code: 409, impacts: expect.any(Array) })
  })
  it('deletes only an unreferenced leaf while retaining audit snapshots', async () => {
    const leaf = await create('areas', { name: '预置可删除叶', code: 'LEAF' })
    await command('areas', 'delete', null, { id: leaf.id, expectedVersion: leaf.version })
    expect((await query('areas')).total).toBe(0)
    expect((await api.query('audit', { siteId })).data.total).toBe(2)
  })
  it('reference version changes reject an otherwise valid new person', async () => {
    const area = await create('areas', { name: '预置区域', code: 'AREA' })
    await update('areas', area, { ...area, name: '已变化' })
    await expect(create('people', { name: '预置', code: 'V', areaId: area.id }, { relatedVersions: { [area.id]: 1 } })).rejects.toMatchObject({ errorCode: 'VERSION_CONFLICT' })
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
  it('site administrator delegates only predefined scoped roles', async () => {
    api.login('demo-site', 'Admin@2026')
    const a = await create('accounts', { name: '预置站员', loginName: 'delegated' }, { siteId: 'site-1' })
    await grant(a, 'viewer', 'site-1')
    await expect(grant({ ...a, version: 2 }, 'viewer', 'site-2')).rejects.toMatchObject({ code: 400 })
    await expect(grant({ ...a, version: 2 }, 'site', 'site-1')).rejects.toMatchObject({ code: 400 })
  })
  it('site administrator cannot remove roles to take over stronger account', async () => {
    let a = await create('accounts', { name: '高权限本地', loginName: 'higher' }, { siteId: 'site-1' })
    a = await grant(a, 'site', 'site-1'); api.login('demo-site', 'Admin@2026')
    await expect(update('accounts', a, { ...a, bindings: [] }, { siteId: 'site-1' })).rejects.toMatchObject({ code: 404 })
  })
  it('area scope permits site context but excludes unknown/outside data', async () => {
    const role = await create('roles', { name: '预置区域只读', operations: ['overview:read', 'assets:read', 'people:read', 'organization:read'], siteIds: ['site-1'], areaIds: ['area-1'] })
    let a = await account(); a = await grant(a, role.id, 'site-1', ['area-1'])
    api.login(a.id, 'Admin@2026')
    expect((await api.query('context')).data.sites).toHaveLength(1)
    expect((await api.query('overview', { siteId: 'site-1' })).data.counts.assets).toBe(36)
    await expect(api.query('overview', { siteId: 'site-2' })).rejects.toMatchObject({ code: 403 })
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
  it('area scope rejects unseen objects and does not count unknown areas', async () => {
    const state = createSeed()
    state.areas.push({ id: 'other-area', siteId: 'site-1', enabled: true, version: 1 })
    state.devices[0].areaId = 'other-area'; state.devices[1].areaId = null
    state.people[0].areaId = 'other-area'; state.people[1].areaId = null
    state.roles.push({ id: 'scoped', enabled: true, grants: [{ operations: ['overview:read', 'assets:read', 'people:read'], siteIds: ['site-1'], areaIds: ['area-1'] }] })
    state.accounts.push({ id: 'scoped-user', enabled: true, roleIds: ['scoped'] })
    const scoped = createAdminService({ seed: () => state, delay: 0, storage: { getItem: key => key.endsWith('Session-Version') ? '1' : 'scoped-user', removeItem: () => {} } })
    expect((await scoped.query('overview', { siteId: 'site-1' })).data.counts.assets).toBe(34)
    expect((await scoped.query('master', { entity: 'people', siteId: 'site-1' })).data.total).toBe(23)
    await expect(scoped.query('person', { siteId: 'site-1', id: 'person-1-0' })).rejects.toMatchObject({ code: 404 })
    await expect(scoped.query('person', { siteId: 'site-1', id: 'person-1-1' })).rejects.toMatchObject({ code: 404 })
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
    expect(safeTarget('/admin/people/19007199254740993000?siteId=sites-19007199254740993-1&token=secret')).toBe('/admin/people/19007199254740993000?siteId=sites-19007199254740993-1')
    expect(peopleReturn('https://evil.invalid')).toBe('/admin/people')
    expect(peopleReturn('/admin/people?siteId=site-1&pageNum=2')).toContain('pageNum=2')
  })
})
