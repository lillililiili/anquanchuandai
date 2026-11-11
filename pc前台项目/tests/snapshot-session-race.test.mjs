import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { ref } from 'vue';
import { createStore } from '../src/mock/data.js';
import { fixtureState } from './fixtures/person-device-data.mjs';

const flush = async () => { for (let i = 0; i < 12; i++) await Promise.resolve(); };
function snapshot(actor) {
  const state = fixtureState('helmet');
  state.operator = { ...state.operator, id: actor, name: actor };
  state.calls = [];
  return state;
}

async function fixture() {
  const source = (await readFile(new URL('../src/mock/runtime.js', import.meta.url), 'utf8'))
    .replace(/^import\s+[\s\S]*?\s+from\s+['"][^'"]+['"];?\s*$/gm, '')
    .replace(/\bexport\s+(?=(?:async\s+)?(?:const|function))/g, '');
  const requests = [], authListeners = [];
  let token = 'old-token';
  const bindings = {
    ref, createStore, DEMO_MODE: false,
    authFetch: (path, options) => new Promise((resolve, reject) => requests.push({ path, token, signal: options?.signal, resolve, reject })),
    authHeaders: () => ({ 'X-Wearable-Token': token }), clearAuth() {}, onAuthCleared: callback => authListeners.push(callback),
    createEventApi: () => ({ command() {} }), createLocationApi: () => ({}), createBusinessCommands: () => () => {},
    localStorage: { getItem: () => null, setItem() {} }, window: { setInterval() {}, addEventListener() {} },
    document: { hidden: false, addEventListener() {} }, setTimeout: () => 1, clearTimeout() {},
  };
  const api = new Function(...Object.keys(bindings), source + '\nreturn {db, connection, guardianReady, refreshSnapshot, isPulling:()=>pulling};')(...Object.values(bindings));
  return { ...api, requests,
    login(value) { token = value; },
    logout() { token = ''; for (const callback of authListeners) callback(); },
    respond(index, state = snapshot('current-actor')) { requests[index].resolve({ ok: true, json: async () => ({ state }) }); },
  };
}

test('same-session callers await one in-flight snapshot rather than treating a busy refresh as failure', async () => {
  const f = await fixture();
  const one = f.refreshSnapshot(), two = f.refreshSnapshot();
  assert.equal(f.requests.length, 1);
  f.respond(0, snapshot('same-actor'));
  assert.deepEqual(await Promise.all([f.guardianReady, one, two]), [true, true, true]);
  assert.equal(f.db.state.operator.id, 'same-actor');
  assert.equal(f.isPulling(), false);
});

test('a new login starts its own authorized snapshot and an old finally cannot clear the new request', async () => {
  const f = await fixture();
  f.login('new-token');
  const current = f.refreshSnapshot();
  assert.equal(f.requests.length, 2, 'the pending old login cannot suppress the new login initialization');
  assert.equal(f.requests[1].token, 'new-token');
  assert.equal(f.requests[0].signal.aborted, true);
  f.respond(0, snapshot('old-actor'));
  assert.equal(await f.guardianReady, false);
  assert.notEqual(f.db.state.operator?.id, 'old-actor');
  assert.equal(f.isPulling(), true, 'new request bookkeeping must survive the old finally');
  const joined = f.refreshSnapshot();
  assert.equal(f.requests.length, 2, 'a same-session refresh still joins the new in-flight request');
  f.respond(1, snapshot('new-actor'));
  assert.deepEqual(await Promise.all([current, joined]), [true, true]);
  assert.equal(f.db.state.operator.id, 'new-actor');
  assert.equal(f.connection.value.status, 'online');
  assert.equal(f.isPulling(), false);
});

test('late transport failures from an old login cannot turn a new successful connection offline', async () => {
  const f = await fixture();
  f.login('new-token');
  const current = f.refreshSnapshot();
  assert.equal(f.requests.length, 2);
  f.respond(1, snapshot('new-actor')); assert.equal(await current, true);
  f.requests[0].reject(Error('old transport failed'));
  assert.equal(await f.guardianReady, false);
  assert.equal(f.connection.value.status, 'online');
  assert.equal(f.db.state.operator.id, 'new-actor');
});

test('logout aborts the old snapshot and late cleanup cannot detach the replacement login', async () => {
  const f = await fixture();
  f.logout();
  assert.equal(f.requests[0].signal.aborted, true);
  f.login('replacement-token');
  const current = f.refreshSnapshot();
  assert.equal(f.requests.length, 2);
  f.requests[0].reject(Object.assign(Error('cancelled'), { name: 'AbortError' }));
  assert.equal(await f.guardianReady, false);
  assert.equal(f.isPulling(), true);
  f.respond(1, snapshot('replacement-actor'));
  assert.equal(await current, true);
  assert.equal(f.db.state.operator.id, 'replacement-actor');
});

test('call-status replies started under an old snapshot cannot update the next account store', async () => {
  const f = await fixture();
  const old = snapshot('old-actor');
  old.calls = [{ id:'old-call', status:'呼叫中', rtc:{callId:'old-remote-call'}, members:[] }];
  f.respond(0, old); await flush();
  assert.equal(f.requests[1].path, '/api/guardian/v1/helmet/calls/old-remote-call');
  const applied = []; f.db.applyServerCallStatus = (...values) => applied.push(values);
  f.login('new-token');
  const current = f.refreshSnapshot();
  assert.equal(f.requests.length, 3);
  f.respond(2, snapshot('new-actor')); assert.equal(await current, true);
  f.requests[1].resolve({ok:true,json:async()=>({status:'unknown'})});
  assert.equal(await f.guardianReady, false);
  assert.deepEqual(applied, []);
  assert.equal(f.connection.value.status, 'online');
  assert.equal(f.db.state.operator.id, 'new-actor');
});
