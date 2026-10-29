import { test } from "node:test";
import assert from "node:assert/strict";
import { deviceStatus, projectDevice, supportsDeviceAction } from "../src/lib/device-telemetry.js";
import { createStore, seed } from "../src/mock/data.js";

const direct = (patch = {}) => ({
  id: "RL-H001", source: "DIRECT_HELMET", sn: "SN-1", deviceNumber: "device-1",
  type: "H", active: true, online: true, battery: 70, worn: true, video: "available",
  freshness: "CURRENT", updated: new Date(Date.now() - 1000).toISOString(),
  batteryFreshness:'CURRENT',isWearedFreshness:'CURRENT',
  communicationProtocol: "SIP", capabilities: [], featureStates: { voice: { supported:true, verified:true, available:true }, broadcast: { supported:true, verified:true, available:true } }, ...patch,
});

function locate(state, deviceId = 'RL-H001') {
  const observed = { latitude:31.2, longitude:121.4, coordinateSystem:'GCJ02', locationQuality:'valid', locationFreshness:'CURRENT', locationReportedAt:new Date(Date.now() - 1000).toISOString() };
  const binding = state.bindings.find(b => b.personId === 'P1' && b.deviceId === deviceId && !b.end);
  Object.assign(binding, { assignmentId: `assignment-${deviceId}`, assignmentVersion: 2 });
  Object.assign(state.people[0], observed, { locationDeviceId: deviceId, locationAssignmentId: binding.assignmentId, locationAssignmentVersion: binding.assignmentVersion });
  Object.assign(state.devices.find(d => d.id === deviceId), observed);
  return observed;
}

test('a current heartbeat does not revive an expired battery or wear observation',()=>{
  const projected=projectDevice(direct({batteryFreshness:'STALE',isWearedFreshness:'UNKNOWN'}));
  assert.equal(projected.online,true);assert.equal(projected.battery,null);assert.equal(projected.worn,null);
});

test("direct identity and real telemetry stay separate from sample video", () => {
  const raw = direct(), projected = projectDevice(raw);
  assert.equal(projected.id, "RL-H001");
  assert.equal(projected.sn, "SN-1");
  assert.equal(projected.deviceNumber, "device-1");
  assert.equal(projected.online, true);
  assert.equal(projected.battery, 70);
  assert.equal(projected.worn, true);
  assert.equal(projected.video, "unavailable");
  assert.equal(raw.video, "available");
});

test("direct belt preserves unconfirmed raw values and cannot gain helmet media actions", () => {
  const raw = direct({ source: "DIRECT_BELT", type: "B", communicationProtocol: "WEBSOCKET",
    worn: null, isWeared: "2", hangerAStatus: "1", hangerBStatus: "0",
    hookAEngaged: null, hookBEngaged: null, capabilities: ["tts", "intercom"] });
  const projected = projectDevice(raw);
  assert.equal(projected.online, true);
  assert.equal(projected.battery, 70);
  assert.equal(projected.worn, null);
  assert.equal(projected.isWeared, "2");
  assert.equal(projected.hangerAStatus, "1");
  assert.equal(projected.hangerBStatus, "0");
  assert.equal(projected.hookAEngaged, null);
  assert.equal(projected.hookBEngaged, null);
  assert.equal(projected.video, "unavailable");
  assert.equal(supportsDeviceAction(projected, "tts"), false);
  assert.equal(supportsDeviceAction(projected, "intercom"), false);
  const stale = projectDevice({ ...raw, freshness: "STALE", hookAEngaged: true, hookBEngaged: false });
  assert.equal(stale.hookAEngaged, null);
  assert.equal(stale.hookBEngaged, null);
  assert.equal(stale.online, null);
});

