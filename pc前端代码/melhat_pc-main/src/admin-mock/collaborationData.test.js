import { beforeEach, describe, expect, it, vi } from 'vitest'
import { createAdminService } from './service'
import { createSeed, TOKEN_KEY, SESSION_VERSION_KEY } from './seed'
import { authorizationEffects } from './authorizationPreview'
import { can } from './access'
import { safeTarget, recordReturn } from './navigation'

let api, storage, serial
const siteId = 'site-1'
function setup(seed = createSeed) {
  const map = new Map([['Admin-Token', 'real'], ['Wearable-Portal-Mock-Token', 'portal']])
  storage = { getItem: k => map.get(k), setItem: (k, v) => map.set(k, v), removeItem: k => map.delete(k) }
  api = createAdminService({ storage, seed, delay: 0 }); api.login('demo-system', 'Admin@2026'); serial = 0
}
beforeEach(() => setup())
const q = async (kind, input = {}) => (await api.query(kind, { siteId, ...input })).data
const exec = async (type, input) => (await api.execute(type, { siteId, operationId: 'a5-' + ++serial, ...input })).data
const form = () => ({ code: 'A5-G', name: '预置A5组', areaId: 'area-1', leaderId: 'person-1-0', personIds: ['person-1-0', 'person-1-4'], sos: { enabled: true, recipientIds: ['person-1-4'] }, remark: '' })
const versions = async () => { const c = await q('groupCandidates'); return Object.fromEntries([...c.people, ...c.areas].map(p => [p.id, p.version])) }
const createGroup = async (data = form(), extra = {}) => exec('groups.create', { data, relatedVersions: await versions(), ...extra })
const updateGroup = async (row, data, extra = {}) => exec('groups.update', { id: row.id, expectedVersion: row.version, relatedVersions: await versions(), data, ...extra })
const account = async () => exec('accounts.create', { data: { name: '预置A5身份', loginName: 'a5-login' } })
const grantInput = (a, extra = {}) => ({ siteId, operationId: 'grant', id: a.id, expectedVersion: a.version, relatedVersions: { viewer: 1 }, data: { name: a.name, loginName: a.loginName, personId: null, bindings: [{ roleId: 'viewer', siteIds: [siteId], areaIds: '*' }] }, ...extra })
const preview = async (type, command) => q('authorizationPreview', { type, command })

