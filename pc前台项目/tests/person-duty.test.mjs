import test from 'node:test';
import assert from 'node:assert/strict';
import { PERSON_DUTY_STATUSES, normalizePersonDutyStatus, personDutyStatusLabel } from '../../shared/person-duty.mjs';
import { personDutyPresentation } from '../src/lib/person-duty.js';
import { createStore, KEY, seed } from '../src/mock/data.js';

test('only explicit duty values become known personnel duty states', () => {
  assert.deepEqual(PERSON_DUTY_STATUSES, { ON_DUTY: '在岗', OFF_DUTY: '离岗', UNKNOWN: '待确认' });
  for (const value of [null, undefined, '', true, false, 'enabled', 'disabled', 'on_duty', 'constructor', {}]) {
    assert.equal(normalizePersonDutyStatus(value), 'UNKNOWN');
    assert.equal(personDutyStatusLabel(value), '待确认');
  }
  assert.equal(normalizePersonDutyStatus('ON_DUTY'), 'ON_DUTY');
  assert.equal(personDutyStatusLabel('OFF_DUTY'), '离岗');
});

test('duty display uses the manual state independently of enabled, online, work and equipment', () => {
  for (const active of [true, false]) for (const online of [true, false]) {
    const facts = { active, enabled: active, online, workId: 'work-1', equipment: ['helmet', 'watch'] };
    assert.deepEqual(personDutyPresentation(facts), { status: 'UNKNOWN', label: '在岗待确认', color: 'muted', title: '尚未维护在岗状态' });
    assert.equal(personDutyPresentation({ ...facts, dutyStatus: 'ON_DUTY' }).color, 'green');
    assert.equal(personDutyPresentation({ ...facts, dutyStatus: 'OFF_DUTY' }).label, '离岗');
    assert.equal(personDutyPresentation({ ...facts, dutyStatus: 'OFF_DUTY' }).color, 'muted');
  }
});

test('manual duty tooltip identifies the operator and formats the update time', () => {
  const person = { dutyStatus: 'ON_DUTY', dutyStatusSource: 'MANUAL', dutyStatusUpdatedBy: '人员管理员', dutyStatusUpdatedAt: '2026-10-27T07:51:35.508036103Z' };
  assert.equal(personDutyPresentation(person).title, '后台人工维护 · 维护人：人员管理员 · 更新时间：2026-10-27 15:51:35');
  assert.equal(personDutyPresentation({ dutyStatus: 'OFF_DUTY', dutyStatusUpdatedAt: 'invalid' }).title, '人员在岗状态');
  assert.equal(personDutyPresentation({ ...person, dutyStatus: 'UNKNOWN' }).title, '尚未维护在岗状态');
});

test('remote and cached off-duty people retain their active archive and current device bindings', () => {
  const values = new Map();
  const storage = { getItem: key => values.get(key), setItem: (key, value) => values.set(key, value), removeItem: key => values.delete(key) };
  const snapshot = seed();
  for (const device of snapshot.devices) device.source = 'PLATFORM';
  const person = snapshot.people.find(row => row.id === 'P1');
  const currentBindings = snapshot.bindings.filter(row => row.personId === person.id && !row.end);
  assert.ok(currentBindings.length > 0);
  Object.assign(person, { dutyStatus: 'OFF_DUTY', dutyStatusSource: 'MANUAL', dutyStatusUpdatedAt: '2026-10-27T07:51:35Z', dutyStatusUpdatedBy: '人员管理员' });
  const store = createStore(storage);
  assert.equal(store.replaceRemote(snapshot), true);
  const cached = createStore(storage);
  for (const target of [store, cached]) {
    const record = target.person(person.id);
    assert.equal(record.active, true);
    assert.equal(record.dutyStatus, 'OFF_DUTY');
    assert.equal(record.dutyStatusSource, 'MANUAL');
    assert.equal(record.dutyStatusUpdatedBy, '人员管理员');
    assert.equal(record.dutyStatusUpdatedAt, '2026-10-27T07:51:35Z');
    assert.equal(target.stats({ station: 'S1' }).people.some(row => row.id === person.id), true);
    assert.deepEqual(target.currentDevices(person.id).map(row => row.id), currentBindings.map(row => row.deviceId));
    assert.deepEqual(target.state.bindings.filter(row => row.personId === person.id && !row.end), currentBindings);
  }
  assert.equal(JSON.parse(values.get(KEY)).people.find(row => row.id === person.id).dutyStatus, 'OFF_DUTY');
});
