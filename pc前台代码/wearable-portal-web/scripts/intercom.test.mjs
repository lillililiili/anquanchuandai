import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createMemoryRepository } from '../src/mock/storage.js'
import { queryDispatch, dispatchCommand, dispatchData } from '../src/mock/dispatch-service.js'
const siteId = 'mock-site-1', deviceId = 'device-1-1-helmet'
for (const mode of ['VOICE', 'VIDEO']) test(`${mode} uses exact device and shared dispatch lifecycle`, () => {
  const repo = createMemoryRepository()
  const q = queryDispatch(repo.readDataset(), 'owner', { siteId, deviceId })
  assert.equal(q.suggested.length, 1)
  assert.equal(q.suggested[0].deviceId, deviceId)
  let n = 0
  function act(action, extra) {
    let result
    repo.transact(d => { result = dispatchCommand(d, 'owner', action, { siteId, expectedVersion: dispatchData(d).version, operationId: 'intercom-' + ++n, ...extra }) })
    return result
  }
  const { id } = act('start', { deviceIds: [deviceId], mode })
  assert.equal(queryDispatch(repo.readDataset(), 'owner', { siteId }).active.mode, mode)
  assert.equal(queryDispatch(repo.readDataset(), 'owner', { siteId }).active.id, id)
  assert.throws(() => act('start', { deviceIds: [deviceId], mode: 'VOICE' }), { code: 409 })
  act('participant', { sessionId: id, deviceId, state: 'CONNECTED' })
  assert.equal(dispatchData(repo.readDataset()).sessions[0].participants[0].state, 'CONNECTED')
  act('end', { sessionId: id })
  assert.equal(queryDispatch(repo.readDataset(), 'owner', { siteId }).active, null)
  assert.equal(dispatchData(repo.readDataset()).sessions[0].state, 'ENDED')
})
test('video entry rejects out-of-scope devices and readonly calls', () => {
  const repo = createMemoryRepository(), d = repo.readDataset()
  assert.throws(() => queryDispatch(d, 'owner', { siteId, deviceId: 'device-2-1-helmet' }), { code: 404 })
  assert.throws(() => dispatchCommand(d, 'reader', 'start', { siteId, expectedVersion: 1, operationId: 'intercom-denied', deviceIds: [deviceId], mode: 'VOICE' }), { code: 403 })
  assert.equal(dispatchData(d).sessions.length, 0)
})
test('both video entrances use the build-isolated intercom component', () => {
  for (const view of ['VideoView', 'VideoDetailView']) {
    const source = readFileSync(new URL('../src/views/video/' + view + '.vue', import.meta.url), 'utf8')
    assert.match(source, /import IntercomEntry from '@intercom-entry'/)
    assert.match(source, /<IntercomEntry :site-id="siteId"/)
    assert.doesNotMatch(source, /对讲尚未接入|通信会话留待 S6/)
  }
  const source = readFileSync(new URL('../src/mock/IntercomEntry.vue', import.meta.url), 'utf8')
  assert.match(source, /useLocalEditor/)
  assert.match(source, /expectedVersion: data.value.version/)
  assert.doesNotMatch(source, /getUserMedia|RTCPeerConnection|new WebSocket/)
})
