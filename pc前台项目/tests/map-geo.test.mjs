import assert from "node:assert/strict";
import test from "node:test";
import { PLANT_CENTER, clampPercent, lonLatToPercent, percentToLonLat } from "../src/components/domain/map-geo.js";

test("示意百分比投影到阳城电厂中心并可还原", () => {
  const center = percentToLonLat([50, 50]);
  assert.equal(center[0], PLANT_CENTER[0]);
  assert.equal(center[1], PLANT_CENTER[1]);
  for (const point of [
    [0, 0],
    [8, 8],
    [35, 45],
    [50, 50],
    [100, 100],
  ]) {
    const back = lonLatToPercent(percentToLonLat(point));
    assert.ok(Math.abs(back[0] - point[0]) < 1e-6);
    assert.ok(Math.abs(back[1] - point[1]) < 1e-6);
  }
  assert.deepEqual(clampPercent([-4, 120]), [0, 100]);
});
