import test from 'node:test'
import assert from 'node:assert/strict'
import { normalizeRing } from '../src/utils/fence-geometry.js'
import { createSeed } from '../src/mock/seed.js'
import { createMemoryRepository } from '../src/mock/storage.js'
import { spatialCommand, spatialRead } from '../src/mock/spatial-service.js'
import { inspectFile, MAX_FILE_BYTES } from '../src/mock/local-file.js'
import { queryDataset } from '../src/mock/engine.js'
import { validateEventDetail } from '../src/utils/event-contract.js'
import { createTransport, MOCK_TOKEN_KEY } from '../src/mock/transport.js'
const siteId = 'mock-site-1'
const base = { siteId, operationId: 'first', name: '预置编辑围栏', ruleType: 'DENY_ENTRY', appliesTo: 'ALL', ring: [[0, 0], [1, 0], [1, 1], [0, 1]] }
test('simple polygon closes; zero coordinates valid; invalid geometry rejected', () => {
  assert.equal(normalizeRing(base.ring).length, 5)
  for (const nodes of [[[0, 0], [1, 1]], [[0, 0], [1, 1], [0, 1], [1, 0]], [[0, 0], [1, 0], [2, 0]], [[NaN, 0], [1, 1], [2, 1]], [[0, 0], [1, 1], [0, 0], [0, 1]], [[181, 0], [1, 0], [1, 1]]]) assert.throws(() => normalizeRing(nodes))
})
test('fence create/update/toggle/delete retains immutable versions; duplicate id idempotent', () => {
  const d = createSeed(), r = spatialCommand(d, 'owner', 'fence-save', base)
  assert.equal(r.version, 1)
  assert.equal(spatialCommand(d, 'owner', 'fence-save', base).replayed, true)
  assert.throws(() => spatialCommand(d, 'owner', 'fence-save', { ...base, name: 'other' }), e => e.code === 409)
  spatialCommand(d, 'owner', 'fence-toggle', { siteId, id: r.id, expectedVersion: 1, operationId: 'toggle' })
  spatialCommand(d, 'owner', 'fence-delete', { siteId, id: r.id, expectedVersion: 2, operationId: 'delete' })
  const history = spatialRead(d, 'reader', 'versions', { siteId, id: r.id })
  assert.deepEqual(history.map(i => i.version), [1, 2, 3]); assert.equal(history[0].status, 'DISABLED')
  assert.ok(!d.entities.fences.some(i => i.id === r.id))
})
test('scope permissions and stale versions fail without committing draft', () => {
  const repo = createMemoryRepository(), before = repo.readDataset()
  for (const [role, input, code] of [['reader', base, 403], ['owner', { ...base, siteId: 'outside' }, 403], ['owner', { ...base, id: 'fence-2-1' }, 404], ['owner', { ...base, id: 'fence-1-1', expectedVersion: 9 }, 409]]) {
    assert.throws(() => repo.transact(d => spatialCommand(d, role, 'fence-save', input)), e => e.code === code)
  }
  assert.deepEqual(repo.readDataset(), before)
})
test('material file signature MIME size guard', async () => {
  const png = new Blob([Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10])], { type: 'image/png' })
  assert.equal((await inspectFile(png, '预置.png')).type, 'PHOTO')
  await assert.rejects(inspectFile(png, 'bad.svg'))
  await assert.rejects(inspectFile(new Blob(['<html>'], { type: 'image/png' }), 'bad.png'))
  await assert.rejects(inspectFile(new Blob([new Uint8Array(MAX_FILE_BYTES + 1)], { type: 'image/png' }), 'large.png'))
})
test('material import association freeze blocks mutation; blob scope and reset', () => {
  const repo = createMemoryRepository(), file = new Blob(['fixture'], { type: 'image/png' }), metadata = { name: '预置.png', type: 'PHOTO', mime: 'image/png', size: file.size }
  let result
  repo.transact(d => { result = spatialCommand(d, 'owner', 'material-import', { siteId, operationId: 'image', file, digest: 'test-hash' }, metadata) })
  assert.equal(spatialRead(repo.readDataset(), 'reader', 'blob', { siteId, id: result.id }).blob.size, file.size)
  repo.transact(d => spatialCommand(d, 'owner', 'material-associate', { siteId, id: result.id, expectedVersion: 1, operationId: 'associate', personId: '9007199254740993101', eventId: 'event-1-1' }))
  repo.transact(d => spatialCommand(d, 'owner', 'material-reference', { siteId, id: result.id, expectedVersion: 2, operationId: 'freeze', eventId: 'event-1-1' }))
  assert.throws(() => repo.transact(d => spatialCommand(d, 'owner', 'material-delete', { siteId, id: result.id, expectedVersion: 2, operationId: 'remove' })), e => e.code === 409)
  assert.equal(repo.readDataset().relations.materialReferences[0].digest, 'test-hash')
  const detail = queryDataset(repo.readDataset(), 'owner', '/api/portal/v1/events/event-1-1', { siteId })
  validateEventDetail(detail, siteId, 'event-1-1')
  assert.equal(detail.materials.data.find(i => i.id === result.id).attribution, 'MANUAL_MOCK')
  assert.throws(() => spatialRead(repo.readDataset(), 'reader', 'blob', { siteId: 'mock-site-2', id: result.id }), e => e.code === 403)
  repo.resetDataset(); assert.ok(!repo.readDataset().entities.materials.some(i => i.id === result.id))
})
test('200MB budget rejects additional file without evicting frozen evidence', () => {
  const repo = createMemoryRepository(), chunk = new Blob([new Uint8Array(MAX_FILE_BYTES)], { type: 'image/png' })
  for (let i = 0; i < 4; i++) repo.transact(d => spatialCommand(d, 'owner', 'material-import', { siteId, operationId: 'large' + i, file: chunk }, { name: 'fixture.png', mime: 'image/png', type: 'PHOTO', size: chunk.size }))
  assert.throws(() => repo.transact(d => spatialCommand(d, 'owner', 'material-import', { siteId, operationId: 'overflow', file: new Blob(['x']) }, { name: 'x.png' })), e => e.code === 413)
  assert.equal(Object.keys(repo.readDataset().entities.materialBlobs).length, 4)
})
test('existing verification evidence is frozen and source failure cannot become success', () => {
  const repo = createMemoryRepository()
  assert.throws(() => repo.transact(d => spatialCommand(d, 'owner', 'material-delete', { siteId, id: 'material-1-1', operationId: 'old-evidence', expectedVersion: 1 })), e => e.code === 409)
  repo.saveScenario({ module: 'fences', mode: 'failure' })
  assert.throws(() => repo.transact(d => spatialCommand(d, 'owner', 'fence-save', base)), e => e.code === 503)
  assert.equal(repo.readDataset().entities.fences.length, 50)
})
test('cancelled or changed session before commit creates no fence', async () => {
  const repo = createMemoryRepository(), session = new Map([[MOCK_TOKEN_KEY, JSON.stringify({ kind: 'MOCK_ONLY', role: 'owner' })]])
  let release
  const request = createTransport({ read: repo.readDataset, update: repo.transact, session: { getItem: k => session.get(k) }, wait: () => new Promise(resolve => { release = resolve }) })
  const controller = new AbortController(), pending = request.post('/mock-spatial/fence-save', base, { signal: controller.signal })
  await new Promise(resolve => setTimeout(resolve, 0)); controller.abort(); release()
  await assert.rejects(pending, e => e.code === 'ERR_CANCELED')
  const switched = request.post('/mock-spatial/fence-save', base)
  await new Promise(resolve => setTimeout(resolve, 0)); session.set(MOCK_TOKEN_KEY, 'other'); release()
  await assert.rejects(switched, e => e.code === 'ERR_CANCELED')
  assert.equal(repo.readDataset().entities.fences.length, 50)
})
