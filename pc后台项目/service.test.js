import { describe, it, expect, beforeEach } from 'vitest'
import { createAdminService, relationship, can, redact } from './service'
import { createSeed, TOKEN_KEY } from './seed'
import { safeTarget, trustedPortal } from './navigation'

function memoryStorage() {
  const data = new Map([['Admin-Token', 'original'], ['Wearable-Portal-Mock-Token', 'portal']])
  return { getItem: key => data.get(key) ?? null, setItem: (key, value) => data.set(key, value), removeItem: key => data.delete(key) }
}
let storage, service
beforeEach(() => { storage = memoryStorage(); service = createAdminService({ storage, delay: 0 }); service.login('demo-system', 'Admin@2026') })
const site = { siteId: 'site-1' }

describe('A0 data and scope', () => {
  it('reads inventory without fabricating audit history', async () => {
    expect((await service.query('devices', site)).data.total).toBe(32)
    expect((await service.query('devices', { ...site, lifecycle: 'STOCK', relation: 'UNASSIGNED' })).data.total).toBe(4)
    expect((await service.query('audit', site)).data.total).toBe(0)
  })
  it.each(['overview', 'details', 'integrations', 'integration', 'integrationJobs', 'integrationJob', 'integrationSettings'])('rejects retired page query %s', async kind => {
    await expect(service.query(kind, site)).rejects.toMatchObject({ errorCode: 'UNKNOWN_QUERY' })
  })
  it.each(['integrations.update', 'integrations.test', 'integrations.preview', 'integrations.confirm', 'integrations.receipt', 'integrationSettings.update'])('rejects retired simulator command %s', async type => {
    await expect(service.execute(type, { ...site, operationId: 'removed' })).rejects.toMatchObject({ errorCode: 'COMMAND_NOT_AVAILABLE' })
  })
  it('supports pagination and string long ID', async () => {
    const first = await service.query('devices', site), next = await service.query('devices', { ...site, pageNum: 2 })
    expect(first.data.rows).toHaveLength(20); expect(next.data.rows).toHaveLength(12)
    expect(first.data.rows[0].id).toBe('RL-H001')
    expect(first.data.rows[0].person.name).toBe('陈建国')
  })
  it('uses keyword and keeps offline available', async () => {
    const res = await service.query('devices', { ...site, lifecycle: 'STOCK', relation: 'UNASSIGNED', keyword: 'RL-H009' })
    expect(res.data.total).toBe(1); expect(res.data.rows[0].communication).toBe('NOT_CONNECTED')
  })
  it('another authorized site exposes its actual stock records', async () => {
    const res = await service.query('devices', { siteId: 'site-2' })
    expect(res.data.availability).toBe('AVAILABLE'); expect(res.data.total).toBe(3); expect(res.data.rows.every(row => row.relation === 'UNASSIGNED')).toBe(true)
  })
  it.each([['demo-system', 2], ['demo-site', 1], ['demo-asset', 1], ['demo-audit', 2]])('identity %s has %i authorized sites', async (id, size) => {
    service.login(id, 'Admin@2026'); expect((await service.query('context')).data.sites).toHaveLength(size)
  })
  it('rejects anonymous and cross-site requests', async () => {
    service.login('demo-asset', 'Admin@2026'); await expect(service.query('devices', { siteId: 'site-2' })).rejects.toMatchObject({ code: 403 })
    service.logout(); await expect(service.query('context')).rejects.toMatchObject({ code: 401 })
  })
  it('invisible object returns 404', async () => {
    await expect(service.query('device', { ...site, id: '29007199254740993000' })).rejects.toMatchObject({ code: 404 })
  })
  it.each([{ pageSize: 101 }, { pageSize: 0 }, { pageNum: 0 }, { pageNum: 1.5 }, { keyword: 12 }, { type: 'bad' }])('rejects invalid parameters %o', async bad => {
    await expect(service.query('devices', { ...site, ...bad })).rejects.toMatchObject({ code: 400 })
  })
  it('does not merge permissions and scopes across roles', () => {
    const s = createSeed(), user = { enabled: true, roleIds: ['a', 'b'] }
    s.roles = [{ id: 'a', grants: [{ operations: ['write'], siteIds: ['site-1'], areaIds: '*' }] }, { id: 'b', grants: [{ operations: ['read'], siteIds: ['site-2'], areaIds: '*' }] }]
    expect(can(s, user, 'write', { siteId: 'site-2' })).toBe(false)
    s.roles[0].grants[0].areaIds = ['a1']
    expect(can(s, user, 'write', { siteId: 'site-1' })).toBe(true)
    expect(can(s, user, 'write', { siteId: 'site-2' })).toBe(false)
  })
  it('source ambiguity never becomes unassigned', () => {
    const s = createSeed()
    const unknown = { ...s.devices.find(d => d.lifecycle === 'STOCK'), relation: 'UNKNOWN' }
    const conflict = { ...s.devices.find(d => d.lifecycle === 'IN_USE'), relation: 'CONFLICT' }
    expect(relationship(s, unknown).state).toBe('UNKNOWN')
    expect(relationship(s, conflict).state).toBe('CONFLICT')
    s.assignments = []; expect(relationship(s, s.devices[0]).state).toBe('CONFLICT')
  })
  it('response cannot mutate repository', async () => {
    const res = await service.query('devices', site); res.data.rows[0].code = 'modified'
    expect((await service.query('devices', site)).data.rows[0].code).not.toBe('modified')
  })
})

