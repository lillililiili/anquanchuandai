import test from 'node:test';
import assert from 'node:assert/strict';
import { fitNavigation, navigationItems, navigationOwner, pageFamily } from '../src/components/layout/navigation.js';

test('detail routes keep their parent navigation highlighted', () => {
  for (const [detail, parent] of Object.entries({ person:'personnel', work:'works', single:'video', tracks:'location', fences:'location', event:'alarms', sos:'dispatch' })) assert.equal(navigationOwner(detail), parent);
  for (const { id } of navigationItems) assert.equal(navigationOwner(id), id);
});
test('wide navigation exposes all routes without reserving unnecessary More space', () => {
  assert.deepEqual(fitNavigation(Array(9).fill(120), 492, 616, 90), { visibleCount:9, leftCount:4 });
});
test('overflow reserves the More control and removes only the trailing suffix', () => {
  assert.deepEqual(fitNavigation(Array(9).fill(120), 500, 350, 90), { visibleCount:6, leftCount:4 });
  assert.deepEqual(fitNavigation(Array(9).fill(120), 370, 350, 90), { visibleCount:5, leftCount:3 });
  assert.deepEqual(fitNavigation(Array(9).fill(120), 100, 100, 90), { visibleCount:0, leftCount:0 });
});

test('utility icons reduce both slots without leaving the right side unused', () => {
  const widths = Array(9).fill(108);
  const layout = fitNavigation(widths, 347, 347, 86);
  assert.deepEqual(layout, { visibleCount:5, leftCount:3 });
  const left = navigationItems.slice(0, layout.leftCount);
  const right = navigationItems.slice(layout.leftCount, layout.visibleCount);
  const more = navigationItems.slice(layout.visibleCount);
  assert.deepEqual([...left, ...right, ...more], navigationItems);
  assert.equal(navigationOwner('tracks'), more.find(item => item.id === 'location').id);
});
test('font-load size changes recompute the fit and restoring the width restores every route', () => {
  assert.equal(fitNavigation(Array(9).fill(90), 500, 500, 90).visibleCount, 9);
  assert.deepEqual(fitNavigation(Array(9).fill(130), 500, 500, 90), { visibleCount:6, leftCount:3 });
  assert.equal(fitNavigation(Array(9).fill(130), 600, 700, 90).visibleCount, 9);
});
test('page-specific visual families do not change route names or control contracts', () => {
  assert.equal(pageFamily('personnel'), 'list'); assert.equal(pageFamily('event'), 'detail');
  assert.equal(pageFamily('screen'), 'sentinel'); assert.equal(pageFamily('overview'), 'monitor');
});
