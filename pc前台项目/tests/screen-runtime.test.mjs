import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createStore, DATE } from '../src/mock/data.js';
import { workBusinessEnabled, workStatus } from '../src/lib/work-business.js';
import { beijingDate, beijingTime } from '../src/lib/location.js';
import * as model from '../src/views/screen/screen-model.js';
import { fixtureState } from './fixtures/person-device-data.mjs';

const source = (await readFile(new URL('../src/views/screen/screen-runtime.js', import.meta.url), 'utf8'))
  .replace(/^import\s+[\s\S]*?\s+from\s+['"][^'"]+['"];?\s*$/gm, '')
  .replace('export function mountScreen', 'function mountScreen');

function screen(snapshot) {
  const db = createStore(null);
  db.replaceRemote(snapshot);
  const nodes = new Map(), timers = [];
  const query = selector => {
    if (!nodes.has(selector)) nodes.set(selector, { style: { setProperty() {} }, dataset: {}, attributes: {}, setAttribute(key, value) { this.attributes[key] = value; }, animate() {} });
    return nodes.get(selector);
  };
  const root = { innerHTML: '', querySelector: () => ({ querySelector: query }) };
  let time = 0, videos = [];
  const bindings = {
    workBusinessEnabled, workStatus, iconMarkup: () => '', DATE, beijingDate, beijingTime,
    db, events: () => db.state.events,
    stationPeople: () => db.state.people, scope: () => ({ station: 'S1' }),
    session: { station: 'S1' }, testSiteName: () => '测试厂站', ...model,
    performance: { now: () => time },
    document: { hidden: false, addEventListener() {}, removeEventListener() {} },
    window: { addEventListener() {}, removeEventListener() {} }, matchMedia: () => ({ matches: true }),
    innerWidth: 1920, innerHeight: 1080,
    setInterval: (fn, ms) => timers.push({ fn, ms }), clearInterval() {},
  };
  const mount = new Function(...Object.keys(bindings), source + '\nreturn mountScreen;')(...Object.values(bindings));
  mount(root, { onVideos: value => { videos = value; } });
  return {
    db, query, root, videos: () => videos,
    refresh(next) { db.replaceRemote(next); timers.find(timer => timer.ms === model.INTERVALS.refresh).fn(); },
    nextPerson() { time += model.INTERVALS.person; timers.find(timer => timer.ms === 250).fn(); },
    nextVideo() { time += model.INTERVALS.video; timers.find(timer => timer.ms === 250).fn(); },
  };
}

test('关闭手表时原面板切为人员装备监护和告警趋势，不依赖作业开关', () => {
  const snapshot = fixtureState('helmet');
  snapshot.businessConfig.workBusinessEnabled = false;
  const view = screen(snapshot);
  assert.notEqual(view.query('.screen-vitals').style.display, 'none');
  assert.notEqual(view.query('.screen-trend').style.display, 'none');
  assert.equal(view.query('[data-watch-vitals]').hidden, true);
  assert.equal(view.query('[data-watch-trend]').hidden, true);
  assert.equal(view.query('[data-screen-equipment-monitor]').hidden, false);
  assert.equal(view.query('[data-screen-event-activity]').hidden, false);
  assert.match(view.query('[data-screen-equipment-monitor]').innerHTML, /人员装备监护/);
  assert.match(view.query('[data-screen-equipment-monitor]').innerHTML, /QA-HELMET-ISOLATED-000001/);
  assert.match(view.query('[data-screen-event-activity]').innerHTML, /近24小时告警趋势/);
  assert.doesNotMatch(view.query('.screen-stats').innerHTML, /台账作业/);
});

test('关闭手表切换为装备内容，重新开启后恢复当前体征与心率', () => {
  const view = screen(fixtureState('watch_visible'));
  assert.equal(view.query('[data-metric="0"]').textContent, '75');
  view.refresh(fixtureState('watch_hidden'));
  assert.equal(view.query('[data-watch-vitals]').hidden, true);
  assert.equal(view.query('[data-watch-trend]').hidden, true);
  const real = fixtureState('watch_hidden');
  const watch = real.devices.find(device => device.type === 'W');
  Object.assign(watch, { source: 'PLATFORM', sourceTime: new Date().toISOString(), freshness: 'CURRENT' });
  real.vitals[0].source = 'PLATFORM';
  view.refresh(real);
  assert.equal(view.query('[data-screen-equipment-monitor]').hidden, false);
  assert.equal(view.query('[data-watch-vitals]').hidden, true);
  real.businessConfig.simulatedWatchVisible = true;
  view.refresh(real);
  assert.equal(view.query('[data-metric="0"]').textContent, '75');
  assert.equal(view.query('[data-person-status]').textContent, '正常');
  assert.equal(view.query('[data-watch-vitals]').hidden, false);
  assert.equal(view.query('[data-screen-equipment-monitor]').hidden, true);
  assert.equal(view.query('[data-screen-event-activity]').hidden, true);
  assert.notEqual(view.query('.screen-vitals').style.display, 'none');
});