describe('A5 authorization preview and mock credentials', () => {
  it('preview is read-only and matches actual effective permission tuples', async () => {
    const a = await account(), input = grantInput(a), before = await q('audit'), p = await preview('accounts.update', input)
    expect(p.required).toBe(true); expect(p.accounts[0].added.length).toBeGreaterThan(0)
    expect((await q('audit')).total).toBe(before.total)
    expect((await q('record', { entity: 'accounts', id: a.id })).roleIds).toEqual([])
    await api.execute('accounts.update', { ...input, previewId: p.previewId })
    api.login(a.id, 'Admin@2026'); expect((await q('context')).sites.map(s => s.id)).toEqual([siteId]); expect(api.canAny('assets:read', siteId)).toBe(true); expect(api.canAny('assets:write', siteId)).toBe(false)
  })
  it('refuses direct authorization writes without preview and rolls back', async () => {
    const a = await account(); await expect(api.execute('accounts.update', grantInput(a))).rejects.toMatchObject({ errorCode: 'PREVIEW_EXPIRED' })
    expect((await q('record', { entity: 'accounts', id: a.id })).roleIds).toEqual([]); expect((await q('audit')).total).toBe(1)
  })
  it.each(['input', 'revision', 'context', 'identity'])('invalidates preview after %s changes', async mode => {
    const a = await account(), input = grantInput(a), p = await preview('accounts.update', input)
    if (mode === 'input') input.data.name = '已修改输入'
    if (mode === 'revision') await createGroup()
    if (mode === 'context') api.changeContext()
    if (mode === 'identity') api.login('demo-system', 'Admin@2026')
    await expect(api.execute('accounts.update', { ...input, previewId: p.previewId })).rejects.toMatchObject({ errorCode: 'PREVIEW_EXPIRED' })
  })
  it('ordinary account profile edit needs no confirmation preview', async () => {
    const a = await account(); const b = await exec('accounts.update', { id: a.id, expectedVersion: a.version, data: { name: '预置更名', loginName: a.loginName, bindings: [] } }); expect(b.name).toBe('预置更名')
  })
  it('preview and actual permission never cross-combine role scopes', () => {
    const s = createSeed(), a = s.accounts.find(a => a.id === 'demo-asset')
    s.areas.push({ id: 'area-x', siteId, name: '另一范围', enabled: true }); s.roles.find(r => r.id === 'asset').grants = [{ operations: ['assets:read'], siteIds: [siteId], areaIds: ['area-1'] }, { operations: ['assets:write'], siteIds: [siteId], areaIds: ['area-x'] }]
    const effects = authorizationEffects(s, a)
    for (const e of effects) expect(can(s, a, e.operation, e)).toBe(true)
    expect(effects.some(e => e.operation === 'assets:write' && e.areaId === 'area-1')).toBe(false)
  })
  it('preview enforces site-admin delegation and built-in protection', async () => {
    const a = await account(); api.login('demo-site', 'Admin@2026')
    const input = grantInput(a); input.data.bindings[0].siteIds = ['site-2']
    await expect(preview('accounts.update', input)).rejects.toMatchObject({ code: 400 })
    await expect(preview('roles.status', { siteId, id: 'site', expectedVersion: 1, enabled: false })).rejects.toMatchObject({ code: 403 })
  })
  it('role status preview lists affected accounts and lost scope', async () => {
    const r = await exec('roles.create', { data: { name: '预置自定义角色', operations: ['assets:read'], siteIds: [siteId], areaIds: '*' } }), a = await account(), input = grantInput(a)
    input.data.bindings[0].roleId = r.id; input.relatedVersions = { [r.id]: r.version }
    await api.execute('accounts.update', { ...input, previewId: (await preview('accounts.update', input)).previewId })
    const command = { siteId, id: r.id, expectedVersion: r.version, enabled: false, operationId: 'disable-role' }, p = await preview('roles.status', command)
    expect(p.accounts[0].noScope).toBe(true); expect(p.accounts[0].lostSites[0].id).toBe(siteId)
    await api.execute('roles.status', { ...command, previewId: p.previewId }); api.login(a.id, 'Admin@2026'); expect((await q('context')).sites).toEqual([])
  })
  it('idempotent authorized retry does not need a fresh preview or duplicate audit', async () => {
    const a = await account(), input = grantInput(a); input.previewId = (await preview('accounts.update', input)).previewId
    const result = await api.execute('accounts.update', input); expect(await api.execute('accounts.update', input)).toEqual(result); expect((await q('audit')).total).toBe(2)
  })
  it('resets mock version only and invalidates old-version session without touching other keys', async () => {
    const input = { id: 'demo-asset', expectedVersion: 1, reason: '预置失效验证', confirm: true, operationId: 'reset-once' }
    const before = (await q('overview')).counts, result = await exec('accounts.resetCredential', input)
    expect(result.credentialVersion).toBe(2); expect((await exec('accounts.resetCredential', input)).credentialVersion).toBe(2)
    expect((await q('overview')).counts).toEqual(before)
    const audit = await q('audit'); expect(JSON.stringify(audit)).toContain('[已脱敏]')
    storage.setItem(TOKEN_KEY, 'demo-asset'); storage.setItem(SESSION_VERSION_KEY, '1')
    await expect(q('context')).rejects.toMatchObject({ code: 401 }); expect(storage.getItem('Admin-Token')).toBe('real'); expect(storage.getItem('Wearable-Portal-Mock-Token')).toBe('portal')
    api.login('demo-asset', 'Admin@2026'); expect(storage.getItem(SESSION_VERSION_KEY)).toBe('2')
  })
  it('rejects versionless legacy sessions', async () => { storage.removeItem(SESSION_VERSION_KEY); expect(api.identity()).toBe(null); await expect(q('context')).rejects.toMatchObject({ code: 401 }) })
  it('cannot reset system or self and requires reason/confirmation', async () => {
    await expect(exec('accounts.resetCredential', { id: 'demo-system', expectedVersion: 1, reason: 'test', confirm: true })).rejects.toMatchObject({ code: 403 })
    await expect(exec('accounts.resetCredential', { id: 'demo-asset', expectedVersion: 1, reason: '' })).rejects.toMatchObject({ fields: { reason: expect.any(String) } })
    api.login('demo-site', 'Admin@2026'); await expect(exec('accounts.resetCredential', { id: 'demo-site', expectedVersion: 1, reason: 'test', confirm: true })).rejects.toMatchObject({ code: 403 })
  })
})

