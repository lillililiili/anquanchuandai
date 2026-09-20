import test from 'node:test'
import assert from 'node:assert/strict'
import { createSeed } from '../src/mock/seed.js'
import { createMemoryRepository } from '../src/mock/storage.js'
import { queryEquipment, assignmentCommand } from '../src/mock/equipment-service.js'
import { queryDataset } from '../src/mock/engine.js'
import { createTransport, MOCK_TOKEN_KEY } from '../src/mock/transport.js'
import { equipmentQuery, safeEquipmentReturn } from '../src/utils/equipment-route.js'
const siteId = 'mock-site-1', base = '/api/portal/v1/equipment', personId = '9007199254740993102'
const options = (d, extra = {}) => queryEquipment(d, 'owner', base + '/options', { siteId, personId, type: 'HELMET', ...extra })
const payload = (p, operationId = 'test-operation') => ({ siteId, personId: p.person.personId, deviceId: p.device.deviceId, expectedVersion: p.expectedVersion, operationId, ...(p.assignment ? { assignmentId: p.assignment.assignmentId } : {}) })
const count = d => queryDataset(d, 'owner', '/api/portal/v1/workbench', { siteId }).equipment.data.length
test('issue then return: 68/69/68, immutable evidence and two distinct history rows', () => {
  const d = createSeed(), evidence = structuredClone([d.entities.events, d.entities.materials, d.entities.tracks]), before = d.relations.history.length
  assert.equal(count(d), 68)
  const p = options(d).choices[0], input = payload(p)
  assignmentCommand(d, 'owner', 'issue', input)
  assert.equal(count(d), 69)
  const issued = structuredClone(d.relations.history[0])
  const v = queryDataset(d, 'owner', '/api/portal/v1/video-sources/' + p.device.deviceId, { siteId })
  assert.equal(v.person.data[0].id, personId); assert.equal(v.person.data[0].snapshotKind, 'CURRENT')
  assignmentCommand(d, 'owner', 'return', payload(options(d).current[0], 'return-operation'))
  assert.equal(count(d), 68); assert.equal(d.relations.history.length, before + 2)
  assert.deepEqual(d.relations.history[1], issued)
  assert.deepEqual([d.entities.events, d.entities.materials, d.entities.tracks], evidence)
  assert.equal(count(createSeed()), 68)
})
test('all three types; offline, stale and unknown communication do not block ledger', () => {
  for (const type of ['HELMET', 'BELT', 'WATCH']) {
    const d = createSeed(), p = options(d, { type }).choices[0]
    const device = d.entities.devices.find(x => x.deviceId === p.device.deviceId)
    device.communication.state = 'OFFLINE'; device.communication.freshness = 'STALE'
    assignmentCommand(d, 'owner', 'issue', payload(p))
    device.communication.state = 'UNKNOWN'
    assignmentCommand(d, 'owner', 'return', payload(options(d, { type }).current[0], 'return'))
    assert.equal(count(d), 68)
  }
})
test('unknown and conflict relations cannot be changed; seed return retains unknown start', () => {
  const d = createSeed()
  for (const id of ['9007199254740993103', '9007199254740993104']) {
    assert.equal(options(d, { personId: id }).choices.length, 0)
    const p = options(d).choices[0], target = d.entities.people.find(x => x.personId === id)
    const input = payload(p); input.personId = id; input.expectedVersion.slot = target.slots.helmet.version
    assert.throws(() => assignmentCommand(d, 'owner', 'issue', input), e => e.code === 409)
  }
  const p = options(d, { personId: '9007199254740993101' }).current[0]
  assignmentCommand(d, 'owner', 'return', payload(p, 'seed-return'))
  assert.equal(d.relations.history[0].startedAt, null)
})
test('permissions, cross-site and invisible objects fail closed', () => {
  const d = createSeed(), input = payload(options(d).choices[0])
  for (const role of ['reader', 'verifier']) assert.throws(() => assignmentCommand(d, role, 'issue', input), e => e.code === 403)
  assert.throws(() => queryEquipment(d, '', base, { siteId }), e => e.code === 401)
  assert.throws(() => queryEquipment(d, 'reader', base, { siteId: 'mock-site-2' }), e => e.code === 403)
  assert.throws(() => assignmentCommand(d, 'owner', 'issue', { ...input, siteId: 'mock-site-2' }), e => e.code === 404)
})
test('idempotency, version conflicts and failed transaction produce no extra history', () => {
  const repo = createMemoryRepository(), before = repo.readDataset(), input = payload(options(before).choices[0])
  const run = x => repo.transact(d => { if (assignmentCommand(d, 'owner', 'issue', x).replayed) return false })
  run(input); const committed = repo.readDataset(); run(input); assert.deepEqual(repo.readDataset(), committed)
  assert.throws(() => run({ ...input, deviceId: 'device-1-2-watch' }), e => e.code === 409)
  assert.throws(() => run({ ...input, operationId: 'another' }), e => e.code === 409)
  assert.deepEqual(repo.readDataset(), committed)
  repo.saveScenario({ module: 'equipment', mode: 'failure' })
  const fault = repo.readDataset()
  assert.throws(() => repo.transact(d => assignmentCommand(d, 'owner', 'issue', { ...input, operationId: 'failure' })), e => e.code === 503)
  assert.deepEqual(repo.readDataset(), fault)
})
test('query pagination, long string IDs and safe return allowlists', () => {
  const d = createSeed(), q = { siteId, type: 'WATCH', pageNum: 2, pageSize: 20 }
  const page = queryEquipment(d, 'owner', base, q)
  assert.equal(page.total, 25); assert.equal(page.items.length, 5)
  assert.equal(typeof options(d).choices[0].person.personId, 'string')
  assert.throws(() => queryEquipment(d, 'owner', base, { siteId, pageSize: 101 }), e => e.code === 400)
  assert.throws(() => queryEquipment(d, 'owner', base, { siteId, unsupported: 'x' }), e => e.code === 400)
  assert.equal(safeEquipmentReturn('//evil.example'), '/equipment')
  assert.equal(safeEquipmentReturn('/equipment?type=WATCH&evil=x'), '/equipment?type=WATCH')
  assert.deepEqual(equipmentQuery({ pageNum: -1, type: 'BAD', siteId }), { siteId })
})
test('cancel and identity changes before commit do not mutate memory', async () => {
  for (const kind of ['abort', 'identity']) {
    const repo = createMemoryRepository(), d = repo.readDataset(), input = payload(options(d).choices[0]), controller = new AbortController()
    let token = JSON.stringify({ kind: 'MOCK_ONLY', role: 'owner' })
    const session = { getItem: key => key === MOCK_TOKEN_KEY ? token : null }
    const transport = createTransport({ read: repo.readDataset, update: repo.transact, session, wait: async () => { if (kind === 'abort') controller.abort(); else token = JSON.stringify({ kind: 'MOCK_ONLY', role: 'reader' }) } })
    await assert.rejects(transport.post(base + '/issue', input, { signal: controller.signal }), e => e.code === 'ERR_CANCELED' && !!e.requestId)
    assert.deepEqual(repo.readDataset(), d)
  }
})
test('competing issues cannot reuse a device or a person/type slot', () => {
  const d = createSeed(), otherId = '9007199254740993105'
  assignmentCommand(d, 'owner', 'return', payload(options(d, { personId: otherId }).current[0], 'release-other'))
  const choices = options(d).choices
  assert.equal(choices.length, 2)
  const first = payload(choices[0], 'first'), sameSlot = payload(choices[1], 'same-slot')
  const otherPair = options(d, { personId: otherId }).choices.find(p => p.device.deviceId === first.deviceId)
  const sameDevice = payload(otherPair, 'same-device')
  assignmentCommand(d, 'owner', 'issue', first)
  const committed = structuredClone(d)
  for (const input of [sameSlot, sameDevice]) assert.throws(() => assignmentCommand(d, 'owner', 'issue', input), e => e.code === 409)
  assert.deepEqual(d, committed)
})
