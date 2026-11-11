import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { allowed, createWearGateway } from '../gateway.mjs';

test('PC routes are opt-in, exact, and never allow state replacement or maintenance', () => {
  for (const [method, route] of [
    ['GET', '/api/guardian/v1/snapshot'], ['GET', '/api/guardian/v1/business-config'],
    ['POST', '/api/guardian/v1/business/commands'],
    ['GET', '/api/guardian/v1/voice-messages/v1/playback'],
    ['POST', '/api/admin/v1/login'], ['POST', '/api/admin/v1/logout'],
    ['GET', '/api/admin/v1/state'], ['POST', '/api/admin/v1/query'], ['POST', '/api/admin/v1/execute'],
    ['PATCH', '/api/admin/v1/business-config'], ['POST', '/api/admin/v1/platform/helmets/sync'],
    ['GET', '/api/admin/v1/works'], ['GET', '/api/admin/v1/works/options'],
    ['POST', '/api/admin/v1/works'], ['PATCH', '/api/admin/v1/works/w1'],
    ['POST', '/api/admin/v1/works/w1/actions'],
  ]) {
    assert.equal(allowed(method, route), false, route);
    assert.equal(allowed(method, route, true), true, route);
  }
  for (const [method, route] of [
    ['PUT', '/api/admin/v1/state'], ['PUT', '/api/guardian/v1/snapshot'],
    ['DELETE', '/api/admin/v1/works/w1'], ['GET', '/api/admin/v1/query'],
    ['GET', '/api/admin/v1/accounts'], ['POST', '/api/admin/v1/maintenance/reset'],
    ['GET', '/api/admin/v1/works/w1/extra'], ['GET', '/actuator/env'],
    ['POST', '/system/user/add'], ['POST', '/api/index.php'],
  ]) assert.equal(allowed(method, route, true), false, `${method} ${route}`);
});

test('PC proxy enforces session presence, preserves backend auth/scope errors and limits login attempts', async t => {
  const seen = [];
  const backend = http.createServer(async (req, res) => {
    const chunks = []; for await (const chunk of req) chunks.push(chunk);
    seen.push({ url: req.url, method: req.method, headers: req.headers, body: Buffer.concat(chunks).toString() });
    const denied = req.url === '/api/admin/v1/login' ? 401 : 403;
    res.writeHead(denied, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: denied === 401 ? 'INVALID_CREDENTIALS' : 'SITE_FORBIDDEN' }));
  });
  backend.listen(0, '127.0.0.1'); await once(backend, 'listening');
  const gateway = createWearGateway({ testOnly: true, pcClients: true, upstreamOrigin: `http://127.0.0.1:${backend.address().port}` });
  gateway.listen(0, '127.0.0.1'); await once(gateway, 'listening');
  t.after(async () => { await new Promise(r => gateway.close(r)); await new Promise(r => backend.close(r)); });
  const origin = `http://127.0.0.1:${gateway.address().port}`;
  for (const route of ['/api/guardian/v1/snapshot', '/api/admin/v1/state']) {
    assert.equal((await fetch(origin + route)).status, 401);
  }
  assert.equal((await fetch(origin + '/api/admin/v1/execute', { method: 'POST', body: '{}' })).status, 401);
  assert.equal(seen.length, 0);
  const headers = { 'X-Wearable-Token': 't'.repeat(43), 'Content-Type': 'application/json', Cookie: 'private', Authorization: 'Bearer private' };
  const body = JSON.stringify({ kind: 'devices', accountId: 'wrong-user', input: { siteId: 'other-site' } });
  const response = await fetch(origin + '/api/admin/v1/query', { method: 'POST', headers, body });
  assert.equal(response.status, 403);
  assert.deepEqual(await response.json(), { error: 'SITE_FORBIDDEN' });
  assert.equal(seen[0].body, body);
  assert.equal(seen[0].headers['x-wearable-token'], headers['X-Wearable-Token']);
  assert.equal(seen[0].headers.cookie, undefined);
  assert.equal(seen[0].headers.authorization, undefined);
  assert.equal((await fetch(origin + '/api/admin/v1/works?siteId=s1&keyword=hat&date=2026-11-05', { headers })).status, 403);
  assert.equal((await fetch(origin + '/api/admin/v1/works?siteId=s1&siteId=s2', { headers })).status, 400);
  assert.equal((await fetch(origin + '/api/guardian/v1/mobile/home?keyword=hat', { headers })).status, 400);
  assert.equal((await fetch(origin + '/api/admin/v1/state', { method: 'PUT', headers, body: '{}' })).status, 404);
  assert.equal((await fetch(origin + '/api/admin/v1/execute', { method: 'POST', headers, body: 'x'.repeat(128 * 1024 + 1) })).status, 413);
  for (let i = 0; i < 12; i++) assert.equal((await fetch(origin + '/api/admin/v1/login', { method: 'POST', body: '{}' })).status, 401);
  assert.equal((await fetch(origin + '/api/admin/v1/login', { method: 'POST', body: '{}' })).status, 429);
  assert.equal((await fetch(origin + '/api/guardian/v1/login', { method: 'POST', body: '{}' })).status, 429);
});
