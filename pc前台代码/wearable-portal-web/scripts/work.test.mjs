import test from 'node:test'
import assert from 'node:assert/strict'
import { createMemoryRepository } from '../src/mock/storage.js'
import { queryWorks, workCommand } from '../src/mock/work-service.js'
import { buildWorkbench } from '../src/mock/workbench.js'
import { projectDataset } from '../src/mock/assignment-model.js'
import { createTransport, MOCK_TOKEN_KEY } from '../src/mock/transport.js'
import { safeWorkReturn, workQuery } from '../src/utils/work-route.js'
import { validateWorkResult } from '../src/utils/work-contract.js'
const siteId = 'mock-site-1', workId = 'work-1-1', personId = '9007199254740993101'
function setup() { const repo = createMemoryRepository(); let seq = 0; return { repo, data: () => repo.readDataset(), run(action, extra = {}, role = 'owner') { let result; repo.transact(d => { result = workCommand(d, role, action, { siteId, workId, expectedVersion: d.relations.monitoring[0].version, operationId: 'test-work-' + ++seq, ...extra }) }); return result } } }
test('work paging filters same totals and safe routes', () => {
  const d = setup().data(), q = { siteId, pageNum: 2, pageSize: 20 }, r = validateWorkResult(queryWorks(d, 'owner', q), q)
  assert.equal(r.total, 25); assert.equal(r.items.length, 5)
  assert.equal(queryWorks(d, 'owner', { siteId, keyword: 'WORK-1-25' }).total, 1)
  assert.equal(queryWorks(d, 'owner', { siteId: 'mock-site-empty' }).total, 0)
  assert.equal(safeWorkReturn('//evil'), '/supervision'); assert.equal(safeWorkReturn('/supervision/work-1-1?siteId=mock-site-1&evil=x', true), '/supervision/work-1-1?siteId=mock-site-1')
  assert.deepEqual(workQuery({ pageSize: 101, state: 'INVALID' }), {})
  for (const q of [{ pageSize: 101 }, { state: 'BAD' }, { extra: true }, { from: '2026-01-01T00:00:00Z' }, { areaId: 'outside' }]) assert.throws(() => queryWorks(d, 'owner', { siteId, ...q }), e => e.code === 400)
})
test('start guards, lifecycle, source facts and independent events', () => {
  const f = setup(), source = f.data().entities.works[0], events = f.data().entities.events
  assert.throws(() => f.run('start'), e => e.code === 400)
  f.run('arrange', { personIds: [], supervisorId: personId }); assert.throws(() => f.run('start'), e => e.code === 400)
  f.run('arrange', { personIds: [personId], supervisorId: personId }); f.run('start'); f.run('pause'); f.run('resume')
  assert.throws(() => f.run('finish', { confirmFinish: true, expectedOpenCount: 0 }), e => e.code === 409)
  f.run('finish', { confirmFinish: true, expectedOpenCount: 1 })
  assert.equal(f.data().relations.monitoring[0].state, 'ENDED'); assert.equal(f.data().relations.monitoring[0].timeline.length, 6)
  assert.deepEqual(f.data().entities.works[0], source); assert.deepEqual(f.data().entities.events, events)
  assert.throws(() => f.run('start'), e => e.code === 409)
})
test('permissions versions invisible scope and idempotency remain atomic', () => {
  const f = setup(), before = f.data()
  for (const [role, extra, code] of [['reader', {}, 403], ['verifier', {}, 403], ['owner', { siteId: 'unknown' }, 403], ['owner', { workId: 'work-2-1' }, 404], ['owner', { expectedVersion: 3 }, 409], ['owner', { personIds: ['outside'] }, 400]]) assert.throws(() => f.run('arrange', { supervisorId: personId, personIds: [personId], ...extra }, role), e => e.code === code)
  assert.deepEqual(f.data(), before)
  const q = { operationId: 'same-op', expectedVersion: 1, supervisorId: personId, personIds: [personId] }
  f.run('arrange', q); assert.equal(f.run('arrange', q).replayed, true); assert.equal(f.data().relations.monitoring[0].timeline.length, 1)
  assert.throws(() => f.run('arrange', { ...q, personIds: [] }), e => e.code === 409)
})
test('same membership projects through people and workbench, checks do not authorize work', () => {
  const f = setup(), other = '9007199254740993105'
  f.run('arrange', { supervisorId: personId, personIds: [personId, other] })
  f.run('check', { personId: other, result: 'NEEDS_REVIEW', note: '报告过期，需要现场核实' })
  const d = f.data(), summary = buildWorkbench(d, 'owner', siteId).works.data[0]
  assert.equal(summary.participantCount, 2); assert.equal(summary.monitorState, 'PENDING')
  assert.equal(projectDataset(d).entities.people.find(p => p.personId === other).works.data.find(w => w.workId === workId).participantCount, 2)
  validateWorkResult(queryWorks(d, 'owner', { siteId, workId }), { siteId, workId })
})
test('source failures and denied sections independent; cross-site query rejects', () => {
  const d = setup().data()
  assert.throws(() => queryWorks(d, 'verifier', { siteId: 'mock-site-2' }), e => e.code === 403)
  assert.throws(() => queryWorks(d, '', { siteId }), e => e.code === 401)
  d.config = { module: 'events', mode: 'forbidden' }
  const r = queryWorks(d, 'owner', { siteId, workId }); assert.equal(r.events.state, 'FORBIDDEN'); assert.equal(r.work.openEventCount, null); assert.equal(r.people.state, 'AVAILABLE')
  d.config = { module: 'works', mode: 'not-integrated' }; assert.equal(queryWorks(d, 'owner', { siteId }).total, null)
  d.config.mode = 'failure'; assert.throws(() => queryWorks(d, 'owner', { siteId }), e => e.code === 503)
})
test('cancel or change identity before work commit writes nothing', async () => {
  for (const kind of ['abort', 'identity']) {
    const repo = createMemoryRepository(), before = repo.readDataset(), ctrl = new AbortController()
    let token = JSON.stringify({ kind: 'MOCK_ONLY', role: 'owner' })
    const t = createTransport({ read: repo.readDataset, update: repo.transact, session: { getItem: k => k === MOCK_TOKEN_KEY ? token : null }, wait: async () => { if (kind === 'abort') ctrl.abort(); else token = JSON.stringify({ kind: 'MOCK_ONLY', role: 'reader' }) } })
    await assert.rejects(t.post('/mock-works/arrange', { siteId, workId, operationId: 'cancel', expectedVersion: 1, personIds: [personId], supervisorId: personId }, { signal: ctrl.signal }), e => e.code === 'ERR_CANCELED')
    assert.deepEqual(repo.readDataset(), before)
  }
})