describe('A0 lifecycle and scenarios', () => {
  it.each([['unavailable', null], ['failure', 503], ['forbidden', 403]])('scenario %s is explicit and section scoped', async (mode, code) => {
    service.setScenario({ target: 'devices', mode })
    if (code) await expect(service.query('devices', site)).rejects.toMatchObject({ code, requestId: expect.any(String), errorCode: expect.any(String) })
    else expect((await service.query('devices', site)).data.availability).toBe('NOT_CONNECTED')
    expect((await service.query('audit', site)).data.total).toBe(0)
    service.restoreScenario(); expect((await service.query('devices', site)).data.total).toBe(32)
  })
  it('supports cancellation', async () => {
    const c = new AbortController(), p = service.query('devices', site, { signal: c.signal }); c.abort()
    await expect(p).rejects.toMatchObject({ name: 'AbortError' })
  })
  it('rejects late response after identity switch', async () => {
    const p = service.query('devices', site); service.login('demo-audit', 'Admin@2026')
    await expect(p).rejects.toMatchObject({ code: 401 })
  })
  it('invalidates pending work on context change', async () => {
    const p = service.query('devices', site); service.changeContext()
    await expect(p).rejects.toMatchObject({ name: 'AbortError' })
  })
  it('reset clears only mock token and notifies', async () => {
    const events = [], unsubscribe = service.subscribe(e => events.push(e.kind))
    service.reset(); expect(storage.getItem(TOKEN_KEY)).toBe(null)
    expect(storage.getItem('Admin-Token')).toBe('original'); expect(storage.getItem('Wearable-Portal-Mock-Token')).toBe('portal')
    expect(events).toEqual(['reset']); unsubscribe(); service.login('demo-system', 'Admin@2026'); expect(events).toEqual(['reset'])
  })
  it('invalid stored identity returns login state', () => {
    storage.setItem(TOKEN_KEY, 'nonexistent'); expect(service.identity()).toBe(null)
  })
  it('does not implement business commands in UI provider', async () => {
    await expect(service.execute('issue', site)).rejects.toMatchObject({ errorCode: 'COMMAND_NOT_AVAILABLE' })
  })
})

describe('transaction foundation (test-only command)', () => {
  const objectId = 'RL-H001'
  const input = { ...site, id: objectId, expectedVersion: 1, operationId: 'test-operation', name: '预置改名' }
  function withCommand(apply) {
    service = createAdminService({ storage, delay: 0, commands: { rename: { permission: 'assets:write', readPermission: 'assets:read', locate: (state, i) => state.devices.find(d => d.id === i.id), apply: apply || ((state, i) => { const d = state.devices.find(d => d.id === i.id); d.name = i.name; d.version++; return { id: d.id, version: d.version } }) } } })
  }
  it('commits once, replays idempotency, changes only current fact', async () => {
    withCommand(); const first = await service.execute('rename', input), second = await service.execute('rename', { name: input.name, ...input })
    expect(second).toEqual(first)
    const audit = (await service.query('audit', site)).data
    expect(audit.total).toBe(1); expect(audit.rows[0].before.name).toBe('安全帽'); expect(audit.rows[0].after.name).toBe('预置改名')
    expect((await service.query('devices', { ...site, relation: 'ASSIGNED' })).data.total).toBe(24)
    await expect(service.execute('rename', { ...input, name: 'different' })).rejects.toMatchObject({ code: 409 })
  })
  it('version mismatch and read-only identity denied', async () => {
    withCommand(); await expect(service.execute('rename', { ...input, expectedVersion: 3 })).rejects.toMatchObject({ code: 409 })
    service.login('demo-audit', 'Admin@2026'); await expect(service.execute('rename', input)).rejects.toMatchObject({ code: 403 })
  })
  it('failed transaction does not change record or audit', async () => {
    withCommand(state => { state.devices[0].name = 'partial'; throw new Error('test failure') })
    await expect(service.execute('rename', input)).rejects.toThrow('test failure')
    expect((await service.query('device', { ...site, id: objectId })).data.name).toBe('安全帽')
    expect((await service.query('audit', site)).data.total).toBe(0)
  })
  it('cancel or identity change before commit rejects', async () => {
    withCommand(); const c = new AbortController(), p = service.execute('rename', input, { signal: c.signal }); c.abort()
    await expect(p).rejects.toMatchObject({ name: 'AbortError' })
    const q = service.execute('rename', input); service.login('demo-site', 'Admin@2026'); await expect(q).rejects.toMatchObject({ code: 401 })
    expect((await service.query('audit', site)).data.total).toBe(0)
  })
  it('logout preserves memory and refresh resets', async () => {
    withCommand(); await service.execute('rename', input); service.logout(); service.login('demo-system', 'Admin@2026')
    expect((await service.query('audit', site)).data.total).toBe(1)
    const refreshed = createAdminService({ storage, delay: 0 })
    expect((await refreshed.query('audit', site)).data.total).toBe(0)
  })
  it('redacts nested secrets and URLs', () => {
    expect(redact({ password: 'secret', nested: { token: 's', url: 'https://private', name: 'ok' } })).toEqual({ password: '[已脱敏]', nested: { token: '[已脱敏]', url: '[已脱敏]', name: 'ok' } })
  })
})

describe('navigation and entry isolation', () => {
  it.each(['https://evil.invalid', '//evil.invalid', '/admin/overview?redirect=https://evil.invalid', '/admin/overview/../../live', '/live', '/admin/unknown'])('sanitizes target %s', target => {
    expect(safeTarget(target)).toBe('/devices')
  })
  it('preserves only valid site query', () => { expect(safeTarget('/audit?siteId=site-1&token=bad')).toBe('/audit?siteId=site-1') })
  it('portal accepts configured base only', () => { expect(trustedPortal('javascript:alert(1)')).toBe(null); expect(trustedPortal('https://user:password@example.com')).toBe(null); expect(trustedPortal('http://localhost:5179/?token=bad')).toBe(null); expect(trustedPortal('http://localhost:5179')).toBe('http://localhost:5179/') })
})
