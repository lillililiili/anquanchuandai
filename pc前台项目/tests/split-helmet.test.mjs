import test from 'node:test';
import assert from 'node:assert/strict';
import { isRealDevice, projectDevice, supportsDeviceAction, deviceSourceLabel } from '../src/lib/device-telemetry.js';
import { featureState } from '../../shared/device-features.mjs';
import { splitHelmetTelemetry, splitRecordingParameters } from '../../shared/split-helmet.mjs';
import { deviceCallUnavailable } from '../src/lib/helmet-device-call.js';
import { loadSplitMedia, splitMediaPath } from '../src/lib/split-media-file.js';
import { createZlmSession, splitProxyPath, waitForZlmIce } from '../src/lib/zlm-session.js';
import { createSplitGroupCall } from '../src/lib/split-group-call.js';
import { createMonitorIntercom } from '../src/lib/monitor-intercom.js';
import { createRtcSession } from '../src/lib/rtc.js';
import { createCommunicationGuard } from '../src/lib/communication-guard.js';
import { mediaKindLabel, mediaTime } from '../src/lib/media-presentation.js';

const context = { deviceId: 'split-1', personId: 'person-1', assignmentId: 'A-1', assignmentVersion: 1 };
const feature = { ...context, supported: true, available: true, verified: false, integrationStatus: 'CONNECTED' };
const device = () => ({ id: 'split-1', source: 'SPLIT_HELMET', type: 'H', communicationProtocol: 'ZLM_WEBRTC', online: true, active: true, freshness: 'CURRENT', sourceTime: new Date().toISOString(), battery: 62, batteryReportedAt: new Date().toISOString(), batteryFreshness: 'CURRENT', worn: true, isWearedFreshness: 'STALE', featureStates: { voice: feature }, capabilities: { actions: ['intercom'] } });
test('split telemetry and voice follow explicit protocol, field freshness and assignment', () => {
  const row = device();
  assert.equal(isRealDevice(row), true);
  assert.equal(deviceSourceLabel('split-helmet'), '分体式安全帽');
  assert.equal(projectDevice(row).battery, 62);
  assert.equal(projectDevice({ ...row, online: false, freshness: 'STALE' }).battery, 62);
  assert.equal(projectDevice({ ...row, batteryReportedAt: '2020-01-01' }).battery, null);
  assert.equal(projectDevice(row).worn, null);
  assert.equal(supportsDeviceAction(row, 'intercom'), true);
  assert.equal(deviceCallUnavailable(row, feature, false, context), '');
  assert.match(deviceCallUnavailable({ ...row, communicationProtocol: 'SIP' }, feature, false, context), /配置异常/);
  assert.equal(featureState({ ...row, featureStates: { voice: { ...feature, available: false } } }, 'voice').available, false);
  assert.match(deviceCallUnavailable(row, feature, false, { ...context, assignmentVersion: 2 }), /已变化/);
});
test('split pressure and storage do not infer height or storage units', () => {
  const now = Date.now();
  const view = splitHelmetTelemetry({ pressure: 101325, pressureReportedAt: new Date(now).toISOString(), pressureFreshness: 'CURRENT', storageTotal: '32G', storageAvailable: '20G', storageAvailableReportedAt: '2020-01-01', storageAvailableFreshness: 'STALE' }, now);
  assert.equal(view.pressure, '101325（单位未提供）'); assert.equal(view.pressureStatus, '近期上报');
  assert.match(view.storage, /32G.*20G/); assert.equal(view.storageStatus, '最后上报');
  assert.equal(view.fields.find(field => field.key === 'storageTotal').status, '时间未确认');
  assert.equal(view.fields.find(field => field.key === 'storageAvailable').status, '最后上报');
  assert.equal(splitHelmetTelemetry({}).pressure, '未上报');
  assert.deepEqual(splitRecordingParameters(300, ''), { durationSeconds: 300 });
  for (const value of [0, 86401, 1.5, 'bad']) assert.throws(() => splitRecordingParameters(value, ''));
  assert.throws(() => splitRecordingParameters(300, 'x'.repeat(513)));
});

