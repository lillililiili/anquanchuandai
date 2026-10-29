import test from 'node:test';
import assert from 'node:assert/strict';
import { createHelmetDeviceCall, deviceCallUnavailable } from '../src/lib/helmet-device-call.js';
import { createCommunicationGuard, communicationGuard } from '../src/lib/communication-guard.js';
import { createRtcSession } from '../src/lib/rtc.js';
import { createStore } from '../src/mock/data.js';

const device = () => ({ id: '866652021714127', deviceNumber: '866652021714127', type: 'H', source: 'DIRECT_HELMET',
  freshness: 'CURRENT', sourceTime: new Date().toISOString(), online: true, active: true,
  featureStates: { voice: { supported:true, verified:true, available:true } }, sipRegistered: true, communicationProtocol: 'SIP', capabilities: { actions: ['intercom'] } });
const assignment = { personId: 'P-real', deviceId: '866652021714127', assignmentId: 'A-real', assignmentVersion: 3 };
const media = { ...assignment, supported: true, verified: true, available: true, integrationStatus: 'CONNECTED' };
const credentials = { protocol: 'SIP', authorizationPassword: 'PRIVATE-TEST-SECRET', video: true };
const offered = { id: 'COMM-test', channelName: 'SIP-test', status: 'offered', credentials };
const flush = () => new Promise(resolve => setImmediate(resolve));
function fixture({ create, join } = {}) {
  const requests = [], rtcEvents = [], timers = new Map();
  let sequence = 0, time = 0, server = { status: 'offered', serverConnected: false, connectedDeviceIds: [] }, joined;
  const guard = createCommunicationGuard();
  const rtc = {
    getActiveCallId: () => null,
    async joinChannel(value, options) { guard.assertAvailable(options.reservation); rtcEvents.push(['join', value]); joined = options; if (join) await join(value, options); },
    async leaveChannel(token) { guard.assertAvailable(token); rtcEvents.push(['leave']); },
    async setMuted(value, token) { guard.assertAvailable(token); rtcEvents.push(['muted', value]); },
    async resumeAudio(token) { guard.assertAvailable(token); rtcEvents.push(['play']); },
  };
  const fetchImpl = async (url, options) => {
    const body = options.body && JSON.parse(options.body);
    requests.push({ url, body, method: options.method || 'GET' });
    let value;
    if (url.endsWith('/mobile/calls')) value = create ? await create(body, requests) : offered;
    else if (url.endsWith('/end')) value = { status: 'ending' };
    else if (url.includes('/mobile/calls/')) value = { status: server.status };
    else if (url.includes('/helmet/calls/')) value = server;
    else throw Error('Unexpected request ' + url);
    if (value?.httpStatus) return { ok: false, status: value.httpStatus, json: async () => value };
    return { ok: true, status: 200, json: async () => value };
  };
  const call = createHelmetDeviceCall({ fetchImpl, rtc, guard, makeId: () => 'stable-test-request', now: () => time,
    schedule: (fn, delay) => { const id = ++sequence; timers.set(id, { fn, delay }); return id; }, cancel: id => timers.delete(id) });
  return { call, guard, requests, rtcEvents, timers, setServer: value => { server = value; },
    setTime: value => { time = value; },
    emit: value => joined.onMediaState(value),
    async timeout() { time = 61000; const [id, timer] = [...timers].find(([, entry]) => entry.delay === 60000); timers.delete(id); await timer.fn(); },
    async terminate(status = 'ended') { server = { status }; await call.refresh(); },
  };
}

