import assert from "node:assert/strict";
import test from "node:test";
import { areaOccupancy, displayedAreas, pointInArea } from "../src/components/domain/map-areas.js";
import { createStore } from "../src/mock/data.js";

const square = [[10, 10], [40, 10], [40, 40], [10, 40]];
const area = { id: "A", station: "S1", name: "新区域名称", points: square };
const person = (id, position, extra = {}) => ({ id, station: "S1", active: true, area: "过时的区域名称", position, ...extra });

test("区域统计使用坐标而非区域名称，排除其他厂站、停用与无效定位并按人员去重", () => {
  const state = { mapAreas: [area], people: [
    person("inside", [20, 20]), person("inside", [20, 20]),
    person("edge", [40, 20]), person("outside", [50, 50]),
    person("stale", [20, 20]), person("missing", null), person("bad", [NaN, 20]),
    person("disabled", [20, 20], { active: false }), person("other", [20, 20], { station: "S2" }),
  ] };
  const result = areaOccupancy(state, "S1", (id) => id !== "stale");
  assert.deepEqual(result.areas[0].personIds, ["inside", "edge"]);
  assert.deepEqual([result.total, result.inside, result.outside, result.unverified], [6, 2, 1, 3]);
  assert.equal(result.inside + result.outside + result.unverified, result.total);
});

test("多边形边界和顶点计入，凹多边形缺口不计入", () => {
  for (const point of [[10, 10], [40, 40], [10, 25], [25, 10], [25, 40], [40, 25]]) assert.equal(pointInArea(point, square), true);
  assert.equal(pointInArea([40.001, 25], square), false);
  const concave = [[10, 10], [40, 10], [40, 20], [20, 20], [20, 40], [10, 40]];
  assert.equal(pointInArea([30, 30], concave), false);
  assert.equal(pointInArea([15, 30], concave), true);
  assert.equal(pointInArea([20, 30], concave), true);
});

test("区域重叠时各区域独立计数，总人数不重复", () => {
  const result = areaOccupancy({ mapAreas: [area, { ...area, id: "B" }], people: [person("P1", [20, 20])] }, "S1", () => true);
  assert.deepEqual(result.areas.map((item) => item.personIds.length), [1, 1]);
  assert.equal(result.inside, 1);
  assert.equal(result.overlapping, 1);
});

test("后台区域清空、禁用、删除、跨厂站及非法边界不会恢复示例区域", () => {
  const state = { stations: [{ id: "S1" }], people: [person("P1", [20, 20])], mapAreas: [] };
  assert.equal(displayedAreas(state, "S1").length, 0);
  assert.equal(areaOccupancy(state, "S1", () => true).outside, 1);
  state.mapAreas = [
    { ...area, enabled: false }, { ...area, archived: true }, { ...area, station: "S2" },
    { ...area, points: [[10, 10], [20, 20], [30, 30]] }, { ...area, points: [[10, 10], [20, "20"], [30, 10]] },
  ];
  assert.equal(displayedAreas(state, "S1").length, 0);
  delete state.mapAreas;
  assert.equal(displayedAreas(state, "S1").length, 4);
  assert.equal(displayedAreas(state, "S2").length, 0);
});

test("现有人员坐标与区域名称不符时按地图实际位置统计，设备离线后移入待核验", () => {
  const db = createStore(null);
  const summary = () => areaOccupancy(db.state, "S1", (id) => db.locationValid(id));
  const result = summary();
  assert.deepEqual(Object.fromEntries(result.areas.map((item) => [item.name, item.personIds.length])), { 锅炉区: 2, 配电区: 1, 汽机厂房: 0, 循环水区: 1 });
  assert.deepEqual([result.inside, result.outside, result.unverified], [4, 3, 1]);
  db.person("P2").position = [35, 35];
  assert.equal(summary().areas.find((item) => item.name === "锅炉区").personIds.length, 3);
  db.device("RL-H002").online = false;
  assert.equal(summary().unverified, 2);
  db.state.mapAreas = [{ ...area, points: [[0, 0], [100, 0], [100, 100], [0, 100]] }];
  assert.equal(summary().areas[0].personIds.length, 6);
});
