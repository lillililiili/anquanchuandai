import test from 'node:test';
import assert from 'node:assert/strict';
import { createStore, seed, DATE } from '../src/mock/data.js';
import { demoEnabled, displayDevice, personMapPosition, demoVideoAvailable, latestDeviceRecord } from '../src/lib/data-mode.js';
import { currentVital, videoPeople } from '../src/views/screen/screen-model.js';
import { beijingDate } from '../src/lib/location.js';

test('real mode starts empty without cached data and enables examples only explicitly', () => {
  for (const value of [undefined, '', 'false', '1', true]) assert.equal(demoEnabled(value), false);
  assert.equal(demoEnabled('true'), true);
  const real = createStore(null);
  assert.equal(real.demoMode, false);
  assert.equal(real.state.people.length, 0);
  assert.equal(real.state.events.length, 0);
  assert.equal(real.state.sos.status, 'ended');
  assert.equal(createStore(null, { demoMode: true }).stats().online, 23);
});

test('old cache keeps only RL-W001 and its sample vital without rewriting storage', () => {
  const original = seed();
  const saved = JSON.stringify(original);
  let writes = 0;
  const db = createStore({ getItem: () => saved, setItem: () => writes++ });
  assert.equal(writes, 0);
  assert.equal(db.stats().people.length, 8);
  assert.equal(db.state.devices.length, 1);
  assert.equal(db.state.bindings.length, 1);
  assert.equal(db.currentDevices('P1').length, 1);
  assert.equal(db.device('RL-H001'), undefined);
  assert.equal(db.device('RL-B001'), undefined);
  assert.equal(db.device('RL-W001').source, 'DEMO_WATCH');
  assert.deepEqual(db.state.events, []);
  assert.deepEqual(db.state.media, []);
  assert.deepEqual(db.state.calls, []);
  assert.equal(db.state.sos.status, 'ended');
  assert.equal(db.stats().devices.length, 0);
  assert.equal(db.stats().online, 0);
  assert.equal(db.locationValid('P1'), false);
  assert.equal(db.vitals('P1').record.heartRate, 72);
  assert.equal(db.vitals('P1').simulated, true);
  assert.match(db.vitals('P1').status, /模拟数据/);
  assert.equal(currentVital(db, db.person('P1'), '2026-10-26 10:00:00').demo, true);
  assert.equal(db.state.vitals.length, 1);
  assert.equal(db.vitals('P2').record, null);
  assert.equal(db.stats().simulatedWatches.length, 1);
  assert.throws(() => db.capture('P1'), /不能生成示例/);
  assert.throws(() => db.reset(), /不能重置/);
  assert.deepEqual(db.tracks('P1', DATE, '00:00', '23:59'), []);
});

test('a sample-looking ID cannot hide real equipment or user-maintained records', () => {
  const snapshot = seed();
  snapshot.devices[0] = { ...snapshot.devices[0], source: 'DIRECT_HELMET', deviceNumber: 'actual-helmet' };
  snapshot.devices[1].remark = '已人工核对的资产';
  snapshot.events[0].verification = { text: '现场核对记录' };
  snapshot.media[0].blobId = 'uploaded-proof';
  const db = createStore({ getItem: () => JSON.stringify(snapshot), setItem: () => assert.fail('read projection must not rewrite storage') });
  assert.equal(db.device('RL-H001').source, 'DIRECT_HELMET');
  assert.equal(db.device('RL-B001').remark, '已人工核对的资产');
  assert.equal(db.state.events.length, 1);
  assert.equal(db.state.media.length, 1);
});

