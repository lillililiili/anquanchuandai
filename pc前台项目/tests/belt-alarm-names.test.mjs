import test from 'node:test';
import assert from 'node:assert/strict';
import { beltAlarmTitle } from '../../shared/belt-alarm-names.mjs';
import { createStore, seed } from '../src/mock/data.js';

const event = (code, patch = {}) => ({ id: 'belt-event', protocol: 'direct-belt', rawAlarmType: code,
  title: `安全带告警（${code}）`, type: '设备通信', status: '待认领', version: 3, ...patch });

test('documented belt codes display specific event names while keeping source evidence', () => {
  for (const [code, title] of [['3', '温度告警'], ['4', '跌落（撞击）告警'], ['6', '静默告警'], ['11', '近电告警']]) {
    const row = event(code), before = structuredClone(row);
    assert.equal(beltAlarmTitle(row), title);
    assert.deepEqual(row, before);
  }
  assert.equal(beltAlarmTitle(event('6', { rawAlarmType: undefined })), '静默告警');
  assert.equal(beltAlarmTitle(event(6)), '静默告警');
});

test('unknown, mismatched, other-protocol and explicitly configured titles are retained', () => {
  for (const row of [event('77'), event('6', { protocol: 'other' }), event('6', { title: '安全带告警（3）' }),
    event('6', { title: '安全带防双解告警（6）' }), event('0', { title: '安全带发起 SOS', type: '人员求助' })]) {
    assert.equal(beltAlarmTitle(row), row.title);
  }
});

test('current and cached snapshots show the same names without changing remote events or workflows', () => {
  let cached = null;
  const storage = { getItem: () => cached, setItem: (_key, value) => { cached = value; }, removeItem: () => {} };
  const db = createStore(storage, { demoMode: false });
  const snapshot = seed();
  snapshot.events = [event('6'), event('77', { id: 'unknown' }), event('7', { id: 'sos-code' })];
  const before = structuredClone(snapshot);
  assert.equal(db.replaceRemote(snapshot), true);
  assert.equal(db.event('belt-event').title, '静默告警');
  assert.equal(db.event('sos-code').type, '设备通信');
  assert.equal(db.event('belt-event').rawAlarmType, '6');
  assert.equal(db.event('belt-event').version, 3);
  assert.equal(db.event('belt-event').status, '待认领');
  assert.deepEqual(snapshot, before);
  const reloaded = createStore(storage, { demoMode: false });
  assert.equal(reloaded.event('belt-event').title, '静默告警');
  assert.equal(reloaded.event('unknown').title, '安全带告警（77）');
});
