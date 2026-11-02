import test from 'node:test';
import assert from 'node:assert/strict';
import dgram from 'node:dgram';
import net from 'node:net';
import { once } from 'node:events';
import { mkdtemp, readFile, writeFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { execFile } from 'node:child_process';
import { createCapture } from './rtp-receiver.mjs';

const SSRC = 123456789;
const run = promisify(execFile);
function rtp(sequence, payload, options = {}) {
  const header = Buffer.alloc(12);
  header[0] = 0x80;
  header[1] = options.pt ?? 96;
  header.writeUInt16BE(sequence, 2);
  header.writeUInt32BE(options.ssrc ?? SSRC, 8);
  return Buffer.concat([header, Buffer.from(payload)]);
}
function frame(packet) {
  const header = Buffer.alloc(2);
  header.writeUInt16BE(packet.length);
  return Buffer.concat([header, packet]);
}
async function eventually(check) {
  const deadline = Date.now() + 3000;
  while (!check()) {
    assert.ok(Date.now() < deadline, 'receiver did not reach expected state');
    await new Promise(resolve => setTimeout(resolve, 10));
  }
}
async function fixture(t, options = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'fuda-capture-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const capture = await createCapture({ directory, id: 'capture-1', ssrc: SSRC, ...options });
  t.after(() => capture.close());
  return { directory, capture };
}
async function udp(t) {
  const socket = dgram.createSocket('udp4');
  socket.bind(0, '127.0.0.1');
  await once(socket, 'listening');
  t.after(() => socket.close());
  return (packet, port) => new Promise((resolve, reject) => socket.send(packet, port, '127.0.0.1', error => error ? reject(error) : resolve()));
}

test('UDP captures only ordered RTP payload and persists safe history on idempotent close', async t => {
  const { directory, capture } = await fixture(t);
  const send = await udp(t);
  for (const packet of [rtp(65534, 'A'), rtp(0, 'B'), rtp(0, 'duplicate'), rtp(65535, 'late'), rtp(1, 'C')]) {
    await send(packet, capture.port);
  }
  await eventually(() => capture.snapshot().packets === 3);
  await Promise.all([capture.close(), capture.close()]);
  assert.equal(await readFile(join(directory, 'capture-1.ps'), 'utf8'), 'ABC');
  const snapshot = capture.snapshot();
  assert.equal(snapshot.packets, 3);
  assert.equal(snapshot.bytes, 3);
  assert.equal(snapshot.lostPackets, 1);
  assert.equal(snapshot.invalidPackets, 0);
  assert.equal(snapshot.state, 'captured');
  assert.match(snapshot.error, /ffmpeg/i);
  assert.equal(snapshot.psFile, 'capture-1.ps');
  assert.equal(snapshot.mp4File, null);
  assert.ok(snapshot.endedAt);
  assert.deepEqual(JSON.parse(await readFile(join(directory, 'capture-1.json'), 'utf8')), snapshot);
  assert.deepEqual(Object.keys(snapshot).sort(), ['id', 'transport', 'port', 'packets', 'bytes', 'lostPackets', 'invalidPackets', 'state', 'startedAt', 'endedAt', 'psFile', 'mp4File', 'error'].sort());
});

test('validates RTP version, PT, SSRC, CSRC, extension and padding before payload writes', async t => {
  const { directory, capture } = await fixture(t);
  const send = await udp(t);
  const badVersion = rtp(1, 'bad'); badVersion[0] = 0x40;
  const shortCsrc = rtp(1, 'x'); shortCsrc[0] = 0x82;
  const shortExtension = rtp(1, 'x'); shortExtension[0] = 0x90;
  const longExtension = rtp(1, Buffer.from([0, 0, 0, 2, 0])); longExtension[0] = 0x90;
  const zeroPadding = rtp(1, Buffer.from([0])); zeroPadding[0] = 0xa0;
  const longPadding = rtp(1, Buffer.from([9])); longPadding[0] = 0xa0;
  const bad = [Buffer.alloc(4), badVersion, shortCsrc, shortExtension, longExtension, zeroPadding, longPadding, rtp(1, 'bad', { pt: 97 }), rtp(1, 'bad', { ssrc: 9 })];
  for (const packet of bad) await send(packet, capture.port);
  const good = rtp(2, Buffer.from([0, 0, 0, 1, 0x12, 0x34, 0, 1, 1, 2, 3, 4, 0x50, 0x53, 0, 2]));
  good[0] = 0xb1; // one CSRC, one extension word and two padding octets
  good[1] |= 0x80; // marker is independent of payload type
  await send(good, capture.port);
  await eventually(() => capture.snapshot().invalidPackets === bad.length && capture.snapshot().packets === 1);
  await capture.close();
  assert.equal(await readFile(join(directory, 'capture-1.ps'), 'utf8'), 'PS');
});

test('TCP passive receiver handles split RFC4571 frames and rejects concurrent clients', async t => {
  const { directory, capture } = await fixture(t, { transport: 'TCP' });
  const client = net.connect(capture.port, '127.0.0.1');
  t.after(() => client.destroy());
  await once(client, 'connect');
  const second = net.connect(capture.port, '127.0.0.1');
  second.on('error', () => {});
  const rejected = once(second, 'close');
  t.after(() => second.destroy());
  await rejected;
  const frames = Buffer.concat([Buffer.from([0, 0]), frame(rtp(1, 'first')), frame(rtp(2, 'second'))]);
  client.write(frames.subarray(0, 3));
  await new Promise(resolve => setTimeout(resolve, 15));
  client.write(frames.subarray(3, 9));
  await new Promise(resolve => setTimeout(resolve, 15));
  client.write(frames.subarray(9));
  await eventually(() => capture.snapshot().packets === 2);
  await capture.close();
  assert.equal(await readFile(join(directory, 'capture-1.ps'), 'utf8'), 'firstsecond');
});

test('unsafe identifiers and invalid configuration cannot create files', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'fuda-config-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  for (const options of [{ id: '../escape' }, { id: 'x/y' }, { id: 'a'.repeat(81) }, { ssrc: -1 }, { ssrc: '123x' }, { transport: 'SCTP' }, { port: 65536 }]) {
    await assert.rejects(createCapture({ directory, id: 'safe', ssrc: SSRC, ...options }));
  }
  assert.deepEqual(await readdir(directory), []);
});

