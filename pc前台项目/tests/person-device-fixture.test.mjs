import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import config from '../vite.person-device-qa.config.mjs';
import { fixtureState, SCENARIOS } from './fixtures/person-device-data.mjs';
import { createStore } from '../src/mock/data.js';
import { personFeature } from '../src/lib/person-equipment.js';
import { allowFixtureFenceCommit } from './fixtures/person-device-writes.mjs';

test('隔离夹具各场景使用真实能力计算，不产生额外人员、实机编号或存储连接', () => {
  const db = createStore(null, { demoMode: false });
  for (const [scenario] of SCENARIOS) {
    const state = fixtureState(scenario);
    assert.equal(state.people.length, scenario === 'video_many' ? 20 : scenario === 'works_many' ? 13 : 1);
    assert.ok(state.devices.every(device => device.id.startsWith('QA-') || device.id === 'RL-W001' && device.source === 'DEMO_WATCH'));
    assert.deepEqual(state.broadcasts, []);
    assert.doesNotMatch(JSON.stringify(state), /866652021714127|866652023095053/);
    assert.equal(db.replaceRemote(state), true);
    assert.equal(personFeature(db, 'QA-PERSON', 'video').supported, !['belt','unassigned'].includes(scenario));
    if (scenario === 'offline') assert.equal(personFeature(db, 'QA-PERSON', 'video').reason, '设备离线');
    if (scenario === 'revoked') {
      assert.equal(personFeature(db, 'QA-PERSON', 'video').verified, true);
      assert.equal(personFeature(db, 'QA-PERSON', 'video').available, false);
      assert.equal(personFeature(db, 'QA-PERSON', 'video').reason, '无操作权限');
    }
    if (scenario === 'unassigned') {
      assert.equal(db.currentDevices('QA-PERSON').length, 0);
      assert.equal(db.state.events[0].personId, '');
    }
    if (scenario.startsWith('watch_')) {
      assert.equal(db.currentDevices('QA-PERSON').filter(device => device.type !== 'W').length, 2);
      assert.equal(db.state.devices.some(device => device.id === 'RL-W001'), scenario === 'watch_visible');
      assert.equal(db.state.vitals.length, scenario === 'watch_visible' ? 1 : 0);
    }
  }
  assert.throws(() => fixtureState('real-device'), /Unknown isolated scenario/);
});

test('非空作业夹具支持13条分页、状态筛选和正确人员联系上下文，能力只存在隔离数据中', () => {
  const db = createStore(null, { demoMode: false });
  const state = fixtureState('works_many');
  assert.equal(db.replaceRemote(state), true);
  assert.equal(state.works.length, 13);
  assert.equal(new Set(state.works.map(work => work.date)).size, 1);
  assert.deepEqual(['监护中','已结束'].map(status => state.works.filter(work => work.status === status).length), [10,3]);
  assert.ok(state.events.every(event => state.devices.some(device => device.id === event.deviceId)));
  for (const work of state.works) {
    const person = db.person(work.members[0]);
    assert.equal(person.workId, work.status === '监护中' ? work.id : '');
    assert.equal(db.currentWork(person.id)?.id, work.status === '监护中' ? work.id : undefined);
    assert.equal(personFeature(db, person.id, 'voice').available, true);
    assert.equal(personFeature(db, person.id, 'voice').deviceId, db.currentDevices(person.id)[0].id);
    assert.deepEqual(work.timeline, []);
    assert.deepEqual(work.risks, []);
  }
  assert.equal(fixtureState('helmet').devices[0].featureStates.voice.verified, false);
});

