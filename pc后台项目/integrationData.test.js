import { beforeEach, describe, expect, it } from 'vitest'
import { createAdminService } from './service'
import { createSeed } from './seed'

let service, sequence
const siteId = 'site-1', deviceId = '19007199254740993000'
const connectorId = (kind = 'DEVICE') => `integration-${siteId}-${kind}`
function setup(change = () => {}, delay = 0) {
  const memory = new Map()
  service = createAdminService({ storage: { getItem: k => memory.get(k), setItem: (k, v) => memory.set(k, v), removeItem: k => memory.delete(k) }, delay, seed: () => { const s = createSeed(); change(s); return s }, now: () => '2026-09-20T12:00:00Z' })
  service.login('demo-system', 'Admin@2026')
}
beforeEach(() => { sequence = 0; setup() })
const q = async (kind, input = {}) => (await service.query(kind, { siteId, ...input })).data
const execute = async (type, row, fields = {}) => (await service.execute(type, { siteId, id: row.id, expectedVersion: row.version, operationId: `integration-test-${++sequence}`, ...fields })).data
const connector = (kind = 'DEVICE') => q('integration', { id: connectorId(kind) })
async function configure(kind = 'DEVICE', fields = {}) { return execute('integrations.update', await connector(kind), { mappedSiteId: siteId, areaId: 'area-1', ...fields }) }
async function preview(kind = 'DEVICE') { return execute('integrations.preview', await connector(kind)) }
const confirm = job => execute('integrations.confirm', job)