test('existing capture files are never overwritten', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'fuda-existing-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  for (const ext of ['ps', 'mp4', 'json']) {
    await writeFile(join(directory, `existing-${ext}.${ext}`), 'keep');
    await assert.rejects(createCapture({ directory, id: `existing-${ext}`, ssrc: SSRC }));
    assert.equal(await readFile(join(directory, `existing-${ext}.${ext}`), 'utf8'), 'keep');
  }
  assert.deepEqual((await readdir(directory)).sort(), ['existing-json.json', 'existing-mp4.mp4', 'existing-ps.ps']);
});

test('bind errors release capture reservation and preserve existing listener', async t => {
  const { directory, capture } = await fixture(t);
  await assert.rejects(createCapture({ directory, id: 'bind-failed', ssrc: SSRC, port: capture.port }), /EADDRINUSE/);
  assert.equal((await readdir(directory)).some(name => name.startsWith('bind-failed')), false);
  const retry = await createCapture({ directory, id: 'bind-failed', ssrc: SSRC });
  await retry.close();
});

test('missing FFmpeg executable is handled, keeps PS and records a safe error', async t => {
  const { directory, capture } = await fixture(t, { ffmpegPath: join(tmpdir(), 'absent-ffmpeg-123.exe') });
  const send = await udp(t);
  await send(rtp(1, 'PS'), capture.port);
  await eventually(() => capture.snapshot().packets === 1);
  await capture.close();
  assert.equal(capture.snapshot().state, 'error');
  assert.match(capture.snapshot().error, /ffmpeg/i);
  assert.ok(!capture.snapshot().error.includes(tmpdir()));
  assert.equal(await readFile(join(directory, 'capture-1.ps'), 'utf8'), 'PS');
  assert.equal(JSON.parse(await readFile(join(directory, 'capture-1.json'), 'utf8')).state, 'error');
});

