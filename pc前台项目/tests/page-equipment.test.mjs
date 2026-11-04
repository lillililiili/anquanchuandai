import * as workBusiness from '../src/lib/work-business.js';
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
import * as videoWall from '../src/views/video/video-wall.js';
import * as mediaPresentation from '../src/lib/media-presentation.js';
import * as statisticsModel from '../src/views/statistics/statistics-model.js';
import * as locationPresentation from '../src/views/location/location-presentation.js';
import * as testSite from '../../shared/test-site.mjs';
import * as vitalValues from '../src/views/person/vital-values.js';
import * as navigation from '../src/components/layout/navigation.js';

function fixture(type = 'B', online = true) {
  const person = { id: 'P1', name: '现场人员', active: true, station: 'S1', team: '一班' };
  const device = { id: type === 'H' ? 'helmet-real' : 'belt-real', type, station: 'S1', active: true, online, source: type === 'H' ? 'DIRECT_HELMET' : 'DIRECT_BELT', freshness: 'CURRENT', sourceTime: new Date().toISOString(), featureStates: Object.fromEntries(['video', 'voice', 'recording'].map(key => [key, { supported: type === 'H', verified: key === 'video', available: type === 'H' && online && key === 'video', reason: key === 'video' ? online ? '' : '设备离线' : '待联调' }])) };
  const work = { id: 'WK1', name: '现场作业', station: 'S1', members: ['P1'], leader: 'P1', supervisor: 'P1', start: '08:00', end: '17:00', date: '2026-10-27', status: '监护中' };
  const state = { stations: [{ id: 'S1', name: '测试厂站' }], people: [person], devices: [device], calls: [], media: [], events: [], works: [work], bindings: [{ id: 'assignment-1', assignmentId: 'assignment-1', assignmentVersion: 1, deviceId: device.id, personId: person.id }], operator: { id: 'operator' }, assistance: {}, businessConfig: { workBusinessEnabled: true, version: 1, simulatedWatchVisible: false }, personEquipmentContext: { P1: { features: Object.fromEntries(['video','voice','recording'].map(key => [key, { ...device.featureStates[key], deviceId: device.id, assignmentId: 'assignment-1', assignmentVersion: 1 }])) } } };
  const db = { state, demoMode: false, person: id => state.people.find(p => p.id === id), device: id => state.devices.find(d => d.id === id), work: id => state.works.find(w => w.id === id), event: id => state.events.find(e => e.id === id), currentDevices: id => state.bindings.filter(b => !b.end && b.personId === id).map(b => db.device(b.deviceId)), currentWork: id => state.works.find(w => w.members.includes(id)), vitals: () => ({ watch: null, record: null }), vitalHistory: () => [], locationValid: () => false, owner: () => person };
  db.stats = () => ({ people: state.people, devices: state.devices, works: state.works, events: state.events, online: online ? 1 : 0, assigned: 1, unresolved: state.events.length, simulatedWatches: [], byType: { H: { total: type === 'H' ? 1 : 0, online: type === 'H' && online ? 1 : 0 }, B: { total: type === 'B' ? 1 : 0, online: type === 'B' && online ? 1 : 0 }, W: { total: 0, online: 0 } } });
  const session = Vue.reactive({ station: 'S1', person: 'P1', work: 'WK1', event: 'E1', filters: {}, formDrafts: {}, personTab: '人员信息', layout: '1+7', volume: 0, layers: { people: true, fences: true }, statsTab: '综合' });
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
async function render(path, f, components = {}) {
  const raw = await readFile(new URL(`../src/views/${path}`, import.meta.url), 'utf8');
  const { descriptor } = parse(raw, { filename: path });
  const code = compileScript(descriptor, { id: path, inlineTemplate: true, templateOptions: { ssr: true } }).content;
  const modules = {
    '@/lib/work-business': workBusiness,
    vue: Vue, 'vue/server-renderer': SSR, 'vue-router': { useRoute: () => f.route },
    '@/mock/runtime': { db: f.db, tick: Vue.ref(0) }, '@/mock/data': { typeNames: { H: '安全帽', B: '安全带', W: '手表' } },
    '@/lib/person-equipment': equipment, '@/lib/device-telemetry': telemetry, '@/lib/external-status': external, '@/lib/date-time': dateTime,
    '../../../../shared/device-features.mjs': features, '@/lib/person-duty': { personDutyPresentation }, './work-source': source, './video-wall': videoWall,
    '@/lib/queries': f.queries, '@/stores/session': { session: f.session, filtersOf: key => f.session.filters[key] || {} },
    '@/lib/media-presentation': mediaPresentation, './statistics-model': statisticsModel, './location-presentation': locationPresentation,
    '../../../../shared/test-site.mjs': testSite, './vital-values': vitalValues, './navigation': navigation,
    '@/lib/dialogs': { previewCsv: (...args) => (f.exports ||= []).push(args) },
    '@/stores/notify': { toast() {} }, '@/stores/modal': { openModal() {} }, '@/lib/actions': { callPerson() {}, go() {}, runGuarded: fn => fn() },
    '@/lib/files': { blobPut() {} }, '@ui-spec/useFieldErrors': { useFieldErrors: () => ({ formRef: Vue.ref(null), errors: Vue.ref({}), validate: () => true }) },
  };
  const compiled = code.replace(/^import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?\s*$/gm, (_, names, quote, from) => {
    if (from.endsWith('.vue')) {
      const name = from.split('/').at(-1).replace('.vue', '');
      modules[from] = { default: components[name] || stub(name) };
    }
    assert.ok(modules[from], `test dependency must be explicit: ${from}`);
    const binding = names.trim().startsWith('{') ? names.replace(/\bas\b/g, ':') : `{ default: ${names} }`;
    return `const ${binding} = modules[${JSON.stringify(from)}];\n`;
  }).replace('export default', 'return');
  const component = new Function('modules', compiled)(modules);
  const app = Vue.createSSRApp(component); app.component('UiIcon', stub('UiIcon'));
  return SSR.renderToString(app);
}

test('关闭作业业务的页面不展示作业与外部关联，旧筛选不隐藏设备监看和待办事件', async () => {
  for (const page of ['overview/OverviewView.vue', 'personnel/PersonnelView.vue', 'person/PersonView.vue', 'video/VideoView.vue', 'location/LocationView.vue', 'alarms/AlarmsView.vue', 'event/EventView.vue', 'statistics/StatisticsView.vue']) {
    const f = fixture('H');
    f.db.state.businessConfig.workBusinessEnabled = false;
    f.session.filters = { video: { workId: 'OBSOLETE' }, location: { workId: 'OBSOLETE' }, personnel: { workStatus: 'idle' }, statistics: { workId: 'OBSOLETE' } };
    f.session.statsTab = '任务';
    f.db.state.events.push({ id: 'E1', personId: 'P1', station: 'S1', deviceId: f.device.id, workId: 'WK1',
      externalId: 'EXT-SECRET', externalStatus: '已回传', title: '真实告警', type: '设备通信', status: '处理中',
      claimedByName: '认领人员', verification: { actorName: '核验人员' }, snapshot: { workName: '历史作业名称', supervisorName: '历史监护人' }, timeline: [], permissions: {} });
    if (page.startsWith('event')) f.route.params.id = 'E1';
    const html = await render(page, f);
    assert.doesNotMatch(html, /作业台账|台账作业|当前作业|关联作业|作业筛选|作业分组|作业状态|作业名称|作业编号|作业监护人|作业信息|历史作业名称|历史监护人|EXT-SECRET|外部系统状态|原安监事件|未接入外部系统|待分配作业|#\/work\//, page);
    if (page.startsWith('alarms') || page.startsWith('event')) {
      assert.match(html, /安全帽直连/, page);
      assert.match(html, /认领人员/, page);
      assert.match(html, /核验人员/, page);
    }
    if (page.startsWith('video')) assert.match(html, /data-component="VideoFrame"/, '过期作业筛选不会筛空监看人员');
  }
});

test('导航和测量用的隐藏导航均移除作业入口，重新开启恢复', async () => {
  const f = fixture('H');
  for (const enabled of [false, true]) {
    f.db.state.businessConfig.workBusinessEnabled = enabled;
    const html = await render('../components/layout/TopNavigation.vue', f);
    assert.equal(html.includes('作业监护'), enabled);
    assert.equal(html.includes('#/works'), enabled);
    assert.match(html, /告警与核验/);
  }
});

test('本地作业展示完整跨日时段及登记来源，没有虚构外部同步字段', async () => {
  const f = fixture('H');
  Object.assign(f.work, { source: 'LOCAL', status: '进行中', plannedStartAt: '2026-11-03T23:00:00+08:00', plannedEndAt: '2026-11-04T02:00:00+08:00' });
  f.route.params.id = 'WK1';
  const html = await render('work/WorkView.vue', f);
  assert.match(html, /本地登记/);
  assert.match(html, /2026-11-03 23:00:00/);
  assert.match(html, /2026-11-04 02:00:00/);
  assert.match(html, /进行中/);
  assert.doesNotMatch(html, /工作票号|>未接入<|同步状态|外部许可/);
});

test('统计CSV按业务开关删除作业与外部列，关闭期间保留事件事实与核验状态', async () => {
  for (const enabled of [false, true]) {
    const f = fixture('H'); f.db.state.businessConfig.workBusinessEnabled = enabled; f.session.statsTab = '事件';
    f.db.state.events.push({ id: 'E1', deviceId: f.device.id, title: '安全带高处作业告警', date: '2026-11-03', time: '10:00', status: '已核验', externalId: 'EXT1', externalStatus: '已回传', snapshot: { workName: '登记作业', personName: '现场人员' } });
    await render('statistics/StatisticsView.vue', f, {
      AppButton: Vue.defineComponent({ setup(_, { attrs }) { attrs.onClick?.(); return () => null; } }),
    });
    const [name, columns, rows] = f.exports[0];
    assert.equal(name, '事件追溯.csv');
    assert.equal(columns.includes('关联作业'), enabled);
    assert.equal(columns.includes('外部系统状态'), enabled);
    assert.equal(rows[0].length, columns.length);
    assert.ok(rows[0].includes('安全带高处作业告警'), '不改写历史事件标题中的风险名称');
    assert.ok(rows[0].includes('已核验'));
  }
});

test('人员班组筛选去除空白及非法选项，保留全部人员和有效班组筛选', async () => {
  const f = fixture('B');
  f.db.state.people = [
    ['P1', '维护一班'], ['P2', '维护一班'], ['P3', ''], ['P4', null],
    ['P5', undefined], ['P6', ' \t '], ['P7', 7], ['P8', false],
    ['P9', {}], ['P10', ' 维护二班 '], ['P11', undefined],
  ].map(([id, team]) => ({ ...f.person, id, team }));
  delete f.db.state.people.at(-1).team;
  let teamSelect, tableRows;
  const components = {
    AppSelect: Vue.defineComponent({ props: ['modelValue', 'name', 'options'], setup(props) {
      if (props.name === 'team') teamSelect = { value: props.modelValue, options: props.options };
      return () => null;
    } }),
    AppTable: Vue.defineComponent({ props: ['rows'], setup(props) {
      tableRows = props.rows;
      return () => null;
    } }),
  };
  await render('personnel/PersonnelView.vue', f, components);
  assert.deepEqual(teamSelect, { value: '', options: [['', '全部'], ['维护一班', '维护一班'], [' 维护二班 ', ' 维护二班 ']] });
  const everyone = ['P1', 'P2', 'P3', 'P4', 'P5', 'P6', 'P7', 'P8', 'P9', 'P10', 'P11'];
  assert.deepEqual(tableRows.map(row => row.person.id), everyone, '全部仍包含未填班组人员');

  f.session.filters.personnel = { team: '维护一班' };
  await render('personnel/PersonnelView.vue', f, components);
  assert.equal(teamSelect.value, '维护一班');
  assert.deepEqual(tableRows.map(row => row.person.id), ['P1', 'P2']);

  f.session.filters.personnel = { team: ' 维护二班 ' };
  await render('personnel/PersonnelView.vue', f, components);
  assert.equal(teamSelect.value, ' 维护二班 ');
  assert.deepEqual(tableRows.map(row => row.person.id), ['P10'], '选项保留原值，与班组筛选保持一致');

  f.session.filters.personnel = {};
  await render('personnel/PersonnelView.vue', f, components);
  assert.equal(teamSelect.value, '');
  assert.deepEqual(tableRows.map(row => row.person.id), everyone);
});

test('仅安全带人员在总览、人员、作业、单路和视频墙不产生视频组件', async () => {
  for (const page of ['overview/OverviewView.vue','personnel/PersonnelView.vue','work/WorkView.vue','single/SingleView.vue','video/VideoView.vue']) {
    const f = fixture('B'); if (page.startsWith('work/')) f.route.params.id = 'WK1';
    const html = await render(page, f);
    assert.doesNotMatch(html, /data-component="VideoFrame"/, page);
    assert.doesNotMatch(html, /data-component="PlatformEquipment"/, page);
    assert.doesNotMatch(html, /data-component="HelmetDevicePanel"/, page);
  }
});

test('离线安全帽保留视频区及禁用的语音入口，不显示语音待联调', async () => {
  const f = fixture('H', false);
  for (const page of ['overview/OverviewView.vue','personnel/PersonnelView.vue','single/SingleView.vue','video/VideoView.vue']) {
    const html = await render(page, f);
    assert.match(html, /data-component="VideoFrame"/, page);
    assert.doesNotMatch(html, /<a\b[^>]*>\s*<section[^>]*data-component="VideoFrame"/, page);
  }
  const personnel = await render('personnel/PersonnelView.vue', f);
  const voiceButton = [...personnel.matchAll(/<button([^>]*)>([\s\S]*?)<\/button>/g)].find(match => match[2].includes('前往语音通话'));
  assert.ok(voiceButton); assert.match(voiceButton[1], /disabled/);
  assert.doesNotMatch(personnel, /对讲 · 待联调/);
});

test('实际语音通道已就绪时详情快捷入口不受人工验收标记阻挡', async () => {
  for (const page of ['personnel/PersonnelView.vue', 'work/WorkView.vue', 'single/SingleView.vue']) {
    const f = fixture('H');
    Object.assign(f.device, { communicationProtocol: 'SIP', voiceAvailable: true, capabilities: { actions: ['intercom'] } });
    const ready = { supported: true, verified: false, available: true, integrationStatus: 'CONNECTED', reason: '' };
    f.device.featureStates.voice = ready;
    Object.assign(f.db.state.personEquipmentContext.P1.features.voice, ready);
    if (page.startsWith('work/')) f.route.params.id = 'WK1';
    const html = await render(page, f);
    const button = [...html.matchAll(/<button([^>]*)>([\s\S]*?)<\/button>/g)].find(match => match[2].includes('前往语音通话'));
    assert.ok(button, page); assert.doesNotMatch(button[1], /disabled/, page);
    assert.doesNotMatch(html, /对讲 · 待联调|远程指导 · 待联调/, page);
  }
});

test('总览历史事件保留日期，只有时分的旧记录不会被补为今天', async () => {
  const f = fixture('H');
  f.db.state.events.push({ id: 'E1', personId: 'P1', deviceId: f.device.id, title: '旧告警', status: '待认领', date: '2026-10-29', time: '19:07' });
  let html = await render('overview/OverviewView.vue', f);
  assert.match(html, /2026-10-29<\/span><span>19:07:00/);
  f.db.state.events[0].date = '';
  html = await render('overview/OverviewView.vue', f);
  assert.match(html, /19:07<\/span>/);
  assert.doesNotMatch(html, /2026-10-29<\/span>/);
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

test('同时领用安全帽和安全带时，安全带告警及 SOS 不带出安全帽视频', async () => {
  for (const source of ['protocol', 'device-type', 'device-source']) {
    for (const type of ['设备通信', '人员求助']) {
      const f = fixture('H');
      const belt = { id: 'belt-real', active: true, ...(source === 'device-type' ? { type: 'B' } : { source: 'DIRECT_BELT' }) };
      if (source !== 'protocol') {
        f.db.state.devices.push(belt);
        f.db.state.bindings.push({ id: 'belt-assignment', deviceId: belt.id, personId: 'P1' });
      }
      f.route.params.id = 'E1';
      f.db.state.events.push({ id: 'E1', station: 'S1', personId: 'P1', deviceId: belt.id, protocol: source === 'protocol' ? 'direct-belt' : undefined, type, title: '安全带告警', status: '处理中', date: '2026-11-02', time: '17:44', snapshot: {}, timeline: [], permissions: {} });
      assert.equal(equipment.personFeature(f.db, 'P1', 'video').supported, true, '人员本身仍有安全帽视频能力');
      for (const page of ['alarms/AlarmsView.vue', 'event/EventView.vue']) {
        const html = await render(page, f);
        assert.doesNotMatch(html, /data-component="VideoFrame"|现场视频|单路监看/, `${source} / ${type} / ${page}`);
        if (page.startsWith('alarms/') && type !== '人员求助') assert.match(html, /class="btn wide primary"[^>]*>去核验<\/a>/);
      }
    }
  }
});

test('安全帽告警在摘要和核验详情仍保留现场视频', async () => {
  const f = fixture('H');
  f.route.params.id = 'E1';
  f.db.state.events.push({ id: 'E1', station: 'S1', personId: 'P1', deviceId: f.device.id, type: '设备通信', title: '安全帽告警', status: '处理中', snapshot: {}, timeline: [], permissions: {} });
  for (const page of ['alarms/AlarmsView.vue', 'event/EventView.vue']) {
    const html = await render(page, f);
    assert.match(html, /data-component="VideoFrame"/, page);
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

test('设备录像查询使用实际功能与领用上下文，不受旧遥测动作列表误禁；离线、无权限与重复点击不下发', async () => {
  const f = fixture('H'), tick = Vue.ref(0), watchers = [], sent = [];
  let resolveCommand;
  const raw = await readFile(new URL('../src/views/materials/DeviceRecordings.vue', import.meta.url), 'utf8');
  const { descriptor } = parse(raw);
  const code = compileScript(descriptor, { id: 'recordings-contract' }).content;
  const modules = {
    '@/lib/work-business': workBusiness,
    vue: { ...Vue, onUnmounted() {}, watch(selector, callback, options) { watchers.push(callback); if (options?.immediate) callback(); } },
    '@/mock/runtime': { db: f.db, tick, connection: Vue.ref({ status: 'online' }) }, '@/lib/auth': { authFetch() { assert.fail('test must never access a backend'); } },
    '@/lib/location': { beijingDate: () => '2026-10-27' }, '@/lib/date-time': dateTime, '@/lib/person-equipment': equipment, '@/lib/device-telemetry': telemetry,
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
  await instance.send('list_recordings', {}); assert.equal(sent.length, 0, 'unavailable recording stays disabled');
  Object.assign(f.device.featureStates.recording, { verified: false, available: true, integrationStatus: 'CONNECTED', reason: '' });
  Object.assign(f.db.state.personEquipmentContext.P1.features.recording, { verified: false, available: true, integrationStatus: 'CONNECTED', reason: '' });
  f.device.capabilities = ['battery','wear','location','alarm','sos','intercom','tts','video']; tick.value++;
  assert.equal(instance.enabled('list_recordings'),true,'server-authorized file query is not a legacy telemetry capability');
  assert.equal(instance.enabled('upload_recording'),true);
  await instance.send('set_config', {}); assert.equal(sent.length,0,'file controls cannot dispatch other device commands');
  const pending = instance.send('list_recordings', { startTime: '2026-10-27 00:00:00', endTime: '2026-10-27 23:59:59' });
  await instance.send('list_recordings', {}); assert.equal(sent.length, 1, 'pending command cannot be duplicated');
  assert.deepEqual(sent[0][5], { personId: 'P1', deviceId: f.device.id, assignmentId: 'assignment-1', assignmentVersion: 1 });
  f.db.state.personEquipmentContext.P1.features.recording.assignmentVersion = 2; tick.value++; watchers[0]();
  resolveCommand({ status: 'sent' }); await pending;
  assert.equal(instance.notice.value, '', 'late result from old assignment is discarded');
  f.device.online = false; tick.value++;
  await instance.send('upload_recording', { files: ['clip.mp4'] }); assert.equal(sent.length, 1, 'offline device cannot upload');
  assert.equal(instance.unavailable.value,'设备离线');
  f.device.online = true;
  Object.assign(f.db.state.personEquipmentContext.P1.features.recording,{available:false,reason:'没有录像操作权限'});tick.value++;
  await instance.send('list_recordings',{});assert.equal(sent.length,1,'permission denial must still block a real command');
  assert.equal(instance.unavailable.value,'没有录像操作权限');
});

test('真实单路页面以调度通信查看会话，不以演示参与者冒充实际通话状态', async () => {
  const f=fixture('H',false);
  const html=await render('single/SingleView.vue',f);
  assert.match(html,/联系现场人员/);
  assert.doesNotMatch(html,/参与者|等待接听|待接入|未发起通话/);
  const button=[...html.matchAll(/<button([^>]*)>([\s\S]*?)<\/button>/g)].find(match=>match[2].includes('前往语音通话'));
  assert.ok(button);
  assert.doesNotMatch(button[1],/disabled/,'导航到调度查看已有会话不需要设备在线；实际呼叫由调度页核验');
});
