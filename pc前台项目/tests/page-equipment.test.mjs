import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parse, compileScript } from '@vue/compiler-sfc';
import * as Vue from 'vue';
import * as SSR from 'vue/server-renderer';
import * as equipment from '../src/lib/person-equipment.js';
import * as source from '../src/views/work/work-source.js';
import { fenceWriteIssue } from '../src/views/fences/fence-policy.js';
import * as telemetry from '../src/lib/device-telemetry.js';
import * as external from '../src/lib/external-status.js';
import * as features from '../../shared/device-features.mjs';
import { personDutyPresentation } from '../src/lib/person-duty.js';
import * as dateTime from '../src/lib/date-time.js';
import { videoPeople as screenVideoPeople } from '../src/views/screen/screen-model.js';

function fixture(type = 'B', online = true) {
  const person = { id: 'P1', name: '现场人员', active: true, station: 'S1', team: '一班' };
  const device = { id: type === 'H' ? 'helmet-real' : 'belt-real', type, station: 'S1', active: true, online, source: type === 'H' ? 'DIRECT_HELMET' : 'DIRECT_BELT', freshness: 'CURRENT', sourceTime: new Date().toISOString(), featureStates: Object.fromEntries(['video', 'voice', 'recording'].map(key => [key, { supported: type === 'H', verified: key === 'video', available: type === 'H' && online && key === 'video', reason: key === 'video' ? online ? '' : '设备离线' : '待联调' }])) };
  const work = { id: 'WK1', name: '现场作业', station: 'S1', members: ['P1'], leader: 'P1', supervisor: 'P1', start: '08:00', end: '17:00', date: '2026-10-27', status: '监护中' };
  const state = { people: [person], devices: [device], calls: [], media: [], events: [], works: [work], bindings: [{ id: 'assignment-1', deviceId: device.id, personId: person.id }], operator: { id: 'operator' }, assistance: {}, businessConfig: { simulatedWatchVisible: false }, personEquipmentContext: { P1: { features: Object.fromEntries(['video','voice','recording'].map(key => [key, { ...device.featureStates[key], deviceId: device.id, assignmentId: 'assignment-1', assignmentVersion: 1 }])) } } };
  const db = { state, demoMode: false, person: id => state.people.find(p => p.id === id), device: id => state.devices.find(d => d.id === id), work: id => state.works.find(w => w.id === id), event: id => state.events.find(e => e.id === id), currentDevices: id => state.bindings.filter(b => !b.end && b.personId === id).map(b => db.device(b.deviceId)), currentWork: id => state.works.find(w => w.members.includes(id)), vitals: () => ({ watch: null, record: null }), vitalHistory: () => [], locationValid: () => false };
  db.stats = () => ({ people: state.people, devices: state.devices, works: state.works, events: state.events, online: online ? 1 : 0, assigned: 1, unresolved: state.events.length, simulatedWatches: [], byType: { H: { total: type === 'H' ? 1 : 0, online: type === 'H' && online ? 1 : 0 }, B: { total: type === 'B' ? 1 : 0, online: type === 'B' && online ? 1 : 0 }, W: { total: 0, online: 0 } } });
  const session = Vue.reactive({ station: 'S1', person: 'P1', work: 'WK1', event: 'E1', filters: {}, formDrafts: {}, personTab: '人员信息', layout: '1+7', volume: 0 });
  const route = { params: { id: 'P1' }, query: {} };
  const queries = { revision: () => 0, people: () => state.people, events: () => state.events, materials: () => state.media, works: () => state.works, scope: () => ({ station: 'S1' }), personName: id => db.person(id)?.name || '未关联人员', helmetOf: id => db.currentDevices(id).find(d => d.type === 'H'), statusColor: () => 'muted', search: () => true };
  return { db, session, route, queries, person, device, work };
}

