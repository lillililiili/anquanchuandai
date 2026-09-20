import test from 'node:test'
import assert from 'node:assert/strict'
import { createSeed } from '../src/mock/seed.js'
import { queryDataset } from '../src/mock/engine.js'
import { capabilityDecision, validateProfile } from '../src/utils/device-profile.js'
import { deviceEventDictionary } from '../src/mock/device-profiles.js'
import { validateVitals, vitalValue } from '../src/utils/vitals-contract.js'
import { queryEquipment, assignmentCommand } from '../src/mock/equipment-service.js'
import { createTransport, MOCK_TOKEN_KEY } from '../src/mock/transport.js'
import { createMemoryRepository } from '../src/mock/storage.js'
const siteId = 'mock-site-1', personId = '9007199254740993101'
const read = (d, query = { personId }, role = 'owner') => queryDataset(d, role, '/api/portal/v1/vitals', { siteId, ...query })
const device = (d, n, type = 'helmet') => d.entities.devices.find(x => x.deviceId === `device-1-${n}-${type}`)
test('profiles preserve declarations, optional/unknown/absent and unverified synthetic configurations', () => {
  const d = createSeed()
  d.entities.devices.forEach(x => validateProfile(x.profile))
  assert.equal(device(d, 1).profile.capabilities.video.declaration, 'DECLARED')
  assert.equal(device(d, 3).profile.capabilities.video.declaration, 'NOT_DECLARED')
  assert.equal(device(d, 3).profile.capabilities.video.installation, 'ABSENT')
  assert.equal(device(d, 5).profile.capabilities.video.installation, 'UNKNOWN')
  assert.equal(device(d, 1).profile.capabilities.gas.installation, 'ABSENT')
  assert.equal(device(d, 3).profile.capabilities.proximity.declaration, 'CONFLICTING')
  assert.equal(device(d, 1).profile.capabilities.record.declaration, 'NOT_DECLARED')
  assert.equal(device(d, 1, 'watch').profile.capabilities.vitals.verification, 'UNVERIFIED')
})
test('capability decisions fail closed for production, permission, module, privacy, unknown and missing', () => {
  const d = createSeed(), opts = { mock: true, permitted: true, moduleEnabled: true }
  assert.equal(capabilityDecision(device(d, 1), 'video', opts).allowed, true)
  for (const options of [{}, { ...opts, mock: false }, { ...opts, permitted: false }, { ...opts, moduleEnabled: false }]) assert.equal(capabilityDecision(device(d, 1), 'video', options).allowed, false)
  for (const i of [3, 5, 6]) assert.equal(capabilityDecision(device(d, i), 'video', opts).allowed, false)
  assert.equal(capabilityDecision({}, 'video', opts).allowed, false)
  device(d, 1).profile.capabilities.video.integration = 'NOT_INTEGRATED'
  assert.equal(capabilityDecision(device(d, 1), 'video', opts).allowed, false)
})
test('candidate event dictionary does not change events or derive unsafe conclusions', () => {
  assert.equal(new Set(deviceEventDictionary.map(x => x.code)).size, deviceEventDictionary.length)
  assert.ok(deviceEventDictionary.every(x => !x.confirmedProtocol && !x.generatesAlarm && x.type !== 'WATCH'))
  const d = createSeed(); assert.equal(d.entities.events.length, 50)
  assert.equal(queryDataset(d, 'owner', '/api/portal/v1/workbench', { siteId }).equipment.data.length, 68)
  assert.ok(device(d, 1, 'belt').profile.observations.some(o => o.label.includes('非人员工时')))
})
test('video and personnel projections use the same profile as equipment', () => {
  const d = createSeed()
  for (const n of [1, 3, 5, 6]) {
    const v = queryDataset(d, 'owner', '/api/portal/v1/video-sources/device-1-' + n + '-helmet', { siteId }).device
    assert.deepEqual(v.profile, device(d, n).profile)
    assert.deepEqual(v.video, device(d, n).capabilities.video)
  }
})
test('all vital responses validate long IDs and separate missing, stale and unknown time', () => {
  const d = createSeed()
  for (const p of d.entities.people) {
    const q = { siteId: p.siteId, personId: p.personId }
    validateVitals(queryDataset(d, 'owner', '/api/portal/v1/vitals', q), q)
  }
  assert.equal(read(d).items.length, 4)
  assert.equal(read(d, { personId: '9007199254740993102' }).state, 'NO_WATCH')
  assert.equal(read(d, { personId: '9007199254740993103' }).state, 'UNKNOWN')
  assert.equal(read(d, { personId: '9007199254740993107' }).state, 'UNKNOWN')
  assert.ok(read(d, { personId: '9007199254740993105' }).items.every(i => i.freshness === 'STALE'))
  assert.ok(read(d, { personId: '9007199254740993106' }).items.every(i => i.sourceTime === null && i.freshness === 'UNKNOWN'))
  assert.equal(read(d, { personId: '9007199254740993108' }).items.find(i => i.metric === 'oxygen').value, null)
  assert.equal(vitalValue({ value: 0 }), '0'); assert.equal(vitalValue({ value: null }), '—')
})
test('vital scope, anonymous, unsupported params and deterministic scenarios reject without exposing readings', () => {
  const d = createSeed()
  assert.throws(() => read(d, { personId }, ''), e => e.code === 401)
  assert.throws(() => read(d, { siteId: 'mock-site-2', personId }, 'reader'), e => e.code === 403)
  assert.throws(() => read(d, { personId: '9007199254740993201' }), e => e.code === 404)
  assert.throws(() => read(d, { personId, url: 'evil' }), e => e.code === 400)
  assert.throws(() => read(d, { personId, deviceId: 'device-1-1-watch' }), e => e.code === 400)
  for (const mode of ['forbidden', 'not-integrated']) {
    d.config = { module: 'vitals', mode }
    const result = read(d); assert.equal(result.items.length, 0); assert.notEqual(result.state, 'AVAILABLE')
  }
  d.config = { module: 'vitals', mode: 'failure' }
  assert.throws(() => read(d), e => e.code === 503)
})
test('watch return, transfer and re-issue never move historical readings or create measurements', () => {
  const d = createSeed(), before = structuredClone(d.entities.vitalObservations)
  const options = p => queryEquipment(d, 'owner', '/api/portal/v1/equipment/options', { siteId, personId: p, type: 'WATCH' })
  const payload = (p, operationId) => ({ siteId, personId: p.person.personId, deviceId: p.device.deviceId, expectedVersion: p.expectedVersion, assignmentId: p.assignment?.assignmentId, operationId })
  assignmentCommand(d, 'owner', 'return', payload(options(personId).current[0], 'return-watch'))
  assert.equal(read(d).state, 'NO_WATCH')
  const second = '9007199254740993102', pair = options(second).choices.find(p => p.device.deviceId === 'device-1-1-watch')
  assignmentCommand(d, 'owner', 'issue', payload(pair, 'issue-watch'))
  assert.equal(read(d, { personId: second }).state, 'EMPTY')
  const history = read(d, { deviceId: pair.device.deviceId })
  assert.ok(history.items.every(i => i.personId === personId))
  assert.deepEqual(d.entities.vitalObservations, before)
})
test('contract rejects cross-person/device, malformed readings and sensitive forbidden payloads', () => {
  const d = createSeed(), q = { siteId, personId }
  for (const mutate of [r => { r.items[0].personId = 'other' }, r => { r.items[0].value = '72' }, r => { r.items[0].sourceTime = null }, r => { r.state = 'FORBIDDEN' }, r => { r.items.push(r.items[0]) }]) {
    const r = read(d); mutate(r); assert.throws(() => validateVitals(r, q))
  }
})
test('vital transport cancellation and account changes discard late responses', async () => {
  const repo = createMemoryRepository(), values = new Map([[MOCK_TOKEN_KEY, JSON.stringify({ kind: 'MOCK_ONLY', role: 'owner' })]])
  let release
  const transport = createTransport({ read: repo.readDataset, update: repo.transact, session: { getItem: key => values.get(key) }, wait: () => new Promise(r => { release = r }) })
  const controller = new AbortController()
  const pending = transport.get('/api/portal/v1/vitals', { params: { siteId, personId }, signal: controller.signal })
  await new Promise(r => setImmediate(r)); controller.abort(); release()
  await assert.rejects(pending, e => e.code === 'ERR_CANCELED' && !!e.requestId)
  const next = transport.get('/api/portal/v1/vitals', { params: { siteId, personId } })
  await new Promise(r => setImmediate(r)); values.set(MOCK_TOKEN_KEY, 'changed'); release()
  await assert.rejects(next, e => e.code === 'ERR_CANCELED')
})
