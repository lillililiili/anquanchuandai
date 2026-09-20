import test from 'node:test'
import assert from 'node:assert/strict'
import { createSeed } from '../src/mock/seed.js'
import { videoAccess, privacyCommand } from '../src/mock/video-service.js'
import { spatialCommand } from '../src/mock/spatial-service.js'
import { recordMedia, recorderType, RECORD_LIMIT_MS, RECORD_LIMIT_BYTES } from '../src/mock/video-capture.js'
const siteId = 'mock-site-1', deviceId = 'device-1-1-helmet'
test('mock media capability scope distinguishes absent unknown privacy and read-only', () => {
  const d = createSeed()
  assert.equal(videoAccess(d, 'reader', siteId, deviceId).deviceId, deviceId)
  for (const [role, site, device, key, code] of [['reader', siteId, deviceId, 'capture', 403], ['owner', 'other', deviceId, 'video', 403], ['owner', siteId, 'device-2-1-helmet', 'video', 404], ['owner', siteId, 'device-1-3-helmet', 'video', 403], ['owner', siteId, 'device-1-6-helmet', 'video', 403], ['owner', siteId, 'device-1-1-watch', 'video', 404]]) assert.throws(() => videoAccess(d, role, site, device, key), e => e.code === code)
})
test('privacy is explicit mock report, closes capability until explicit off; stale update rejected', () => {
  const d = createSeed(), input = { siteId, deviceId, expectedPrivacy: 'OFF', privacy: 'ON' }
  privacyCommand(d, 'owner', input)
  assert.throws(() => videoAccess(d, 'owner', siteId, deviceId), /隐私/)
  assert.throws(() => privacyCommand(d, 'owner', input), e => e.code === 409)
  assert.throws(() => privacyCommand(d, 'reader', { ...input, expectedPrivacy: 'ON' }), e => e.code === 403)
  privacyCommand(d, 'owner', { ...input, expectedPrivacy: 'ON', privacy: 'OFF' })
  assert.equal(videoAccess(d, 'owner', siteId, deviceId).profile.privacy, 'OFF')
})
test('generated media preserves device but never inherits wearer or source time; idempotent save', () => {
  const d = createSeed(), file = new Blob(['fixture'], { type: 'image/png' }), input = { siteId, deviceId, generationMethod: 'MOCK_CAPTURE', generatedAt: '2026-09-19T00:00:00.000Z', operationId: 'capture-1', file, digest: 'hash' }, metadata = { type: 'PHOTO', name: '本地抓拍.png', mime: 'image/png', size: file.size }
  const result = spatialCommand(d, 'owner', 'material-import', input, metadata), m = d.entities.materials.find(m => m.id === result.id)
  assert.equal(m.deviceId, deviceId); assert.equal(m.capturedAt, null); assert.equal(m.personId, null); assert.equal(m.generationMethod, 'MOCK_CAPTURE')
  assert.equal(spatialCommand(d, 'owner', 'material-import', input, metadata).replayed, true)
  privacyCommand(d, 'owner', { siteId, deviceId, expectedPrivacy: 'OFF', privacy: 'ON' })
  assert.throws(() => spatialCommand(d, 'owner', 'material-import', { ...input, operationId: 'capture-2' }, metadata), /隐私/)
})
test('source failure is not media availability; no codec support yields null and fixed limits', () => {
  const d = createSeed(); d.config = { module: 'video', mode: 'failure' }
  assert.throws(() => videoAccess(d, 'owner', siteId, deviceId), e => e.code === 503)
  assert.equal(recorderType({ isTypeSupported: () => false }), null)
  assert.equal(recorderType({ isTypeSupported: type => type.includes('vp8') }), 'video/webm;codecs=vp8')
  assert.equal(RECORD_LIMIT_MS, 60000); assert.equal(RECORD_LIMIT_BYTES, 52428800)
})
test('recorder timeout, over-budget and repeated disposal release streams without empty success', () => {
  const original = globalThis.document, timers = new Map(); let tracks = 0, next = 0, latest, saved = 0, failed = 0
  const clock = { setInterval(fn) { timers.set(++next, fn); return next }, clearInterval(id) { timers.delete(id) }, setTimeout(fn, ms) { assert.equal(ms, 60000); timers.set(++next, fn); return next }, clearTimeout(id) { timers.delete(id) } }
  const media = { readyState: 2, videoWidth: 640, videoHeight: 360, paused: false, ended: false }
  class Recorder {
    static isTypeSupported() { return true }
    constructor() { latest = this; this.state = 'inactive' }
    start() { this.state = 'recording' }
    stop() { this.state = 'inactive'; this.onstop() }
  }
  globalThis.document = { createElement() { return { getContext: () => ({ drawImage() {}, fillRect() {}, fillText() {} }), captureStream() { tracks++; let live = true; return { getTracks: () => [{ stop() { if (live) { live = false; tracks-- } } }] } } } } }
  const start = () => recordMedia(media, () => saved++, () => failed++, () => {}, { Recorder, clock, now: () => 0 })
  try {
    let r = start(); latest.ondataavailable({ data: new Blob(['frame']) }); [...timers.values()].at(-1)(); assert.equal(saved, 1); assert.equal(tracks, 0); assert.equal(timers.size, 0); r.dispose(); r.dispose()
    r = start(); latest.ondataavailable({ data: { size: RECORD_LIMIT_BYTES + 1 } }); assert.equal(failed, 1); assert.equal(saved, 1); assert.equal(tracks, 0); assert.equal(timers.size, 0)
    r = start(); latest.ondataavailable({ data: new Blob(['discarded']) }); r.dispose(); r.dispose(); assert.equal(saved, 1); assert.equal(tracks, 0)
    r = start(); r.stop(); assert.equal(failed, 2); assert.equal(saved, 1)
  } finally { globalThis.document = original }
})