describe('A5 persistent-person group model in page memory', () => {
  it('preserves baseline and marks seed policy unknown with no fabricated history', async () => {
    expect((await q('overview')).counts).toEqual({ assets: 36, available: 17, assigned: 12, maintenance: 3, unknown: 1, conflict: 1 })
    const g = await q('group', { id: 'group-1' }); expect(g.leaderId).toBe(null); expect(g.sos).toBe(null); expect((await q('groupHistory', { id: g.id })).total).toBe(0)
  })
  it('creates and updates group with independent leader and notification recipients', async () => {
    const g = await createGroup(); expect(g.sos.recipientIds).not.toContain(g.leaderId)
    expect((await q('group', { id: g.id })).notificationEffective).toBe(true)
    const data = form(); data.name = '预置新名称'; const updated = await updateGroup(g, data)
    expect(updated.version).toBe(2); const h = await q('groupHistory', { id: g.id }); expect(h.rows[1].name).toBe('预置A5组')
  })
  it.each([
    ['duplicate', d => { d.personIds.push(d.personIds[0]) }, 'personIds'],
    ['cross site', d => { d.personIds.push('person-2-0') }, 'personIds'],
    ['leader outside', d => { d.leaderId = 'person-1-8' }, 'leaderId'],
    ['no members', d => { d.personIds = [] }, 'personIds'],
    ['no receivers', d => { d.sos.recipientIds = [] }, 'sos'],
    ['unknown receiver', d => { d.sos.recipientIds = ['person-1-8'] }, 'sos'],
    ['cross area', d => { d.areaId = 'area-2' }, 'areaId'],
    ['forged site', d => { d.siteId = 'site-2' }, 'name']
  ])('rejects %s atomically', async (_name, mutate, field) => {
    const d = form(); mutate(d); await expect(createGroup(d)).rejects.toMatchObject({ fields: { [field]: expect.any(String) } }); expect((await q('groups')).total).toBe(1); expect((await q('audit')).total).toBe(0)
  })
  it('requires explicit receiver adjustment when removing a member', async () => {
    const g = await createGroup(), d = form(); d.personIds = [g.leaderId]
    await expect(updateGroup(g, d)).rejects.toMatchObject({ fields: { sos: expect.any(String) } })
    d.sos = { enabled: false, recipientIds: [] }; await updateGroup(g, d)
  })
  it('blocks person disable while group active and releases after group disabled', async () => {
    const g = await createGroup()
    await expect(exec('people.status', { id: 'person-1-4', expectedVersion: 1, enabled: false })).rejects.toMatchObject({ code: 409 })
    await exec('groups.status', { id: g.id, expectedVersion: 1, enabled: false })
    await exec('people.status', { id: 'person-1-4', expectedVersion: 1, enabled: false })
    await expect(exec('groups.status', { id: g.id, expectedVersion: 2, enabled: true, relatedVersions: await versions() })).rejects.toMatchObject({ fields: { personIds: expect.any(String) } })
    expect((await q('group', { id: g.id })).sos.recipientIds).toEqual(['person-1-4'])
  })
  it('allows disabling an incomplete seed but cannot enable without complete config', async () => {
    await exec('groups.status', { id: 'group-1', expectedVersion: 1, enabled: false }); await expect(exec('groups.status', { id: 'group-1', expectedVersion: 2, enabled: true, relatedVersions: await versions() })).rejects.toMatchObject({ fields: { leaderId: expect.any(String) } })
  })
  it('keeps same-site code uniqueness and does not merge sites', async () => {
    await createGroup(); await expect(createGroup({ ...form(), code: ' a5-g ' })).rejects.toMatchObject({ code: 409 })
    const candidate = await q('groupCandidates', { siteId: 'site-2' }), d = { ...form(), areaId: 'area-2', leaderId: 'person-2-0', personIds: ['person-2-0'], sos: { enabled: false, recipientIds: [] } }
    await exec('groups.create', { siteId: 'site-2', data: d, relatedVersions: Object.fromEntries([...candidate.people, ...candidate.areas].map(p => [p.id, p.version])) })
  })
  it('old object/person/area versions and same operation with different input reject', async () => {
    const v = await versions(), input = { data: form(), relatedVersions: v, operationId: 'once' }, g = await exec('groups.create', input)
    expect((await exec('groups.create', input)).id).toBe(g.id); expect((await q('groupHistory', { id: g.id })).total).toBe(1)
    await expect(exec('groups.create', { ...input, data: { ...form(), name: '不同' } })).rejects.toMatchObject({ errorCode: 'IDEMPOTENCY_CONFLICT' })
    await expect(updateGroup(g, form(), { expectedVersion: 0 })).rejects.toMatchObject({ errorCode: 'VERSION_CONFLICT' })
    await expect(updateGroup(g, form(), { relatedVersions: { ...v, 'person-1-0': 99 } })).rejects.toMatchObject({ code: 409 })
    await expect(updateGroup(g, form(), { relatedVersions: { ...v, 'area-1': 99 } })).rejects.toMatchObject({ code: 409 })
    expect((await q('groupHistory', { id: g.id })).total).toBe(1)
  })
  it('readonly can inspect but cannot write, asset account has no group access', async () => {
    api.login('demo-audit', 'Admin@2026'); expect((await q('groups')).total).toBe(1); await expect(createGroup()).rejects.toMatchObject({ code: 403 })
    api.login('demo-asset', 'Admin@2026'); await expect(q('group', { id: 'group-1' })).rejects.toMatchObject({ code: 403 })
  })
  it('same-site cross-area group requires coverage of all members; unseen group is 404', async () => {
    const seed = () => { const s = createSeed(); s.areas.push({ id: 'area-extra', siteId, name: '预置跨区域', version: 1, enabled: true }); s.people.find(p => p.id === 'person-1-4').areaId = 'area-extra'; s.accounts.find(a => a.id === 'demo-site').roleScopes = { site: { siteIds: [siteId], areaIds: ['area-1'] } }; return s }
    setup(seed); const g = await createGroup(); api.login('demo-site', 'Admin@2026'); expect((await q('groups')).rows.some(r => r.id === g.id)).toBe(false); await expect(q('group', { id: g.id })).rejects.toMatchObject({ code: 404 }); expect((await q('groupCandidates')).people.some(p => p.id === 'person-1-4')).toBe(false)
  })
  it('terminal summary redacts equipment and account without widening group permission', async () => {
    setup(() => { const s = createSeed(); const r = s.roles.find(r => r.id === 'audit'); r.grants[0].operations = ['overview:read', 'access:read', 'people:read']; s.accounts.find(a => a.id === 'demo-system').personId = 'person-1-0'; return s })
    api.login('demo-audit', 'Admin@2026'); const t = await q('groupTerminals', { id: 'group-1' }); expect(t.rows[0].devices).toEqual([]); expect(t.rows[0].slots.HELMET).toBe('UNAVAILABLE'); expect(t.rows[0].account.state).toBe('FORBIDDEN'); expect(t.rows[0].pc).toBe('NOT_CONNECTED')
  })
  it('return and reissue derive current terminals without changing frozen group configuration', async () => {
    const g = await createGroup(), before = await q('groupHistory', { id: g.id }), selection = await q('assignmentCandidates', { resource: 'selection', personId: 'person-1-0' }), old = selection.current.find(r => r.type === 'HELMET')
    await exec('assignments.return', { personId: selection.person.id, personVersion: selection.person.version, acknowledged: true, items: [{ deviceId: old.deviceId, deviceVersion: old.deviceVersion, assignmentId: old.id, assignmentVersion: old.version, condition: 'GOOD' }] })
    const afterReturn = await q('groupTerminals', { id: g.id }); expect(afterReturn.rows[0].slots.HELMET).toBe('UNASSIGNED')
    const next = await q('assignmentCandidates', { resource: 'selection', personId: 'person-1-0' })
    await exec('assignments.issue', { personId: next.person.id, personVersion: next.person.version, acknowledged: true, items: [{ deviceId: '19007199254740993012', deviceVersion: 1 }] })
    expect((await q('groupTerminals', { id: g.id })).rows[0].devices.some(d => d.code === 'EQ-1-013')).toBe(true)
    expect(await q('groupHistory', { id: g.id })).toEqual(before)
  })
  it('cancel and identity change before commit leave no group or audit', async () => {
    const input = { siteId, data: form(), relatedVersions: await versions(), operationId: 'cancel' }, controller = new AbortController()
    const pending = api.execute('groups.create', input, { signal: controller.signal }); controller.abort(); await expect(pending).rejects.toMatchObject({ name: 'AbortError' })
    const changed = api.execute('groups.create', input); api.login('demo-audit', 'Admin@2026'); await expect(changed).rejects.toMatchObject({ code: 401 }); api.login('demo-system', 'Admin@2026'); expect((await q('groups')).total).toBe(1); expect((await q('audit')).total).toBe(0)
  })
  it('observer exceptions cannot turn committed group into failure', async () => {
    const log = vi.spyOn(console, 'error').mockImplementation(() => {}); const off = api.subscribe(() => { throw new Error('observer') }); try { const g = await createGroup(); expect((await q('group', { id: g.id })).version).toBe(1) } finally { off(); log.mockRestore() }
  })
  it('paginates group history, string IDs and immutable names', async () => {
    let g = await createGroup(); for (let i = 0; i < 21; i++) g = await updateGroup(g, { ...form(), name: '预置版本' + i })
    const h = await q('groupHistory', { id: g.id, pageNum: 2 }); expect(h.total).toBe(22); expect(h.rows).toHaveLength(2); expect(h.rows[1].members[0].name).toBe('人员1-01'); expect(typeof g.id).toBe('string')
  })
  it('distinguishes unavailable, failure, forbidden and empty filters', async () => {
    expect((await q('groups', { keyword: '不存在的组' })).total).toBe(0)
    api.setScenario({ target: 'groups', mode: 'unavailable' }); expect((await q('groups')).availability).toBe('NOT_CONNECTED')
    api.setScenario({ target: 'groups', mode: 'failure' }); await expect(q('groups')).rejects.toMatchObject({ code: 503 })
    api.setScenario({ target: 'groups', mode: 'forbidden' }); await expect(q('groups')).rejects.toMatchObject({ code: 403 })
  })
  it('preserves safe group return and refresh reset isolation', async () => {
    expect(safeTarget('/admin/access/groups/group-1?siteId=site-1&returnTo=https://bad')).toBe('/admin/access/groups/group-1?siteId=site-1&returnTo=%2Fadmin%2Faccess%2Fgroups')
    expect(recordReturn('https://evil', '/admin/access/groups')).toBe('/admin/access/groups')
    await createGroup(); api.logout(); api.login('demo-system', 'Admin@2026'); expect((await q('groups')).total).toBe(2); api.reset(); api.login('demo-system', 'Admin@2026'); expect((await q('groups')).total).toBe(1); expect(storage.getItem('Wearable-Portal-Mock-Token')).toBe('portal')
  })
})