test("missing, expired or future observations never become current/offline", () => {
  for (const patch of [
    { freshness: "STALE" }, { updated: null },
    { updated: new Date(Date.now() - 360000).toISOString() },
    { updated: new Date(Date.now() + 60000).toISOString() },
  ]) {
    const d = projectDevice(direct(patch));
    assert.equal(d.online, null);
    assert.equal(d.battery, null);
    assert.equal(d.worn, null);
    assert.notEqual(deviceStatus(d), "在线");
    assert.notEqual(deviceStatus(d), "离线");
  }
  assert.equal(deviceStatus(direct({ online: false })), "离线");
  assert.equal(deviceStatus(projectDevice(direct({ online: false, freshness: "STALE" }))), "离线");
  assert.equal(deviceStatus(direct({ online: null })), "状态未知");
});

test("source alone grants no communications and verified SIP uses its own adapter", () => {
  assert.equal(supportsDeviceAction(direct(), "intercom"), false);
  assert.equal(supportsDeviceAction(direct({ source: "PLATFORM", communicationProtocol: "" }), "tts"), false);
  assert.equal(supportsDeviceAction(direct({ capabilities: ["intercom"] }), "intercom"), true);
  assert.equal(supportsDeviceAction(direct({ communicationProtocol: 'UNKNOWN', capabilities: ["intercom"] }), "intercom"), false);
  assert.equal(supportsDeviceAction(direct({ capabilities: ["tts"] }), "tts"), true);
  assert.equal(supportsDeviceAction(direct({ online: false, capabilities: ["tts"] }), "tts"), false);
});

test("store projections do not change the authoritative snapshot", () => {
  const store = createStore(null), state = seed();
  Object.assign(state.devices[0], direct({ freshness: "STALE" }));
  store.replaceRemote(state);
  assert.equal(store.device("RL-H001").online, null);
  assert.equal(store.currentDevices("P1")[0].online, null);
  assert.equal(store.stats().online, 0);
  assert.equal(store.state.devices[0].online, true);
  assert.equal(store.locationValid("P1"), false);
});

test("a fresh heartbeat cannot revive a stale GPS position", () => {
  const store = createStore(null), state = seed();
  const observed = locate(state);
  Object.assign(state.devices[0], direct({ locationFreshness: "STALE", locationReportedAt: new Date(Date.now() - 600000).toISOString() }));
  store.replaceRemote(state);
  assert.equal(store.device("RL-H001").online, true);
  assert.equal(store.locationValid("P1"), false);
  Object.assign(store.state.devices[0], observed);
  assert.equal(store.locationValid("P1"), true);
});

test("a bound belt supplies its own current position without falling back to another device", () => {
  const store = createStore(null), state = seed();
  const location = locate(state, 'RL-B001');
  Object.assign(state.devices[0], direct({ locationFreshness: "STALE" }));
  Object.assign(state.devices[1], direct({ id: "RL-B001", source: "DIRECT_BELT", type: "B", ...location }));
  store.replaceRemote(state);
  assert.equal(store.locationDevice("P1").id, "RL-B001");
  assert.equal(store.locationValid("P1"), true);
  Object.assign(store.state.devices[0], location);
  assert.equal(store.locationDevice("P1").id, "RL-B001");
  store.state.devices[1].locationFreshness = "STALE";
  assert.equal(store.locationValid("P1"), false);
  store.state.devices[1].locationFreshness = "CURRENT";
  delete store.state.people[0].locationDeviceId;
  assert.equal(store.locationDevice("P1"), null);
  assert.equal(store.locationValid("P1"), false);
  store.state.people[0].locationDeviceId = "RL-B001";
  Object.assign(store.state.devices[1], location);
  store.state.bindings.find(b => b.deviceId === "RL-B001").end = new Date().toISOString();
  assert.equal(store.locationValid("P1"), false);
  const samples = createStore(null, { demoMode: true });
  assert.equal(samples.locationValid("P1"), true);
  assert.equal(samples.locationDevice("P1").id, "RL-H001");
});