test('assigned real device requires readiness, registration, freshness and a matching assignment before HTTP', async () => {
  assert.equal(deviceCallUnavailable(device(), media, false, assignment), '');
  assert.equal(deviceCallUnavailable({ ...device(), sipRegistered: undefined, voiceAvailable: true, capabilities: ['intercom'] }, media, false, assignment), '');
  for (const [d, m, other] of [[{ ...device(), online: false }, media], [{ ...device(), sipRegistered: false }, media],
    [{ ...device(), sourceTime: '2020-01-01' }, media], [device(), { status: 'unavailable' }], [device(), media, true]]) {
    const f = fixture(); await assert.rejects(f.call.start(d, m, other, assignment)); assert.equal(f.requests.length, 0);
  }
});
test('history media cannot authorize a call; only the matching current person voice context can',async()=>{
  const f=fixture();
  await assert.rejects(f.call.start(device(),{status:'ready',items:[],commands:[]},false,assignment));
  await assert.rejects(f.call.start(device(),media,false,{...assignment,assignmentVersion:4}));
  await assert.rejects(f.call.start(device(),media,false));
  assert.equal(f.requests.length,0);
  await f.call.start(device(),media,false,assignment);await f.terminate();
});

test('captured assignment and voice-only request are used; SIP secrets never enter public state', async () => {
  const f = fixture(); await f.call.start(device(), media, false, assignment);
  assert.deepEqual(f.requests[0].body, { ...assignment, deviceId: device().id, video: false, idempotencyKey: 'stable-test-request' });
  assert.equal(f.rtcEvents[0][1].video, false);
  assert.equal(f.call.getState().phase, 'connecting');
  assert.equal(JSON.stringify(f.call.getState()).includes('PRIVATE-TEST-SECRET'), false);
  await assert.rejects(f.call.start(device(), media, false, assignment), /先结束/);
  assert.equal(f.requests.filter(r => r.url.endsWith('/mobile/calls')).length, 1);
  await f.terminate();
});

test('remote audio does not assert physical connection; server must identify this exact helmet', async () => {
  const f = fixture(); await f.call.start(device(), media, false, assignment); f.emit('remote_audio');
  assert.equal(f.call.getState().serverConnected, false);
  f.setServer({ status: 'connected', serverConnected: true, connectedDeviceIds: ['another-helmet'] });
  await f.call.refresh(); assert.equal(f.call.getState().serverConnected, false);
  f.setServer({ status: 'connected', serverConnected: true, connectedDeviceIds: [device().id] });
  await f.call.refresh(); assert.equal(f.call.getState().phase, 'active'); assert.equal(f.call.getState().serverConnected, true);
  assert.equal([...f.timers.values()].some(t => t.delay === 60000), false);
  await f.terminate();
});

test('uncertain creation retries the same request key and keeps the shared session reserved', async () => {
  let attempts = 0;
  const f = fixture({ create: async () => { if (++attempts === 1) throw Error('network lost'); return offered; } });
  await f.call.start(device(), media, false, assignment);
  assert.equal(f.call.getState().phase, 'unknown');
  assert.throws(() => f.guard.acquire(), /先结束/);
  await f.call.refresh();
  assert.deepEqual(f.requests.filter(r => r.url.endsWith('/mobile/calls')).map(r => r.body.idempotencyKey), ['stable-test-request', 'stable-test-request']);
  assert.equal(f.rtcEvents.filter(([kind]) => kind === 'join').length, 1);
  await f.terminate(); assert.doesNotThrow(() => f.guard.acquire());
});

test('permission failure creates no RTC session and releases reservation', async () => {
  const f = fixture({ create: async () => ({ httpStatus: 403, message: '设备不在授权范围' }) });
  await f.call.start(device(), media, false, assignment);
  assert.equal(f.call.getState().phase, 'failed'); assert.deepEqual(f.rtcEvents, []);
  assert.doesNotThrow(() => f.guard.acquire());
});

test('microphone failure requests server end; it never reports local cleanup as confirmed termination', async () => {
  const f = fixture({ join: async () => { const error = Error('denied'); error.name = 'NotAllowedError'; throw error; } });
  await f.call.start(device(), media, false, assignment);
  assert.equal(f.call.getState().phase, 'ending'); assert.match(f.call.getState().error, /麦克风/);
  assert.equal(f.requests.filter(r => r.url.endsWith('/end')).length, 1);
  assert.equal(f.rtcEvents.filter(([kind]) => kind === 'leave').length, 1);
  assert.throws(() => f.guard.acquire()); await f.terminate();
});

