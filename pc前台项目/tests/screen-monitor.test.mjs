import test from 'node:test';
import assert from 'node:assert/strict';
import { personEquipmentMonitor, eventActivity } from '../src/views/screen/screen-model.js';

test('监护卡片使用当前领用的真实设备，有效上报显示零电量及实际挂接状态', () => {
  const current = { source: 'PLATFORM', sourceTime: new Date().toISOString(), freshness: 'CURRENT', active: true, online: true };
  const feature = { supported: true, verified: true, available: true };
  const devices = [
    { ...current, id: 'H1', type: 'H', battery: 0, worn: false, featureStates: { battery: feature, wear: feature } },
    { ...current, id: 'B1', type: 'B', battery: 35, hookAEngaged: true, hookBEngaged: false, featureStates: { battery: feature, hooks: feature } },
  ];
  const db = { currentDevices: id => id === 'P1' ? devices : [] };
  const [helmet, belt] = personEquipmentMonitor(db, { id: 'P1' });
  assert.equal(helmet.battery, 0);
  assert.equal(helmet.detail, '未佩戴');
  assert.equal(helmet.detailTone, 'warn');
  assert.equal(belt.detail, '已挂接 / 未挂接');
  assert.equal(belt.battery, 35);
  assert.ok(personEquipmentMonitor(db, { id: 'P2' }).every(item => item.status === '未领用'));
});

test('过期、离线或未核验的遥测不会显示成正常，模拟及停用设备不进入监护卡片', () => {
  const feature = { supported: true, verified: true, available: true };
  const device = { id: 'B1', type: 'B', source: 'PLATFORM', active: true, online: true, battery: 90,
    sourceTime: new Date(Date.now() - 600000).toISOString(), freshness: 'STALE', hookAEngaged: true, hookBEngaged: true,
    featureStates: { battery: feature, hooks: feature } };
  const db = { currentDevices: () => [device] };
  let belt = personEquipmentMonitor(db, { id: 'P1' })[1];
  assert.equal(belt.battery, null);
  assert.equal(belt.detail, '暂无有效上报');
  assert.equal(belt.status, '数据陈旧');
  Object.assign(device, { sourceTime: new Date().toISOString(), freshness: 'CURRENT', online: false });
  belt = personEquipmentMonitor(db, { id: 'P1' })[1];
  assert.equal(belt.status, '离线'); assert.equal(belt.battery, null); assert.equal(belt.detailTone, 'muted');
  device.online = true; device.featureStates.hooks = { ...feature, verified: false };
  assert.equal(personEquipmentMonitor(db, { id: 'P1' })[1].detail, '暂无有效上报');
  device.active = false;
  assert.equal(personEquipmentMonitor(db, { id: 'P1' })[1].status, '未领用');
  device.active = true; device.source = 'DEMO';
  assert.equal(personEquipmentMonitor(db, { id: 'P1' })[1].status, '未领用');
});

test('24 小时趋势按发生时间分段，跨日和时区一致，已核验事件仍计入发生量', () => {
  const now = '2026-11-06T05:30:00Z';
  const events = [
    { occurredAt: '2026-11-05T05:30:00Z' }, // window start
    { occurredAt: '2026-11-05T17:30:00+08:00' }, // next bucket boundary
    { occurredAt: '2026-11-05 21:31:00', status: '已核验' },
    { date: '2026-11-06', time: '01:31:00' },
    { occurredAt: 'invalid', date: '2026-11-06', time: '05:31:00' },
    { occurredAt: now, date: '2000-01-01', time: '00:00:00' }, // primary time wins
    { occurredAt: '2026-11-06T01:31:00Z', status: '待认领' },
    { occurredAt: '2026-11-05T05:29:59Z' }, // too old
    { occurredAt: '2026-11-06T05:30:01Z' }, // future
  ];
  const before = structuredClone(events);
  const activity = eventActivity(events, now);
  assert.deepEqual(activity.buckets.map(item => item.count), [1, 1, 1, 1, 1, 2]);
  assert.deepEqual(activity.buckets.map(item => item.label), ['13:30', '17:30', '21:30', '01:30', '05:30', '09:30']);
  assert.equal(activity.buckets[2].range, '11-05 21:30 至 11-06 01:30');
  assert.equal(activity.undated, 0);
  assert.deepEqual(events, before);
});

test('缺失完整日期的事件不会伪装成今天的告警，空数据保持零发生量', () => {
  const now = Date.parse('2026-11-06T05:30:00Z');
  const activity = eventActivity([{ time: '10:00:00' }, { occurredAt: 'invalid' }, {}], now);
  assert.equal(activity.undated, 3);
  assert.deepEqual(activity.buckets.map(item => item.count), [0, 0, 0, 0, 0, 0]);
  assert.deepEqual(eventActivity([], now), { buckets: activity.buckets, undated: 0 });
});
