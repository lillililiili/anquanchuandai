const { test } = require("node:test");
const assert = require("node:assert/strict");
const D = require("../js/data.js");
const storage = () => {
  let text = null;
  return { getItem: () => text, setItem: (_, v) => (text = v) };
};
const create = () => D.createStore(storage());
test("初始数据人数、作业、装备通信与视频数量口径正确", () => {
  const d = create(),
    s = d.stats({ station: "S1", date: D.DATE });
  assert.equal(s.people.length, 8);
  assert.equal(s.devices.length, 24);
  assert.equal(s.works.length, 3);
  assert.equal(s.assigned, 7);
  assert.equal(s.online, 23);
  assert.deepEqual(s.byType, {
    H: { total: 8, online: 8 },
    B: { total: 8, online: 7 },
    W: { total: 8, online: 8 },
  });
  assert.deepEqual(s.video, { available: 6, interrupted: 1, off: 1 });
  assert.equal(d.device("RL-H004").online, true);
  assert.equal(s.unresolved, 3);
});
test("厂站、日期与作业筛选同时影响列表和汇总", () => {
  const d = create();
  for (const scope of [
    { station: "S2" },
    { date: "2026-09-16" },
    { workId: "missing" },
  ]) {
    const s = d.stats(scope);
    assert.equal(s.people.length, 0);
    assert.equal(s.devices.length, 0);
    assert.equal(s.works.length, 0);
    assert.equal(s.events.length, 0);
  }
  const s = d.stats({ station: "S1", date: D.DATE, workId: "GL-20260915-018" });
  assert.equal(s.people.length, 3);
  assert.equal(s.devices.length, 9);
  assert.equal(s.online, 8);
  assert.equal(s.events.length, 1);
});
test("核验草稿不改变统计，提交后数量、列表、时间线一致且不重复提交", () => {
  const d = create(),
    id = "RL-E-0915-001";
  d.verify(
    id,
    { conclusion: "设备通信异常", situation: "检查通信连接" },
    false,
  );
  assert.equal(d.stats().verified, 0);
  assert.equal(d.event(id).status, "待现场核验");
  const external = d.event(id).externalStatus;
  d.verify(id, { conclusion: "设备通信异常", situation: "检查通信连接" }, true);
  assert.equal(d.stats().verified, 1);
  assert.equal(d.stats().unresolved, 2);
  assert.equal(d.event(id).externalStatus, external);
  assert.match(d.event(id).timeline.at(-1).text, /已提交/);
  assert.throws(
    () => d.verify(id, { conclusion: "设备通信异常", situation: "重复" }, true),
    /已经完成/,
  );
  assert.equal(d.stats().verified, 1);
});
test("保存失败回滚内存状态，不能假报成功", () => {
  const d = D.createStore({
    getItem: () => null,
    setItem: () => {
      throw Error("quota");
    },
  });
  assert.throws(() => d.claim("RL-E-0915-002"), /quota/);
  assert.equal(d.event("RL-E-0915-002").status, "待认领");
  assert.equal(d.state.audit.length, 0);
});
test("核验必填校验失败时不产生写入", () => {
  const d = create();
  assert.throws(() =>
    d.verify("RL-E-0915-001", { conclusion: "", situation: "" }, true),
  );
  assert.equal(d.state.audit.length, 0);
});
test("设备归还、重绑影响当前归属和数量但保留历史记录", () => {
  const d = create(),
    event = d.event("RL-E-0915-001"),
    snapshot = JSON.stringify(event.snapshot);
  assert.throws(() => d.bind("P2", "RL-H001"), /其他人员/);
  d.release("RL-H001");
  assert.equal(d.currentDevices("P1").length, 2);
  assert.equal(d.stats().devices.length, 23);
  d.bind("P2", "RL-H001");
  assert.equal(d.owner("RL-H001").id, "P2");
  assert.equal(d.owner("RL-H002"), null);
  assert.equal(d.currentDevices("P2").length, 3);
  assert.equal(JSON.stringify(d.event(event.id).snapshot), snapshot);
  assert.ok(
    d.state.bindings.some(
      (b) => b.deviceId === "RL-H001" && b.personId === "P1" && b.end,
    ),
  );
  assert.ok(d.state.bindings.some((b) => b.deviceId === "RL-H002" && b.end));
});
test("更新人员名字时历史资料快照不变，当前关联读取新名字", () => {
  const d = create();
  d.updatePerson("P1", { name: "陈建国更新", team: "维护一班", active: true });
  assert.equal(d.owner("RL-H001").name, "陈建国更新");
  assert.equal(d.state.media[0].snapshot.personName, "陈建国");
  assert.equal(d.event("RL-E-0915-001").snapshot.personName, "陈建国");
});
test("设备状态更新统一统计，低电量仍为在线", () => {
  const d = create();
  d.updateDevice("RL-H004", {
    battery: 10,
    online: true,
    active: true,
    video: "available",
  });
  assert.equal(d.stats().online, 23);
  assert.equal(d.stats().video.available, 7);
  d.updateDevice("RL-B001", { battery: 60, online: true, active: true });
  assert.equal(d.stats().online, 24);
});
test("作业成员去重、不允许同时分配两项作业、变更影响统计", () => {
  const d = create();
  assert.throws(
    () => d.updateWork("GL-20260915-018", { members: ["P1", "P4"] }),
    /其他作业/,
  );
  d.updateWork("GL-20260915-018", {
    members: ["P1", "P2", "P3", "P8", "P8"],
    supervisor: "P3",
    leader: "P2",
  });
  assert.equal(d.work("GL-20260915-018").members.length, 4);
  assert.equal(d.stats().assigned, 8);
  assert.equal(d.stats({ workId: "GL-20260915-018" }).devices.length, 12);
  assert.throws(
    () =>
      d.updateWork("GL-20260915-018", {
        members: ["P1"],
        start: "12:00",
        end: "10:00",
      }),
    /晚于/,
  );
});
test("抓拍、录像记录生成相同日期的关联资料", () => {
  const d = create(),
    id = d.capture("P1", "photo", 0, { blobId: "file-1" }),
    m = d.state.media.find((x) => x.id === id);
  assert.equal(m.date, D.DATE);
  assert.equal(m.deviceId, "RL-H001");
  assert.equal(m.workId, "GL-20260915-018");
  assert.equal(m.snapshot.personName, "陈建国");
  assert.equal(m.blobId, "file-1");
  const v = d.capture("P1", "video", 38);
  assert.equal(d.state.media.find((m) => m.id === v).duration, 38);
});
test("重载存储保留核验、媒体和绑定修改", () => {
  const store = storage(),
    a = D.createStore(store);
  a.claim("RL-E-0915-002");
  const id = a.capture("P1");
  a.release("RL-W001");
  const b = D.createStore(store);
  assert.equal(b.event("RL-E-0915-002").status, "处理中");
  assert.ok(b.state.media.find((m) => m.id === id));
  assert.equal(b.owner("RL-W001"), null);
});
test("围栏几何校验、位置变化判定、停用和归档保留记录", () => {
  const d = create();
  assert.throws(
    () =>
      d.saveFence(null, {
        name: "交叉",
        points: [
          [0, 0],
          [90, 90],
          [0, 80],
          [80, 0],
        ],
      }),
    /交叉|过小/,
  );
  d.movePerson("P1", [8, 8]);
  assert.equal(d.state.fenceRecords.length, 1);
  assert.equal(d.state.fenceRecords[0].type, "离开");
  d.toggleFence("F1", false);
  d.movePerson("P1", [35, 45]);
  d.movePerson("P1", [8, 8]);
  assert.equal(d.state.fenceRecords.length, 1);
  d.deleteFence("F1");
  assert.equal(d.state.fenceRecords.length, 1);
  assert.equal(d.state.fences.find((f) => f.id === "F1").archived, true);
});
test("通信流程、成员去重、回执和 SOS 独立于告警", () => {
  const d = create();
  const c = d.startCall(["P1", "P1", "P2"], "群呼");
  assert.equal(d.state.calls[0].members.length, 2);
  assert.throws(() => d.startCall(["P3"], "单呼"), /先结束/);
  d.updateCall(c, "connect");
  d.updateCall(c, "mute");
  d.updateCall(c, "invite", "P3");
  assert.equal(d.state.calls[0].muted, true);
  assert.equal(d.state.calls[0].members.length, 3);
  d.updateCall(c, "end");
  assert.equal(d.state.calls[0].status, "已结束");
  d.broadcast("G1", "检查装备");
  assert.equal(d.state.broadcasts.length, 1);
  d.sos("join");
  d.sos("end");
  assert.equal(d.stats().events.length, 3);
  assert.equal(d.stats().unresolved, 3);
  assert.equal(d.state.sos.status, "ended");
});
test("轨迹查询不补齐缺口并校验时间范围", () => {
  const d = create();
  assert.throws(() => d.tracks("P1", D.DATE, "12:00", "09:00"), /晚于/);
  assert.deepEqual(d.tracks("P1", "2026-09-16", "09:00", "11:00"), []);
  const p = d.tracks("P1", D.DATE, "09:00", "10:42");
  assert.equal(p.find((x) => x.time === "09:46").gap, true);
  assert.equal(p.filter((x) => x.time > "09:38" && x.time < "09:46").length, 0);
});
test("停用人员自动结束当前领用并移除作业及分组，历史保留", () => {
  const d = create();
  d.updatePerson("P1", { name: "陈建国", team: "维护一班", active: false });
  assert.equal(d.stats().people.length, 7);
  assert.equal(d.owner("RL-H001"), null);
  assert.ok(d.work("GL-20260915-018").members.every((id) => id !== "P1"));
  assert.equal(d.event("RL-E-0915-001").personId, "P1");
});
test("换绑不改写历史轨迹，当前地图位置依赖有效安全帽", () => {
  const d = create();
  assert.equal(d.locationValid("P1"), true);
  d.release("RL-H001");
  assert.equal(d.locationValid("P1"), false);
  assert.throws(() => d.movePerson("P1", [20, 20]), /安全帽/);
  d.bind("P2", "RL-H001");
  assert.equal(
    d.currentDevices("P2").find((x) => x.type === "H").id,
    "RL-H001",
  );
  assert.equal(d.tracks("P2", D.DATE, "09:00", "10:42")[0].deviceId, "RL-H002");
  assert.throws(() => d.movePerson("P2", [-1, 101]), /无效/);
});
test("SOS重复加入被拒绝，记录包含值守员，演示时钟在既有时间线之后", () => {
  const d = create();
  d.sos("join");
  assert.throws(() => d.sos("join"), /已经加入/);
  assert.ok(d.state.sos.timeline.at(-1).time > "10:42:14");
  d.sos("end");
  assert.ok(d.state.calls[0].members.includes("operator"));
  assert.equal(d.stats().unresolved, 3);
});
test("核验上传资料区分拍摄来源和告警设备", () => {
  const d = create(),
    id = d.addEventPhoto("RL-E-0915-001", "upload-test", "现场照片");
  const m = d.state.media.find((m) => m.id === id);
  assert.equal(m.deviceId, "本地上传");
  assert.equal(m.eventDeviceId, "RL-B001");
  assert.equal(m.eventId, "RL-E-0915-001");
  assert.equal(m.date, D.DATE);
});

