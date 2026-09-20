import test from 'node:test'
import assert from 'node:assert/strict'
import { createMemoryRepository } from '../src/mock/storage.js'
import { queryDispatch, dispatchCommand, dispatchData, closeActiveDispatch } from '../src/mock/dispatch-service.js'
import { safeDispatchReturn, dispatchQuery } from '../src/utils/dispatch-route.js'
import { createTransport, MOCK_TOKEN_KEY } from '../src/mock/transport.js'
import { queryDataset } from '../src/mock/engine.js'
import { validateEventDetail, validateEventPage } from '../src/utils/event-contract.js'
import { validateDispatch } from '../src/utils/dispatch-contract.js'
const siteId = 'mock-site-1', one = 'device-1-1-helmet', two = 'device-1-2-helmet'
function setup() { const repo = createMemoryRepository(); let n = 0; return { repo, read: () => repo.readDataset(), run(action, extra = {}, role = 'owner') { let r; repo.transact(d => { r = dispatchCommand(d, role, action, { siteId, expectedVersion: dispatchData(d).version, operationId: 'dispatch-test-' + ++n, ...extra }) }); return r } } }
test('dispatch paging and source entry scope preserve long IDs', () => {
  const s = setup(), q = { siteId, pageNum: 2 }
  assert.equal(queryDispatch(s.read(), 'owner', q).items.length, 20)
  assert.equal(queryDispatch(s.read(), 'owner', { siteId, personId: '9007199254740993101' }).suggested[0].personId, '9007199254740993101')
  assert.equal(queryDispatch(s.read(), 'owner', { siteId: 'mock-site-empty' }).total, 0)
  assert.throws(() => queryDispatch(s.read(), 'owner', { siteId, pageSize: 101 }), { code: 400 })
  assert.throws(() => queryDispatch(s.read(), 'reader', { siteId: 'mock-site-2' }), { code: 403 })
  assert.throws(() => queryDispatch(s.read(), 'owner', { siteId, workId: 'work-2-1' }), { code: 404 })
  assert.throws(() => queryDispatch(s.read(), null, { siteId }), { code: 401 })
  assert.deepEqual(dispatchQuery({ siteId, personId: '9007199254740993101', returnTo: '//evil', pageSize: '999' }), { siteId, personId: '9007199254740993101' })
  assert.equal(safeDispatchReturn('//evil.test'), '/dispatch')
  assert.equal(safeDispatchReturn('/dispatch/sos/sos-1?siteId=mock-site-1&url=evil'), '/dispatch/sos/sos-1?siteId=mock-site-1')
})
test('one global session, mixed explicit outcomes, terminal participants do not reconnect', () => {
  const s = setup(), result = s.run('start', { deviceIds: [one, two], mode: 'VOICE' })
  assert.throws(() => s.run('start', { deviceIds: [one], mode: 'VOICE' }), { code: 409 })
  s.run('participant', { sessionId: result.id, deviceId: one, state: 'CONNECTED' })
  let session = dispatchData(s.read()).sessions[0]
  assert.deepEqual(session.participants.map(p => p.state), ['CONNECTED', 'RINGING'])
  s.run('participant', { sessionId: result.id, deviceId: two, state: 'REJECTED' })
  assert.throws(() => s.run('participant', { sessionId: result.id, deviceId: two, state: 'CONNECTED' }), { code: 409 })
  s.run('participant', { sessionId: result.id, deviceId: one, state: 'LEFT' })
  session = dispatchData(s.read()).sessions[0]; assert.equal(session.state, 'ENDED')
  const next = s.run('start', { deviceIds: [one], mode: 'VIDEO' }); s.run('participant', { sessionId: next.id, deviceId: one, state: 'TIMED_OUT' })
  assert.equal(dispatchData(s.read()).sessions[0].state, 'ENDED')
})
test('unknown belt phone and watch do not become callable; readonly and stale writes rejected atomically', () => {
  const s = setup(), before = s.read()
  for (const q of [{ deviceIds: ['device-1-1-belt'], mode: 'VOICE' }, { deviceIds: ['device-1-1-watch'], mode: 'VIDEO' }, { deviceIds: [one], mode: 'PHONE' }]) assert.throws(() => s.run('start', q))
  assert.throws(() => s.run('start', { deviceIds: [one], mode: 'VOICE' }, 'verifier'), { code: 403 })
  assert.throws(() => s.run('start', { deviceIds: [one], mode: 'VOICE', expectedVersion: 99 }), { code: 409 })
  assert.deepEqual(s.read(), before)
})
test('operation replay does not duplicate session, group or broadcast', () => {
  const s = setup(), q = { operationId: 'idempotent', expectedVersion: 1, deviceIds: [one], name: '预置协助组' }
  s.run('group', q); assert.equal(s.run('group', q).replayed, true)
  assert.equal(dispatchData(s.read()).groups.length, 1)
  assert.throws(() => s.run('group', { ...q, name: '不同输入' }), { code: 409 })
  assert.equal(s.read().entities.teams.length, 4)
})
test('broadcast independent task validates text and per-target receipts', () => {
  const s = setup(); assert.throws(() => s.run('broadcast', { deviceIds: [one], text: '字'.repeat(201) }), { code: 400 })
  const task = s.run('broadcast', { deviceIds: [one, two], text: '本地撤离说明，仅预置' })
  s.run('receipt', { taskId: task.id, deviceId: one, state: 'SUCCESS' })
  s.run('receipt', { taskId: task.id, deviceId: two, state: 'FAILED' })
  const d = dispatchData(s.read()); assert.equal(d.sessions.length, 0); assert.deepEqual(d.broadcasts[0].recipients.map(r => r.state), ['SUCCESS', 'FAILED'])
  assert.throws(() => s.run('receipt', { taskId: task.id, deviceId: one, state: 'FAILED' }), { code: 409 })
})
test('SOS independent of session, unknown attribution and event contract remain valid', () => {
  const s = setup(), r = s.run('sos', { deviceId: 'device-1-1-belt' }), d = s.read(), event = d.entities.events[0]
  assert.equal(event.eventId, r.eventId); assert.equal(event.person.data, null); assert.equal(event.workId, null); assert.equal(dispatchData(d).sessions.length, 0)
  validateEventDetail(queryDataset(d, 'owner', '/api/portal/v1/events/' + r.eventId, { siteId }), siteId, r.eventId)
  validateEventPage(queryDataset(d, 'owner', '/api/portal/v1/events', { siteId }), { siteId })
  const helmet = s.run('sos', { deviceId: one }), session = s.run('start', { deviceIds: [one], mode: 'VOICE', eventId: helmet.eventId })
  s.run('end', { sessionId: session.id })
  assert.equal(s.read().entities.events.find(e => e.eventId === helmet.eventId).phase, 'UNCLAIMED')
  s.repo.resetDataset(); assert.equal(s.read().entities.events.length, 50)
})
test('dispatch unavailable, failure and source section masking do not invent data', () => {
  const s = setup(), d = s.read(); d.config = { module: 'dispatch', mode: 'not-integrated' }
  assert.throws(() => queryDispatch(d, 'owner', { siteId }), { errorCode: 'NOT_INTEGRATED' })
  d.config.mode = 'failure'; assert.throws(() => queryDispatch(d, 'owner', { siteId }), { code: 503 })
  d.config = { module: 'people', mode: 'forbidden' }; assert.equal(queryDispatch(d, 'owner', { siteId }).items.some(c => c.personId), false)
  s.run('start', { deviceIds: [one], mode: 'VOICE' }); s.repo.transact(d => closeActiveDispatch(d, '失效清理'))
  assert.equal(dispatchData(s.read()).sessions[0].state, 'ENDED')
})
test('cancel and identity change before dispatch commit write nothing', async () => {
  for (const changeIdentity of [false, true]) {
    const repo = createMemoryRepository(), values = new Map([[MOCK_TOKEN_KEY, JSON.stringify({ kind: 'MOCK_ONLY', role: 'owner' })]]), signal = new AbortController()
    const transport = createTransport({ read: repo.readDataset, update: repo.transact, session: { getItem: k => values.get(k) }, wait: async () => { if (changeIdentity) values.set(MOCK_TOKEN_KEY, 'changed'); else signal.abort() } })
    await assert.rejects(transport.post('/mock-dispatch/start', { siteId, deviceIds: [one], mode: 'VOICE', operationId: 'cancel', expectedVersion: 1 }, { signal: signal.signal }), { code: 'ERR_CANCELED' })
    assert.equal(dispatchData(repo.readDataset()).sessions.length, 0)
  }
})
test('dispatch contract validates scoped snapshots and rejects malformed participants', () => {
  const s = setup(); s.run('start', { deviceIds: [one], mode: 'VOICE' })
  const q = { siteId }, r = queryDispatch(s.read(), 'owner', q)
  validateDispatch(r, q)
  const bad = structuredClone(r); bad.sessions[0].participants[0].state = 'LIVE'
  assert.throws(() => validateDispatch(bad, q))
  assert.throws(() => validateDispatch(r, { siteId: 'mock-site-2' }))
  const id = s.run('sos', { deviceId: one }).eventId, d = s.read()
  d.config = { module: 'locations', mode: 'forbidden' }
  assert.equal(queryDispatch(d, 'owner', { siteId, eventId: id }).sos.find(e => e.eventId === id).positionSnapshot, null)
  assert.equal(queryDataset(d, 'owner', '/api/portal/v1/events/' + id, { siteId }).event.positionSnapshot, undefined)
})
