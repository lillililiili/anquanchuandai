import test from 'node:test';
import assert from 'node:assert/strict';
import { formatBeijingDateTime } from '../src/lib/date-time.js';

test('binding timestamps display Beijing time to seconds, including backend nanoseconds', () => {
  assert.equal(formatBeijingDateTime('2026-10-27T07:51:35.508036103Z'), '2026-10-27 15:51:35');
  assert.equal(formatBeijingDateTime('2026-09-15T00:00:00.000Z'), '2026-09-15 08:00:00');
  assert.equal(formatBeijingDateTime('2026-10-26T16:00:00Z'), '2026-10-27 00:00:00');
  assert.equal(formatBeijingDateTime('2026-12-31T23:59:59Z'), '2027-01-01 07:59:59');
});

test('explicit offsets refer to the same instant', () => {
  for (const value of ['2026-10-27T15:51:35+08:00', '2026-10-27T15:51:35+0800', '2026-10-27T03:51:35-04:00']) {
    assert.equal(formatBeijingDateTime(value), '2026-10-27 15:51:35');
  }
});

test('legacy local timestamps keep their Beijing wall-clock time', () => {
  assert.equal(formatBeijingDateTime('2026-09-14 08:12:30'), '2026-09-14 08:12:30');
  assert.equal(formatBeijingDateTime('2026-09-14T08:12:30.123456789'), '2026-09-14 08:12:30');
  assert.equal(formatBeijingDateTime(' 2026-09-14 08:12 '), '2026-09-14 08:12:00');
});

test('missing or invalid timestamps do not show malformed dates', () => {
  for (const value of [null, undefined, '', ' ', 'invalid', '—', 0, {}, '2026-02-30T10:00:00Z', '2026-13-01T10:00:00Z', '2026-10-27T24:00:00Z', '2026-10-27T10:60:00Z', '2026-10-27T10:00:60Z', '2026-10-27T10:00:00+25:00']) {
    assert.equal(formatBeijingDateTime(value), '—', String(value));
  }
});