const credentials = (count = 1) => ({ protocol: 'ZLM_WEBRTC', channel: 'session-1', heartbeatUrl: '/api/guardian/v1/split/sessions/session-1/heartbeat', sessions: Array.from({ length: count }, (_, i) => ({ deviceId: 'hat-' + i, playUrl: `/api/guardian/v1/split/sessions/session-1/devices/hat-${i}/play`, talkUrl: `/api/guardian/v1/split/sessions/session-1/devices/hat-${i}/talk` })) });
class FakeStream { constructor() { this.tracks = []; } addTrack(track) { this.tracks.push(track); } }
const microphone = () => { const track = { kind: 'audio', readyState: 'live', stop() { this.readyState = 'ended'; } }; return { getAudioTracks: () => [track], getTracks: () => [track] }; };
function rtcFixture({ failTalk = false, heartbeatFailure = false } = {}) {
  const peers = [], requests = [], statuses = [], timers = new Map(); let sequence = 0;
  class Peer {
    constructor() { this.iceGatheringState = 'complete'; this.connectionState = 'new'; this.transceivers = []; peers.push(this); }
    addTransceiver(track, options) { const row = { track, options, sender: { replaceTrack: async value => { row.replacement = value; } } }; this.transceivers.push(row); return row; }
    async createOffer() { return { type: 'offer', sdp: 'v=0\r\nOFFER' }; }
    async setLocalDescription(value) { this.localDescription = value; }
    async setRemoteDescription(value) { this.remoteDescription = value; this.connectionState = 'connected'; this.onconnectionstatechange?.(); }
    close() { this.connectionState = 'closed'; this.closed = true; }
  }
  const options = { PeerConnection: Peer, Stream: FakeStream, microphoneStream: microphone(), onDeviceState: value => statuses.push(value), audioFactory: () => null,
    schedule: (fn, ms) => { const id = ++sequence; timers.set(id, { fn, ms }); return id; }, cancel: id => timers.delete(id),
    fetchImpl: async (url, options) => { requests.push({ url, options }); return { ok: !(failTalk && url.endsWith('/talk') || heartbeatFailure && url.endsWith('/heartbeat')), status: 503, text: async () => 'v=0\r\nANSWER' }; } };
  return { options, peers, requests, statuses, timers };
}
test('ZLM proxy rejects vendor URLs, duplicate hats and groups beyond eight before network', async () => {
  for (const value of ['https://vendor.example/sdp', '//example.test/sdp', '/api/guardian/v1/split/sessions/../heartbeat']) assert.throws(() => splitProxyPath(value));
  const f = rtcFixture(); await assert.rejects(createZlmSession(credentials(9), f.options));
  const duplicate = credentials(2); duplicate.sessions[1].deviceId = duplicate.sessions[0].deviceId;
  await assert.rejects(createZlmSession(duplicate, f.options)); assert.equal(f.requests.length, 0);
});
test('ZLM uses separate play/talk peers, raw SDP, mute and a 60-second heartbeat', async () => {
  const f = rtcFixture(), session = await createZlmSession(credentials(2), f.options);
  assert.equal(f.peers.length, 4); assert.equal(f.requests.length, 4);
  assert.ok(f.requests.every(row => row.options.headers['Content-Type'] === 'application/sdp' && row.options.body.startsWith('v=0')));
  assert.ok([...f.timers.values()].some(timer => timer.ms === 60000));
  await session.setMuted(true);
  assert.ok(f.peers.filter(peer => peer.transceivers.length === 1).every(peer => peer.transceivers[0].replacement === null));
  await session.close(); assert.ok(f.peers.every(peer => peer.closed)); assert.equal(f.timers.size, 0);
});

