import test from 'node:test';
import assert from 'node:assert/strict';
import { placeAreaLabel } from '../src/components/domain/map-labels.js';

const setup = () => ({ center: [200, 200], bounds: [100, 100, 300, 300], size: [90, 64], viewport: [600, 400], occupied: [], contains: ([x, y]) => x >= 100 && x <= 300 && y >= 100 && y <= 300 });
const overlap = ([x, y], [width, height], box) => x - width / 2 - 4 < box[2] && x + width / 2 + 4 > box[0] && y - height / 2 - 4 < box[3] && y + height / 2 + 4 > box[1];
test('空区域的人数标签保留在区域内部中心', () => {
  assert.deepEqual(placeAreaLabel(setup()), [200, 200]);
});
test('区域人数标签避让中心人员标记且仍保持在区域内', () => {
  const input = setup(); input.occupied = [[176, 176, 224, 224]];
  const result = placeAreaLabel(input);
  assert.equal(overlap(result, input.size, input.occupied[0]), false);
  assert.equal(input.contains(result), true);
});
test('狭窄区域挤满人员时标签贴近轮廓并保持完整可见', () => {
  const input = setup(); input.bounds = [150, 170, 250, 230];
  input.contains = ([x, y]) => x >= 150 && x <= 250 && y >= 170 && y <= 230;
  input.occupied = [[150, 170, 250, 230]];
  const result = placeAreaLabel(input);
  assert.equal(overlap(result, input.size, input.occupied[0]), false);
  assert.ok(result[1] - input.size[1] / 2 >= 0 && result[1] + input.size[1] / 2 <= input.viewport[1]);
});
test('后续区域标签也避让已放置的区域标签', () => {
  const input = setup(); input.occupied = [[155, 168, 245, 232], [150, 100, 250, 160]];
  const result = placeAreaLabel(input);
  assert.equal(input.occupied.some(box => overlap(result, input.size, box)), false);
});
