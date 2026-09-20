import { test } from 'node:test';
import assert from 'node:assert/strict';
import { availableRoutes } from '../src/utils/availableRoutes.js';

test('missing views and empty groups are removed without changing source menus', () => {
  const routes = [{ path: '/system', component: 'Layout', children: [
    { path: 'dept', component: 'system/dept/index' },
    { path: 'log', component: 'ParentView', children: [{ path: 'operlog', component: 'monitor/operlog/index' }] }
  ] }, { path: '/tool', component: 'Layout', children: [{ path: 'gen', component: 'tool/gen/index' }] }];
  const result = availableRoutes(routes, new Set(['system/dept/index']));
  assert.equal(result.length, 1);
  assert.deepEqual(result[0].children.map(x => x.path), ['dept']);
  assert.equal(routes[0].children.length, 2);
});
test('external links and available hidden permission routes are preserved', () => {
  const routes = [{ path: 'https://example.com', component: 'Layout' },
    { path: '/edit', component: 'system/user/index', hidden: true, permissions: ['system:user:edit'] }];
  assert.deepEqual(availableRoutes(routes, new Set(['system/user/index'])), routes);
});
test('missing menu response is handled', () => {
  assert.deepEqual(availableRoutes(null, new Set()), []);
});
