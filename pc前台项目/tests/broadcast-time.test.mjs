import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parse, compileScript } from '@vue/compiler-sfc';
import * as Vue from 'vue';
import * as SSR from 'vue/server-renderer';
import * as dateTime from '../src/lib/date-time.js';

const pages = ['DispatchView.vue', 'BroadcastRecords.vue'];
const compiledPages = new Map();
const communicationSource = (await readFile(new URL('../src/lib/shared-communications.js', import.meta.url), 'utf8'))
  .replace(/^import .*;\s*$/gm, '').replace(/export function /g, 'function ');
const communications = new Function('db', communicationSource + '\nreturn { sharedCalls, sharedBroadcasts };');

function stub(name) {
  return Vue.defineComponent({
    props: ['title', 'text', 'rows'],
    setup(props, { slots }) {
      return () => name === 'AppTable'
        ? Vue.h('table', [Vue.h('tbody', slots.default?.({ rows: props.rows || [] }))])
        : Vue.h('section', { 'data-component': name }, [props.title || props.text, slots.extra?.(), slots.actions?.(), slots.default?.()]);
    },
  });
}

async function renderBroadcast(page, time, origin = 'shared') {
  if (!compiledPages.has(page)) {
    const raw = await readFile(new URL('../src/views/dispatch/' + page, import.meta.url), 'utf8');
    const { descriptor } = parse(raw, { filename: page });
    compiledPages.set(page, compileScript(descriptor, {
      id: 'broadcast-time-' + page, inlineTemplate: true, templateOptions: { ssr: true },
    }).content);
  }
  const record = { id: 'qa-broadcast', station: 'S1', groupName: '测试分组', text: '时间回归', status: '已受理', members: [] };
  const db = { demoMode: false, state: {
    stations: [{ id: 'S1', siteId: 'site-1' }], calls: [], groups: [],
    broadcasts: origin === 'legacy' ? [{ ...record, time }] : [],
    communicationRecords: origin === 'shared' ? [{ ...record, operationType: 'broadcast', siteId: 'site-1', createdAt: time, actorName: '测试分组', status: 'accepted' }] : [],
  } };
  const session = Vue.reactive({ station: 'S1', selectedMembers: [], filters: {}, group: '' });
  const unexpected = () => { throw Error('Rendering timestamps must not perform network or device actions'); };
  const modules = {
    vue: Vue, 'vue/server-renderer': SSR, 'vue-router': { useRoute: () => ({ query: {} }) },
    '@/mock/runtime': { db, refreshSnapshot: unexpected }, '@/lib/shared-communications': communications(db),
    '@/lib/date-time': dateTime, '@/stores/session': { session, filtersOf: () => ({}) },
    '@/lib/queries': { people: () => [], revision() {}, personName: id => id, helmetOf() {}, search: () => true },
    '@/lib/person-equipment': { personFeature: () => ({ supported: false, available: false }), personDevice() {}, operationContext: unexpected },
    '@/lib/auth': { authFetch: unexpected }, '@/lib/device-telemetry': { deviceStatus() {} }, '@/lib/rtc': { resumeAudio: unexpected },
    '@/stores/modal': { openModal: unexpected }, '@/stores/notify': { toast: unexpected }, '@/lib/actions': { runGuarded: unexpected },
    '../../../../shared/device-features.mjs': { featureState() {}, featureUnavailableReason: value => value },
    '@ui-spec/useFieldErrors': { useFieldErrors: () => ({ formRef: Vue.ref(null), errors: Vue.ref({}), validate: () => false }) },
  };
  const code = compiledPages.get(page).replace(/^import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?\s*$/gm, (_, names, _quote, from) => {
    if (from.endsWith('.vue')) modules[from] = { default: stub(from.split('/').at(-1).replace('.vue', '')) };
    assert.ok(modules[from], 'Explicit render dependency: ' + from);
    const binding = names.trim().startsWith('{') ? names.replace(/\bas\b/g, ':') : `{ default: ${names} }`;
    return `const ${binding} = modules[${JSON.stringify(from)}];\n`;
  }).replace('export default', 'return');
  const app = Vue.createSSRApp(new Function('modules', code)(modules));
  app.component('UiIcon', stub('UiIcon'));
  const html = await SSR.renderToString(app);
  // Read the actual card's <time> or the modal row's first cell, not another page label.
  const match = page === 'DispatchView.vue' ? html.match(/<time>(.*?)<\/time>/) : html.match(/<tr>\s*<td>(.*?)<\/td>/);
  assert.ok(match, `${page} must render the broadcast record`);
  return match[1];
}

test('broadcast card and records modal convert real UTC creation time to Beijing seconds', async () => {
  for (const page of pages) assert.equal(await renderBroadcast(page, '2026-11-04T09:23:07.123456789Z'), '2026-11-04 17:23:07', page);
});

test('both broadcast views keep the Beijing date when UTC crosses into the next year', async () => {
  for (const page of pages) assert.equal(await renderBroadcast(page, '2026-12-31T16:23:07Z'), '2027-01-01 00:23:07', page);
});

test('both broadcast views preserve existing Beijing local timestamps', async () => {
  for (const page of pages) assert.equal(await renderBroadcast(page, '2026-11-04 17:23:07', 'legacy'), '2026-11-04 17:23:07', page);
});

test('both broadcast views render missing and invalid shared or legacy timestamps as unknown', async () => {
  for (const page of pages) for (const origin of ['shared', 'legacy']) for (const value of [undefined, null, '', 'invalid']) {
    assert.equal(await renderBroadcast(page, value, origin), '—', `${page} / ${origin} / ${value}`);
  }
});