test('地理围栏在隔离内存完成新增、停启和归档，旧示意不能启用且刷新还原', () => {
  const db = createStore(null, { demoMode: false });
  db.replaceRemote(fixtureState('fences'));
  db.setRemoteCommit(next => allowFixtureFenceCommit(db.state, next, 'fences'));
  const points = [[117.087,36.654],[117.088,36.654],[117.088,36.655],[117.087,36.655]];
  const id = db.saveFence(null, {name:'隔离新围栏',points,coordinateSystem:'GCJ02',members:['QA-PERSON'],enabled:true,station:'S1'});
  assert.deepEqual(db.state.fences.find(f => f.id === id).points,points);
  db.toggleFence(id,false);
  assert.equal(db.state.fences.find(f => f.id === id).enabled,false);
  db.toggleFence(id,true);
  assert.equal(db.state.fences.find(f => f.id === id).enabled,true);
  const before=JSON.stringify(db.state);
  assert.throws(()=>db.toggleFence('QA-FENCE-LEGACY',true),/旧版示意坐标/);
  assert.equal(JSON.stringify(db.state),before);
  db.deleteFence(id);
  assert.equal(db.state.fences.find(f => f.id === id).archived,true);
  db.deleteFence('QA-FENCE-LEGACY');
  assert.equal(db.state.fences.find(f => f.id === 'QA-FENCE-LEGACY').archived,true);
  assert.deepEqual(db.state.fenceRecords,[]);
  db.replaceRemote(fixtureState('fences'));
  assert.equal(db.state.fences.length,2);
  assert.equal(db.state.fences.some(f => f.id === id),false);
});

test('围栏内存门禁拒绝其他场景、其他业务及伪装成围栏操作的跨范围写入', () => {
  const db=createStore(null,{demoMode:false});db.replaceRemote(fixtureState('fences'));
  const before=structuredClone(db.state),next=structuredClone(db.state);
  next.audit.push({text:'保存电子围栏'});
  assert.throws(()=>allowFixtureFenceCommit(before,next,'helmet'),/不允许/);
  next.people[0].name='不应修改的人员';
  assert.throws(()=>allowFixtureFenceCommit(before,next,'fences'),/只允许围栏/);
  next.people[0].name=before.people[0].name;next.audit.at(-1).text='发起单呼';
  assert.throws(()=>allowFixtureFenceCommit(before,next,'fences'),/未允许/);
});

test('多镜头夹具有二十个独立人员领用上下文及两个真实筛选集合，仍只存在隔离内存', () => {
  const db = createStore(null, { demoMode: false });
  const state = fixtureState('video_many');
  assert.equal(db.replaceRemote(state), true);
  assert.equal(new Set(state.devices.map(device => device.id)).size, 20);
  assert.equal(new Set(state.bindings.map(binding => binding.assignmentId)).size, 20);
  assert.deepEqual(state.works.map(work => work.members.length), [10, 10]);
  for (const person of state.people) {
    const video = personFeature(db, person.id, 'video');
    assert.equal(video.available, true);
    assert.equal(video.deviceId, db.currentDevices(person.id)[0].id);
    assert.equal(db.currentWork(person.id).id, person.workId);
  }
});

test('隔离 Vite 无 API 代理且替换别名及相对路径的运行时和认证模块', () => {
  assert.equal(config.server.host, '127.0.0.1');
  assert.equal(config.server.port, 5194);
  assert.equal(config.server.strictPort, true);
  assert.deepEqual(config.server.proxy, {});
  assert.match(config.cacheDir, /\.vite-person-device-qa$/);
  const resolve = config.plugins[0].resolveId;
  const source = fileURLToPath(new URL('../src/lib/actions.js', import.meta.url));
  assert.match(resolve('@/mock/runtime', source), /person-device-runtime\.js$/);
  assert.match(resolve('./auth', source), /person-device-auth\.js$/);
  assert.match(resolve(path.join(path.dirname(source), 'auth.js'), source), /person-device-auth\.js$/);
  assert.match(resolve('@/stores/session', source), /person-device-session\.js$/);
  assert.equal(resolve('./person-equipment', source), undefined);
});

test('隔离服务对 API 请求返回 503，并用 CSP 限制外部连接和媒体', () => {
  let middleware;
  config.plugins[0].configureServer({ middlewares: { use(fn) { middleware = fn; } } });
  const headers = {}, response = { setHeader(name,value) { headers[name] = value; }, end(body) { this.body = body; } };
  middleware({ url: '/api/guardian/v1/devices/QA/commands' }, response, () => assert.fail('API must not reach middleware or a proxy'));
  assert.equal(response.statusCode, 503);
  assert.match(response.body, /backend requests are disabled/);
  assert.match(headers['Content-Security-Policy'], /connect-src 'self' ws:\/\/127\.0\.0\.1:5194/);
  assert.match(headers['Content-Security-Policy'], /media-src 'none'/);
  assert.doesNotMatch(headers['Content-Security-Policy'], /18084|https:/);
});