test('real current location rejects incomplete or changed assignments and mixed observations', () => {
  const invalid = [
    state => { delete state.people[0].locationDeviceId; },
    state => { delete state.people[0].locationAssignmentId; },
    state => { delete state.people[0].locationAssignmentVersion; },
    state => { state.people[0].locationAssignmentId = 'old-issue'; },
    state => { state.people[0].locationAssignmentVersion = 1; },
    state => { delete state.bindings[0].assignmentVersion; },
    state => { state.bindings[0].end = new Date().toISOString(); },
    state => { state.bindings.push({ ...state.bindings[0], personId: 'P2' }); },
    state => { state.devices[0].online = false; },
    state => { state.people[0].longitude = 120; },
    state => { state.people[0].locationReportedAt = new Date(Date.now() - 2000).toISOString(); },
    state => { state.people[0].coordinateSystem = 'WGS84'; },
  ];
  for (const invalidate of invalid) {
    const store = createStore(null), state = seed();
    Object.assign(state.devices[0], direct()); locate(state); store.replaceRemote(state);
    assert.equal(store.locationValid('P1'), true);
    invalidate(store.state);
    assert.equal(store.locationDevice('P1'), null, invalidate.toString());
    assert.equal(store.locationValid('P1'), false, invalidate.toString());
  }
});

test('expired business cache waits for the server without claiming sample data was loaded', () => {
  const saved = seed(); saved.businessConfig = { dataVersion: 'old' }; let removed = false;
  const store = createStore({ getItem: () => JSON.stringify(saved), removeItem: () => { removed = true; }, setItem() {} }, { requiredDataVersion: 'wearable-person-v2' });
  assert.equal(removed, true);
  assert.match(store.loadError, /本地业务缓存已失效，等待读取服务器数据/);
  assert.doesNotMatch(store.loadError, /已载入初始/);
  assert.equal(store.state.people.length, 0);
  assert.equal(store.state.devices.length, 0);
});

test("unsupported protocol or unverified capability blocks commands before network or snapshot writes", () => {
  const store = createStore(null), state = seed();
  Object.assign(state.devices[0], direct({ communicationProtocol:'UNKNOWN', capabilities: ["intercom"] }));
  store.replaceRemote(state);
  let sent = 0;
  store.setVoice(() => { sent++; });
  assert.throws(() => store.startCall(["P1"], "单呼"), /语音协议/);
  assert.throws(() => store.broadcast("G1", "请检查"), /播报能力|状态待确认/);
  assert.equal(sent, 0);
  assert.equal(store.state.calls.length, 0);
});

test("local media join and unidentified remote audio cannot mark every device connected", async () => {
  let callbacks;
  const store = createStore(null, { loadRtc: async () => ({
    joinChannel: async (_rtc, events) => { callbacks = events; },
    leaveChannel: async () => {},
  }) });
  const state = seed();
  Object.assign(state.devices[0], direct({ source: "PLATFORM", communicationProtocol: "AGORA", capabilities: { actions: ["intercom"] } }));
  store.replaceRemote(state);
  store.setVoice(() => ({ appId: "app", channel: "channel", token: "fake-test-token" }));
  const id = store.startCall(["P1"], "单呼");
  await store.updateCall(id, "connect");
  assert.equal(store.state.calls[0].connectionQuality, "local_joined");
  assert.match(store.state.calls[0].statusLabel, /设备接通待确认/);
  assert.deepEqual(store.state.calls[0].joined, []);
  callbacks.onMediaState("remote_audio");
  assert.match(store.state.calls[0].statusLabel, /设备身份待确认/);
  assert.deepEqual(store.state.calls[0].joined, []);
  assert.throws(() => store.updateCall(id, "invite", "P2"), /不支持追加成员/);
  await store.updateCall(id, "end");
  callbacks.onMediaState("remote_audio");
  assert.equal(store.state.calls[0].status, "已结束");
});