test("体征按人员和本次手表绑定查询，初始观测时间使用演示日期", () => {
  const d = create();
  for (const p of d.state.people) {
    const v = d.vitals(p.id);
    assert.equal(v.record.personId, p.id);
    assert.equal(v.record.deviceId, v.watch.id);
    assert.ok(v.record.observedAt.startsWith(D.DATE));
    assert.equal(d.deviceAt(p.id, v.record.observedAt, "W").id, v.watch.id);
  }
  assert.equal(d.vitals("P1").record.heartRate, 72);
  assert.equal(d.vitals("P2").record.heartRate, 78);
});
test("更换手表不会把上一位佩戴者或上次领用的观测作为当前数据", () => {
  const d = create(), old = structuredClone(d.vitalHistory("P1"));
  d.release("RL-W002");
  d.bind("P1", "RL-W002");
  assert.equal(d.vitals("P1").watch.id, "RL-W002");
  assert.equal(d.vitals("P1").record, null);
  assert.equal(d.vitals("P2").record, null);
  assert.deepEqual(d.vitalHistory("P1"), old);
  d.bind("P1", "RL-W001");
  assert.equal(d.vitals("P1").record, null);
});
test("手表离线明确表达最近观测，停用或归还设备不再显示当前读数", () => {
  const d = create();
  d.updateDevice("RL-W001", { ...d.device("RL-W001"), online: false });
  assert.match(d.vitals("P1").status, /离线/);
  assert.equal(d.vitals("P1").record.heartRate, 72);
  d.release("RL-W001");
  assert.equal(d.vitals("P1").status, "未绑定手表");
  assert.equal(d.vitals("P1").record, null);
  assert.equal(d.vitalHistory("P1").length, 1);
});
test("旧存档无损升级体征，修改姓名不篡改历史，刷新保持相同观测", () => {
  const mem = storage(), old = D.seed();
  delete old.vitals;
  old.people[0].name = "陈工";
  mem.setItem(D.KEY, JSON.stringify(old));
  const d = D.createStore(mem);
  assert.equal(d.person("P1").name, "陈工");
  assert.equal(d.vitals("P1").record.personName, "陈建国");
  d.updatePerson("P1", { ...d.person("P1"), name: "陈建国（维护）" });
  const fresh = D.createStore(mem);
  assert.deepEqual(fresh.vitals("P1"), d.vitals("P1"));
  assert.equal(fresh.person("P1").name, "陈建国（维护）");
});