test('开启手表但尚未领用时保留原生命体征空态，关闭后轮播全部在册人员', () => {
  const snapshot = fixtureState('helmet');
  snapshot.businessConfig.simulatedWatchVisible = true;
  const view = screen(snapshot);
  assert.equal(view.query('[data-watch-vitals]').hidden, false);
  assert.equal(view.query('[data-screen-person]').textContent, '暂无手表体征数据');
  snapshot.businessConfig.simulatedWatchVisible = false;
  snapshot.people.push({ ...snapshot.people[0], id: 'P2', name: '未领用人员' });
  view.refresh(snapshot); view.nextPerson();
  const html = view.query('[data-screen-equipment-monitor]').innerHTML;
  assert.match(html, /未领用人员/);
  assert.doesNotMatch(html, /QA-HELMET-ISOLATED-000001/);
  assert.match(html, /未领用/);
  snapshot.people = []; snapshot.events = [];
  view.refresh(snapshot);
  assert.match(view.query('[data-screen-equipment-monitor]').innerHTML, /暂无在册人员/);
  assert.match(view.query('[data-screen-event-activity]').innerHTML, /近24小时告警趋势/);
  assert.doesNotMatch(view.query('[data-screen-event-activity]').innerHTML, /：[1-9]\d* 项/);
});

test('总数只在顶部汇总，装备和事件面板保留各自明细与变化', () => {
  const snapshot = fixtureState('both');
  snapshot.businessConfig.workBusinessEnabled = false;
  snapshot.people[0].team = '';
  snapshot.events = Array.from({ length: 188 }, (_, index) => ({ ...snapshot.events[0], id: `QA-EVENT-${index}` }));
  const view = screen(snapshot);
  assert.match(view.query('.screen-stats').innerHTML, /188/);
  assert.doesNotMatch(view.root.innerHTML, /screen-event-summary/);
  const equipment = view.query('[data-equipment]').innerHTML;
  assert.doesNotMatch(equipment, /<table|佩戴状态|电量&lt;20%|信号/);
  const monitor = view.query('[data-screen-equipment-monitor]').innerHTML;
  assert.match(monitor, /电量/);
  assert.match(monitor, /双钩状态/);
  assert.doesNotMatch(monitor, /关联待核验事件|188|>在线<|未分配班组|1 \/ 1/);
  assert.doesNotMatch(view.query('[data-platform-summary]').textContent, /共\s*2\s*台|在线\s*2/);
  view.refresh(fixtureState('offline'));
  assert.match(view.query('[data-screen-equipment-monitor]').innerHTML, /离线/);
  assert.match(view.query('[data-equipment]').innerHTML, /离线 1/);
});

test('零路、单路和多路视频按实际数量排布，翻页不会改变地图布局', () => {
  const view = screen(fixtureState('belt'));
  assert.equal(view.videos().length, 0);
  assert.notEqual(view.query('.screen-videos').style.display, 'none');
  assert.equal(view.query('.screen').dataset.videoCount, '0');
  view.refresh(fixtureState('helmet'));
  assert.equal(view.videos().length, 1);
  assert.equal(view.query('.screen').dataset.videoCount, '1');
  assert.equal(view.query('[data-screen-videos]').style.gridTemplateColumns, 'repeat(1, minmax(0, 1fr))');
  view.refresh(fixtureState('video_many'));
  assert.equal(view.query('.screen').dataset.videoCount, '3');
  for (let i = 0; i < 6; i++) view.nextVideo();
  assert.equal(view.videos().length, 2);
  assert.equal(view.query('[data-screen-videos]').style.gridTemplateColumns, 'repeat(2, minmax(0, 1fr))');
  assert.equal(view.query('.screen').dataset.videoCount, '3');
  assert.equal(view.query('[data-video-page]').textContent, '20 路 · 7 / 7 页');
});