const componentCache = new Map();
function stub(name) {
  if (componentCache.has(name)) return componentCache.get(name);
  const component = Vue.defineComponent({ name, props: ['title','text','rows'], setup(props, { slots, attrs }) { return () => Vue.h(name === 'AppButton' ? 'button' : 'section', { ...attrs, 'data-component': name }, [props.title || props.text, slots.title?.(), slots.extra?.(), slots.actions?.(), slots.default?.({ rows: props.rows || [] })]); } });
  componentCache.set(name, component); return component;
}
async function render(path, f) {
  const raw = await readFile(new URL(`../src/views/${path}`, import.meta.url), 'utf8');
  const { descriptor } = parse(raw, { filename: path });
  const code = compileScript(descriptor, { id: path, inlineTemplate: true, templateOptions: { ssr: true } }).content;
  const modules = {
    vue: Vue, 'vue/server-renderer': SSR, 'vue-router': { useRoute: () => f.route },
    '@/mock/runtime': { db: f.db, tick: Vue.ref(0) }, '@/mock/data': { typeNames: { H: '安全帽', B: '安全带', W: '手表' } },
    '@/lib/person-equipment': equipment, '@/lib/device-telemetry': telemetry, '@/lib/external-status': external, '@/lib/date-time': dateTime,
    '../../../../shared/device-features.mjs': features, '@/lib/person-duty': { personDutyPresentation }, './work-source': source,
    '@/lib/queries': f.queries, '@/stores/session': { session: f.session, filtersOf: key => f.session.filters[key] || {} },
    '@/stores/notify': { toast() {} }, '@/stores/modal': { openModal() {} }, '@/lib/actions': { callPerson() {}, go() {}, runGuarded: fn => fn() },
    '@/lib/files': { blobPut() {} }, '@ui-spec/useFieldErrors': { useFieldErrors: () => ({ formRef: Vue.ref(null), errors: Vue.ref({}), validate: () => true }) },
  };
  const compiled = code.replace(/^import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?\s*$/gm, (_, names, quote, from) => {
    if (from.endsWith('.vue')) modules[from] = { default: stub(from.split('/').at(-1).replace('.vue', '')) };
    assert.ok(modules[from], `test dependency must be explicit: ${from}`);
    const binding = names.trim().startsWith('{') ? names.replace(/\bas\b/g, ':') : `{ default: ${names} }`;
    return `const ${binding} = modules[${JSON.stringify(from)}];\n`;
  }).replace('export default', 'return');
  const component = new Function('modules', compiled)(modules);
  const app = Vue.createSSRApp(component); app.component('UiIcon', stub('UiIcon'));
  return SSR.renderToString(app);
}

test('仅安全带人员在总览、人员、作业、单路和视频墙不产生视频组件', async () => {
  for (const page of ['overview/OverviewView.vue','personnel/PersonnelView.vue','work/WorkView.vue','single/SingleView.vue','video/VideoView.vue']) {
    const f = fixture('B'); if (page.startsWith('work/')) f.route.params.id = 'WK1';
    const html = await render(page, f);
    assert.doesNotMatch(html, /data-component="VideoFrame"/, page);
    assert.doesNotMatch(html, /data-component="PlatformEquipment"/, page);
    assert.doesNotMatch(html, /data-component="HelmetDevicePanel"/, page);
  }
});

test('离线安全帽仍保留视频区和待联调语音状态，入口没有包在链接里', async () => {
  const f = fixture('H', false);
  for (const page of ['overview/OverviewView.vue','personnel/PersonnelView.vue','single/SingleView.vue','video/VideoView.vue']) {
    const html = await render(page, f);
    assert.match(html, /data-component="VideoFrame"/, page);
    assert.doesNotMatch(html, /<a\b[^>]*>\s*<section[^>]*data-component="VideoFrame"/, page);
  }
  const personnel = await render('personnel/PersonnelView.vue', f);
  const voiceButton = [...personnel.matchAll(/<button([^>]*)>([\s\S]*?)<\/button>/g)].find(match => match[2].includes('对讲 · 待联调'));
  assert.ok(voiceButton); assert.match(voiceButton[1], /disabled/);
});

test('大屏和视频墙共用当前领用视频人员，真实帽不再被 demo 开关排除', () => {
  const f = fixture('H');
  assert.deepEqual(screenVideoPeople(f.db, f.db.state.people).map(p => p.id), ['P1']);
  f.device.online = false;
  assert.deepEqual(screenVideoPeople(f.db, f.db.state.people).map(p => p.id), ['P1']);
  assert.equal(equipment.personFeature(f.db, 'P1', 'video').available, false);
  f.db.state.bindings[0].end = '2026-10-27T12:00:00Z';
  assert.deepEqual(screenVideoPeople(f.db, f.db.state.people), []);
  const belt = fixture('B'); assert.deepEqual(screenVideoPeople(belt.db, belt.db.state.people), []);
});

test('事件没有影像时显示证据空态，当前视频独立；未领用事件不消失', async () => {
  for (const type of ['B', 'H']) {
    const f = fixture(type); f.route.params.id = 'E1';
    f.db.state.events.push({ id: 'E1', station: 'S1', personId: 'P1', deviceId: f.device.id, type: '设备通信', title: '连接待核验', status: '待现场核验', snapshot: {}, timeline: [], permissions: {} });
    const html = await render('event/EventView.vue', f);
    assert.match(html, /暂无本事件的影像证据/);
    if (type === 'H') assert.match(html, /当前现场视频/); else assert.doesNotMatch(html, /data-component="VideoFrame"/);
    f.db.state.events[0].personId = '';
    const unassigned = await render('event/EventView.vue', f);
    assert.match(unassigned, /未关联人员/); assert.doesNotMatch(unassigned, /data-component="VideoFrame"/);
  }
});

test('未关联人员的安全带 SOS 保留告警和协助入口，位置使用事件而不是当前人员', async () => {
  const f = fixture('B');
  const event = { id: 'E1', station: 'S1', personId: '', deviceId: f.device.id, type: '人员求助', title: '设备 SOS', status: '待认领', date: '2026-10-27', time: '10:00:00', snapshot: {}, timeline: [], permissions: { 'events:claim': true, 'sos:assist': true } };
  f.db.state.events.push(event); f.route.query.eventId = event.id;
  f.db.state.assistance.E1 = { status: 'waiting', members: [], timeline: [] };
  for (const page of ['alarms/AlarmsView.vue', 'sos/SosView.vue']) {
    const html = await render(page, f);
    assert.match(html, /未关联人员/); assert.match(html, /data-component="EventLocation"/);
    assert.doesNotMatch(html, /data-component="VideoFrame"/);
    assert.match(html, page.startsWith('sos') ? /接警认领/ : /立即响应/);
  }
});

