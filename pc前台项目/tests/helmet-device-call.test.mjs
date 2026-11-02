import test from 'node:test';
import assert from 'node:assert/strict';
import { createHelmetDeviceCall, deviceCallStatus, deviceCallUnavailable } from '../src/lib/helmet-device-call.js';
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
function fixture({ create, join, prepare, recoveryRows = [], recoveryFailure, closeRequest, discover } = {}) {
  const requests = [], discoveries = [], rtcEvents = [], timers = new Map();
  let sequence = 0, time = 0, server = { status: 'offered', serverConnected: false, connectedDeviceIds: [] }, joined;
  const guard = createCommunicationGuard();
  const rtc = {
    getActiveCallId: () => null,
    async prepareMicrophone(options) { guard.assertAvailable(options.reservation); if (prepare) await prepare(options); options.onMediaState('microphone_ready'); },
    async joinChannel(value, options) { guard.assertAvailable(options.reservation); rtcEvents.push(['join', value]); joined = options; if (join) await join(value, options); },
    async leaveChannel(token) { guard.assertAvailable(token); rtcEvents.push(['leave']); },
    async setMuted(value, token) { guard.assertAvailable(token); rtcEvents.push(['muted', value]); },
    async resumeAudio(token) { guard.assertAvailable(token); rtcEvents.push(['play']); },
  };
  const fetchImpl = async (url, options) => {
    const body = options.body && JSON.parse(options.body);
    if (url.includes('/mobile/calls?')) {
      discoveries.push(url);
      if (recoveryFailure) throw Error('recovery unavailable');
      return { ok: true, status: 200, json: async () => discover ? discover(discoveries.length) : recoveryRows };
    }
    requests.push({ url, body, method: options.method || 'GET' });
    let value;
    if (url.endsWith('/mobile/calls')) value = create ? await create(body, requests) : offered;
    else if (url.endsWith('/end')) value = { status: 'ending' };
    else if (url.includes('/mobile/calls/')) value = { ...server };
    else if (url.includes('/helmet/calls/')) value = server;
    else throw Error('Unexpected request ' + url);
    if (value?.httpStatus) return { ok: false, status: value.httpStatus, json: async () => value };
    return { ok: true, status: 200, json: async () => value };
  };
  const call = createHelmetDeviceCall({ fetchImpl, rtc, guard, makeId: () => 'stable-test-request', now: () => time, getOperatorId: () => 'qa-operator', getCloseRequest: () => closeRequest,
    schedule: (fn, delay) => { const id = ++sequence; timers.set(id, { fn, delay }); return id; }, cancel: id => timers.delete(id) });
  return { call, guard, requests, discoveries, rtcEvents, timers, setServer: value => { server = value; }, setRecoveryRows: value => { recoveryRows = value; },
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
  assert.equal(f.rtcEvents.filter(([kind]) => kind === 'join').length, 0);
  assert.equal(f.call.getState().recovered, true);
  await f.terminate(); assert.doesNotThrow(() => f.guard.acquire());
});

