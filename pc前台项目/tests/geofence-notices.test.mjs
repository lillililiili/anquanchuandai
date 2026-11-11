import test from 'node:test';
import assert from 'node:assert/strict';
import { createGeofenceNoticeTracker } from '../src/lib/geofence-notices.js';
import { eventSource } from '../src/lib/work-business.js';
import { readFile } from 'node:fs/promises';
import { parse } from '@vue/compiler-sfc';
import { effectScope, nextTick, reactive, ref, watch } from 'vue';

const alarm = (id, changes = {}) => ({ id, station: 'S1', type: '电子围栏', source: 'PLATFORM_GEOFENCE',
  protocol: 'platform-geofence', status: '待认领', occurredAt: '2026-11-09T12:00:10Z', ...changes });
function fixture() {
  const tracker = createGeofenceNoticeTracker();
  return { tracker, update: (events, changes = {}) => tracker.update({ accountId: 'duty', station: 'S1', online: true, events, ...changes }) };
}
test('initial history stays in the list; new enter and leave alarms each trigger one notice', () => {
  const { tracker, update } = fixture();
  const previous = alarm('old'), enter = alarm('enter', { fenceDirection: '进入' }), leave = alarm('leave', { fenceDirection: '离开', occurredAt: '2026-11-09T12:00:20Z' });
  assert.deepEqual(update([previous]), []);
  assert.deepEqual(update([enter, previous]).map(e => e.id), ['enter']);
  assert.deepEqual(update([leave, enter, previous]).map(e => e.id), ['leave', 'enter']);
  tracker.dismiss('enter');
  assert.deepEqual(update([leave, enter, previous]).map(e => e.id), ['leave']);
  tracker.dismissAll();
  assert.deepEqual(update([leave, { ...enter, version: 2 }, previous]), []);
});
test('offline caches do not establish a baseline; reconnect delivers each new alarm once', () => {
  const { update, tracker } = fixture();
  assert.deepEqual(update([], { online: false }), []);
  assert.deepEqual(update([alarm('historical')]), []);
  assert.deepEqual(update([alarm('during-outage')], { online: false }), []);
  assert.deepEqual(update([alarm('during-outage'), alarm('historical')]).map(e => e.id), ['during-outage']);
  tracker.dismissAll();
  assert.deepEqual(update([alarm('during-outage'), alarm('historical')]), []);
});
test('account and station switches clear pending notices and baseline the new authorized history', () => {
  const { update } = fixture(); update([]); update([alarm('first')]);
  assert.deepEqual(update([alarm('second')], { accountId: 'another' }), []);
  assert.deepEqual(update([alarm('site-two', { station: 'S2' })], { accountId: 'another', station: 'S2' }), []);
  assert.deepEqual(update([alarm('new-site-two', { station: 'S2' }), alarm('elsewhere')], { accountId: 'another', station: 'S2' }).map(e => e.id), ['new-site-two']);
  assert.deepEqual(update([], { accountId: '' }), []);
});
test('resolved, removed and unrelated events cannot remain as fence notices', () => {
  const { update } = fixture(); update([]);
  assert.deepEqual(update([alarm('fence'), alarm('device', { source: 'device' }), alarm('sos', { type: '人员求助' })]).map(e => e.id), ['fence']);
  assert.deepEqual(update([alarm('fence', { status: '已核验' })]), []);
  assert.deepEqual(update([alarm('revoked')]).map(e => e.id), ['revoked']);
  assert.deepEqual(update([]), []);
  assert.deepEqual(update([alarm('revoked')]), [], 'restored visibility must not repeat an already seen alarm');
});
test('fence alarm source remains platform geofence even when location came from a belt or helmet', () => {
  for (const source of ['DIRECT_BELT', 'DIRECT_HELMET']) assert.equal(eventSource(alarm('fence'), { source }), '平台电子围栏');
});

test('the mounted notice controller reacts to snapshots, opens event details and clears on logout', async () => {
  const raw = await readFile(new URL('../src/components/layout/GeofenceNotices.vue', import.meta.url), 'utf8');
  const body = parse(raw).descriptor.scriptSetup.content.replace(/^import\s+[\s\S]*?\s+from\s+['"][^'"]+['"];?\s*$/gm, '');
  const tick = ref(0), connection = ref({ status: 'online' }), session = reactive({ station: 'S1', filters: {} });
  const db = { state: { operator: { id: 'duty' }, events: [] } }, routes = [], scope = effectScope();
  let logout, cleanup, closed = 0;
  const bindings = { onUnmounted: callback => { cleanup = callback; }, ref, watch, useRouter: () => ({ push: path => routes.push(path) }),
    db, tick, connection, session, closeModal: () => closed++, onAuthCleared: callback => { logout = callback; return () => { logout = null; }; }, createGeofenceNoticeTracker };
  const view = scope.run(() => new Function(...Object.keys(bindings), body + '\nreturn { notices, open, openAll };')(...Object.values(bindings)));
  try {
    db.state.events = [alarm('new')]; tick.value++; await nextTick();
    assert.equal(view.notices.value[0].id, 'new');
    view.open(view.notices.value[0]);
    assert.deepEqual(routes, ['/event/new']); assert.equal(closed, 1); assert.equal(view.notices.value.length, 0);
    view.openAll(); assert.equal(session.filters.alarms.type, '电子围栏'); assert.equal(routes.at(-1), '/alarms');
    db.state.events.unshift(alarm('second')); tick.value++; await nextTick();
    assert.equal(view.notices.value[0].id, 'second'); logout(); assert.deepEqual(view.notices.value, []);
    cleanup(); assert.equal(logout, null);
  } finally { scope.stop(); }
});
