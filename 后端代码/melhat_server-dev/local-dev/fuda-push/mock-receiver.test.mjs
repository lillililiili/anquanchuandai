import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, createHmac, randomUUID } from 'node:crypto';
import { createReceiver } from './mock-receiver.mjs';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import fs from 'node:fs';
import { syncBuiltinESMExports } from 'node:module';

const secret = Buffer.alloc(32, 7), appId = 'local-push-test';
async function fixture(t, options = {}) {
  const instance = createReceiver({ appId, secretBase64: secret.toString('base64'), ...options });
  await new Promise(done => instance.server.listen(0, '127.0.0.1', done));
  t.after(() => new Promise(done => { instance.server.close(done); instance.server.closeAllConnections(); }));
  return { ...instance, url: `http://127.0.0.1:${instance.server.address().port}/receive` };
}
function request(eventId, nonce = randomUUID()) {
  const body = JSON.stringify({ schemaVersion: '1.0', eventId, eventType: 'STATUS', data: { deviceId: 'synthetic-helmet', onlineStatus: 'ONLINE' } });
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = createHmac('sha256', secret).update(['POST', '/receive', appId, timestamp, nonce, createHash('sha256').update(body).digest('hex')].join('\n')).digest('hex');
  return { method: 'POST', body, headers: { 'Content-Type': 'application/json', 'X-App-Id': appId, 'X-Timestamp': timestamp, 'X-Nonce': nonce, 'X-Signature': signature } };
}
test('new nonce retries are acknowledged once while replayed nonce is rejected', async t => {
  const r = await fixture(t), first = request('FP-test');
  assert.equal((await fetch(r.url, first)).status, 200);
  assert.equal((await fetch(r.url, first)).status, 409);
  assert.deepEqual(await (await fetch(r.url, request('FP-test'))).json(), { code: 0 });
  assert.equal(r.events.size, 1);
});
test('lost acknowledgement after save can be safely retried', async t => {
  const r = await fixture(t, { dropFirstResponse: true });
  await assert.rejects(fetch(r.url, request('FP-response-lost')));
  assert.equal(r.events.size, 1);
  assert.equal((await fetch(r.url, request('FP-response-lost'))).status, 200);
  assert.equal(r.events.size, 1);
});
test('tampered bytes are rejected before saving', async t => {
  const r = await fixture(t), req = request('FP-tampered'); req.body += ' ';
  assert.equal((await fetch(r.url, req)).status, 401); assert.equal(r.events.size, 0);
});

test('saved events survive restart and retries do not append duplicate rows', async t => {
  const folder = await mkdtemp(join(tmpdir(), 'fuda-receiver-'));
  t.after(() => rm(folder, { recursive: true, force: true }));
  const storageFile = join(folder, 'events.jsonl');
  const first = await fixture(t, { storageFile });
  assert.equal((await fetch(first.url, request('FP-durable'))).status, 200);
  const saved = await readFile(storageFile, 'utf8');
  assert.equal(saved.trim().split('\n').length, 1);
  const next = await fixture(t, { storageFile });
  assert.equal(next.events.size, 1);
  assert.equal((await fetch(next.url, request('FP-durable'))).status, 200);
  assert.equal(await readFile(storageFile, 'utf8'), saved);
  assert.ok(next.events.get('FP-durable').receivedAt);
});

test('corrupt receiver history fails visibly instead of silently losing deduplication', async t => {
  const folder = await mkdtemp(join(tmpdir(), 'fuda-receiver-'));
  t.after(() => rm(folder, { recursive: true, force: true }));
  const storageFile = join(folder, 'events.jsonl');
  await writeFile(storageFile, '{broken\n');
  assert.throws(() => createReceiver({ appId, secretBase64: secret.toString('base64'), storageFile }), /history/i);
});

test('simulator can serve a local inspection route without weakening receive signature checks', async t => {
  const r = await fixture(t, { handleOther(req, res) { res.end('inspection'); } });
  assert.equal(await (await fetch(r.url.replace('/receive', '/'))).text(), 'inspection');
  assert.equal((await fetch(r.url, { method: 'POST', body: '{}' })).status, 401);
});

test('failed storage flush rolls back its append before the sender retries', async t => {
  const folder = await mkdtemp(join(tmpdir(), 'fuda-receiver-'));
  t.after(() => rm(folder, { recursive: true, force: true }));
  const storageFile = join(folder, 'events.jsonl'), r = await fixture(t, { storageFile });
  const original = fs.fsyncSync; let fail = true;
  fs.fsyncSync = fd => { if (fail) { fail = false; throw Error('simulated flush failure'); } return original(fd); };
  syncBuiltinESMExports();
  try { assert.equal((await fetch(r.url, request('FP-storage-retry'))).status, 503); }
  finally { fs.fsyncSync = original; syncBuiltinESMExports(); }
  assert.equal((await fetch(r.url, request('FP-storage-retry'))).status, 200);
  assert.equal((await readFile(storageFile, 'utf8')).trim().split('\n').length, 1);
  assert.equal(createReceiver({ appId, secretBase64: secret.toString('base64'), storageFile }).events.size, 1);
});
