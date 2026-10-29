import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createPrivacyLog, EVENT_REASONS } from '../diagnostics.mjs';

const BASENAME = 'belt-gateway-events.ndjson';
const TIME = '2026-10-21T06:24:34.586Z';
const record = (count, overrides = {}) => ({ time: TIME, event: 'http_request', reason: 'received', count, ...overrides });
function fixture(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'belt-private-log-test-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return { directory, file: path.join(directory, BASENAME) };
}
function read(file) {
  return fs.readFileSync(file, 'utf8').trim().split('\n').map(line => JSON.parse(line));
}

test('only the four allowlisted fields reach NDJSON; payload accessors are not invoked', t => {
  const { directory, file } = fixture(t);
  const observe = createPrivacyLog(directory);
  const input = record(1, { url: '/secret-token/wsBelt', device_id: 'private-id', error: new Error('private-message'), payload: { token: 'private-token' } });
  Object.defineProperty(input, 'headers', { get() { throw new Error('must not read headers'); } });
  Object.defineProperty(input, 'toJSON', { get() { throw new Error('must not invoke serializer'); } });
  observe(input);
  const connection = record(1, { event: 'transport_connection', reason: 'open' });
  observe(connection);
  assert.deepEqual(read(file), [record(1), connection]);
  assert.equal(fs.readFileSync(file, 'utf8').includes('private'), false);
  assert.equal(Object.isFrozen(EVENT_REASONS), true);
  assert.equal(Object.isFrozen(EVENT_REASONS.http_result), true);
});

test('unknown pairs, invalid types, inherited fields and getters are ignored without poisoning sink', t => {
  const { directory, file } = fixture(t);
  const observe = createPrivacyLog(directory);
  const invalid = [null, [], 'error', record(1, { event: 'secret-event' }), record(1, { reason: 'secret-error' }),
    record(1, { event: 'http_request', reason: 'ok' }), record(1, { event: 'toString' }),
    record(1, { time: 1 }), record(1, { time: '2026-02-30T06:24:34.586Z' }), record(1, { time: 'invalid' }),
    record(0), record(-1), record(0.5), record(Number.MAX_SAFE_INTEGER + 1), record('1'),
    Object.create(record(1)), new Proxy({}, { getOwnPropertyDescriptor() { throw new Error('secret-proxy-error'); } })];
  const accessor = record(1);
  Object.defineProperty(accessor, 'event', { get() { throw new Error('secret-getter-error'); } });
  invalid.push(accessor);
  for (const input of invalid) assert.doesNotThrow(() => observe(input));
  assert.equal(fs.existsSync(file), false);
  observe(record(2));
  assert.deepEqual(read(file), [record(2)]);
});

test('SOS diagnostic stages write only allowlisted enums and discard all additional payload fields', t => {
  const { directory, file } = fixture(t);
  const observe = createPrivacyLog(directory);
  const names = ['ws_action_received', 'ws_action_validated', 'ws_action_forwarded', 'ws_login_response',
    'ws_location_response', 'ws_sos_response', 'ws_sip_sos_response', 'ws_error_response', 'ws_response_invalid'];
  const expected = [];
  for (const event of names) {
    for (const reason of EVENT_REASONS[event]) {
      const safe = record(1, { event, reason });
      const input = { ...safe, act: 'private-act', cmd: 'private-cmd', device_id: 'private-device',
        url: 'ws://private-token.invalid/private-key', coordinates: 'private-coordinates',
        error: new Error('private-exception'), payload: { secret: 'private-secret' } };
      Object.defineProperty(input, 'raw', { get() { throw new Error('must not inspect raw response'); } });
      observe(input);
      expected.push(safe);
    }
    observe(record(1, { event, reason: 'private-unknown-action' }));
  }
  assert.deepEqual(read(file), expected);
  assert.equal(fs.readFileSync(file, 'utf8').includes('private'), false);
  assert.ok(expected.every(item => Object.keys(item).length === 4));
});

test('fixed-window cap drops excess events and preserves count gaps when the next window starts', t => {
  const { directory, file } = fixture(t);
  let now = 10000;
  t.mock.method(Date, 'now', () => now);
  const observe = createPrivacyLog(directory, { maxEventsPerSecond: 2 });
  for (let count = 1; count <= 5; count++) observe(record(count));
  now = 10999;
  observe(record(6));
  assert.deepEqual(read(file).map(item => item.count), [1, 2]);
  now = 11000;
  observe(record(7));
  assert.deepEqual(read(file).map(item => item.count), [1, 2, 7]);
});

