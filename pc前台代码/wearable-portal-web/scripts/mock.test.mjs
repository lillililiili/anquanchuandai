import test from 'node:test'
import assert from 'node:assert/strict'
import { createSeed, identities, defaultScenario } from '../src/mock/seed.js'
import { queryDataset } from '../src/mock/engine.js'
import { createTransport, MOCK_TOKEN_KEY, delay } from '../src/mock/transport.js'
import { createMemoryRepository } from '../src/mock/storage.js'
import { validateContext, validatePage, validateDetail } from '../src/utils/portal-contract.js'
import { validateS2Page, validateS2Item, validateTrack } from '../src/utils/spatial-contract.js'
import { validateVideoPage, validateVideoDetail } from '../src/utils/video-contract.js'
import { validateAlarmPage, validateAlarmSummary, validateAlarmDetail } from '../src/utils/alarm-contract.js'
const seed = () => createSeed('2026-09-17T08:00:00.000Z')
const root = '/api/portal/v1', q = { siteId: 'mock-site-1' }
const query = (p, params = q, d = seed(), role = 'owner') => queryDataset(d, role, root + p, params)
test('deterministic seeds and shared memory without browser storage', () => {
  assert.deepEqual(seed(), seed())
  const memory = createMemoryRepository(seed)
  memory.saveScenario({ module: 'people', mode: 'failure' })
  assert.equal(memory.readDataset().config.mode, 'failure')
  const copy = memory.readDataset(); copy.entities.people.length = 0
  assert.equal(memory.readDataset().entities.people.length, 50)
  assert.throws(() => memory.transact(d => { d.entities.people.length = 0; throw new Error('abort') }))
  assert.equal(memory.readDataset().entities.people.length, 50)
  assert.equal(createMemoryRepository(seed).readDataset().config.mode, 'normal')
  memory.resetDataset(); assert.equal(memory.readDataset().config.mode, 'normal')
})
test('context identities and string long IDs', () => {
  for (const i of identities) assert.equal(validateContext(query('/context', {}, seed(), i.id)).sites.length, i.sites.length)
  assert.ok(BigInt(seed().entities.people[0].personId) > BigInt(Number.MAX_SAFE_INTEGER))
})
test('read endpoints use their current model validators', () => {
  validateContext(query('/context', {}))
  const people = validatePage(query('/people')), id = people.items[0].personId
  validateDetail(query('/people/' + id)); validatePage(query(`/people/${id}/equipment-history`), true)
  for (const [path, kind] of [['/devices', 'devices'], ['/locations/latest', 'locations'], ['/fences', 'fences'], ['/materials', 'materials']]) {
    const p = validateS2Page(query(path), kind, q)
    if (['fences', 'materials'].includes(kind)) validateS2Item(query(path + '/' + p.items[0].id), kind, q.siteId, p.items[0].id)
  }
  const tq = { ...q, deviceId: 'device-1-1-helmet', from: '2026-09-17T00:00:00Z', to: '2026-09-18T00:00:00Z' }
  validateTrack(query('/tracks', tq), tq)
  validateVideoPage(query('/video-sources'), q); validateVideoDetail(query('/video-sources/device-1-1-helmet'), q.siteId, 'device-1-1-helmet')
  validateAlarmPage(query('/events'), q); validateAlarmSummary(query('/events/summary')); validateAlarmDetail(query('/events/event-1-1'), q.siteId, 'event-1-1')
})
test('all seeded details and nested evidence pass contracts', () => {
  const d = seed()
  for (const p of d.entities.people) validateDetail(query('/people/' + p.personId, { siteId: p.siteId }, d))
  for (const v of d.entities.videos) validateVideoDetail(query('/video-sources/' + v.deviceId, { siteId: v.siteId }, d), v.siteId, v.deviceId)
  for (const e of d.entities.events) {
    validateAlarmDetail(query('/events/' + e.eventId, { siteId: e.siteId }, d), e.siteId, e.eventId)
  }
})
test('pagination and shared scopes, independent histories', () => {
  assert.equal(query('/people').total, 25); assert.equal(query('/people', { ...q, pageNum: 2 }).items.length, 5)
  for (const path of ['/people', '/fences', '/materials', '/video-sources', '/events']) assert.equal(query(path, { siteId: 'mock-site-empty' }).total, 0)
  const id = seed().entities.people[0].personId
  assert.equal(query(`/people/${id}/equipment-history`, { ...q, pageSize: 10, pageNum: 2 }).items.length, 10)
  assert.throws(() => query('/events/event-1-1/timeline'), { code: 404 })
  assert.throws(() => query('/events/event-1-1/verifications'), { code: 404 })
})
test('filters and summaries derive from same facts', () => {
  const filter = { ...q, handlingStatus: 'UNHANDLED' }
  assert.equal(query('/events', filter).total, query('/events/summary', filter).data.total)
  assert.equal(query('/people', { ...q, keyword: 'no-match' }).total, 0)
  assert.equal(query('/materials', { ...q, type: 'PHOTO' }).total, 9)
  assert.equal(query('/video-sources', { ...q, keyword: 'no-match' }).statistics.data.devices, 0)
})
test('reject unsupported filters, invalid pagination, time ranges and enums', () => {
  for (const extra of [{ pageSize: 101 }, { pageNum: 0 }, { url: 'bad' }, { workState: 'UNKNOWN' }]) assert.throws(() => query('/people', { ...q, ...extra }), e => e.code === 400)
  assert.throws(() => query('/events', { ...q, phase: 'INVALID' }))
  assert.throws(() => query('/materials', { ...q, from: 'bad' }))
})
test('authorization and object visibility', () => {
  assert.throws(() => query('/people', q, seed(), 'bad'), e => e.code === 401)
  assert.throws(() => query('/people', { siteId: 'mock-site-2' }, seed(), 'reader'), e => e.code === 403)
  assert.throws(() => query('/events/event-2-1'), e => e.code === 404)
  assert.throws(() => query('/events/event-1-1/verifications', q, seed(), 'reader'), e => e.code === 404)
  assert.throws(() => query('/tracks', { ...q, deviceId: 'device-2-1-helmet' }), e => e.code === 404)
})
test('unknown historic attribution remains unknown and no addresses', () => {
  const t = query('/tracks', { ...q, deviceId: 'device-1-3-helmet', from: '2026-09-17T00:00:00Z', to: '2026-09-18T00:00:00Z' }).data
  assert.equal(t.personId, null); assert.equal(t.attribution, 'UNKNOWN'); assert.equal(t.gaps.length, 1)
  assert.equal(query('/events/event-1-3').event.person.state, 'NOT_INTEGRATED')
  assert.equal(/https?:|rtc|token|url|path/i.test(JSON.stringify(query('/video-sources/device-1-1-helmet'))), false)
})
test('unintegrated, failure and forbidden differ from empty', () => {
  const d = seed(); d.config = { module: 'people', mode: 'not-integrated' }
  assert.equal(validatePage(query('/people', q, d)).total, null)
  d.config.mode = 'failure'; assert.throws(() => query('/people', q, d), e => e.code === 503)
  d.config.mode = 'forbidden'; assert.equal(query('/people/' + d.entities.people[0].personId, q, d).works.state, 'FORBIDDEN')
})
function harness(wait = async () => {}) {
  let d = seed(); const session = new Map(); session.getItem = k => session.get(k); session.removeItem = k => session.delete(k)
  return { session, read: () => d, transport: createTransport({ read: async () => structuredClone(d), update: async fn => fn(d), session, wait }), config: c => { d.config = c } }
}