test('server permission refusal releases the prepared microphone without joining', async () => {
  const f = fixture({ create: async () => ({ httpStatus: 403, errorCode: 'PERMISSION_DENIED', message: '设备不在授权范围' }) });
  await f.call.start(device(), media, false, assignment);
  assert.equal(f.call.getState().phase, 'failed'); assert.deepEqual(f.rtcEvents, [['leave']]);
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

test('microphone permission is obtained before any cloud call or ringing deadline', async () => {
  let allow;
  const f = fixture({ prepare: () => new Promise(resolve => { allow = resolve; }) });
  const starting = f.call.start(device(), media, false, assignment);
  await flush();
  assert.equal(f.requests.length, 0);
  assert.match(deviceCallStatus(f.call.getState()), /麦克风授权.*尚未呼叫/);
  assert.equal([...f.timers.values()].some(timer => timer.delay === 60000), false);
  await f.call.refresh(); assert.equal(f.requests.length, 0);
  allow(); await starting;
  assert.equal(f.requests.filter(row => row.url.endsWith('/mobile/calls')).length, 1);
  await f.terminate();
});

test('microphone failure or cancelled preparation never creates even a cleanup cloud call', async () => {
  const denied = fixture({ prepare: async () => { throw Error('电脑麦克风权限被拒绝，未呼叫设备'); } });
  await denied.call.start(device(), media, false, assignment);
  assert.equal(denied.requests.length, 0); assert.equal(denied.call.getState().phase, 'failed');
  assert.match(denied.call.getState().error, /麦克风权限被拒绝/);
  assert.doesNotThrow(() => denied.guard.acquire());
  let allow;
  const cancelled = fixture({ prepare: () => new Promise(resolve => { allow = resolve; }) });
  const starting = cancelled.call.start(device(), media, false, assignment);
  await flush(); await cancelled.call.end(); allow(); await starting;
  assert.equal(cancelled.requests.length, 0); assert.equal(cancelled.call.getState().phase, 'ended');
  assert.doesNotThrow(() => cancelled.guard.acquire());
});

test('an answered helmet with an unjoined browser is not reported as missed device answering', async () => {
  const f = fixture(); await f.call.start(device(), media, false, assignment); f.emit('invite_sent');
  f.setServer({ status: 'answered', serverConnected: false, connectedDeviceIds: [device().id] });
  await f.call.refresh();
  assert.equal(f.call.getState().deviceAnswered, true); assert.equal(f.call.getState().localJoined, false);
  assert.match(deviceCallStatus(f.call.getState()), /设备已应答.*电脑已发出入会请求/);
  assert.equal(f.requests.some(row => row.url.endsWith('/joined')), false);
  await f.timeout();
  assert.match(f.call.getState().error, /安全帽已应答.*电脑.*入会确认.*超时/);
  assert.doesNotMatch(f.call.getState().error, /等待安全帽接听超时/);
  await f.terminate();
});

test('only established local membership reports joined and both independent confirmations are needed', async () => {
  const f = fixture(); await f.call.start(device(), media, false, assignment); f.emit('invite_sent');
  f.setServer({ status: 'connected', serverConnected: true, connectedDeviceIds: [device().id] });
  await f.call.refresh(); assert.equal(f.call.getState().phase, 'connecting');
  assert.equal(f.requests.some(row => row.url.endsWith('/joined')), false);
  f.emit('local_joined'); await flush(); f.emit('remote_audio'); await f.call.refresh();
  assert.equal(f.requests.filter(row => row.url.endsWith('/joined')).length, 1);
  assert.equal(f.call.getState().phase, 'active');
  assert.match(deviceCallStatus(f.call.getState()), /双方已接通/);
  await f.terminate();
});

const ownedRow = (values = {}) => ({ ...assignment, id: 'COMM-existing', channelName: 'SIP-existing',
  operationType: 'call', requesterUserId: 'qa-operator', status: 'answered', connectedDeviceIds: [device().id], ...values });

test('lost creation followed by a conflict never clears the key or permits another call', async () => {
  for (const errorCode of ['CALL_UNAVAILABLE','PLATFORM_UNCONFIRMED','CALL_BUSY','ASSIGNMENT_CHANGED']) {
    let count = 0;
    const f = fixture({ create: async () => ++count === 1 ? { httpStatus: 502, message: 'upstream result lost' } : { httpStatus: 409, errorCode } });
    await f.call.start(device(), media, false, assignment); await f.call.refresh();
    assert.equal(f.call.getState().phase, 'unknown');
    await assert.rejects(f.call.start(device(), media, false, assignment), /先结束/);
    assert.equal(count, 2); assert.deepEqual(new Set(f.requests.map(row => row.body?.idempotencyKey).filter(Boolean)), new Set(['stable-test-request']));
    assert.throws(() => f.guard.acquire()); assert.equal(f.rtcEvents.some(([kind]) => kind === 'join'), false);
    await f.call.detach();
  }
});

test('known pre-submission changes while microphone permission is pending fail without an unknown session', async () => {
  for (const errorCode of ['ASSIGNMENT_CHANGED','ASSIGNMENT_REQUIRED','FEATURE_PENDING_ACCEPTANCE','FEATURE_UNSUPPORTED','FEATURE_NOT_CONNECTED','MEDIA_SERVICE_UNAVAILABLE']) {
    let allow;
    const f = fixture({ prepare: () => new Promise(resolve => { allow = resolve; }), create: async () => ({ httpStatus: errorCode === 'MEDIA_SERVICE_UNAVAILABLE' ? 503 : 409, errorCode, message: '服务端已确认未下发' }) });
    const starting = f.call.start(device(), media, false, assignment); await flush();
    assert.equal(f.requests.length, 0); allow(); await starting;
    assert.equal(f.call.getState().phase, 'failed'); assert.doesNotThrow(() => f.guard.acquire());
    assert.deepEqual(f.rtcEvents, [['leave']]); assert.equal(f.requests.some(row => row.url.endsWith('/end')), false);
  }
});

test('same-key recovery may return a terminal public row without credentials or a channel', async () => {
  for (const status of ['ended', 'failed']) {
    let count = 0;
    const f = fixture({ create: async () => { if (++count === 1) throw Error('response lost'); return { id: 'COMM-test', status, failReason: status === 'failed' ? '未下发' : '' }; } });
    await f.call.start(device(), media, false, assignment); await f.call.refresh();
    assert.equal(f.call.getState().phase, status); assert.equal(f.call.getState().recordId, 'COMM-test');
    assert.equal(f.rtcEvents.filter(([kind]) => kind === 'join').length, 0); assert.equal(f.rtcEvents.filter(([kind]) => kind === 'leave').length, 1);
    assert.doesNotThrow(() => f.guard.acquire()); assert.equal(f.requests.some(row => row.url.endsWith('/end')), false);
  }
});

test('a public unknown creation without a channel stays recoverable and refresh never dials again', async () => {
  const f = fixture({ create: async () => ownedRow({ channelName: '', status: 'unknown' }) });
  await f.call.start(device(), media, false, assignment);
  assert.equal(f.call.getState().recovered, true); assert.equal(f.call.getState().phase, 'unknown');
  f.setServer(ownedRow({ status: 'answered' })); await f.call.refresh();
  assert.equal(f.call.getState().callId, 'SIP-existing'); assert.equal(f.call.getState().localJoined, false);
  assert.match(deviceCallStatus(f.call.getState()), /已有会话.*设备已应答.*本页未加入/);
  assert.equal(f.rtcEvents.some(([kind]) => kind === 'join'), false);
  assert.equal(f.requests.filter(row => row.url.endsWith('/mobile/calls')).length, 1);
  await f.terminate();
});

test('fresh page recovers only its actor public session before microphone and requires explicit end', async () => {
  let microphone = 0, implicitClose = 0;
  const f = fixture({ recoveryRows: [ownedRow({ id:'COMM-other', requesterUserId:'another-account' }), ownedRow()], prepare: async () => { microphone++; }, closeRequest: async () => { implicitClose++; } });
  await assert.rejects(f.call.start(device(), media, false, assignment), /先结束/);
  assert.equal(f.call.getState().recordId, 'COMM-existing'); assert.equal(microphone, 0); assert.equal(f.requests.length, 0);
  await assert.rejects(f.call.setMuted(true), /尚未加入/);
  f.setServer(ownedRow({ status:'connected', serverConnected:true })); await f.call.refresh();
  assert.equal(f.call.getState().phase, 'unknown'); assert.equal(f.call.getState().localJoined, false);
  assert.equal(f.requests.some(row => row.url.includes('/credentials') || row.url.includes('/helmet/')), false);
  await f.call.detach(); assert.equal(implicitClose, 0); assert.equal(f.requests.some(row => row.url.endsWith('/end')), false);
  await f.call.recover({ operatorId:'qa-operator' }); await f.call.end();
  assert.equal(f.requests.filter(row => row.url.endsWith('/end')).length, 1); await f.terminate();
});

test('foreign or terminal recovery rows do not become a local session and discovery failure blocks dialing', async () => {
  const f = fixture({ recoveryRows: [ownedRow({requesterUserId:'another-account'}), ownedRow({status:'ended'})] });
  await f.call.recover({ operatorId:'qa-operator' }); assert.equal(f.call.getState().recordId, ''); assert.equal(f.requests.length, 0);
  let microphone = 0;
  const unavailable = fixture({ recoveryFailure: true, prepare: async () => { microphone++; } });
  await assert.rejects(unavailable.call.start(device(), media, false, assignment), /未能核对/);
  assert.equal(microphone, 0); assert.equal(unavailable.requests.length, 0); assert.match(unavailable.call.getState().recoveryError, /不会重复拨号/);
});

test('a known busy creation discovers the existing session without another POST or automatic joining', async () => {
  const f = fixture({ discover: count => count === 1 ? [] : [ownedRow()], create: async () => ({ httpStatus:409, errorCode:'CALL_BUSY' }) });
  await f.call.start(device(), media, false, assignment);
  assert.equal(f.call.getState().recordId, 'COMM-existing'); assert.equal(f.call.getState().recovered, true);
  assert.equal(f.requests.filter(row => row.url.endsWith('/mobile/calls')).length, 1);
  assert.equal(f.rtcEvents.some(([kind]) => kind === 'join'), false); assert.equal(f.requests.some(row => row.url.endsWith('/end')), false);
  await f.call.detach();
});

test('account exit immediately detaches locally and closes only the original locally started record with its original request', async () => {
  const closes = [];
  const f = fixture({ closeRequest: async url => { closes.push(url); throw Error('old login expired'); } });
  await f.call.start(device(), media, false, assignment);
  await f.call.detach({ request: async () => assert.fail('new account must not close old account call') });
  assert.deepEqual(closes, ['/api/guardian/v1/mobile/calls/COMM-test/end']);
  assert.equal(f.call.getState().phase, 'idle'); assert.equal(f.call.getState().recordId, '');
  assert.notEqual(f.call.getState().serverStatus, 'ended'); assert.equal(f.rtcEvents.filter(([kind]) => kind === 'leave').length, 1);
  assert.doesNotThrow(() => f.guard.acquire());
});

test('late create after logout is never joined and only its returned record is closed under original auth', async () => {
  let reply; const closes = [];
  const f = fixture({ create: () => new Promise(resolve => { reply = resolve; }), closeRequest: async url => { closes.push(url); } });
  const starting = f.call.start(device(), media, false, assignment); await flush();
  await f.call.detach(); reply(offered); await starting;
  assert.equal(f.call.getState().phase, 'idle'); assert.equal(f.rtcEvents.some(([kind]) => kind === 'join'), false);
  assert.deepEqual(closes, ['/api/guardian/v1/mobile/calls/COMM-test/end']);
});

test('stale recovery is discarded after logout or actor change without touching the new actor session', async () => {
  let reply;
  const f = fixture({ discover: count => count === 1 ? new Promise(resolve => { reply = resolve; }) : [ownedRow({ requesterUserId:'new-operator', id:'COMM-new' })] });
  const recovering = f.call.recover({ operatorId:'qa-operator' }); await flush(); await f.call.detach();
  await f.call.recover({ operatorId:'new-operator' }); reply([ownedRow()]); await recovering;
  assert.equal(f.call.getState().recordId, 'COMM-new'); assert.equal(f.call.getState().recovered, true);
  assert.equal(f.requests.length, 0); assert.equal(f.rtcEvents.length, 0); await f.call.detach();
});

test('changing page subscribers retains the same locally active session until explicit end', async () => {
  const f = fixture(); const unsubscribe = f.call.subscribe(() => {});
  await f.call.start(device(), media, false, assignment); unsubscribe();
  let state; const next = f.call.subscribe(value => { state=value; });
  assert.equal(state.recordId, 'COMM-test'); assert.equal(f.requests.some(row => row.url.endsWith('/end')), false);
  assert.equal(f.rtcEvents.some(([kind]) => kind === 'leave'), false);
  next(); await f.terminate();
});

test('server recoveryOnly preserves a no-longer-authorized existing call without credentials or automatic hangup', async () => {
  const f = fixture({ create: async () => ownedRow({ recoveryOnly:true, operationErrorCode:'ASSIGNMENT_CHANGED' }) });
  await f.call.start(device(),media,false,assignment);
  assert.equal(f.call.getState().recovered,true); assert.equal(f.call.getState().phase,'unknown');
  assert.equal(f.rtcEvents.some(([kind])=>kind==='join'),false); assert.equal(f.requests.some(row=>row.url.endsWith('/end')),false);
  await f.terminate();
});

test('logout during pre-dial discovery cancels the start without opening a microphone or posting', async () => {
  let reply, microphone=0;
  const f=fixture({ discover:()=>new Promise(resolve=>{reply=resolve;}), prepare:async()=>{microphone++;} });
  const starting=f.call.start(device(),media,false,assignment); await flush(); await f.call.detach(); reply([]);
  await assert.rejects(starting,/尚未核对|登录状态/);
  assert.equal(microphone,0); assert.equal(f.requests.length,0); assert.equal(f.call.getState().phase,'idle');
});

test('switching actors closes only a locally owned call and recovers the new actor without local audio', async () => {
  const closes=[]; const f=fixture({ closeRequest:async url=>{closes.push(url);} });
  await f.call.start(device(),media,false,assignment);
  f.setRecoveryRows([ownedRow({id:'COMM-new',requesterUserId:'new-account'})]);
  await f.call.recover({operatorId:'new-account'});
  assert.deepEqual(closes,['/api/guardian/v1/mobile/calls/COMM-test/end']);
  assert.equal(f.call.getState().recordId,'COMM-new'); assert.equal(f.call.getState().localJoined,false);
  assert.equal(f.rtcEvents.filter(([kind])=>kind==='join').length,1);
  await f.call.detach(); assert.equal(closes.length,1);
});
