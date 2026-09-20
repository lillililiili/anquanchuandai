import test from 'node:test'
import assert from 'node:assert/strict'
import { createSeed } from '../src/mock/seed.js'
import { createMemoryRepository } from '../src/mock/storage.js'
import { eventCommand, eventEditor } from '../src/mock/event-service.js'
import { queryDataset } from '../src/mock/engine.js'
import { validateEventRecords, validateEventDetail } from '../src/utils/event-contract.js'
import { buildWorkbench } from '../src/mock/workbench.js'
import { createTransport, MOCK_TOKEN_KEY } from '../src/mock/transport.js'
const siteId = 'mock-site-1', eventId = 'event-1-1', actor = 'owner'
const form = { conclusion: 'ACTION_REQUIRED', scene: '本地现场情况', measures: '本地措施', evidence: [] }
test('event commits canceled by abort/account changes never persist', async () => {
  for (const kind of ['abort', 'identity']) {
    const repo = createMemoryRepository(), before = repo.readDataset(), controller = new AbortController()
    let token = JSON.stringify({ kind: 'MOCK_ONLY', role: 'owner' })
    const transport = createTransport({ read: repo.readDataset, update: repo.transact, session: { getItem: key => key === MOCK_TOKEN_KEY ? token : null }, wait: async () => { if (kind === 'abort') controller.abort(); else token = JSON.stringify({ kind: 'MOCK_ONLY', role: 'reader' }) } })
    await assert.rejects(transport.post('/mock-events/claim', { siteId, eventId, expectedVersion: 1, operationId: 'cancel-test' }, { signal: controller.signal }), e => e.code === 'ERR_CANCELED')
    assert.deepEqual(repo.readDataset(), before)
  }
})
test('explicit source reports retain raw facts and never imply recovery or video on belts', () => {
  const d = createSeed(), helmet = d.entities.events.find(e => e.eventId === 'event-1-1'), belt = d.entities.events.find(e => e.eventId === 'event-1-2')
  assert.equal(helmet.deviceReport.category, 'HELMET_SOS'); assert.equal(belt.deviceReport.category, 'BELT_LOCK_REPORT')
  assert.equal(belt.deviceReport.rawType, belt.eventType)
  const fact = structuredClone(helmet.deviceReport), sourceTime = helmet.sourceUpdatedAt
  eventCommand(d, actor, 'claim', { siteId, eventId, expectedVersion: 1, operationId: 'report-claim' })
  assert.deepEqual(helmet.deviceReport, fact); assert.equal(helmet.sourceUpdatedAt, sourceTime)
  assert.equal(queryDataset(d, actor, '/api/portal/v1/events/event-1-2', { siteId }).video.state, 'NOT_INTEGRATED')
})
function setup() { const repo = createMemoryRepository(); let serial = 0; return { repo, execute(action, extra = {}, role = actor) { let result; repo.transact(d => { result = eventCommand(d, role, action, { siteId, eventId, expectedVersion: d.entities.events.find(e => e.eventId === eventId).version || 1, operationId: 'test-' + ++serial, ...extra }) }); return result }, data: () => repo.readDataset() } }
test('claim draft submit complete are separate; workbench/list/summary stay consistent', () => {
  const f = setup(), before = buildWorkbench(f.data(), actor, siteId).open.data.length
  f.execute('claim'); assert.equal(f.data().entities.events[0].phase, 'PROCESSING'); f.execute('verify')
  f.execute('draft', { form }); f.execute('draft', { form: { ...form, scene: 'changed' } })
  assert.equal(f.data().relations.eventDrafts.length, 1); assert.equal(f.data().entities.events[0].phase, 'AWAITING_VERIFICATION')
  f.execute('submit', { form }); assert.equal(f.data().relations.eventDrafts.length, 0); assert.equal(f.data().entities.events[0].phase, 'AWAITING_VERIFICATION')
  f.execute('complete'); assert.equal(f.data().entities.events[0].phase, 'LOCAL_COMPLETED'); assert.equal(buildWorkbench(f.data(), actor, siteId).open.data.length, before - 1)
  assert.throws(() => f.execute('submit', { form }), e => e.code === 409)
  const page = queryDataset(f.data(), actor, '/api/portal/v1/events', { siteId, mine: 'true' }), summary = queryDataset(f.data(), actor, '/api/portal/v1/events/summary', { siteId, mine: 'true' })
  assert.equal(page.total, summary.data.total); assert.equal(page.total, buildWorkbench(f.data(), actor, siteId).mine.data.length)
})
test('unconfirmed cannot complete; receipts do not change phase or original system', () => {
  const f = setup(); f.execute('claim'); f.execute('verify'); f.execute('submit', { form: { ...form, conclusion: 'UNCONFIRMED' } })
  assert.throws(() => f.execute('complete'), e => e.code === 409)
  const original = queryDataset(f.data(), actor, '/api/portal/v1/events/' + eventId, { siteId }).originalSystem
  f.execute('receipt', { channel: 'summary', result: 'FAILED' }); f.execute('receipt', { channel: 'verification', result: 'SUCCESS' })
  const detail = validateEventDetail(queryDataset(f.data(), actor, '/api/portal/v1/events/' + eventId, { siteId }), siteId, eventId)
  assert.equal(detail.event.phase, 'AWAITING_VERIFICATION'); assert.equal(detail.summaryDelivery.data.state, 'FAILED'); assert.equal(detail.verificationDelivery.data.state, 'SUCCESS'); assert.deepEqual(detail.originalSystem, original)
})
test('read-only cross-site invisible stale and repeated claim fail atomically', () => {
  const f = setup(), before = f.data()
  for (const [role, extra, code] of [['reader', {}, 403], [actor, { siteId: 'outside' }, 403], [actor, { eventId: 'event-2-1' }, 404], [actor, { expectedVersion: 99 }, 409]]) assert.throws(() => f.execute('claim', extra, role), e => e.code === code)
  assert.deepEqual(f.data(), before); f.execute('claim'); assert.throws(() => f.execute('claim'), e => e.code === 409)
})
test('duplicate operation replays without timeline; conflicting input rejected', () => {
  const d = createSeed(), input = { siteId, eventId, expectedVersion: 1, operationId: 'claim-one' }
  eventCommand(d, actor, 'claim', input); const count = d.relations.timeline.length
  assert.equal(eventCommand(d, actor, 'claim', input).replayed, true); assert.equal(d.relations.timeline.length, count)
  assert.throws(() => eventCommand(d, actor, 'verify', input), e => e.code === 409)
})
test('transfer only responsible to authorized actor; draft belongs to editor', () => {
  const f = setup(); f.execute('claim'); f.execute('transfer', { assigneeId: 'mock-verifier' })
  assert.throws(() => f.execute('verify'), e => e.code === 403); f.execute('verify', {}, 'verifier')
  f.execute('draft', { form }, 'verifier')
  assert.equal(eventEditor(f.data(), actor, { siteId, eventId }).draft, null)
  assert.equal(eventEditor(f.data(), 'verifier', { siteId, eventId }).draft.actorId, 'mock-verifier')
})
test('submitted evidence frozen immutable; missing fields/version/scope fail without record', () => {
  const f = setup(); f.execute('claim'); f.execute('verify')
  for (const bad of [{ ...form, scene: '' }, { ...form, measures: '' }, { ...form, evidence: [{ id: 'material-2-1', version: 1 }] }, { ...form, evidence: [{ id: 'material-1-2', version: 99 }] }]) assert.throws(() => f.execute('submit', { form: bad }))
  f.execute('submit', { form: { ...form, evidence: [{ id: 'material-1-2', version: 1 }] } })
  const d = f.data(), record = d.relations.verifications[0]; assert.equal(d.entities.materials.find(m => m.id === 'material-1-2').frozen, true)
  assert.equal(record.evidence.data[0].associationSource, 'MANUAL_MOCK')
  const q = { siteId, pageNum: 1, pageSize: 20 }
  validateEventRecords(queryDataset(d, actor, `/api/portal/v1/events/${eventId}/verifications`, q), q, eventId, 'verifications')
  validateEventRecords(queryDataset(d, actor, `/api/portal/v1/events/${eventId}/timeline`, q), q, eventId, 'timeline')
})
