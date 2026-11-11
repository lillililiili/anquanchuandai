import test from 'node:test';
import assert from 'node:assert/strict';
import { serverClock, serverNow, syncServerTime, resetServerClock, createServerClock } from '../../shared/server-clock.mjs';
import { authFetch, clearAuth, saveAuth } from '../src/lib/auth.js';
import { hasCurrentLocation, isCurrentDevice, projectDevice } from '../src/lib/device-telemetry.js';
import { mapLocation } from '../src/lib/location.js';
import { deviceLocation } from '../../shared/device-location.mjs';
import { createStore, seed } from '../src/mock/data.js';

const second = Date.parse('2026-11-05T09:00:00Z');
const dateHeader = new Date(second).toUTCString();
const response = (patch = {}) => ({ status: 200, ok: true, redirected: false,
  headers: new Headers({ Date: dateHeader }), url: 'https://wear.example.test/api/guardian/v1/snapshot', ...patch });
const direct = (patch = {}) => ({ source: 'DIRECT_HELMET', type: 'H', active: true, online: true,
  freshness: 'CURRENT', sourceTime: new Date(second + 500).toISOString(),
  longitude: 121.4, latitude: 31.2, coordinateSystem: 'GCJ02', locationQuality: 'valid',
  locationFreshness: 'CURRENT', locationReportedAt: new Date(second + 500).toISOString(), ...patch });

async function withBrowser(run) {
  const original = { storage: globalThis.sessionStorage, fetch: globalThis.fetch, window: globalThis.window, now: Date.now };
  const values = new Map();
  globalThis.sessionStorage = { getItem: key => values.get(key) ?? null, setItem: (key, value) => values.set(key, value), removeItem: key => values.delete(key) };
  globalThis.window = { location: { origin: 'https://wear.example.test', hash: '#/statistics' } };
  try { saveAuth('test-current-session', 'test-account'); await run(values); }
  finally { resetServerClock(); Date.now = original.now; globalThis.sessionStorage = original.storage; globalThis.fetch = original.fetch; globalThis.window = original.window; }
}

test('a valid snapshot corrects fast or slow client clocks for equipment counts and map locations', async () => {
  await withBrowser(async () => {
    globalThis.fetch = async () => response();
    for (const skew of [-3000, 3600000]) {
      resetServerClock(); Date.now = () => second + skew;
      await authFetch('/api/guardian/v1/snapshot');
      assert.equal(serverClock.synchronized, true);
      assert.equal(projectDevice(direct()).online, true);
      assert.equal(hasCurrentLocation(direct()), true);
      assert.deepEqual(mapLocation(direct(), { current: true }), [121.4, 31.2]);
      assert.equal(deviceLocation(direct()).status, '近期上报');
      const state = seed();
      const helmet = state.devices.find(d => d.id === 'RL-H001');
      const belt = state.devices.find(d => d.id === 'RL-B001');
      Object.assign(helmet, direct());
      Object.assign(belt, direct({ source: 'DIRECT_BELT', type: 'B' }));
      const db = createStore(null); db.replaceRemote(state);
      assert.equal(db.stats().byType.H.online, 1);
      assert.equal(db.stats().byType.B.online, 1);
      assert.equal(db.state.devices.find(d => d.id === helmet.id).sourceTime, helmet.sourceTime, 'raw evidence remains unchanged');
    }
  });
});

test('calibration retains five-minute expiry, genuine offline, unknown, and future-time rejection', () => {
  const clock = createServerClock({ monotonicNow: () => 0 });
  clock.syncFromHttpDate(dateHeader);
  const now = clock.now();
  assert.equal(isCurrentDevice(direct({ sourceTime: new Date(now - 300000).toISOString() }), now), true);
  for (const patch of [
    { sourceTime: new Date(now - 300001).toISOString() },
    { sourceTime: new Date(now + 60000).toISOString() },
    { sourceTime: null }, { freshness: 'STALE' }, { freshness: 'UNKNOWN' },
  ]) assert.equal(projectDevice(direct(patch), now).online, null);
  assert.equal(projectDevice(direct({ online: false }), now).online, false);
  assert.equal(projectDevice(direct({ online: null }), now).online, null);
  assert.equal(hasCurrentLocation(direct({ locationReportedAt: new Date(now - 300001).toISOString() }), now), false);
});

test('only successful same-origin guardian API responses calibrate the current session', async () => {
  await withBrowser(async () => {
    const cases = [
      ['https://other.example/api/guardian/v1/snapshot', response()],
      ['/assets/data.json', response()],
      ['/api/guardian/v1/snapshot', response({ ok: false, status: 503 })],
      ['/api/guardian/v1/snapshot', response({ redirected: true })],
      ['/api/guardian/v1/snapshot', response({ url: 'https://other.example/api/guardian/v1/snapshot' })],
      ['/api/guardian/v1/snapshot', response({ headers: new Headers() })],
    ];
    for (const [url, reply] of cases) {
      resetServerClock(); globalThis.fetch = async () => reply;
      await authFetch(url);
      assert.equal(serverClock.synchronized, false, url);
    }
    globalThis.fetch = async () => response();
    await authFetch('/api/guardian/v1/snapshot');
    assert.equal(serverClock.synchronized, true);
    clearAuth();
    assert.equal(serverClock.synchronized, false);
  });
});

test('a successful late response from an old login cannot calibrate a new login', async () => {
  await withBrowser(async () => {
    let finish;
    globalThis.fetch = () => new Promise(resolve => { finish = resolve; });
    const pending = authFetch('/api/guardian/v1/snapshot');
    saveAuth('test-next-session', 'next-account');
    finish(response()); await pending;
    assert.equal(serverClock.synchronized, false);
  });
});

test('once calibrated, changing the system clock cannot alter live device projection', () => {
  const original = Date.now;
  try {
    resetServerClock(); syncServerTime(dateHeader);
    const calibrated = serverNow();
    Date.now = () => second + 86400000;
    assert.equal(projectDevice(direct()).online, true);
    Date.now = () => second - 86400000;
    assert.equal(projectDevice(direct()).online, true);
    assert.ok(serverNow() >= calibrated);
  } finally { Date.now = original; resetServerClock(); }
});
