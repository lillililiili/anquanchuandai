import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createRouter, Inbox, validateConfig } from '../gateway.mjs';

const secret = 'test-only-manufacturer-secret-0001';
const downstreamSecret = 'test-only-wearable-secret-00000001';
const prefix = '/api/helmet/notify/';
async function listen(server) {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return `http://127.0.0.1:${server.address().port}`;
}
async function close(server) { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
async function fixture(t, { oldStatus = 200, newStatus = 200, routes = { NEW: 'wearable', HOLD: 'paused' }, inbox } = {}) {
  const requests = { old: [], wearable: [] };
  let status = newStatus;
  function endpoint(kind) {
    return http.createServer(async (request, response) => {
      const chunks = []; for await (const chunk of request) chunks.push(chunk);
      requests[kind].push({ path: request.url, body: Buffer.concat(chunks).toString(), headers: request.headers });
      response.writeHead(kind === 'old' ? oldStatus : status, { 'Content-Type': 'application/json' });
      response.end(kind === 'old' ? '{"code":200,"message":"original-result"}' : JSON.stringify({ code: status }));
    });
  }
  const old = endpoint('old'), newer = endpoint('wearable');
  const config = { version: 1, routes, legacyOrigin: await listen(old), wearableOrigin: await listen(newer), incomingSecret: secret, wearableSecret: downstreamSecret };
  let now = Date.now();
  const app = createRouter({ config, filename: ':memory:', inbox, testOnly: true, clock: () => now });
  const url = await listen(app.server);
  t.after(async () => { await close(app.server); await close(old); await close(newer); app.inbox?.close?.(); });
  return { ...app, requests, config, advance: delta => { now += delta; }, setNewStatus: value => { status = value; },
    post: (kind, payload, headers = {}) => fetch(url + prefix + kind, {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Helmet-Callback-Secret': secret, ...headers }, body: JSON.stringify(payload),
    }) };
}

test('explicit new SN is durable before ack and forwarded with stable authenticated identity', async t => {
  const f = await fixture(t);
  assert.equal((await f.post('deviceStatus', { helmetSn: 'NEW', power: '0' })).status, 200);
  assert.equal(f.requests.old.length, 0); assert.equal(f.requests.wearable.length, 0);
  assert.equal(f.inbox.summary().pending, 1);
  await f.pump();
  assert.equal(f.requests.wearable.length, 1);
  const sent = f.requests.wearable[0];
  assert.equal(sent.headers['x-helmet-callback-secret'], downstreamSecret);
  assert.match(sent.headers['x-split-ingress-id'], /^[a-f0-9-]{36}$/);
  assert.equal(JSON.parse(sent.body).power, '0');
  assert.equal(f.inbox.summary().pending, 0);
});

test('pausing an SN also holds its existing durable queue without blocking other devices', async t => {
  const f = await fixture(t, { routes: { HOLD: 'paused', NEW: 'wearable' } });
  const receivedAt = new Date().toISOString();
  f.inbox.add({ id:'persisted-before-pause',sn:'HOLD',kind:'sos',body:JSON.stringify({helmetSn:'HOLD',type:'sos'}),receivedAt,target:f.config.wearableOrigin,version:1 });
  assert.equal((await f.post('sos',{helmetSn:'NEW',type:'sos'})).status,200);
  await f.pump();await f.pump();
  assert.equal(f.requests.wearable.length,1);assert.equal(JSON.parse(f.requests.wearable[0].body).helmetSn,'NEW');
  assert.equal(f.requests.old.length,0);assert.equal(f.inbox.summary().pending,1);
  assert.equal(f.inbox.next(Date.now()).ingress_id,'persisted-before-pause');
});

test('legacy preserves original body/status and never joins asynchronous retry', async t => {
  const f = await fixture(t, { oldStatus: 503 });
  const payload = { helmetSn: 'OLD', type: 'sos' };
  const result = await f.post('sos', payload, { 'X-Split-Ingress-Id': 'untrusted-injected-value' });
  assert.equal(result.status, 503);
  assert.equal(await result.text(), '{"code":200,"message":"original-result"}');
  assert.equal(f.requests.old[0].body, JSON.stringify(payload));
  assert.equal(f.requests.old[0].headers['x-split-ingress-id'], undefined);
  await f.pump(); await f.pump();
  assert.equal(f.requests.old.length, 1); assert.equal(f.inbox.summary().total, 0);
});

test('paused and malformed routes cannot fall through to old platform', async t => {
  const f = await fixture(t);
  assert.equal((await f.post('gnss', { helmetSn: 'HOLD' })).status, 409);
  assert.equal((await f.post('gnss', { helmetSn: '../OLD' })).status, 400);
  assert.equal((await f.post('gnss?override=old', { helmetSn: 'NEW' })).status, 404);
  assert.equal((await f.post('gnss', { helmetSn: 'NEW' }, { 'X-Helmet-Callback-Secret': 'wrong' })).status, 401);
  assert.equal(f.requests.old.length, 0); assert.equal(f.inbox.summary().total, 0);
});

test('new outage retries same ingress in device order while legacy keeps working', async t => {
  const f = await fixture(t, { newStatus: 503 });
  await f.post('sosCall', { helmetSn: 'NEW' });
  await f.post('sosCallEnd', { helmetSn: 'NEW' });
  await f.pump(); await f.pump();
  assert.equal(f.requests.wearable.length, 1);
  const first = f.requests.wearable[0];
  assert.equal((await f.post('deviceStatus', { helmetSn: 'OLD', power: '42' })).status, 200);
  f.advance(4000); f.setNewStatus(200); await f.pump(); await f.pump();
  assert.equal(f.requests.wearable.length, 3);
  assert.equal(f.requests.wearable[1].headers['x-split-ingress-id'], first.headers['x-split-ingress-id']);
  assert.equal(f.requests.wearable[1].headers['x-split-received-at'], first.headers['x-split-received-at']);
  assert.ok(f.requests.wearable[2].path.endsWith('/sosCallEnd'));
  assert.equal(f.inbox.summary().pending, 0);
});

test('new persistence failure fails closed without changing legacy route', async t => {
  const inbox = { add() { throw Error('disk-full'); }, next() {}, close() {} };
  const f = await fixture(t, { inbox });
  assert.equal((await f.post('sosCall', { helmetSn: 'NEW' })).status, 503);
  assert.equal((await f.post('sosCall', { helmetSn: 'OLD' })).status, 200);
  assert.equal(f.requests.wearable.length, 0); assert.equal(f.requests.old.length, 1);
});

test('restart retains receipt target, route version and identity', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'split-router-'));
  try {
    const filename = path.join(dir, 'inbox.sqlite');
    const first = new Inbox(filename);
    first.add({ id: 'receipt-1', sn: 'NEW', kind: 'sosCall', body: '{"helmetSn":"NEW"}', receivedAt: '2026-11-16T00:00:00Z', target: 'https://original-wearable.example', version: 4 });
    first.close();
    const reopened = new Inbox(filename), row = reopened.next(Date.now());
    assert.equal(row.ingress_id, 'receipt-1'); assert.equal(row.route_version, 4);
    assert.equal(row.target, 'https://original-wearable.example'); reopened.close();
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('configuration rejects insecure origins and ambiguous SN destinations', () => {
  const base = { version: 1, routes: {}, incomingSecret: secret, wearableSecret: downstreamSecret, legacyOrigin: 'https://old.example/prod-api', wearableOrigin: 'https://new.example/split-callback' };
  assert.doesNotThrow(() => validateConfig(base));
  assert.doesNotThrow(() => validateConfig({ ...base, incomingSecret: 'existing-secret' }));
  assert.throws(() => validateConfig({ ...base, incomingSecret: '' }));
  assert.throws(() => validateConfig({ ...base, wearableSecret: 'too-short' }));
  assert.throws(() => validateConfig({ ...base, legacyOrigin: 'http://old.example' }));
  assert.throws(() => validateConfig({ ...base, routes: { NEW: ['wearable', 'old'] } }));
  assert.throws(() => validateConfig({ ...base, wearableOrigin: 'https://user:password@new.example' }));
});
