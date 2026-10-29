import { test } from 'node:test';
import assert from 'node:assert/strict';
import { deviceLocation } from '../../shared/device-location.mjs';

const now = Date.parse('2026-10-21T06:00:00Z');
const report = {
  latitude: '35.4', longitude: '112.5', online: true,
  locationFreshness: 'CURRENT', locationReportedAt: '2026-10-21T05:59:50Z',
};

test('unassigned received positions remain visible without implying GPS precision', () => {
  const view = deviceLocation({ ...report, relation: 'UNASSIGNED' }, now);
  assert.equal(view.position, '纬度 35.400000，经度 112.500000');
  assert.equal(view.status, '近期上报');
  assert.equal(view.reportedAt, '2026-10-21T05:59:50.000Z');
});

test('missing, invalid and zero-pair coordinates never become a displayed position', () => {
  for (const patch of [
    { latitude: null }, { latitude: '' }, { latitude: false },
    { longitude: 'NaN' }, { latitude: 91 }, { longitude: -181 },
    { latitude: 0, longitude: 0 },
  ]) {
    assert.deepEqual(deviceLocation({ ...report, ...patch }, now), {
      position: '未收到有效位置', reportedAt: null, status: '未收到有效位置',
    });
  }
  assert.match(deviceLocation({ ...report, latitude: 0 }, now).position, /纬度 0\.000000/);
});

test('expired, offline or unverified reports retain coordinates and are labeled historical', () => {
  for (const patch of [
    { locationFreshness: 'STALE' }, { online: false },
    { locationReportedAt: '2026-10-21T05:00:00Z' },
    { locationReportedAt: null }, { locationReportedAt: '2026-10-21T06:01:00Z' },
    { locationFreshness: 'UNKNOWN' },
  ]) {
    const view = deviceLocation({ ...report, ...patch }, now);
    assert.match(view.position, /纬度 35\.400000/);
    assert.match(view.status, /^最后上报/);
  }
});