test('ring timeout closes local audio, asks server to end and waits for its terminal status', async () => {
  const f = fixture(); await f.call.start(device(), media, false, assignment); await f.timeout();
  assert.equal(f.call.getState().phase, 'ending'); assert.match(f.call.getState().error, /超时/);
  assert.throws(() => f.guard.acquire()); await f.terminate();
  assert.equal(f.call.getState().phase, 'timeout'); assert.equal(f.timers.size, 0);
});

test('closing panel while create is pending ends its late result without joining or touching another device', async () => {
  let resolve;
  const f = fixture({ create: () => new Promise(done => { resolve = done; }) });
  const starting = f.call.start(device(), media, false, assignment); await flush();
  await f.call.dispose('some-other-device'); assert.equal(f.call.getState().endRequested, false);
  await f.call.dispose(device().id); resolve(offered); await starting;
  assert.equal(f.rtcEvents.filter(([kind]) => kind === 'join').length, 0);
  assert.equal(f.requests.filter(r => r.url.endsWith('/end')).length, 1);
  await f.terminate();
});

test('mute and audio-play use only the reserved session and remote termination cleans it', async () => {
  const f = fixture(); await f.call.start(device(), media, false, assignment);
  await f.call.setMuted(true); await f.call.resumeAudio();
  assert.equal(f.call.getState().muted, true);
  await f.terminate('failed'); assert.equal(f.call.getState().phase, 'failed');
  assert.equal(f.rtcEvents.filter(([kind]) => kind === 'leave').length, 1);
  assert.equal(f.timers.size, 0);
});

test('unconfirmed hangup stops background polling after its bounded cleanup window and remains explicitly unknown', async () => {
  const f = fixture(); await f.call.start(device(), media, false, assignment); await f.call.dispose(device().id);
  f.setTime(46000);
  const [id, timer] = [...f.timers].find(([, entry]) => entry.delay === 2000);
  f.timers.delete(id); await timer.fn();
  assert.equal(f.timers.size, 0); assert.equal(f.call.getState().phase, 'unknown');
  assert.throws(() => f.guard.acquire());
  await f.terminate(); assert.equal(f.call.getState().phase, 'ended');
});

test('shared RTC refuses another join, mute or leave while a device request owns it', async () => {
  const guard = createCommunicationGuard(), owner = guard.acquire(); let closed = 0;
  const rtc = createRtcSession(undefined, async () => ({ close: async () => { closed++; }, setMuted: async () => {} }), guard);
  await assert.rejects(rtc.joinChannel({ protocol: 'SIP' }), /先结束/);
  await rtc.joinChannel({ protocol: 'SIP', callId: 'mine' }, { reservation: owner });
  await assert.rejects(rtc.leaveChannel(), /先结束/); await assert.rejects(rtc.setMuted(true), /先结束/);
  assert.equal(rtc.getActiveCallId(), 'mine'); assert.equal(closed, 0);
  await rtc.leaveChannel(owner); guard.release(owner); assert.equal(closed, 1);
});

test('existing personnel call entry is blocked before any server call while device session is reserved', () => {
  const owner = communicationGuard.acquire();
  try {
    const store = createStore(null); let requests = 0; store.setVoice(() => { requests++; });
    assert.throws(() => store.startCall(['P1'], '单呼'), /调度通信/);
    assert.equal(requests, 0);
  } finally { communicationGuard.release(owner); }
});

const pendingVoice = () => ({ ...media, verified: false, available: false, reason: '待联调', verificationStatus: 'PENDING' });
const pendingDevice = () => ({ ...device(), featureStates: { voice: { supported: true, verified: false, available: false, reason: '待联调' } } });
const acceptance = () => ({ acceptanceTest: true, operator: { id: 'demo-system' } });

