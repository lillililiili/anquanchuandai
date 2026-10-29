import test from 'node:test';
import assert from 'node:assert/strict';
import { createStore, seed } from '../src/mock/data.js';
import { statisticsView, personRealEquipmentCount } from '../src/views/statistics/statistics-model.js';
import { locationPresentation } from '../src/views/location/location-presentation.js';
import { bloodPressure, vitalValue } from '../src/views/person/vital-values.js';

test('historical date selects only dated works/events and never invents past equipment state', () => {
  const db = createStore(null), state = seed();
  state.works = [{ id:'W1', station:'S1', date:'2026-10-01', members:['P1'] }, { id:'W2', station:'S1', date:'2026-10-02', members:['P2'] }, { id:'W3', station:'S1', members:['P1'] }];
  state.events = [{ id:'E1', station:'S1', workId:'W1', date:'2026-10-01', status:'已核验' }, { id:'E2', station:'S1', workId:'W1', date:'2026-10-02', status:'待现场核验' }, { id:'E3', station:'S1', workId:'W1', status:'处理中' }, { id:'E4', station:'S2', workId:'W1', date:'2026-10-01' }];
  Object.assign(state.devices[0], { source:'DIRECT_HELMET', freshness:'CURRENT', sourceTime:new Date().toISOString(), online:true });
  db.replaceRemote(state);
  const all = statisticsView(db, { station:'S1', date:'2026-10-01' });
  assert.deepEqual(all.works.map(w => w.id), ['W1']);
  assert.deepEqual(all.events.map(e => e.id), ['E1']);
  assert.equal(all.verified, 1); assert.equal(all.unresolved, 0);
  assert.deepEqual(all.devices.map(d => d.id), ['RL-H001']);
  assert.equal(all.online, 1);
  const scoped = statisticsView(db, { station:'S1', workId:'W1', date:'2026-10-02' });
  assert.deepEqual(scoped.people.map(p => p.id), ['P1']);
  assert.deepEqual(scoped.works, []);
  assert.deepEqual(scoped.events.map(e => e.id), ['E2']);
  assert.equal(personRealEquipmentCount(db, scoped, 'P1'), 1);
  assert.equal(personRealEquipmentCount(db, scoped, 'P2'), 0);
});

test('last known offline location is explicitly history and invalid raw person coordinates are not current', () => {
  const historical = { deviceId:'belt-real', longitude:117.2, latitude:36.7, coordinateSystem:'GCJ02', locationSource:'DIRECT_BELT', locationReportedAt:'2026-10-01T01:00:00Z' };
  const db = { locationValid: () => false, locationDevice: () => null };
  const person = { id:'P1', ...historical };
  assert.equal(locationPresentation(db, person).summary, '暂无有效当前位置');
  person.lastKnownLocation = historical;
  const result = locationPresentation(db, person);
  assert.equal(result.deviceId, 'belt-real');
  assert.match(result.summary, /最后已知位置 · 历史/);
  assert.match(result.detail, /不绘制为当前位置/);
  db.locationValid = () => true; db.locationDevice = () => ({ id:'helmet-current' });
  assert.match(locationPresentation(db, person).summary, /^当前位置/);
  assert.equal(locationPresentation(db, person).deviceId, 'helmet-current');
});

test('missing vital measurements stay empty instead of becoming zero or undefined pressure', () => {
  for (const value of [null, undefined, '', NaN, Infinity]) assert.equal(vitalValue(value, 1), null);
  assert.equal(vitalValue(36.5, 1), '36.5');
  assert.equal(bloodPressure({ systolic:120 }), null);
  assert.equal(bloodPressure({ systolic:120, diastolic:80 }), '120 / 80');
});
