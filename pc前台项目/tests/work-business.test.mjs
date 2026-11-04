import test from 'node:test';
import assert from 'node:assert/strict';
import { createStore } from '../src/mock/data.js';
import { fixtureState } from './fixtures/person-device-data.mjs';
import { workBusinessEnabled, currentWorkFor, workPeriod, workOnDate, workStatus, workSource, eventSource, clearWorkSelection, withoutWorkQuery } from '../src/lib/work-business.js';
import { statisticsView } from '../src/views/statistics/statistics-model.js';

test('业务配置未确认时不显示作业；版本更旧的配置及快照不能重新开启', () => {
  const db = createStore(null);
  assert.equal(workBusinessEnabled(db), false);
  const first = fixtureState('helmet');
  assert.equal(db.replaceRemote(first), true);
  assert.equal(workBusinessEnabled(db), true);
  assert.equal(db.applyBusinessConfig({ workBusinessEnabled: false, version: 2, simulatedWatchVisible: false }), true);
  assert.equal(db.applyBusinessConfig({ workBusinessEnabled: true, version: 1 }), false);
  assert.equal(db.replaceRemote(structuredClone(first)), false);
  assert.equal(workBusinessEnabled(db), false);
  assert.equal(db.applyBusinessConfig({ workBusinessEnabled: 'true', version: 3 }), false);
  assert.equal(db.applyBusinessConfig({ workBusinessEnabled: true, version: 3 }), true);
  assert.equal(workBusinessEnabled(db), true);
});

test('关闭后旧作业筛选不能筛空人员、装备、事件，历史关联仍保存在原记录', () => {
  const db = createStore(null), state = fixtureState('helmet');
  state.businessConfig.workBusinessEnabled = false;
  db.replaceRemote(state);
  assert.equal(db.work('QA-WORK'), null);
  assert.equal(db.currentWork('QA-PERSON'), undefined);
  const stats = statisticsView(db, { station: 'S1', workId: '不存在的旧作业' });
  assert.equal(stats.people.length, 1);
  assert.equal(stats.devices.length, 1);
  assert.equal(stats.events.length, 1);
  assert.deepEqual(stats.works, []);
  assert.equal(db.state.events[0].workId, 'QA-WORK');
  db.applyBusinessConfig({ workBusinessEnabled: true, version: 2 });
  assert.equal(db.work('QA-WORK').id, 'QA-WORK');
});

test('跨日作业按完整时间唯一匹配，超时、重叠、人员停用及跨厂站均不匹配', () => {
  const now = Date.parse('2026-11-04T00:30:00+08:00'), state = fixtureState('helmet', new Date(now));
  const work = state.works[0];
  Object.assign(work, { source: 'LOCAL', status: '进行中', plannedStartAt: '2026-11-03T23:00:00+08:00', plannedEndAt: '2026-11-04T01:00:00+08:00' });
  assert.equal(currentWorkFor(state, 'QA-PERSON', now), work);
  assert.equal(workOnDate(work, '2026-11-03'), true);
  assert.equal(workOnDate(work, '2026-11-04'), true);
  assert.equal(workOnDate(work, '2026-11-05'), false);
  assert.equal(currentWorkFor(state, 'QA-PERSON', Date.parse(work.plannedEndAt)), null);
  state.works.push({ ...work, id: 'CONFLICT' });
  assert.equal(currentWorkFor(state, 'QA-PERSON', now), null);
  state.works.pop(); state.people[0].active = false;
  assert.equal(currentWorkFor(state, 'QA-PERSON', now), null);
  state.people[0].active = true; state.people[0].station = 'S2';
  assert.equal(currentWorkFor(state, 'QA-PERSON', now), null);
  state.people[0].station = 'S1'; work.status = '待开始';
  assert.equal(currentWorkFor(state, 'QA-PERSON', now), null);
  work.status = '进行中'; work.supervisor = 'MISSING';
  assert.equal(currentWorkFor(state, 'QA-PERSON', now), null);
  work.supervisor = 'QA-PERSON'; work.demo = true;
  assert.equal(currentWorkFor(state, 'QA-PERSON', now), null, '已确认演示作业不因重新开启而生效');
});

test('旧日期及监护中状态兼容，本地登记和真实告警来源不冒充外部系统', () => {
  const work = { date: '2026-11-03', start: '08:00', end: '18:00', status: '监护中', source: 'LOCAL' };
  assert.deepEqual(workPeriod(work), { start: '2026-11-03T08:00:00+08:00', end: '2026-11-03T18:00:00+08:00' });
  assert.equal(workStatus(work), '进行中');
  assert.equal(workSource(work), '本地登记');
  assert.equal(eventSource({ source: 'manual_sos' }), '手机 SOS');
  assert.equal(eventSource({ protocol: 'direct-belt' }), '安全带直连');
  assert.equal(eventSource({}, { source: 'DIRECT_HELMET' }), '安全帽直连');
});

test('模式切换只清理作业选择，保留核验草稿、照片、人员、通信和媒体状态', () => {
  const session = { work: 'W1', person: 'P1', event: 'E1', personTab: '作业信息', statsTab: '任务',
    filters: { video: { workId: 'W1', deviceId: 'H1' }, personnel: { workStatus: 'assigned', q: '张' } },
    formDrafts: { E1: { situation: '现场记录', photoIds: ['PHOTO1'] } }, recording: { person: 'P1' }, volume: 50 };
  const before = structuredClone(session);
  clearWorkSelection(session);
  assert.equal(session.work, '');
  assert.equal(session.personTab, '人员信息');
  assert.equal(session.statsTab, '综合');
  assert.deepEqual(session.filters, { video: { deviceId: 'H1' }, personnel: { q: '张' } });
  for (const field of ['person','event','formDrafts','recording','volume']) assert.deepEqual(session[field], before[field]);
  assert.deepEqual(withoutWorkQuery({ workId: 'W1', taskId: 'W1', workStatus: 'assigned', tab: '任务', eventId: 'E1', personId: 'P1' }), { eventId: 'E1', personId: 'P1' });
  assert.deepEqual(withoutWorkQuery({ tab: '人员', date: '2026-11-03' }), { tab: '人员', date: '2026-11-03' });
});