test('server-labelled simulated watches are shown separately from real equipment counts', () => {
  const snapshot = seed();
  snapshot.devices = snapshot.devices.filter(device => device.type === 'W').map(device => ({ ...device, source: 'DEMO_WATCH', demo: true }));
  snapshot.bindings = snapshot.bindings.filter(binding => snapshot.devices.some(device => device.id === binding.deviceId));
  const db = createStore(null); db.replaceRemote(snapshot);
  assert.equal(db.vitals('P1').simulated, true);
  const vital = currentVital(db, db.person('P1'), '2026-10-26 10:00:00');
  assert.deepEqual(vital.values, [72, 98, null]);
  assert.equal(vital.trend.length, 1, 'one stored simulated observation must not become five invented points');
  assert.equal(vital.trend[0].value, 72);
  assert.equal(db.stats().devices.length, 0);
  assert.equal(db.stats().simulatedWatches.length, 1);
  assert.deepEqual(db.state.devices.map(device => device.id), ['RL-W001']);
  assert.deepEqual(db.state.vitals.map(record => record.personId), ['P1']);
  assert.equal(db.vitals('P2').watch, undefined);
  assert.equal(demoVideoAvailable({ type: 'H', source: 'DEMO_WATCH', video: 'available' }), false);
});

test('single-watch remote view preserves the original saved snapshot and actual watches', () => {
  const snapshot = seed();
  snapshot.devices = snapshot.devices.filter(device => device.type === 'W').map(device => ({ ...device, source: 'DEMO_WATCH', demo: true }));
  snapshot.devices[1] = { ...snapshot.devices[1], source: 'PLATFORM', demo: false, freshness: 'CURRENT', sourceTime: new Date().toISOString() };
  snapshot.vitals[1] = { ...snapshot.vitals[1], source: '设备上报', demo: false };
  snapshot.bindings = snapshot.bindings.filter(binding => snapshot.devices.some(device => device.id === binding.deviceId));
  const original = JSON.stringify(snapshot), writes = [];
  const db = createStore({ getItem: () => null, setItem: (_, value) => writes.push(value) });
  db.replaceRemote(snapshot);
  assert.equal(JSON.stringify(snapshot), original);
  assert.deepEqual(writes, [original]);
  assert.deepEqual(db.state.devices.map(device => device.id), ['RL-W001', 'RL-W002']);
  assert.equal(db.stats().simulatedWatches.length, 1);
  assert.equal(db.stats().devices.length, 1);
  assert.equal(db.vitals('P2').record.source, '设备上报');
  const missing = structuredClone(snapshot);
  missing.devices = missing.devices.filter(device => device.id !== 'RL-W001');
  db.replaceRemote(missing);
  assert.equal(db.stats().simulatedWatches.length, 0);
  assert.equal(db.state.vitals.some(record => record.source === '预置观测'), false);
});

test('real vital sources override leftover demo flags and sample vitals follow the active owner', () => {
  const snapshot = seed();
  snapshot.devices = snapshot.devices.filter(device => device.type === 'W').map(device => ({ ...device, source: 'DEMO_WATCH', demo: true }));
  snapshot.bindings.find(binding => binding.id === 'BIND2').personId = 'P2';
  snapshot.vitals.push({ ...snapshot.vitals[0], id: 'new-owner-sample', personId: 'P2', source: 'DEMO_WATCH', demo: true });
  for (const source of ['PLATFORM', 'device', 'DIRECT_WATCH']) {
    snapshot.vitals.push({ ...snapshot.vitals[2], id: `real-${source}`, source, demo: true });
  }
  const db = createStore(null); db.replaceRemote(snapshot);
  assert.equal(db.vitals('P1').record, null);
  assert.equal(db.vitals('P2').record.id, 'new-owner-sample');
  assert.deepEqual(db.state.vitals.filter(record => record.source === '预置观测'), []);
  assert.equal(db.vitalHistory('P3').length, 3);
});

test('real mode does not repopulate removed demonstration events and observations', () => {
  const snapshot = seed(); snapshot.events = []; delete snapshot.vitals;
  const db = createStore({ getItem: () => JSON.stringify(snapshot), setItem: () => assert.fail('must not save an unsolicited migration') });
  assert.deepEqual(db.state.events, []);
  assert.deepEqual(db.state.vitals, []);
  db.state.vitals.push({id:'VITAL-SEED-imported',personId:'P1',source:'人工导入',observedAt:'2026-10-23T00:00:00Z'});
  assert.equal(db.vitalHistory('P1').length, 1, 'an ID that looks like a sample is not proof of sample provenance');
});