test('a monitoring microphone negotiates only talk on the existing lease and leaves playback running', async () => {
  const f = rtcFixture(), creds = credentials(), guard = createCommunicationGuard();
  const view = await createZlmSession(creds, { ...f.options, playbackOnly: true });
  const live = { protocol: creds.protocol, sessionId: creds.channel, heartbeatUrl: creds.heartbeatUrl, ...creds.sessions[0] };
  const requests = [], phases = [];
  const rtc = createRtcSession(undefined, undefined, guard, {
    getUserMedia: async constraints => { requests.push(constraints); return f.options.microphoneStream; },
    zlmFactory: (c, options) => createZlmSession(c, { ...f.options, ...options }),
  });
  const talk = createMonitorIntercom({ guard, rtc, onChange: phase => phases.push(phase) });
  assert.equal(requests.length, 0);
  await talk.start(live);
  assert.deepEqual(requests, [{ audio: true, video: false }]);
  assert.deepEqual(f.requests.map(r => r.url), [live.playUrl, live.talkUrl]);
  assert.equal([...f.timers.values()].filter(t => t.ms === 60000).length, 1);
  assert.equal(phases.at(-1), 'on');
  await talk.stop();
  assert.equal(f.peers[0].closed, undefined);
  assert.equal(f.peers[1].closed, true);
  assert.equal(f.options.microphoneStream.getAudioTracks()[0].readyState, 'ended');
  assert.equal(phases.at(-1), 'off');
  await view.close();
});