test('rotation retains only the newest three files, each within its byte budget', t => {
  const { directory, file } = fixture(t);
  const bytesPerRecord = Buffer.byteLength(JSON.stringify(record(1)) + '\n');
  const observe = createPrivacyLog(directory, { maxBytes: bytesPerRecord * 2 });
  for (let count = 1; count <= 9; count++) observe(record(count));
  assert.deepEqual(fs.readdirSync(directory).sort(), [BASENAME, `${BASENAME}.1`, `${BASENAME}.2`]);
  assert.deepEqual(read(file).map(item => item.count), [9]);
  assert.deepEqual(read(`${file}.1`).map(item => item.count), [7, 8]);
  assert.deepEqual(read(`${file}.2`).map(item => item.count), [5, 6]);
  for (const name of fs.readdirSync(directory)) assert.ok(fs.statSync(path.join(directory, name)).size <= bytesPerRecord * 2);
});

test('single-file rotation and smaller configured bounds also constrain existing logs', t => {
  const { directory, file } = fixture(t);
  fs.writeFileSync(file, 'x'.repeat(1024));
  fs.writeFileSync(`${file}.1`, 'old');
  fs.writeFileSync(`${file}.2`, 'oldest');
  const observe = createPrivacyLog(directory, { maxBytes: 160, maxFiles: 1 });
  observe(record(1));
  observe(record(2));
  assert.deepEqual(fs.readdirSync(directory), [BASENAME]);
  assert.deepEqual(read(file), [record(2)]);
});

test('oversize records and options beyond hard ceilings never create a log', t => {
  const { directory, file } = fixture(t);
  for (const options of [{ maxBytes: 1 }, { maxBytes: 262145 }, { maxFiles: 4 }, { maxFiles: 0 }, { maxEventsPerSecond: 51 }]) {
    assert.doesNotThrow(() => createPrivacyLog(directory, options)(record(1)));
  }
  assert.equal(fs.existsSync(file), false);
});

test('a nonregular intended log path disables logging without altering it', t => {
  const { directory, file } = fixture(t);
  fs.mkdirSync(`${file}.1`);
  const observe = createPrivacyLog(directory);
  assert.doesNotThrow(() => observe(record(1)));
  assert.equal(fs.existsSync(file), false);
  assert.equal(fs.statSync(`${file}.1`).isDirectory(), true);
});

test('directory junctions/symlinks are rejected without writing through them', t => {
  const { directory } = fixture(t);
  const destination = path.join(directory, 'destination');
  const link = path.join(directory, 'linked');
  fs.mkdirSync(destination);
  fs.symlinkSync(destination, link, process.platform === 'win32' ? 'junction' : 'dir');
  const observe = createPrivacyLog(link);
  assert.doesNotThrow(() => observe(record(1)));
  assert.deepEqual(fs.readdirSync(destination), []);
});

test('an intended log symlink is rejected and its target remains unchanged', t => {
  const { directory, file } = fixture(t);
  const destination = path.join(directory, 'destination');
  fs.mkdirSync(destination);
  // A junction needs no elevated symlink privilege on Windows, and exercises
  // the same lstat rejection before the intended log path can be opened.
  fs.symlinkSync(destination, file, process.platform === 'win32' ? 'junction' : 'dir');
  const observe = createPrivacyLog(directory);
  assert.doesNotThrow(() => observe(record(1)));
  assert.equal(fs.lstatSync(file).isSymbolicLink(), true);
  assert.deepEqual(fs.readdirSync(destination), []);
});

test('an IO failure is swallowed and permanently disables this observer', t => {
  const { directory, file } = fixture(t);
  const observe = createPrivacyLog(directory);
  observe(record(1));
  fs.unlinkSync(file);
  fs.mkdirSync(file);
  assert.doesNotThrow(() => observe(record(2)));
  fs.rmdirSync(file);
  assert.doesNotThrow(() => observe(record(3)));
  assert.equal(fs.existsSync(file), false);
  assert.doesNotThrow(() => createPrivacyLog(path.join(directory, 'missing'))(record(4)));
});