describe('A6 synthetic integration transactions', () => {
  it('seeds six unconnected connectors per site and safe immutable credentials', async () => {
    const list = await q('integrations', { pageSize: 100 })
    expect(list.total).toBe(6); expect(new Set(list.rows.map(r => r.kind)).size).toBe(6)
    expect(list.rows.every(r => r.status === 'NOT_CONNECTED' && r.credential === 'MOCK-ONLY')).toBe(true)
    expect((await q('integrations', { siteId: 'site-empty' })).total).toBe(6)
    expect((await q('integrationJobs')).total).toBe(0)
  })
  it('preview has no target effects; confirmation preserves local fields and assignments', async () => {
    await configure()
    const before = await q('device', { id: deviceId }), assignments = await q('assignments', { deviceId })
    const job = await preview()
    expect(job).toMatchObject({ status: 'PREVIEW', counts: { created: 1, updated: 1, conflicts: 0, skipped: 0 }, source: '本后台合成样本' })
    expect((await q('overview')).counts.assets).toBe(36)
    expect(await q('device', { id: deviceId })).toEqual(before)
    expect((await confirm(job)).status).toBe('COMPLETED')
    expect((await q('overview')).counts.assets).toBe(37)
    const after = await q('device', { id: deviceId })
    for (const field of ['name', 'areaId', 'lifecycle', 'relation', 'remark', 'manufacturer', 'sn', 'communication', 'verification', 'assemblies']) expect(after[field]).toEqual(before[field])
    expect(after.sourceName).toBe('来源安全帽样本')
    expect((await q('assignments', { deviceId })).rows.map(r => ({ ...r, deviceVersion: 1 }))).toEqual(assignments.rows)
    expect((await q('deviceHistory', { id: deviceId })).total).toBe(0)
  })
  it('repeated sync skips known source fields and never duplicates equipment', async () => {
    await configure(); await confirm(await preview())
    const job = await preview()
    expect(job.counts).toEqual({ created: 0, updated: 0, skipped: 2, conflicts: 0 })
    await confirm(job); expect((await q('overview')).counts.assets).toBe(37)
  })
  it('same-name people remain two external identities and reimport is stable', async () => {
    await configure('PERSON'); await confirm(await preview('PERSON'))
    const people = (await q('master', { entity: 'people', pageSize: 100 })).rows.filter(p => p.name === '同名演示人员')
    expect(people).toHaveLength(2); expect(new Set(people.map(p => p.sourcePersonId)).size).toBe(2)
    const job = await preview('PERSON'); expect(job.counts.skipped).toBe(2); await confirm(job)
    expect((await q('master', { entity: 'people', pageSize: 100 })).total).toBe(27)
  })
  it('missing mapping persists conflicts, blocks entire batch, and retries the same job after repair', async () => {
    const job = await preview(); expect(job.status).toBe('CONFLICT'); expect(job.counts.conflicts).toBe(2)
    await expect(confirm(job)).rejects.toMatchObject({ code: 409 })
    await configure(); const retried = await execute('integrations.retry', job)
    expect(retried.id).toBe(job.id); expect(retried.attempts).toHaveLength(2); expect(retried.status).toBe('PREVIEW')
    await confirm(retried); expect((await q('integrationJobs')).total).toBe(1)
  })
  it.each(['same-site', 'cross-site'])('duplicate manufacturer identity (%s) blocks batch without disclosing another site', async mode => {
    setup(s => { const first = s.devices[0]; s.devices.push({ ...structuredClone(first), id: 'secret-other-device', siteId: mode === 'same-site' ? siteId : 'site-2', name: 'private-name' }) })
    await configure(); const job = await preview()
    expect(job.status).toBe('CONFLICT'); expect(job.rows[0].targetId).toBeNull()
    await expect(confirm(job)).rejects.toMatchObject({ code: 409 })
    expect(JSON.stringify(job)).not.toContain('secret-other-device'); expect(JSON.stringify(await q('integrationJob', { id: job.id }))).not.toContain('private-name')
    expect(job).not.toHaveProperty('targetSnapshot')
    expect((await q('overview')).counts.assets).toBe(mode === 'same-site' ? 37 : 36)
  })
  it('configuration changes invalidate old previews; target changes invalidate confirmation', async () => {
    await configure(); let job = await preview(); await configure('DEVICE', { endpointKey: 'SAMPLE_B' })
    await expect(confirm(job)).rejects.toMatchObject({ code: 409 })
    job = await preview()
    await service.execute('devices.disable', { siteId, deviceId: '19007199254740993012', deviceVersion: 1, reason: '本地变化', operationId: 'local-change' })
    await expect(confirm(job)).rejects.toMatchObject({ code: 409 })
    expect((await q('overview')).counts.assets).toBe(36)
  })
  it('trimmed case-insensitive manufacturer identities conflict with the existing ledger', async () => {
    setup(s => { s.devices.push({ ...s.devices[0], id: 'normalized-duplicate', sn: `  ${s.devices[0].sn.toLowerCase()} `, manufacturer: ` ${s.devices[0].manufacturer} ` }) })
    await configure(); const job = await preview(); expect(job.status).toBe('CONFLICT'); expect(job.counts.conflicts).toBe(1)
    await expect(confirm(job)).rejects.toMatchObject({ code: 409 }); expect((await q('overview')).counts.assets).toBe(37)
  })
  it('settings version changes invalidate a previously successful preview', async () => {
    await configure(); const job = await preview()
    await execute('integrationSettings.update', await q('integrationSettings'), { defaultScenario: 'TIMEOUT' })
    await expect(confirm(job)).rejects.toMatchObject({ code: 409 }); expect((await q('overview')).counts.assets).toBe(36)
  })
  it('task status, ID and source filters work together with pagination', async () => {
    const conflict = await preview(); await configure(); const ready = await preview(); await confirm(ready)
    expect((await q('integrationJobs', { status: 'CONFLICT', keyword: conflict.id })).rows.map(r => r.id)).toEqual([conflict.id])
    expect((await q('integrationJobs', { status: 'COMPLETED', keyword: '本后台合成样本', pageSize: 1 })).total).toBe(1)
    expect((await q('integrationJobs', { status: 'FAILED' })).total).toBe(0)
    await expect(q('integrationJobs', { status: 'UNKNOWN' })).rejects.toMatchObject({ code: 400 })
    await expect(q('integrationJobs', { keyword: 2 })).rejects.toMatchObject({ code: 400 })
  })
  it('another equally privileged account cannot confirm someone else’s preview', async () => {
    setup(s => { s.roles.find(r => r.id === 'audit').grants = [{ operations: ['*'], siteIds: [siteId], areaIds: '*' }] })
    await configure(); const job = await preview(); service.login('demo-audit', 'Admin@2026')
    await expect(confirm(job)).rejects.toMatchObject({ code: 403 }); expect((await q('overview')).counts.assets).toBe(36)
    expect(await q('integrationJob', { id: job.id })).not.toHaveProperty('actorSnapshot')
  })
  it.each([false, true])('permission revocation and later restoration invalidate old preview (restore=%s)', async restore => {
    setup(s => {
      s.roles.push({ id: 'integration-operator', name: '模拟接入办理', enabled: true, version: 1, builtin: false, grants: [{ operations: ['overview:read', 'integrations:read', 'integrations:write', 'assets:read', 'assets:write'], siteIds: [siteId], areaIds: '*' }] })
      s.accounts.find(a => a.id === 'demo-audit').roleIds = ['integration-operator']
    })
    await configure(); service.login('demo-audit', 'Admin@2026'); const job = await preview(); service.login('demo-system', 'Admin@2026')
    for (const enabled of restore ? [false, true] : [false]) {
      const command = { siteId, id: 'integration-operator', expectedVersion: enabled ? 2 : 1, enabled, operationId: `role-${enabled}` }
      const p = await q('authorizationPreview', { type: 'roles.status', command })
      await service.execute('roles.status', { ...command, previewId: p.previewId })
    }
    service.login('demo-audit', 'Admin@2026')
    await expect(confirm(job)).rejects.toMatchObject({ code: restore ? 409 : 403 })
    service.login('demo-system', 'Admin@2026'); expect((await q('overview')).counts.assets).toBe(36)
  })
  it('settings default is consumed and failed retry has its own recorded attempt', async () => {
    let settings = await q('integrationSettings')
    settings = await execute('integrationSettings.update', settings, { defaultScenario: 'TIMEOUT' })
    await configure(); const tested = await execute('integrations.test', await connector())
    expect(tested.status).toBe('NOT_CONNECTED'); expect(tested.lastTest.result).toBe('TIMEOUT')
    const job = await preview(); expect(job.status).toBe('FAILED')
    await execute('integrationSettings.update', settings, { defaultScenario: 'SUCCESS' })
    const retry = await execute('integrations.retry', job); expect(retry.status).toBe('PREVIEW'); expect(retry.attempts).toHaveLength(2)
    await confirm(retry); expect((await q('overview')).counts.assets).toBe(37)
  })
  it('controlled scenario field mismatch blocks import and explicit override wins over default', async () => {
    await execute('integrationSettings.update', await q('integrationSettings'), { defaultScenario: 'TIMEOUT' })
    await configure('DEVICE', { scenario: 'FIELD_MISMATCH' }); expect((await preview()).status).toBe('CONFLICT')
    await configure('DEVICE', { scenario: 'SUCCESS' }); expect((await preview()).status).toBe('PREVIEW')
  })
  it.each([{ endpointKey: 'https://real.invalid' }, { credential: 'secret' }, { mappedSiteId: 'site-2' }, { areaId: 'area-2' }, { scenario: '<script>' }, { rows: [] }])('rejects unsafe or unauthorized config %o atomically', async fields => {
    const before = await connector(); await expect(execute('integrations.update', before, fields)).rejects.toMatchObject({ code: 400 }); expect(await connector()).toEqual(before)
  })
  it.each(['demo-site', 'demo-asset', 'demo-audit'])('default identity %s cannot write integrations', async id => {
    const c = await connector(); service.login(id, 'Admin@2026'); await expect(execute('integrations.test', c)).rejects.toMatchObject({ code: 403 })
  })
  it('area-only grants cannot access full-site connectors or use sync target permissions', async () => {
    setup(s => { s.roles.find(r => r.id === 'audit').grants = [{ operations: ['*'], siteIds: [siteId], areaIds: ['area-1'] }] })
    service.login('demo-audit', 'Admin@2026'); await expect(q('integrations')).rejects.toMatchObject({ code: 403 })
    setup(s => { s.roles.find(r => r.id === 'audit').grants = [{ operations: ['integrations:read', 'integrations:write', 'overview:read'], siteIds: [siteId], areaIds: '*' }] })
    service.login('demo-audit', 'Admin@2026'); const c = await connector(); await expect(execute('integrations.preview', c)).rejects.toMatchObject({ code: 403 })
  })
  it('idempotent confirm returns the original response and altered input conflicts', async () => {
    await configure(); const job = await preview(), input = { siteId, id: job.id, expectedVersion: job.version, operationId: 'confirm-once' }
    const result = await service.execute('integrations.confirm', input)
    expect(await service.execute('integrations.confirm', input)).toEqual(result)
    await expect(service.execute('integrations.confirm', { ...input, expectedVersion: 999 })).rejects.toMatchObject({ code: 409 })
    expect((await q('overview')).counts.assets).toBe(37)
  })
  it('device audit records source-only changes and idempotent confirmation appends nothing twice', async () => {
    await configure(); const job = await preview(), before = await q('device', { id: deviceId })
    const input = { siteId, id: job.id, expectedVersion: job.version, operationId: 'audited-confirm-once' }
    const result = await service.execute('integrations.confirm', input)
    const changes = await q('deviceChanges', { id: deviceId })
    expect(changes.total).toBe(1)
    const change = changes.rows[0]
    expect(change).toMatchObject({ action: 'integrations.update', objectId: deviceId, jobId: job.id, operationId: input.operationId, requestId: result.requestId, result: 'SUCCESS' })
    expect(change.before).not.toHaveProperty('sourceName')
    expect(change.after.sourceName).toBe('来源安全帽样本')
    for (const field of ['name', 'areaId', 'lifecycle', 'relation', 'remark']) {
      expect(change.before[field]).toEqual(before[field]); expect(change.after[field]).toEqual(before[field])
    }
    const created = result.data.rows.find(row => row.action === 'CREATE')
    const createdChanges = await q('deviceChanges', { id: created.targetId })
    expect(createdChanges.total).toBe(1)
    expect(createdChanges.rows[0]).toMatchObject({ action: 'integrations.create', before: null, after: { sourceName: '来源安全带样本' }, operationId: input.operationId, jobId: job.id })
    const audit = await q('audit', { pageSize: 100 })
    expect(await service.execute('integrations.confirm', input)).toEqual(result)
    expect(await q('deviceChanges', { id: deviceId })).toEqual(changes)
    expect(await q('deviceChanges', { id: created.targetId })).toEqual(createdChanges)
    expect(await q('audit', { pageSize: 100 })).toEqual(audit)
  })
  it.each(['DEVICE', 'PERSON'])('write-only target grant cannot inspect or import %s jobs', async kind => {
    setup(s => { s.roles.find(r => r.id === 'audit').grants = [{ operations: ['overview:read', 'integrations:read', 'integrations:write', kind === 'DEVICE' ? 'assets:write' : 'people:write'], siteIds: [siteId], areaIds: '*' }] })
    const failed = await preview(kind); await configure(kind); const ready = await preview(kind)
    service.login('demo-audit', 'Admin@2026')
    expect((await q('integrations')).total).toBe(6)
    expect((await q('integrationJobs')).total).toBe(0)
    expect((await q('integrationJobs', { connectorId: connectorId(kind) })).rows).toEqual([])
    await expect(q('integrationJob', { id: ready.id })).rejects.toMatchObject({ code: 404 })
    await expect(preview(kind)).rejects.toMatchObject({ code: 403 })
    await expect(confirm(ready)).rejects.toMatchObject({ code: 403 })
    await expect(execute('integrations.retry', failed)).rejects.toMatchObject({ code: 403 })
  })
  it('removing target read after preview hides its identifiers and count immediately', async () => {
    const operations = ['overview:read', 'integrations:read', 'integrations:write', 'assets:read', 'assets:write']
    setup(s => { s.roles.push({ id: 'target-reader', name: '接入读写', enabled: true, builtin: false, version: 1, grants: [{ operations, siteIds: [siteId], areaIds: '*' }] }); s.accounts.find(a => a.id === 'demo-audit').roleIds = ['target-reader'] })
    await configure(); service.login('demo-audit', 'Admin@2026'); const job = await preview(); service.login('demo-system', 'Admin@2026')
    const command = { siteId, id: 'target-reader', expectedVersion: 1, operationId: 'revoke-target-read', data: { name: '接入仅写', operations: operations.filter(op => op !== 'assets:read'), siteIds: [siteId], areaIds: '*' } }
    const p = await q('authorizationPreview', { type: 'roles.update', command })
    await service.execute('roles.update', { ...command, previewId: p.previewId })
    service.login('demo-audit', 'Admin@2026')
    expect((await q('integrationJobs')).total).toBe(0)
    await expect(q('integrationJob', { id: job.id })).rejects.toMatchObject({ code: 404 })
    await expect(confirm(job)).rejects.toMatchObject({ code: 403 })
  })
  it('return connectors have independent synthetic receipts and never create target entities', async () => {
    for (const kind of ['SUMMARY_RETURN', 'VERIFICATION_RETURN', 'WORK_TICKET', 'SAFETY']) {
      const c = await execute('integrations.receipt', await connector(kind))
      expect(c.status).toBe('NOT_CONNECTED'); expect(c.lastReceipt.source).toBe('本后台合成样本')
      await expect(execute('integrations.preview', c)).rejects.toMatchObject({ code: 400 })
    }
    expect((await q('overview')).counts.assets).toBe(36); expect((await q('master', { entity: 'people' })).total).toBe(25); expect((await q('integrationJobs')).total).toBe(0)
    expect((await connector()).lastReceipt).toBeUndefined()
  })
  it.each(['abort', 'context', 'identity'])('pending %s interruption leaves no preview or entities', async mode => {
    setup(() => {}, 20); await configure(); const c = await connector(), controller = new AbortController()
    const pending = service.execute('integrations.preview', { siteId, id: c.id, expectedVersion: c.version, operationId: 'cancel-preview' }, { signal: controller.signal })
    if (mode === 'abort') controller.abort()
    if (mode === 'context') service.changeContext()
    if (mode === 'identity') service.login('demo-site', 'Admin@2026')
    await expect(pending).rejects.toBeTruthy(); service.login('demo-system', 'Admin@2026')
    expect((await q('integrationJobs')).total).toBe(0); expect((await q('overview')).counts.assets).toBe(36)
  })
  it('reset restores connectors, settings and imported entities to the seed', async () => {
    await configure(); await confirm(await preview()); service.reset(); service.login('demo-system', 'Admin@2026')
    expect((await q('overview')).counts.assets).toBe(36); expect((await q('integrationJobs')).total).toBe(0); expect((await connector()).mappedSiteId).toBeNull()
  })
})


