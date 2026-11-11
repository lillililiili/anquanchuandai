import test from 'node:test';
import assert from 'node:assert/strict';
import { createServerClock } from './server-clock.mjs';

const serverSecond = Date.parse('2026-11-05T09:00:00Z');
const header = new Date(serverSecond).toUTCString();

test('HTTP Date calibrates ahead and behind wall clocks within its one-second precision', () => {
  for (const offset of [-7200000, -3000, 3000, 7200000]) {
    let elapsed = 10;
    const clock = createServerClock({ wallNow: () => serverSecond + offset, monotonicNow: () => elapsed });
    assert.equal(clock.now(), serverSecond + offset);
    assert.equal(clock.syncFromHttpDate(header, 0), true);
    assert.equal(clock.now(), serverSecond + 999);
    elapsed += 125;
    assert.equal(clock.now(), serverSecond + 1124);
  }
});

test('synchronized time advances monotonically when the local system clock jumps', () => {
  let elapsed = 0, wall = serverSecond;
  const clock = createServerClock({ wallNow: () => wall, monotonicNow: () => elapsed });
  clock.syncFromHttpDate(header);
  wall += 86400000; elapsed = 1000;
  assert.equal(clock.now(), serverSecond + 1999);
  wall -= 172800000; elapsed = 2000;
  assert.equal(clock.now(), serverSecond + 2999);
  clock.reset();
  assert.equal(clock.synchronized, false);
  assert.equal(clock.now(), wall);
});

test('missing and invalid Date headers preserve the existing authority or fallback', () => {
  let elapsed = 0;
  const clock = createServerClock({ wallNow: () => 42, monotonicNow: () => elapsed });
  for (const value of [null, undefined, '', 'invalid date']) assert.equal(clock.syncFromHttpDate(value), false);
  assert.equal(clock.synchronized, false);
  assert.equal(clock.now(), 42);
  clock.syncFromHttpDate(header);
  elapsed = 5000;
  assert.equal(clock.syncFromHttpDate(null), false);
  assert.equal(clock.now(), serverSecond + 5999);
});

test('late responses from older requests cannot change a newer time anchor', () => {
  let elapsed = 100;
  const clock = createServerClock({ monotonicNow: () => elapsed });
  clock.syncFromHttpDate(header, 90);
  elapsed = 200;
  assert.equal(clock.syncFromHttpDate(new Date(serverSecond + 60000).toUTCString(), 80), false);
  assert.equal(clock.now(), serverSecond + 1099);
  assert.equal(clock.syncFromHttpDate(header, 150), true);
  assert.equal(clock.now(), serverSecond + 1099, 'same-second sampling must not move time backwards');
});

test('invalid request timestamps cannot overwrite synchronization', () => {
  const clock = createServerClock({ monotonicNow: () => 100 });
  for (const started of [NaN, Infinity, 101]) assert.equal(clock.syncFromHttpDate(header, started), false);
  assert.equal(clock.synchronized, false);
});