test('pending voice needs explicit administrator acceptance and never modifies permanent feature states', async () => {
  for (const options of [{}, { ...acceptance(), acceptanceTest: false }, { ...acceptance(), acceptanceTest: 'true' },
    { acceptanceTest: true, operator: { id: 'demo-duty' } }, { acceptanceTest: true },
    { acceptanceTest: true, operator: { id: 'demo-system', enabled: false } }]) {
    const f = fixture(); await assert.rejects(f.call.start(pendingDevice(), pendingVoice(), false, assignment, options));
    assert.equal(f.requests.length, 0); assert.equal(f.rtcEvents.length, 0);
  }
  const f = fixture(), d = pendingDevice(), feature = pendingVoice(), original = JSON.stringify({ d, feature });
  await f.call.start(d, feature, false, assignment, acceptance());
  assert.deepEqual(f.requests[0].body, { ...assignment, video: false, idempotencyKey: 'stable-test-request', acceptanceTest: true });
  assert.equal(f.call.getState().acceptanceTest, true);
  assert.equal(JSON.stringify({ d, feature }), original);
  assert.equal(deviceCallUnavailable(d, feature, false, assignment), '待联调');
  await f.terminate();
});

test('administrator acceptance cannot bypass permission, assignment, freshness, physical type or SIP readiness', async () => {
  const cases = [
    [{ ...pendingDevice(), online: false }, pendingVoice(), assignment],
    [{ ...pendingDevice(), sourceTime: '2020-01-01' }, pendingVoice(), assignment],
    [{ ...pendingDevice(), type: 'B', source: 'DIRECT_BELT' }, pendingVoice(), assignment],
    [{ ...pendingDevice(), sipRegistered: false }, pendingVoice(), assignment],
    [{ ...pendingDevice(), communicationProtocol: 'AGORA' }, pendingVoice(), assignment],
    [{ ...pendingDevice(), capabilities: { actions: [] } }, pendingVoice(), assignment],
    [pendingDevice(), { ...pendingVoice(), reason: '无操作权限' }, assignment],
    [pendingDevice(), { ...pendingVoice(), integrationStatus: 'NOT_CONNECTED' }, assignment],
    [pendingDevice(), { ...pendingVoice(), supported: false }, assignment],
    [pendingDevice(), pendingVoice(), { ...assignment, assignmentVersion: 4 }],
    [pendingDevice(), pendingVoice(), undefined],
  ];
  for (const [d, feature, captured] of cases) {
    const f = fixture(); await assert.rejects(f.call.start(d, feature, false, captured, acceptance()));
    assert.equal(f.requests.length, 0); assert.equal(f.rtcEvents.length, 0);
  }
});

test('acceptance retries preserve the same flag and key; original cleanup remains possible after authority changes', async () => {
  let attempts = 0;
  const f = fixture({ create: async () => { if (++attempts === 1) throw Error('network lost'); return offered; } });
  await f.call.start(pendingDevice(), pendingVoice(), false, assignment, acceptance());
  assert.equal(f.call.getState().phase, 'unknown');
  await f.call.refresh();
  const creations = f.requests.filter(row => row.url.endsWith('/mobile/calls'));
  assert.equal(creations.length, 2); assert.deepEqual(creations[0].body, creations[1].body);
  assert.equal(creations[0].body.acceptanceTest, true);
  assert.match(deviceCallUnavailable(pendingDevice(), pendingVoice(), false, assignment, { acceptanceTest: true, operator: { id: 'demo-duty' } }), /系统管理员/);
  assert.match(deviceCallUnavailable(pendingDevice(), { ...pendingVoice(), assignmentVersion: 4 }, false, assignment, acceptance()), /领用/);
  await f.call.end(); assert.equal(f.requests.filter(row => row.url.endsWith('/end')).length, 1);
  await f.terminate(); assert.equal(f.call.getState().phase, 'ended');
});

test('assignment payload cannot smuggle acceptance or video flags into a normal call', async () => {
  const f = fixture();
  await f.call.start(device(), media, false, { ...assignment, acceptanceTest: true, video: true, operator: { id: 'demo-system' } });
  assert.deepEqual(f.requests[0].body, { ...assignment, video: false, idempotencyKey: 'stable-test-request' });
  assert.equal(f.call.getState().acceptanceTest, false); await f.terminate();
});
