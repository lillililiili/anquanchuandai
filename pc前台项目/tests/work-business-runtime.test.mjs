import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { ref } from 'vue';
import { createStore } from '../src/mock/data.js';
import { fixtureState } from './fixtures/person-device-data.mjs';
import { workBusinessEnabled, workStatus, withoutWorkQuery } from '../src/lib/work-business.js';

const flush = async () => { for (let i = 0; i < 12; i++) await Promise.resolve(); };

test('运行时每5秒及恢复前台读取统一配置，过期快照不能复活开关，跨登录响应被丢弃', async () => {
  const source = (await readFile(new URL('../src/mock/runtime.js', import.meta.url), 'utf8'))
    .replace(/^import\s+[\s\S]*?\s+from\s+['"][^'"]+['"];?\s*$/gm, '')
    .replace(/\bexport\s+(?=(?:async\s+)?(?:const|function))/g, '');
  const requests = [], intervals = [], listeners = {}, authListeners = [];
  let token = 'isolated-session';
  const bindings = {
    ref, createStore, DEMO_MODE: false,
    authFetch: path => new Promise(resolve => requests.push({ path, resolve })),
    authHeaders: () => ({ 'X-Wearable-Token': token }), clearAuth() {}, onAuthCleared: callback => authListeners.push(callback),
    createEventApi: () => ({ command() {} }), createLocationApi: () => ({}), createBusinessCommands: () => () => {},
    localStorage: { getItem: () => null, setItem() {} },
    window: { setInterval: (fn, ms) => intervals.push({ fn, ms }), addEventListener: (name, fn) => listeners[name] = fn },
    document: { hidden: false, addEventListener: (name, fn) => listeners[name] = fn }, setTimeout: () => 1, clearTimeout() {},
  };
  const api = new Function(...Object.keys(bindings), source + '\nreturn {db, guardianReady, refreshBusinessConfig, refreshSnapshot};')(...Object.values(bindings));
  const initial = fixtureState('helmet');
  requests.shift().resolve({ ok: true, json: async () => ({ state: initial }) });
  await api.guardianReady;
  assert.equal(workBusinessEnabled(api.db), true);
  assert.equal(intervals[0].ms, 5000);
  intervals[0].fn();
  const config = requests.find(item => item.path.endsWith('business-config'));
  const snapshot = requests.find(item => item.path.endsWith('snapshot'));
  config.resolve({ ok: true, json: async () => ({ workBusinessEnabled: false, version: 2 }) });
  await flush();
  snapshot.resolve({ ok: true, json: async () => ({ state: structuredClone(initial) }) });
  await flush();
  assert.equal(workBusinessEnabled(api.db), false);
  assert.equal(api.db.state.businessConfig.version, 2);
  requests.length = 0;
  listeners.visibilitychange();
  assert.deepEqual(requests.map(item => item.path).sort(), ['/api/guardian/v1/business-config', '/api/guardian/v1/snapshot']);
  token = 'different-session'; authListeners.forEach(callback => callback());
  for (const request of requests) request.resolve({ ok: true, json: async () => request.path.endsWith('snapshot') ? { state: initial } : { workBusinessEnabled: true, version: 3 } });
  await flush();
  assert.equal(workBusinessEnabled(api.db), false, '先前登录的响应不能为新会话确认业务模式');
});

test('历史作业链接关闭时返回总览，开启时保留授权访问', async () => {
  const source = (await readFile(new URL('../src/router/index.js', import.meta.url), 'utf8'))
    .replace(/^import\s+[\s\S]*?\s+from\s+['"][^'"]+['"];?\s*$/gm, '').replace('export const router', 'const router');
  let guard;
  const db = { state: { businessConfig: { workBusinessEnabled: false } } };
  const bindings = { db, guardianReady: Promise.resolve(), workBusinessEnabled, closeModal() {}, createWebHashHistory() {},
    sessionStorage: { getItem: () => 'logged-in' }, createRouter: () => ({ beforeEach: fn => guard = fn, afterEach() {} }) };
  new Function(...Object.keys(bindings), source)(...Object.values(bindings));
  for (const name of ['works','work']) assert.deepEqual(await guard({ name, meta: { auth: true } }), { name: 'overview' });
  assert.equal(await guard({ name: 'event', meta: { auth: true } }), undefined);
  db.state.businessConfig.workBusinessEnabled = true;
  assert.equal(await guard({ name: 'work', meta: { auth: true } }), undefined);
});