test('denied microphone and foreign talk URL leave the open monitor intact', async () => {
  const f = rtcFixture(), c = credentials(), guard = createCommunicationGuard();
  const view = await createZlmSession(c, { ...f.options, playbackOnly: true });
  const live = { protocol: c.protocol, sessionId: c.channel, heartbeatUrl: c.heartbeatUrl, ...c.sessions[0] };
  let prompts = 0;
  const states = [], rtc = createRtcSession(undefined, undefined, guard, {
    getUserMedia: async () => { prompts++; throw Object.assign(Error(), { name: 'NotAllowedError' }); },
  });
  const mic = createMonitorIntercom({ guard, rtc, onChange: (phase, message) => states.push({ phase, message }) });
  await mic.start({ ...live, talkUrl: live.talkUrl.replace('session-1','other') });
  assert.equal(prompts, 0);
  await mic.start(live);
  assert.equal(prompts, 1);
  assert.match(states.at(-1).message, /麦克风权限/);
  assert.equal(f.peers.length, 1);
  assert.equal(f.peers[0].closed, undefined);
  guard.release(guard.acquire());
  await view.close();
});
test('failed talk leaves successful playback alive, and heartbeat failure closes peers', async () => {
  const f = rtcFixture({ failTalk: true, heartbeatFailure: true });
  const session = await createZlmSession(credentials(), f.options);
  assert.ok(f.statuses.some(row => row.kind === 'talk' && row.state === 'failed'));
  assert.equal(f.peers[0].closed, undefined);
  await [...f.timers.values()].find(timer => timer.ms === 60000).fn();
  assert.ok(f.peers.every(peer => peer.closed)); await session.close();
});
test('ICE cancellation removes listeners without publishing SDP', async () => {
  const listeners = new Map(), timers = new Map(), abort = new AbortController();
  const peer = { iceGatheringState: 'gathering', addEventListener: (name, fn) => listeners.set(name, fn), removeEventListener: name => listeners.delete(name) };
  const pending = waitForZlmIce(peer, abort.signal, { schedule: fn => { timers.set(1, fn); return 1; }, cancel: id => timers.delete(id) });
  abort.abort(); await assert.rejects(pending); assert.equal(timers.size, 0); assert.equal(listeners.size, 0);
});
test('protected file loader never sends account authorization to a vendor', async () => {
  let calls = 0; const fetchImpl = async () => { calls++; return { ok: true, blob: async () => new Blob(['file'], { type: 'video/mp4' }) }; };
  assert.throws(() => splitMediaPath('https://vendor.example/file.mp4'));
  await assert.rejects(loadSplitMedia({ url: 'https://vendor.example/file.mp4' }, { fetchImpl })); assert.equal(calls, 0);
  assert.equal((await loadSplitMedia({ url: '/api/guardian/v1/split/devices/hat-1/files/asset-1' }, { fetchImpl })).type, 'video/mp4');
  const directoryFile = { source: 'SPLIT_HELMET', kind: 'video', recordingOrigin: 'device', createdAt: '2026-11-16T00:00:00Z' };
  assert.equal(mediaKindLabel(directoryFile), '设备内录像'); assert.equal(mediaTime(directoryFile).label, '设备文件时间');
});
test('group creation uncertainty resolves the same idempotency key before ending', async () => {
  const payloads = []; let attempts = 0;
  const guard = createCommunicationGuard();
  const call = createSplitGroupCall({ guard, getUserMedia: async () => microphone(), makeId: () => 'stable-key', fetchImpl: async (url, options) => {
    if (url.includes('?')) return { ok: true, json: async () => [] };
    if (url.endsWith('/end')) return { ok: true, json: async () => ({ status: 'ended' }) };
    payloads.push(JSON.parse(options.body)); if (++attempts === 1) throw Error('network timeout');
    return { ok: true, json: async () => ({ id: 'row-1', status: 'offered' }) };
  } });
  await call.start([context, { ...context, personId: 'person-2', deviceId: 'split-2', assignmentId: 'A-2' }]);
  assert.equal(call.getState().phase, 'unknown'); assert.throws(() => guard.acquire());
  await call.end(); assert.equal(call.getState().phase, 'ended'); assert.deepEqual(payloads[0], payloads[1]);
  const owner = guard.acquire(); guard.release(owner);
});
test('group joined reports only hats with both peer connections and retains partial progress', async () => {
  const joined = []; let states;
  const call = createSplitGroupCall({ guard: createCommunicationGuard(), getUserMedia: async () => microphone(),
    fetchImpl: async (url, options) => {
      if (url.includes('?')) return { ok: true, json: async () => [] };
      if (url.endsWith('/end')) return { ok: true, json: async () => ({ status: 'ended' }) };
      if (url.endsWith('/joined')) { joined.push(JSON.parse(options.body)); return { ok: true, json: async () => ({ status: 'connected' }) }; }
      return { ok: true, json: async () => ({ id: 'row-1', credentials: credentials(2) }) };
    },
    createSession: async (_, options) => { states = options.onDeviceState; states({ deviceId: 'hat-0', kind: 'play', state: 'connected' }); return { close: async () => {}, retry: async () => {} }; },
  });
  await call.start([context, { ...context, personId: 'person-2', deviceId: 'split-2', assignmentId: 'A-2' }]);
  assert.equal(joined.length, 0);
  states({ deviceId: 'hat-0', kind: 'talk', state: 'connected' });
  states({ deviceId: 'hat-1', kind: 'play', state: 'connected' });
  states({ deviceId: 'hat-1', kind: 'talk', state: 'connected' });
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(joined.at(-1), { peerConnected: true, connectedDeviceIds: ['hat-0', 'hat-1'] });
  await call.end();
});
test('loss of the entire group media session releases microphone and ends the server row', async () => {
  const mic = microphone(), guard = createCommunicationGuard(); let mediaState, ends = 0, closed = 0;
  const call = createSplitGroupCall({ guard, getUserMedia: async () => mic,
    fetchImpl: async (url) => {
      if (url.includes('?')) return { ok: true, json: async () => [] };
      if (url.endsWith('/end')) { ends++; return { ok: true, json: async () => ({ status: 'ended' }) }; }
      return { ok: true, json: async () => ({ id: 'row-1', credentials: credentials(2) }) };
    },
    createSession: async (_, options) => { mediaState = options.onMediaState; return { close: async () => { closed++; } }; },
  });
  await call.start([context, { ...context, personId: 'person-2', deviceId: 'split-2', assignmentId: 'A-2' }]);
  mediaState('failed'); await new Promise(resolve => setImmediate(resolve));
  assert.equal(mic.getAudioTracks()[0].readyState, 'ended'); assert.equal(closed, 1); assert.equal(ends, 1); assert.equal(call.getState().phase, 'ended');
  const token = guard.acquire(); guard.release(token);
});
