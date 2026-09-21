import test from 'node:test'
import assert from 'node:assert/strict'
import { createSeed } from '../src/mock/seed.js'
import { createMemoryRepository } from '../src/mock/storage.js'
import { eventCommand } from '../src/mock/event-service.js'
import { queryDataset } from '../src/mock/engine.js'
import { validateAlarmPage, validateAlarmDetail, legacyAlarm } from '../src/utils/alarm-contract.js'
import { buildWorkbench } from '../src/mock/workbench.js'
import { workSummary } from '../src/mock/work-model.js'
import { buildStatistics } from '../src/mock/statistics-service.js'
import { createTransport, MOCK_TOKEN_KEY } from '../src/mock/transport.js'
import { dispatchCommand, queryDispatch, dispatchData } from '../src/mock/dispatch-service.js'
const siteId = 'mock-site-1', eventId = 'event-1-1'
const input = (extra = {}) => ({ siteId, eventId, expectedVersion: 1, operationId: 'handle-one', description: '  已联系现场检查  ', ...extra })
const read = (d, q = {}) => queryDataset(d, 'owner', '/api/portal/v1/events', { siteId, ...q })
test('direct handle updates list detail workbench work and statistics; facts stay unchanged', () => {
  const d = createSeed(), e = d.entities.events[0], fact = structuredClone(e.deviceReport), occurredAt = e.occurredAt
  const before = buildWorkbench(d, 'owner', siteId).open.data.length
  eventCommand(d, 'verifier', 'handle', input())
  assert.equal(e.handlingStatus, 'HANDLED'); assert.equal(e.handlingNote, '已联系现场检查'); assert.equal(e.handledBy.id, 'mock-verifier')
  assert.deepEqual(e.deviceReport, fact); assert.equal(e.occurredAt, occurredAt)
  assert.equal(read(d, { handlingStatus: 'UNHANDLED' }).total, before - 1)
  assert.equal(buildWorkbench(d, 'owner', siteId).open.data.length, before - 1)
  assert.equal(buildWorkbench(d, 'verifier', siteId).mine.data.length, before - 1)
  assert.equal(workSummary(d, d.entities.works[0]).openEventCount, 0)
  validateAlarmDetail(queryDataset(d, 'reader', '/api/portal/v1/events/' + eventId, { siteId }), siteId, eventId)
  const report = buildStatistics(d, 'owner', { siteId, from: '2000-01-01T00:00:00Z', to: '2099-01-01T00:00:00Z' })
  assert.equal(report.metrics.find(m => m.id === 'completed').count, d.entities.events.filter(e => e.siteId === siteId && e.handlingStatus === 'HANDLED').length)
})
test('three equipment types, distinct impact/fall, historical names and half-open times filter correctly', () => {
  const d = createSeed('2026-09-20T08:00:00Z')
  for (const deviceType of ['HELMET', 'BELT', 'WATCH']) {
    const p = validateAlarmPage(read(d, { deviceType }), { siteId })
    assert.ok(p.total > 0); assert.ok(p.items.every(e => e.deviceType === deviceType))
  }
  for (const eventType of ['HELMET_OFF_HAT', 'HELMET_FALL', 'HELMET_PROXIMITY', 'HELMET_SILENCE', 'HELMET_IMPACT_REPORT']) assert.ok(read(d, { eventType }).total)
  assert.ok(read(d, { keyword: '人员1-01' }).items.some(e => e.eventId === eventId))
  assert.equal(read(d, { keyword: 'no-such-device' }).total, 0)
  assert.equal(read(d, { pageNum: 2 }).items.length, 5)
  assert.equal(read(d, { from: '2026-09-20T05:00:00Z', to: '2026-09-20T06:30:00Z' }).total, 0)
  assert.ok(read(d, { from: '2026-09-20T06:30:00Z', to: '2026-09-20T07:00:00Z' }).total > 0)
  assert.equal(read(d, { deviceType: 'WATCH' }).items[0].person.data, null)
})
test('invalid description, permissions, versions and sources never commit', () => {
  const repo = createMemoryRepository(), before = repo.readDataset()
  for (const [role, extra, code] of [['reader', {}, 403], ['owner', { siteId: 'outside' }, 403], ['owner', { eventId: 'event-2-1' }, 404], ['owner', { expectedVersion: 99 }, 409], ['owner', { description: '  ' }, 400], ['owner', { description: '字'.repeat(1001) }, 400]]) {
    assert.throws(() => repo.transact(d => eventCommand(d, role, 'handle', input(extra))), e => e.code === code)
    assert.deepEqual(repo.readDataset(), before)
  }
  for (const mode of ['failure', 'not-integrated', 'forbidden']) {
    const d = createSeed(); d.config = { module: 'events', mode }; const saved = structuredClone(d)
    assert.throws(() => eventCommand(d, 'owner', 'handle', input())); assert.deepEqual(d, saved)
  }
})
test('idempotency, immutable handled records and removed workflows', () => {
  const d = createSeed()
  eventCommand(d, 'owner', 'handle', input()); const before = structuredClone(d)
  assert.equal(eventCommand(d, 'owner', 'handle', input()).replayed, true); assert.deepEqual(d, before)
  for (const extra of [{ description: 'different' }, { operationId: 'second', expectedVersion: 2 }]) assert.throws(() => eventCommand(d, 'owner', 'handle', input(extra)), { code: 409 })
  for (const action of ['claim', 'transfer', 'verify', 'draft', 'submit', 'complete', 'receipt']) assert.throws(() => eventCommand(d, 'owner', action, input()), { code: 400 })
  assert.equal(legacyAlarm({ phase: 'LOCAL_COMPLETED', legacyHandled: 1 }).handlingStatus, 'UNKNOWN')
})
test('transport abort and account changes leave no handling record', async () => {
  for (const reason of ['abort', 'identity']) {
    const repo = createMemoryRepository(), before = repo.readDataset(), controller = new AbortController()
    let token = JSON.stringify({ kind: 'MOCK_ONLY', role: 'owner' })
    const t = createTransport({ read: repo.readDataset, update: repo.transact, session: { getItem: k => k === MOCK_TOKEN_KEY ? token : null }, wait: async () => { if (reason === 'abort') controller.abort(); else token = 'changed' } })
    await assert.rejects(t.post('/mock-events/handle', input(), { signal: controller.signal }), { code: 'ERR_CANCELED' })
    assert.deepEqual(repo.readDataset(), before)
  }
})
test('SOS handling and active communication remain independent', () => {
  const d = createSeed()
  const result = dispatchCommand(d, 'owner', 'sos', { siteId, deviceId: 'device-1-1-helmet', operationId: 'sos-alarm', expectedVersion: dispatchData(d).version })
  const session = dispatchCommand(d, 'owner', 'start', { siteId, deviceIds: ['device-1-1-helmet'], mode: 'VOICE', eventId: result.eventId, operationId: 'session-alarm', expectedVersion: dispatchData(d).version })
  eventCommand(d, 'owner', 'handle', input({ eventId: result.eventId }))
  const state = queryDispatch(d, 'owner', { siteId })
  assert.equal(state.sessions.find(s => s.id === session.id).state, 'ACTIVE')
  assert.equal(state.sos.find(e => e.eventId === result.eventId).handlingStatus, 'HANDLED')
})