test('首次加载配置未知时保留已存筛选，只有确认关闭才清除作业选择', async () => {
  const source = await readFile(new URL('../src/App.vue', import.meta.url), 'utf8');
  const start = source.indexOf('watchEffect(() => {');
  const body = source.slice(start, source.indexOf('\nconst bare', start));
  const db = { state: { businessConfig: {} } }, session = { work: 'LOCAL1' };
  let effect, resets = 0;
  const bindings = { db, session, tick: { value: 0 }, route: { name: 'personnel', query: {} }, router: { replace() {} },
    watchEffect: callback => effect = callback, clearWorkSelection: () => resets++, withoutWorkQuery };
  new Function(...Object.keys(bindings), body)(...Object.values(bindings));
  effect(); assert.equal(resets, 0);
  db.state.businessConfig.workBusinessEnabled = true; effect(); assert.equal(resets, 0);
  db.state.businessConfig.workBusinessEnabled = false; effect(); assert.equal(resets, 1);
});

test('驻留大屏关闭作业指标后重新排成三列，保留人员、装备和待核验事件', async () => {
  const source = await readFile(new URL('../src/views/screen/screen-runtime.js', import.meta.url), 'utf8');
  const body = source.slice(source.indexOf('  function statistics(stats)'), source.indexOf('  function trend(vital)'));
  const db = { state: { businessConfig: { workBusinessEnabled: true } } }, node = { style: {}, innerHTML: '' };
  const statistics = new Function('db', 'workBusinessEnabled', 'workStatus', 'events', 'state', 'query', 'symbols', 'equipmentPanel', body + '\nreturn statistics;')(
    db, workBusinessEnabled, workStatus, () => [], {}, () => node, {}, () => {});
  const stats = { people: [{ id: 'P1' }], assigned: 1, works: [{ status: '进行中' }], devices: [{ id: 'H1' }], online: 1, unresolved: 2 };
  statistics(stats);
  assert.match(node.innerHTML, /台账作业/);
  db.state.businessConfig.workBusinessEnabled = false; statistics(stats);
  assert.equal(node.style.gridTemplateColumns, 'repeat(3, 1fr)');
  assert.doesNotMatch(node.innerHTML, /作业|待分配/);
  assert.match(node.innerHTML, /在册人员/);
  assert.match(node.innerHTML, /真实领用装备在线/);
  assert.match(node.innerHTML, /待核验事件/);
});

test('打开中的地图人员浮层随模式隐藏作业字段，保留定位来源及人员/轨迹入口', async () => {
  const source = await readFile(new URL('../src/components/domain/PlantMap.vue', import.meta.url), 'utf8');
  const body = source.slice(source.indexOf('function renderPopup()'), source.indexOf('function renderPeople()'));
  const node = { innerHTML: '' }, person = { id: 'P1', name: '张工' };
  const db = { state: { businessConfig: { workBusinessEnabled: true } }, locationValid: () => true, locationDevice: () => ({ id: 'H1' }) };
  const bindings = { map: true, ensurePopup() {}, props: { popup: true }, visiblePeople: { value: [person] }, hoveredId: { value: 'P1' },
    positionOf: () => [117,36], popupOverlay: { getElement: () => node, setPosition() {} }, db, workBusinessEnabled, workName: () => '作业甲', esc: String, iconMarkup: () => '', projected: value => value };
  const render = new Function(...Object.keys(bindings), body + '\nreturn renderPopup;')(...Object.values(bindings));
  render(); assert.match(node.innerHTML, /作业甲/);
  db.state.businessConfig.workBusinessEnabled = false; render();
  assert.doesNotMatch(node.innerHTML, /作业/);
  assert.match(node.innerHTML, /H1/); assert.match(node.innerHTML, /历史轨迹/); assert.match(node.innerHTML, /查看人员/);
});