test('login requires matching credentials and preserves role permissions', async () => {
  const { transport: t, session } = harness()
  for (const credentials of [{}, { username: 'owner' }, { username: 'admin' }, { username: 'admin', password: 'wrong' }, { username: 'admin', password: 'Wearable@2026' }, { username: 'unknown', password: 'Admin@2026' }]) {
    await assert.rejects(t.post('/login', credentials, { skipAuth: true, skipUnauthorized: true }), e => e.code === 401 && e.errorCode === 'INVALID_CREDENTIALS' && !!e.requestId)
    assert.equal(session.get(MOCK_TOKEN_KEY), undefined)
  }
  for (const [username, password, role] of [['admin', 'Admin@2026', 'owner'], ['verifier', 'Verify@2026', 'verifier'], ['viewer', 'View@2026', 'reader']]) {
    const result = await t.post('/login', { username, password }, { skipAuth: true })
    assert.equal(JSON.parse(result.token).role, role)
    session.set(MOCK_TOKEN_KEY, result.token)
    assert.deepEqual((await t.get('/getInfo')).roles, [role])
    session.delete(MOCK_TOKEN_KEY)
  }
})
test('transport authentication, denied writes, requestId and isolated sessions', async () => {
  const { session, transport: t } = harness()
  const login = await t.post('/login', { username: 'admin', password: 'Admin@2026' }, { skipAuth: true }); session.set(MOCK_TOKEN_KEY, login.token)
  assert.equal((await t.get('/getInfo')).user.nickName, '负责人')
  assert.equal((await t.get(root + '/people', { params: q })).data.total, 25)
  await assert.rejects(t.post(root + '/equipment-assignments', {}), e => e.code === 405 && !!e.requestId)
  await assert.rejects(t.get('/unknown'), e => e.code === 404)
  assert.equal((await t.get('/captchaImage', { skipAuth: true })).captchaEnabled, false)
  session.set('Wearable-Portal-Token', 'real'); t.expire(); assert.equal(session.get('Wearable-Portal-Token'), 'real')
  await assert.rejects(t.get('/getInfo'), e => e.code === 401)
})
test('abort and changed sessions prevent late results', async () => {
  const c = new AbortController(); const p = delay(3000, c.signal); c.abort(); await assert.rejects(p, e => e.code === 'ERR_CANCELED')
  let release; const h = harness(() => new Promise(r => { release = r }))
  h.session.set(MOCK_TOKEN_KEY, JSON.stringify({ kind: 'MOCK_ONLY', role: 'owner' }))
  const pending = h.transport.get(root + '/people', { params: q }); await Promise.resolve(); h.session.set(MOCK_TOKEN_KEY, 'changed'); release()
  await assert.rejects(pending, e => e.code === 'ERR_CANCELED')
})
test('slow next query is consumed only once', async () => {
  const waits = [], h = harness(async ms => waits.push(ms)); h.session.set(MOCK_TOKEN_KEY, JSON.stringify({ kind: 'MOCK_ONLY', role: 'owner' }))
  h.config({ ...defaultScenario(), slowNext: true })
  await h.transport.get(root + '/people', { params: q }); await h.transport.get(root + '/people', { params: q })
  assert.deepEqual(waits, [3000, 200])
})
