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
