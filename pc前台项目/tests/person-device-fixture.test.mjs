import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import config from '../vite.person-device-qa.config.mjs';
import { fixtureState, SCENARIOS } from './fixtures/person-device-data.mjs';
import { createStore } from '../src/mock/data.js';
import { personFeature } from '../src/lib/person-equipment.js';

test('隔离夹具各场景使用真实能力计算，不产生额外人员、实机编号或存储连接', () => {
  const db = createStore(null, { demoMode: false });
  for (const [scenario] of SCENARIOS) {
    const state = fixtureState(scenario);
    assert.equal(state.people.length, 1);
    assert.ok(state.devices.every(device => device.id.startsWith('QA-')));
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
  }
  assert.throws(() => fixtureState('real-device'), /Unknown isolated scenario/);
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
