import test from 'node:test';
import assert from 'node:assert/strict';
import { createEventApi } from '../src/lib/guardian-events.js';

test('event writes use shared endpoints and preserve the form version', async () => {
  let request, refreshed = 0;
  const api = createEventApi({ current: () => ({ version: 8 }), uuid: () => 'request-001', refresh: async () => refreshed++, fetchImpl: async (url, options) => { request = { url, body: JSON.parse(options.body) }; return { ok: true, json: async () => ({ id: "SOS-1", version: 9 }) }; } });
  await api.command('SOS-1', 'verification', { expectedVersion: 3, situation: '现场确认', conclusion: '需现场处理' });
  assert.equal(request.url, '/api/guardian/v1/events/SOS-1/verification');
  assert.equal(request.body.expectedVersion, 3);
  assert.equal(request.body.requestId, 'request-001');
  assert.equal(refreshed, 1);
});

test('network retry reuses the same request ID and double click sends once', async () => {
  let calls = 0, ids = [], counter = 0, resolve;
  const api = createEventApi({ current: () => ({ version: 1 }), uuid: () => `request-${++counter}`, refresh: async () => {}, fetchImpl: async (_url, options) => {
    calls++; ids.push(JSON.parse(options.body).requestId);
    if (calls === 1) throw Error('断网');
    await new Promise(r => { resolve = r; });
    return { ok: true, json: async () => ({ id: "SOS-1", version: 2 }) };
  } });
  await assert.rejects(api.command('SOS-1', 'claim'), /断网/);
  const first = api.command('SOS-1', 'claim'), second = api.command('SOS-1', 'claim');
  resolve(); await Promise.all([first, second]);
  assert.equal(calls, 2); assert.deepEqual(ids, ['request-1', 'request-1']);
});

test('conflict refreshes the event and never retries or simulates success', async () => {
  let calls = 0, refresh = 0;
  const api = createEventApi({ current: () => ({ version: 1 }), uuid: () => 'request-001', refresh: async () => refresh++, fetchImpl: async () => { calls++; return { ok: false, status: 409, json: async () => ({ message: '事件已更新' }) }; } });
  await assert.rejects(api.command('SOS-1', 'assist-end'), /事件已更新/);
  assert.equal(calls, 1); assert.equal(refresh, 1);
});

test('different SOS IDs never share a request or assistance operation', async () => {
  const urls = [];
  const api = createEventApi({ current: () => ({ version: 1 }), uuid: () => 'request-001', refresh: async () => {}, fetchImpl: async url => { urls.push(url); return { ok: true, json: async () => ({ id: url.split("/").at(-2), version: 2 }) }; } });
  await Promise.all([api.command('SOS-1', 'assist-end'), api.command('SOS-2', 'assist-join')]);
  assert.deepEqual(urls, ['/api/guardian/v1/events/SOS-1/assist-end', '/api/guardian/v1/events/SOS-2/assist-join']);
});

test('verification keeps the pending request on HTTP-200 errors and malformed acknowledgments', async () => {
  const ids = [], replies = [{ code: 500, msg: '依赖不可用' }, { id: 'SOS-2', version: 2 }, { id: 'SOS-1', version: 2 }];
  let refreshes = 0, counter = 0;
  const api = createEventApi({ current: () => ({ version: 1 }), uuid: () => `request-${++counter}`,
    refresh: async () => { refreshes++; return false; },
    fetchImpl: async (_url, options) => {
      ids.push(JSON.parse(options.body).requestId);
      return new Response(JSON.stringify(replies.shift()));
    },
  });
  const submit = () => api.command('SOS-1', 'verification', { conclusion: '需现场处理' });
  await assert.rejects(submit(), /依赖不可用/);
  await assert.rejects(submit(), /响应无效/);
  assert.equal(refreshes, 0);
  assert.deepEqual(await submit(), { id: 'SOS-1', version: 2 });
  assert.equal(refreshes, 1);
  assert.deepEqual(ids, ['request-1', 'request-1', 'request-1']);
});
