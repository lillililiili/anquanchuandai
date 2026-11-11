import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parse, compileScript } from '@vue/compiler-sfc';
import * as Vue from 'vue';
import * as SSR from 'vue/server-renderer';
import * as dateTime from '../src/lib/date-time.js';

const filename = 'EventView.vue';
const source = await readFile(new URL('../src/views/event/EventView.vue', import.meta.url), 'utf8');
const { descriptor } = parse(source, { filename });
const compiled = compileScript(descriptor, {
  id: 'event-verification-time', inlineTemplate: true, templateOptions: { ssr: true },
}).content;

function stub(name) {
  return Vue.defineComponent({
    props: ['title'],
    setup(props, { slots }) {
      return () => Vue.h('section', { 'data-component': name }, [props.title, slots.default?.()]);
    },
  });
}

async function submittedLabel(submittedAt) {
  const event = { id: 'E1', station: 'S1', type: '人员求助', title: '时间回归',
    status: '已核验', version: 1, permissions: {}, timeline: [], observations: [],
    verification: { submittedAt, actorName: '核验人员', conclusion: '需现场处理', situation: '已确认', measures: '' } };
  const unexpected = () => { throw Error('Rendering verification time must not perform network or device actions'); };
  const modules = {
    vue: Vue, 'vue/server-renderer': SSR, 'vue-router': { useRoute: () => ({ params: { id: event.id } }) },
    '@/mock/runtime': { db: { event: () => event, work: () => null, device: () => null, state: { media: [] }, verify: unexpected, observe: unexpected } },
    '@/stores/session': { session: Vue.reactive({ station: 'S1', formDrafts: {} }) },
    '@/lib/queries': { revision() {}, materials: () => [], personName: id => id, statusColor: () => 'green' },
    '@/lib/work-business': { workBusinessEnabled: () => false, eventSource: () => '本地事件' },
    '@/lib/external-status': { hasExternalSource: () => false, externalStatusPresentation: () => ({}) },
    '@/lib/person-equipment': { eventVideoSupported: () => false }, '@/lib/date-time': dateTime,
    '@/lib/actions': { go: unexpected }, '@/lib/files': { blobPut: unexpected },
    '@/stores/modal': { openModal: unexpected }, '@/stores/notify': { toast: unexpected },
    '@ui-spec/useFieldErrors': { useFieldErrors: () => ({ formRef: Vue.ref(null), errors: Vue.ref({}), validate: unexpected }) },
  };
  const code = compiled.replace(/^import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?\s*$/gm, (_, names, _quote, from) => {
    if (from.endsWith('.vue')) modules[from] = { default: stub(from.split('/').at(-1)) };
    assert.ok(modules[from], 'Explicit render dependency: ' + from);
    const binding = names.trim().startsWith('{') ? names.replace(/\bas\b/g, ':') : `{ default: ${names} }`;
    return `const ${binding} = modules[${JSON.stringify(from)}];\n`;
  }).replace('export default', 'return');
  const html = await SSR.renderToString(Vue.createSSRApp(new Function('modules', code)(modules)));
  // Inspect the real submitted-result strip, not a separate timeline timestamp.
  const match = html.match(/<div class="warning-box"><p>([\s\S]*?)<\/p><\/div>/);
  assert.ok(match, 'Verified event must render its submitted-result strip');
  return match[1].replace(/<[^>]*>/g, '').trim();
}

test('verified event submission strip formats backend UTC nanoseconds as Beijing seconds', async () => {
  assert.equal(await submittedLabel('2026-11-04T11:17:29.022220617Z'), '2026-11-04 19:17:29　核验人员已提交');
});

test('verified event submission strip converts the UTC date across midnight', async () => {
  assert.equal(await submittedLabel('2026-12-31T16:23:07Z'), '2027-01-01 00:23:07　核验人员已提交');
});

test('verified event submission strip preserves legacy Beijing local time', async () => {
  assert.equal(await submittedLabel('2026-11-04 19:17:29'), '2026-11-04 19:17:29　核验人员已提交');
});

test('verified event submission strip uses an unknown marker for absent or invalid time', async () => {
  for (const time of [undefined, null, '', 'invalid']) assert.equal(await submittedLabel(time), '—　核验人员已提交');
});
