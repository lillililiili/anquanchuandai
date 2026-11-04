import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compileScript, parse } from '@vue/compiler-sfc';
import * as Vue from 'vue';
import { createEventApi } from '../src/lib/guardian-events.js';

const source = await readFile(new URL('../src/views/event/EventView.vue', import.meta.url), 'utf8');
const { descriptor } = parse(source);
const script = compileScript(descriptor, { id: 'event-verification' }).content
  .replace(/^import\s+(.+?)\s+from\s+(['"])([^'"]+)\2;?$/gm, (_, names, _quote, path) =>
    `const ${names.startsWith('{') ? names : `{ default: ${names} }`} = dependency(${JSON.stringify(path)});`)
  .replace('export default', 'return');
const setup = new Function('dependency', script);

function fixture(t) {
  const route = Vue.reactive({ params: { id: 'one' } });
  const session = Vue.reactive({ station: 'station', formDrafts: {} });
  const server = {
    one: { id: 'one', station: 'station', version: 1 },
    two: { id: 'two', station: 'station', version: 2 },
  };
  const events = Vue.ref(structuredClone(server));
  const requests = [];
  const applied = new Set();
  let beforeResponse;
  const refresh = async () => { events.value = structuredClone(server); };
  const api = createEventApi({
    current: id => events.value[id],
    refresh,
    uuid: () => 'request-' + requests.length,
    async fetchImpl(url, options) {
      const [id, action] = url.split('/').slice(-2);
      const body = JSON.parse(options.body);
      requests.push({ id, action, body });
      const item = server[id];
      if (applied.has(body.requestId)) {
        return { ok: true, json: async () => structuredClone(item) };
      }
      if (body.expectedVersion !== item.version) {
        return { ok: false, status: 409, json: async () => ({ message: '事件已被其他终端更新' }) };
      }
      item.version++;
      applied.add(body.requestId);
      if (action === 'verification') item.verification = body;
      const saved = structuredClone(item);
      await beforeResponse?.();
      return { ok: true, json: async () => saved };
    },
  });
  const modules = {
    vue: Vue,
    'vue-router': { useRoute: () => route },
    '@ui-spec/useFieldErrors': { useFieldErrors: () => ({ errors: Vue.ref({}), validate: fields => Object.values(fields).every(value => !value) }) },
    '@/mock/runtime': { db: {
      event: id => events.value[id],
      observe: (id, body) => api.command(id, 'observations', body),
      addEventPhoto: (id, blobId, name, expectedVersion) => api.command(id, 'photos', { blobId, name, expectedVersion }),
      verify: (id, body) => api.command(id, 'verification', body),
    } },
    '@/stores/session': { session },
    '@/lib/queries': { revision() {} },
    '@/lib/files': { blobPut: async () => {} },
    '@/stores/notify': { toast() {} },
  };
  const scope = Vue.effectScope();
  t.after(() => scope.stop());
  const component = setup(path => modules[path] ?? {});
  const view = scope.run(() => component.setup({}, { expose() {} }));
  return { view, session, route, server, refresh, requests, onResponse: fn => { beforeResponse = fn; } };
}

test('saving a field observation and adding a photo allows verification without losing typed fields', async t => {
  const { view, requests, server } = fixture(t);
  view.form.value.situation = '现场情况';
  view.observation.value = '补充情况';
  await view.appendObservation();
  view.form.value.conclusion = '需现场处理';
  view.form.value.measures = '现场措施';
  await view.uploadPhoto({ target: { files: [{ type: 'image/png', size: 8, name: 'site.png' }] } });
  await view.submitVerify();
  assert.equal(view.formError.value, '');
  assert.deepEqual(requests.map(({ action, body }) => [action, body.expectedVersion]), [
    ['observations', 1], ['photos', 2], ['verification', 3],
  ]);
  assert.equal(server.one.verification.situation, '现场情况');
  assert.equal(server.one.verification.measures, '现场措施');
});

test('an observation leaves an already stale verification draft subject to conflict', async t => {
  const { view, server, refresh, requests } = fixture(t);
  view.form.value.conclusion = '需现场处理';
  view.form.value.situation = '原草稿';
  server.one.version++;
  await refresh();
  view.observation.value = '补充情况';
  await view.appendObservation();
  await view.submitVerify();
  assert.deepEqual(requests.map(({ body }) => body.expectedVersion), [2, 1]);
  assert.equal(view.formError.value, '事件已被其他终端更新');
  assert.equal(view.form.value.situation, '原草稿');
});

test('an observation response updates only the draft for the event it was sent to', async t => {
  const { view, session, route, onResponse } = fixture(t);
  view.observation.value = '第一条事件补充';
  onResponse(async () => {
    route.params.id = 'two';
    await Vue.nextTick();
    view.observation.value = '第二条事件补充';
  });
  await view.appendObservation();
  assert.equal(session.formDrafts.one.expectedVersion, 2);
  assert.equal(session.formDrafts.two.expectedVersion, 2);
  assert.equal(view.observation.value, '第二条事件补充');
});

test('replaying an observation does not rebase the draft over an intervening remote write', async t => {
  const { view, server, requests, onResponse } = fixture(t);
  view.form.value.conclusion = '需现场处理';
  view.form.value.situation = '原草稿';
  view.observation.value = '补充情况';
  onResponse(() => { throw Error('断网'); });
  await view.appendObservation();
  assert.equal(view.observationError.value, '断网');
  server.one.version++;
  onResponse(undefined);
  await view.appendObservation();
  assert.equal(requests[0].body.requestId, requests[1].body.requestId);
  await view.submitVerify();
  assert.equal(requests[2].body.expectedVersion, 1);
  assert.equal(view.formError.value, '事件已被其他终端更新');
});