test('作业计划时间不会生成检查、到场记录；风险只来自实际字段', () => {
  const work = { id: 'WK1', start: '08:00', leader: 'P1', members: ['P1'] };
  assert.deepEqual(source.workTimeline(work, [], () => '张工'), []);
  assert.deepEqual(source.workRisks(work), { riskFactors: '', measures: '' });
  assert.deepEqual(source.workRisks({ risks: ['高处作业'], safetyMeasures: '系好安全带' }), { riskFactors: '高处作业', measures: '系好安全带' });
  const history = source.workTimeline({ ...work, timeline: [{ time: '10:00', text: '实际记录' }, { text: '无时间' }] }, [{ workId: 'WK2', title: '其他作业' }], () => '张工');
  assert.deepEqual(history, [{ time: '10:00', text: '实际记录' }]);
});

test('生产围栏拒绝旧百分比和未知坐标系，真实坐标系与隔离演示可保存', () => {
  for (const coordinateSystem of [undefined, '', 'PERCENT', 'EPSG:3857']) assert.match(fenceWriteIssue({ coordinateSystem }), /重新绘制/);
  for (const coordinateSystem of ['GCJ02','WGS84']) assert.equal(fenceWriteIssue({ coordinateSystem }), '');
  assert.equal(fenceWriteIssue({}, true), '');
});

test('设备录像查询使用领用上下文；离线、待联调和重复点击不下发，旧响应不覆盖换绑后状态', async () => {
  const f = fixture('H'), tick = Vue.ref(0), watchers = [], sent = [];
  let resolveCommand;
  const raw = await readFile(new URL('../src/views/materials/DeviceRecordings.vue', import.meta.url), 'utf8');
  const { descriptor } = parse(raw);
  const code = compileScript(descriptor, { id: 'recordings-contract' }).content;
  const modules = {
    vue: { ...Vue, onUnmounted() {}, watch(selector, callback, options) { watchers.push(callback); if (options?.immediate) callback(); } },
    '@/mock/runtime': { db: f.db, tick, connection: Vue.ref({ status: 'online' }) }, '@/lib/auth': { authFetch() { assert.fail('test must never access a backend'); } },
    '@/lib/location': { beijingDate: () => '2026-10-27' }, '@/lib/person-equipment': equipment, '@/lib/device-telemetry': telemetry,
    '@/lib/helmet-media': { COMMAND_LABELS: { list_recordings: '查询设备录像', upload_recording: '上传选中录像' }, COMMAND_STATUSES: { sent: '已发送，设备待回执' }, createHelmetMediaApi: () => ({ read: async () => ({ recordings: [], commands: [] }), command: (...args) => { sent.push(args); return new Promise(resolve => { resolveCommand = resolve; }); } }) },
  };
  const compiled = code.replace(/^import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?\s*$/gm, (_, names, quote, from) => {
    if (from.endsWith('.vue')) modules[from] = { default: stub(from.split('/').at(-1).replace('.vue','')) };
    assert.ok(modules[from], from);
    const binding = names.trim().startsWith('{') ? names.replace(/\bas\b/g, ':') : `{ default: ${names} }`;
    return `const ${binding} = modules[${JSON.stringify(from)}];\n`;
  }).replace('export default','return');
  const component = new Function('modules','setInterval','clearInterval',compiled)(modules, () => 1, () => {});
  const instance = component.setup({ personId: 'P1' }, { expose() {}, emit() {} });
  await instance.send('list_recordings', {}); assert.equal(sent.length, 0, 'unverified recording stays disabled');
  Object.assign(f.device.featureStates.recording, { verified: true, available: true });
  Object.assign(f.db.state.personEquipmentContext.P1.features.recording, { verified: true, available: true });
  f.device.capabilities = { actions: ['list_recordings','upload_recording'] }; tick.value++;
  const pending = instance.send('list_recordings', { startTime: '2026-10-27 00:00:00', endTime: '2026-10-27 23:59:59' });
  await instance.send('list_recordings', {}); assert.equal(sent.length, 1, 'pending command cannot be duplicated');
  assert.deepEqual(sent[0][5], { personId: 'P1', deviceId: f.device.id, assignmentId: 'assignment-1', assignmentVersion: 1 });
  f.db.state.personEquipmentContext.P1.features.recording.assignmentVersion = 2; tick.value++; watchers[0]();
  resolveCommand({ status: 'sent' }); await pending;
  assert.equal(instance.notice.value, '', 'late result from old assignment is discarded');
  f.device.online = false; tick.value++;
  await instance.send('upload_recording', { files: ['clip.mp4'] }); assert.equal(sent.length, 1, 'offline device cannot upload');
});