test('unassigned connected hardware stays unassigned and separate from worn equipment stats', () => {
  const db = createStore(null), snapshot = seed();
  const stamp = new Date().toISOString();
  snapshot.devices.push({ id: 'real-helmet', type: 'H', station: 'S1', active: true, source: 'DIRECT_HELMET', sourceTime: stamp, freshness: 'CURRENT', online: true });
  db.replaceRemote(snapshot);
  assert.equal(db.owner('real-helmet'), null);
  assert.equal(db.device('real-helmet').online, true);
  assert.equal(db.stats().devices.length, 0);
  assert.equal(db.stats().online, 0);
  assert.equal(db.state.bindings.some(b => b.deviceId === 'real-helmet'), false);
  // A separately confirmed existing assignment is counted without altering other ledger rows.
  const assigned = structuredClone(snapshot);
  assigned.bindings.push({ id:'actual-binding', personId:'P1', deviceId:'real-helmet', start:stamp, end:null });
  db.replaceRemote(assigned);
  assert.equal(db.stats().devices.length, 1);
  assert.equal(db.stats().online, 1);
  db.state.devices.at(-1).sourceTime = new Date(Date.now() - 600001).toISOString();
  assert.equal(db.stats().online, 0);
});

test('real maps never convert schematic positions into geographic markers', () => {
  const snapshot = seed();
  assert.equal(personMapPosition(snapshot.people[0]), null);
  assert.deepEqual(personMapPosition(snapshot.people[0], true), snapshot.people[0].position);
  const actual = { longitude:117.1, latitude:36.5, coordinateSystem:'GCJ02', locationQuality:'valid', locationFreshness:'CURRENT', locationReportedAt:new Date().toISOString(), position:[50,50] };
  assert.deepEqual(personMapPosition(actual), {coordinates:[117.1,36.5]});
  actual.locationFreshness = 'STALE';
  assert.equal(personMapPosition(actual), null);
  assert.equal(personMapPosition(actual, true), null);
});

test('real mode cannot play sample streams or generate sample vital trends', () => {
  const db = createStore(null); db.replaceRemote(seed());
  const preset = db.state.devices[0];
  assert.equal(demoVideoAvailable(preset), false);
  assert.equal(demoVideoAvailable(preset, true), true);
  assert.equal(demoVideoAvailable({...preset,source:'DIRECT_HELMET'}, true), false);
  assert.equal(displayDevice(preset).video, 'unavailable');
  assert.deepEqual(videoPeople(db, db.state.people), []);
  const vital = currentVital(db, db.person('P1'), `${DATE} 10:42:18`);
  assert.deepEqual(vital.values, [null,null,null]);
  assert.deepEqual(vital.trend, []);
});

test('current work and new audit timestamps use today while historic dates stay intact', () => {
  const db = createStore(null), snapshot = seed();
  snapshot.works[0].date = '2000-01-01';
  db.replaceRemote(snapshot);
  assert.equal(db.currentWork('P1'), undefined);
  db.state.works[0].date = beijingDate();
  assert.equal(db.currentWork('P1').id, snapshot.works[0].id);
  assert.equal(db.now().slice(0,10), beijingDate());
  assert.match(db.now(), /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/);
});

test('device record timestamp works without factory sync and never changes freshness', () => {
  const devices = [
    { source:'DIRECT_HELMET', lastSeenAt:'2026-10-23T08:43:45Z', freshness:'STALE' },
    { source:'PLATFORM', sourceTime:'2026-10-23T08:40:00Z' },
    { source:'DEMO', updated:'2030-01-01T00:00:00Z' },
  ];
  assert.equal(latestDeviceRecord(devices), '2026-10-23T08:43:45.000Z');
  assert.equal(devices[0].freshness, 'STALE');
  assert.equal(latestDeviceRecord([{source:'DIRECT_HELMET',updated:'bad'}]), null);
});