test('duration limit stops reception and calls onLimit once even if callback rejects', async t => {
  const originalSetTimeout = globalThis.setTimeout;
  let expire;
  t.mock.method(globalThis, 'setTimeout', (callback, milliseconds, ...args) => {
    if (milliseconds === 300000) expire = callback;
    return originalSetTimeout(callback, milliseconds, ...args);
  });
  const reasons = [];
  const { directory, capture } = await fixture(t, { onLimit: async reason => { reasons.push(reason); throw Error('callback failure'); } });
  assert.equal(typeof expire, 'function');
  expire();
  expire();
  await capture.close();
  assert.deepEqual(reasons, ['duration-limit']);
  assert.match(capture.snapshot().error, /duration-limit/);
  assert.equal(JSON.parse(await readFile(join(directory, 'capture-1.json'), 'utf8')).state, 'captured');
});

test('four-capture concurrency ceiling releases a slot after close', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'fuda-concurrency-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const captures = [];
  t.after(async () => { for (const capture of captures) await capture.close(); });
  for (let index = 0; index < 4; index++) captures.push(await createCapture({ directory, id: `concurrent-${index}`, ssrc: SSRC }));
  await assert.rejects(createCapture({ directory, id: 'too-many', ssrc: SSRC }), /four/i);
  await captures[0].close();
  const replacement = await createCapture({ directory, id: 'replacement', ssrc: SSRC });
  captures.push(replacement);
  await replacement.close();
});

test('TCP truncated framing is counted invalid and a later sender can reconnect', async t => {
  const { directory, capture } = await fixture(t, { transport: 'TCP' });
  const first = net.connect(capture.port, '127.0.0.1');
  t.after(() => first.destroy());
  await once(first, 'connect');
  first.end(Buffer.from([0, 24, 0x80]));
  await eventually(() => capture.snapshot().invalidPackets === 1);
  const second = net.connect(capture.port, '127.0.0.1');
  t.after(() => second.destroy());
  await once(second, 'connect');
  second.write(frame(rtp(1, 'reconnected')));
  await eventually(() => capture.snapshot().packets === 1);
  await capture.close();
  assert.equal(await readFile(join(directory, 'capture-1.ps'), 'utf8'), 'reconnected');
});

test('optional FFmpeg capture converts PS audio to AAC while preserving video', { skip: !process.env.FFMPEG_PATH }, async t => {
  const { directory, capture } = await fixture(t, { ffmpegPath: process.env.FFMPEG_PATH });
  const source = join(directory, 'source.ps');
  await run(process.env.FFMPEG_PATH, ['-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'color=c=blue:s=160x120:r=10', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100', '-t', '0.8', '-c:v', 'libx264', '-c:a', 'mp2', '-f', 'mpeg', source]);
  const bytes = await readFile(source);
  const send = await udp(t);
  let seq = 0;
  for (let offset = 0; offset < bytes.length; offset += 1200) await send(rtp(seq++, bytes.subarray(offset, offset + 1200)), capture.port);
  await eventually(() => capture.snapshot().packets === seq);
  await capture.close();
  assert.equal(capture.snapshot().state, 'ready', capture.snapshot().error);
  assert.equal(capture.snapshot().mp4File, 'capture-1.mp4');
  const { stderr } = await run(process.env.FFMPEG_PATH, ['-hide_banner', '-i', join(directory, capture.snapshot().mp4File), '-f', 'null', '-']);
  assert.match(stderr, /Video: h264/);
  assert.match(stderr, /Audio: aac/);
});
