import { test } from "node:test";
import assert from "node:assert/strict";
import { createRtcSession } from "../src/lib/rtc.js";

function fakeRtc() {
  const events = new Map(), seen = [];
  const microphone = { close: () => seen.push("microphone-close"), setEnabled: async () => {} };
  const client = {
    on: (event, callback) => events.set(event, callback),
    removeAllListeners: () => events.clear(),
    join: async () => seen.push("join"),
    publish: async () => seen.push("publish"),
    subscribe: async (_user, type) => seen.push("subscribe-" + type),
    leave: async () => seen.push("leave"),
  };
  const session = createRtcSession(async () => ({ default: { createClient: () => client, createMicrophoneAudioTrack: async () => microphone } }));
  return { session, events, seen, client };
}
const credentials = { appId: "app", channel: "channel", token: "fake-test-token" };

test("remote audio is subscribed and played; leaving removes listeners and closes audio", async () => {
  const { session, events, seen } = fakeRtc(), states = [];
  await session.joinChannel(credentials, { onMediaState: state => states.push(state) });
  assert.deepEqual(states, []);
  const user = { uid: 2, audioTrack: { play: () => seen.push("play"), stop: () => seen.push("stop") } };
  events.get("user-published")(user, "audio");
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(seen.slice(-2), ["subscribe-audio", "play"]);
  assert.deepEqual(states, ["remote_audio"]);
  events.get("user-left")(user);
  assert.equal(states.at(-1), "local_joined");
  await session.leaveChannel();
  assert.equal(events.size, 0);
  assert.ok(seen.includes("microphone-close"));
  assert.equal(seen.at(-1), "leave");
});

test("microphone publish failure cleans the partial session", async () => {
  const { session, client, seen, events } = fakeRtc();
  client.publish = async () => { throw Error("publish failed"); };
  await assert.rejects(session.joinChannel(credentials), /publish failed/);
  assert.equal(events.size, 0);
  assert.ok(seen.includes("microphone-close"));
  assert.equal(seen.at(-1), "leave");
});

test("unsupported protocol is rejected before starting an Agora session", async () => {
  const { session, seen } = fakeRtc();
  await assert.rejects(session.joinChannel({ ...credentials, protocol: "UNSUPPORTED" }), /媒体协议/);
  assert.deepEqual(seen, []);
});

test('SIP branch never loads Agora and releases the protocol session on leave', async()=>{
  const seen=[];
  const session=createRtcSession(async()=>{throw Error('Agora must not load');},async(rtc,events)=>{
    assert.equal(rtc.protocol,'SIP');events.onMediaState('remote_audio');
    return {close:async()=>seen.push('close'),setMuted:async value=>seen.push(value)};
  });
  await session.joinChannel({protocol:'SIP'},{onMediaState:state=>seen.push(state)});
  await session.setMuted(true);await session.leaveChannel();
  assert.deepEqual(seen,['remote_audio',true,'close']);
});

test('leaving while SIP connection is pending cancels and cleans its later result', async()=>{
  let finish,closed=0;
  const session=createRtcSession(undefined,()=>new Promise(resolve=>{finish=()=>resolve({close:async()=>{closed++;}})}));
  const joining=session.joinChannel({protocol:'SIP'});
  await new Promise(resolve=>setTimeout(resolve,0));
  await session.leaveChannel();finish();
  await assert.rejects(joining,/取消/);assert.equal(closed,1);
});

function microphone() {
  let stopped = 0;
  const track = { kind: 'audio', readyState: 'live', stop() { this.readyState = 'ended'; stopped++; } };
  return { stream: { getTracks: () => [track], getAudioTracks: () => [track] }, get stopped() { return stopped; } };
}
test('prepared microphone is captured once and transferred to SIP without a second permission request', async () => {
  const mic = microphone(), stages = []; let acquisitions = 0;
  const session = createRtcSession(undefined, async (_rtc, options) => {
    assert.equal(options.microphoneStream, mic.stream);
    assert.equal(mic.stopped, 0);
    return { close: async () => {} };
  }, undefined, { getUserMedia: async constraints => { acquisitions++; assert.deepEqual(constraints, { audio:true, video:false }); return mic.stream; } });
  await session.prepareMicrophone({ onMediaState: value => stages.push(value) });
  assert.deepEqual(stages, ['microphone_permission','microphone_ready']);
  await session.joinChannel({ protocol: 'SIP' }); await session.leaveChannel();
  assert.equal(acquisitions, 1); assert.ok(mic.stopped > 0);
});
test('cancelled permission and timed-out permission stop a late media stream', async () => {
  for (const timeout of [false,true]) {
    const mic = microphone(); let allow, timer;
    const session = createRtcSession(undefined, undefined, undefined, {
      getUserMedia: () => new Promise(resolve => { allow = resolve; }),
      schedule: fn => { timer = fn; return 1; }, cancel: () => {},
    });
    const preparation = session.prepareMicrophone();
    const rejected = assert.rejects(preparation, timeout ? /授权超时.*未呼叫/ : /取消.*未呼叫/);
    if (timeout) timer(); else await session.leaveChannel();
    await rejected; allow(mic.stream); await new Promise(resolve => setImmediate(resolve));
    assert.equal(mic.stopped, 1); assert.equal(session.getActiveCallId(), undefined);
  }
});
test('microphone refusal, absence and occupancy return distinct public errors', async () => {
  for (const [name, text] of [['NotAllowedError', /权限被拒绝/], ['NotFoundError', /未检测到麦克风/], ['NotReadableError', /被占用或无法读取/]]) {
    const session = createRtcSession(undefined, undefined, undefined, { getUserMedia: async () => { const error = Error('private browser error'); error.name = name; throw error; } });
    await assert.rejects(session.prepareMicrophone(), text); assert.equal(session.getActiveCallId(), undefined);
  }
});

test('cancellation while SIP waits for previous cleanup cannot orphan or reuse the transferred microphone', async () => {
  const mic = microphone(); let sipCreated = 0;
  const session = createRtcSession(undefined, async () => { sipCreated++; return { close: async () => {} }; }, undefined,
    { getUserMedia: async () => mic.stream });
  await session.prepareMicrophone();
  const joining = session.joinChannel({ protocol: 'SIP' });
  const rejected = assert.rejects(joining, /取消/);
  await session.leaveChannel(); await rejected;
  assert.equal(sipCreated, 0); assert.ok(mic.stopped > 0); assert.equal(session.getActiveCallId(), undefined);
});
test('SIP close rejection still stops the session microphone', async () => {
  const mic = microphone();
  const session = createRtcSession(undefined, async () => ({ close: async () => { throw Error('cleanup unavailable'); } }), undefined,
    { getUserMedia: async () => mic.stream });
  await session.prepareMicrophone(); await session.joinChannel({ protocol: 'SIP' });
  await assert.rejects(session.leaveChannel(), /cleanup unavailable/);
  assert.ok(mic.stopped > 0); assert.equal(session.getActiveCallId(), undefined);
});
