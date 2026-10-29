  import { supportsDeviceAction, hasCurrentLocation, isRealDevice } from "../lib/device-telemetry.js";
  import { mapLocation } from "../lib/location.js";
  import { displayDevice } from "../lib/data-mode.js";
  import { isSimulatedWatch, isSimulatedVital, projectCachedSamples, projectSingleSimulatedWatch } from "../lib/sample-data.js";
  import { beijingDate, beijingTime } from "../lib/location.js";
  import { communicationGuard } from "../lib/communication-guard.js";

  "use strict";
  const DATE = "2026-09-15",
    KEY = "rolling-native-v1";
  const clone = (x) => JSON.parse(JSON.stringify(x));
  const typeNames = { H: "智能安全帽", B: "智能安全带", W: "智能手表" };
  const workLocations = ["锅炉区", "汽机厂房", "配电区"];
  const assetForPerson = (id) => {
    const index = Number(String(id || '').match(/\d+$/)?.[0] || 1) - 1;
    return ['scene-boiler.png', 'scene-turbine.png', 'scene-electric.png', 'scene-water.png'][index % 4] || 'scene-boiler.png';
  };
  function withoutAdministrativeAreas(snapshot) {
    const next = { ...snapshot };
    delete next.mapAreas;
    for (const kind of ['people', 'devices', 'groups', 'works']) {
      if (!Array.isArray(snapshot[kind])) continue;
      next[kind] = snapshot[kind].map(record => {
        const row = { ...record };
        delete row.areaId;
        if (kind !== 'works') delete row.area;
        return row;
      });
    }
    return next;
  }
  function seed() {
    const people = [
      "陈建国",
      "李志远",
      "周明",
      "王海峰",
      "赵晓东",
      "刘洋",
      "孙伟",
      "何平",
    ].map((name, i) => ({
      id: "P" + (i + 1),
      name,
      team:
        i < 3
          ? "维护一班"
          : i < 5
            ? "运行一班"
            : i < 7
              ? "电气一班"
              : "运行一班",
      station: "S1",
      active: true,
      position: [
        [36, 37],
        [44, 53],
        [31, 48],
        [61, 51],
        [57, 62],
        [23, 68],
        [21, 76],
        [81, 48],
      ][i],
      locationValid: i !== 5,
      phone: "",
      updated: "10:" + ["39", "41", "40", "41", "38", "26", "37", "15"][i],
    }));
    const devices = people.flatMap((p, i) =>
      ["H", "B", "W"].map((type) => ({
        id: "RL-" + type + String(i + 1).padStart(3, "0"),
        type,
        station: "S1",
        active: true,
        online: !(type === "B" && i === 0),
        battery:
          type === "H" && i === 3
            ? 18
            : type === "B" && i === 0
              ? 62
              : i === 0
                ? type === "H"
                  ? 68
                  : 61
                : 78 - i * 2,
        video:
          type === "H"
            ? i === 3
              ? "interrupted"
              : i === 6
                ? "off"
                : "available"
            : null,
        updated:
          DATE +
          " " +
          (type === "B" && i === 0 ? "10:38:56" : p.updated + ":00"),
      })),
    );
    const bindings = devices.map((d, i) => ({
      id: "BIND" + i,
      deviceId: d.id,
      personId: "P" + (Math.floor(i / 3) + 1),
      start: i < 3 ? "2026-09-14 08:12:30" : DATE + " 08:00:00",
      end: null,
      operator: "赵晓东",
    }));
    bindings.push({
      id: "BIND-HIST-001",
      deviceId: "RL-W003",
      personId: "P1",
      start: "2026-09-10 17:36:20",
      end: "2026-09-14 08:10:12",
      operator: "李志远",
    });
    const works = [
      {
        id: "GL-20260915-018",
        name: "锅炉平台检修",
        area: workLocations[0],
        members: ["P1", "P2", "P3"],
        supervisor: "P3",
        leader: "P2",
        start: "08:30",
        end: "12:00",
        source: "工作票",
        synced: true,
      },
      {
        id: "XJ-20260915-006",
        name: "汽机设备巡检",
        area: workLocations[1],
        members: ["P4", "P5"],
        supervisor: "P5",
        leader: "P5",
        start: "09:00",
        end: "16:00",
        source: "巡检任务",
        synced: true,
      },
      {
        id: "JC-20260915-003",
        name: "配电区检查",
        area: workLocations[2],
        members: ["P6", "P7"],
        supervisor: "P7",
        leader: "P7",
        start: "10:00",
        end: "15:00",
        source: "检查任务",
        synced: false,
      },
    ].map((w) => ({ ...w, station: "S1", date: DATE, status: "监护中" }));
    const events = [
      {
        id: "RL-E-0915-001",
        personId: "P1",
        deviceId: "RL-B001",
        workId: works[0].id,
        title: "安全带连接中断",
        type: "设备通信",
        status: "待现场核验",
        time: "10:39",
        externalStatus: "处理中",
      },
      {
        id: "RL-E-0915-002",
        personId: "P4",
        deviceId: "RL-H004",
        workId: works[1].id,
        title: "安全帽低电量 18%",
        type: "低电量",
        status: "待认领",
        time: "10:41",
        externalStatus: "待回传",
      },
      {
        id: "RL-E-0915-003",
        personId: "P6",
        deviceId: "RL-H006",
        workId: works[2].id,
        title: "人员位置待核验",
        type: "位置异常",
        status: "处理中",
        time: "10:26",
        externalStatus: "待回传",
      },
      {
        id: "RL-E-0915-004",
        personId: "P8",
        deviceId: "RL-H008",
        workId: "",
        title: "安全帽发起 SOS",
        type: "人员求助",
        status: "待认领",
        time: "10:42",
        externalStatus: "待回传",
      },
      {
        id: "RL-E-0915-005",
        personId: "P7",
        deviceId: "RL-H007",
        workId: works[2].id,
        title: "进入配电区限制区域",
        type: "电子围栏",
        status: "待现场核验",
        time: "10:18",
        externalStatus: "待回传",
      },
      {
        id: "RL-E-0915-006",
        personId: "P3",
        deviceId: "RL-B003",
        workId: works[0].id,
        title: "高处作业未检测到挂接",
        type: "安全带挂接",
        status: "待认领",
        time: "10:33",
        externalStatus: "处理中",
      },
      {
        id: "RL-E-0915-007",
        personId: "P5",
        deviceId: "RL-W005",
        workId: works[1].id,
        title: "心率偏高 128 bpm",
        type: "生命体征",
        status: "处理中",
        time: "10:36",
        externalStatus: "待回传",
      },
    ].map((e, i) => ({
      ...e,
      station: "S1",
      date: DATE,
      externalId: "AQ-20260915-" + String(17 + i).padStart(3, "0"),
      snapshot: {
        personName: people.find((p) => p.id === e.personId).name,
        deviceId: e.deviceId,
        workName: works.find((w) => w.id === e.workId)?.name || "待分配",
      },
      draft: null,
      verification: null,
      timeline: [
        { time: e.time, text: "检测到" + e.title },
        { time: e.time > "10:41" ? e.time : "10:41", text: i === 0 ? "周明开始现场核验" : "事件已登记" },
      ],
    }));
    const media = [
      {
        id: "IMG-0915-001",
        kind: "photo",
        title: "锅炉平台现场核验",
        personId: "P1",
        workId: works[0].id,
        eventId: events[0].id,
        deviceId: "RL-H001",
        asset: "scene-boiler.png",
        time: "10:39:12",
      },
      {
        id: "VID-0915-002",
        kind: "video",
        title: "汽机巡检片段",
        personId: "P4",
        workId: works[1].id,
        deviceId: "RL-H004",
        asset: "scene-turbine.png",
        duration: 38,
        time: "10:32:05",
      },
      {
        id: "IMG-0915-003",
        kind: "photo",
        title: "配电区检查照片",
        personId: "P7",
        workId: works[2].id,
        deviceId: "RL-H007",
        asset: "scene-electric.png",
        time: "10:18:42",
      },
      {
        id: "VID-0915-004",
        kind: "video",
        title: "平台入口记录",
        personId: "P2",
        workId: works[0].id,
        deviceId: "RL-H002",
        asset: "scene-boiler.png",
        duration: 21,
        time: "09:58:10",
      },
    ].map((m) => ({
      ...m,
      station: "S1",
      date: DATE,
      created: DATE + " " + m.time,
      snapshot: {
        personName: people.find((p) => p.id === m.personId).name,
        workName: works.find((w) => w.id === m.workId).name,
      },
      source: "设备回传",
    }));
    return {
      version: 1,
      seq: 100,
      clock: 10 * 3600 + 42 * 60 + 18,
      stations: [
        { id: "S1", name: "临江示范电厂" },
        { id: "S2", name: "北江示范电厂" },
      ],
      people,
      devices,
      bindings,
      vitals: people.map((p, k) => ({
        id: "VITAL-SEED-" + p.id,
        personId: p.id,
        personName: p.name,
        deviceId: "RL-W" + String(k + 1).padStart(3, "0"),
        bindingId: "BIND" + (k * 3 + 2),
        observedAt: DATE + " " + p.updated + ":00",
        receivedAt: DATE + " " + p.updated + ":05",
        source: "预置观测",
        heartRate: [72, 78, 75, 82, 76, 80, 74, 77][k],
        oxygen: [98, 98, 99, 97, 98, 98, 99, 98][k],
        temperature: [36.5, 36.6, 36.5, 36.7, 36.4, 36.6, 36.5, 36.6][k],
        systolic: [118, 122, 120, 125, 119, 121, 117, 123][k],
        diastolic: [76, 78, 75, 80, 77, 79, 74, 78][k],
      })),
      works,
      events,
      media,
      groups: works.map((w, i) => ({
        id: "G" + (i + 1),
        name: ["锅炉检修协助组", "汽机巡检协助组", "配电检查协助组"][i],
        members: [...w.members],
        station: "S1",
      })),
      fences: [
        {
          id: "F1",
          name: "锅炉检修区域",
          points: [
            [25, 23],
            [47, 28],
            [48, 66],
            [26, 68],
            [20, 52],
          ],
          enabled: true,
          enter: false,
          leave: true,
          members: ["P1", "P2", "P3"],
          department: "设备检修部",
          owner: "周明",
          station: "S1",
        },
        {
          id: "F2",
          name: "配电区限制区域",
          points: [
            [12, 60],
            [29, 60],
            [29, 87],
            [12, 87],
          ],
          enabled: true,
          enter: true,
          leave: false,
          members: ["P6", "P7"],
          department: "设备运行部",
          owner: "孙伟",
          station: "S1",
        },
        {
          id: "F3",
          name: "循环水临时作业区",
          points: [
            [73, 27],
            [90, 27],
            [90, 75],
            [73, 75],
          ],
          enabled: false,
          enter: true,
          leave: true,
          members: ["P8"],
          department: "设备运行部",
          owner: "何平",
          station: "S1",
        },
      ],
      fenceRecords: [],
      calls: [],
      broadcasts: [],
      sos: {
        id: "DRILL-SOS-0915-01",
        eventId: "RL-E-0915-004",
        personId: "P8",
        deviceId: "RL-H008",
        personName: "何平",
        station: "S1",
        status: "waiting",
        members: ["P3"],
        timeline: [
          { time: "10:42:08", text: "收到安全帽 SOS" },
          { time: "10:42:10", text: "发送分组邀请" },
          { time: "10:42:14", text: "周明加入协助" },
        ],
      },
      audit: [],
    };
  }
  function createStore(storage, { demoMode = false, requiredDataVersion = null, loadRtc = () => import("../lib/rtc.js") } = {}) {
    let state = seed(),
      loadError = "";
    if (!demoMode) {
      // A first visit waits for the backend. Existing saved ledgers are loaded intact below.
      for (const key of Object.keys(state)) if (Array.isArray(state[key]) && key !== 'stations') state[key] = [];
      state.sos = { status: 'ended', members: [], timeline: [] };
    }
    try {
      const raw = storage && storage.getItem(KEY);
      if (raw) {
        const parsed = JSON.parse(raw);
        if (parsed.version !== 1) throw Error("版本不匹配");
        if (!demoMode && requiredDataVersion && parsed.businessConfig?.dataVersion !== requiredDataVersion) {
          storage.removeItem(KEY);
          throw Error('旧业务缓存已清理，正在读取当前业务数据');
        }
        const stationName = parsed.stations?.[0]?.name || "";
        if (!/[\u4e00-\u9fff]/.test(stationName)) storage.removeItem(KEY);
        else state = demoMode ? parsed : projectCachedSamples(parsed, seed());
      }
    } catch (e) {
      loadError = (demoMode ? "本地演示数据读取失败，已载入初始演示数据：" : "本地业务缓存已失效，等待读取服务器数据：") + e.message;
    }
    state = withoutAdministrativeAreas(state);
    // Upgrade older saves without replacing business changes or inventing new bindings.
    const fresh = seed();
    if (!Array.isArray(state.vitals)) {
      state.vitals = (demoMode ? fresh.vitals : []).filter((v) => state.bindings.some((b) =>
        b.id === v.bindingId && b.personId === v.personId && b.deviceId === v.deviceId &&
        b.start <= v.observedAt && (!b.end || b.end > v.observedAt)));
    }
    if (!Array.isArray(state.events)) state.events = [];
    const addedEvents = demoMode ? fresh.events.filter((event) => !state.events.some((item) => item.id === event.id)) : [];
    let changed = addedEvents.length > 0;
    if (addedEvents.length) state.events.push(...addedEvents);
    if (demoMode && state.sos && !state.sos.eventId && state.events.some((item) => item.id === "RL-E-0915-004")) {
      state.sos.eventId = "RL-E-0915-004";
      changed = true;
    }
    for (const item of demoMode ? state.sos?.timeline || [] : []) {
      if (item.text === "收到 SOS 演练请求") {
        item.text = "收到安全帽 SOS";
        changed = true;
      }
      if (item.text === "周明加入") {
        item.text = "周明加入协助";
        changed = true;
      }
    }
    for (const call of demoMode ? state.calls || [] : []) {
      if (call.kind === "SOS 演练") {
        call.kind = "SOS协助";
        changed = true;
      }
    }
    if (changed && storage) {
      try {
        storage.setItem(KEY, JSON.stringify(state));
      } catch {
        /* 浏览器拒绝写入时仍保留本次内存中的新告警。 */
      }
    }
    const listeners = new Set();
    let remoteCommit = null;
    let voice = null;
    let applyingVoice = false;
    // Authentication credentials never enter persisted snapshots or localStorage.
    const callCredentials = new Map();
    const now = (s) => demoMode ? DATE +
      " " +
      [
        Math.floor(s.clock / 3600) % 24,
        Math.floor(s.clock / 60) % 60,
        s.clock % 60,
      ]
        .map((v) => String(v).padStart(2, "0"))
        .join(":") : beijingDate() + " " + beijingTime(new Date().toISOString());
    function commit(label, fn) {
      const volatileCommunication = !demoMode && voice && ['发起单呼', '发起群呼', '更新通话', '发送文字广播', 'SOS 协助操作'].includes(label);
      const next = clone(state);
      next.clock++;
      const value = fn(next);
      if (volatileCommunication) next.seq = state.seq;
      else next.audit.push({ id: "A" + ++next.seq, time: now(next), text: label });
      validate(next);
      if (remoteCommit && !volatileCommunication) remoteCommit(next);
      if (storage && !volatileCommunication) storage.setItem(KEY, JSON.stringify(next));
      state = next;
      listeners.forEach((fn) => fn(state));
      return value;
    }
    function person(id) {
      return state.people.find((p) => p.id === id);
    }
    function device(id) {
      return displayDevice(state.devices.find((d) => d.id === id), demoMode);
    }
    function work(id) {
      return state.works.find((w) => w.id === id);
    }
    function event(id) {
      return state.events.find((e) => e.id === id);
    }
    function currentDevices(pid) {
      return state.bindings
        .filter((b) => !b.end && b.personId === pid)
        .map((b) => device(b.deviceId))
        .filter(Boolean);
    }
    function owner(did) {
      const b = state.bindings.find((b) => !b.end && b.deviceId === did);
      return b ? person(b.personId) : null;
    }
    function vitalHistory(pid) {
      return state.vitals.filter((v) => v.personId === pid && (demoMode || !isSimulatedVital(v) || isSimulatedWatch(device(v.deviceId))))
        .sort((a, b) => b.observedAt.localeCompare(a.observedAt));
    }
    function vitals(pid) {
      const p = person(pid);
      const watch = currentDevices(pid).find((d) => d.type === "W" && d.active);
      const binding = watch && state.bindings.find((b) => !b.end && b.personId === pid && b.deviceId === watch.id);
      const record = p?.active && binding ? vitalHistory(pid).find((v) =>
        v.bindingId === binding.id && v.deviceId === watch.id && v.observedAt >= binding.start) || null : null;
      const simulated = Boolean(record && isSimulatedVital(record) && (demoMode || isSimulatedWatch(watch)));
      const status = !p?.active ? "人员已停用" : !watch ? "未绑定手表" : simulated ? watch.online === false ? "模拟数据 · 手表离线" : "模拟数据 · 非实时测量" : watch.online == null ? "暂无真实体征数据" : !watch.online ? "手表离线 · 最近观测" : !record ? "暂无本次领用观测" : "最近观测";
      return { watch, record, status, simulated };
    }
    function locationDevice(pid) {
      const p = person(pid);
      const devices = currentDevices(pid);
      if (demoMode) return devices.find(d => d.type === "H" && d.active && d.online) || null;
      if (!p?.active || !p.locationDeviceId || !p.locationAssignmentId || p.locationAssignmentVersion == null) return null;
      const d = devices.find(d => d.id === p.locationDeviceId && d.active && isRealDevice(d) &&
        (d.type === "H" || d.type === "B" && d.source === "DIRECT_BELT") && hasCurrentLocation(d));
      if (!d) return null;
      const bindings = state.bindings.filter(b => !b.end && b.deviceId === d.id);
      const binding = bindings.length === 1 ? bindings[0] : null;
      if (!binding || binding.personId !== pid || binding.assignmentId !== p.locationAssignmentId ||
        binding.assignmentVersion == null || binding.assignmentVersion !== p.locationAssignmentVersion) return null;
      // The person projection and the selected device must describe one observation.
      // Never borrow another device's fresh heartbeat to revive old person coordinates.
      if (!mapLocation(p, { current: true }) || !mapLocation(d, { current: true }) ||
        Number(p.longitude) !== Number(d.longitude) || Number(p.latitude) !== Number(d.latitude) ||
        p.coordinateSystem !== d.coordinateSystem ||
        Date.parse(p.locationReportedAt) !== Date.parse(d.locationReportedAt)) return null;
      return d;
    }
    function locationValid(pid) {
      const p = person(pid);
      const d = locationDevice(pid);
      if (!p?.active || !d) return false;
      return isRealDevice(d) ? Boolean(mapLocation(p, { current: true })) : Boolean(p.locationValid);
    }
    function deviceAt(pid, time, type = "H") {
      const b = state.bindings.find(
        (b) =>
          b.personId === pid &&
          b.start <= time &&
          (!b.end || b.end > time) &&
          device(b.deviceId)?.type === type,
      );
      return b ? device(b.deviceId) : null;
    }
    function currentWork(pid) {
      return state.works.find(
        (w) =>
          w.date === (demoMode ? DATE : beijingDate()) && w.members.includes(pid) && w.status !== "已结束",
      );
    }
    function filter(list, scope = {}) {
      return list.filter(
        (x) =>
          (!scope.station || x.station === scope.station) &&
          (!scope.date || !x.date || x.date === scope.date) &&
          (!scope.workId ||
            scope.workId === "all" ||
            x.workId === scope.workId ||
            x.id === scope.workId),
      );
    }
    function stats(scope = {}) {
      const works = filter(state.works, scope);
      const members = new Set(works.flatMap((w) => w.members));
      const dateValid = !demoMode || !scope.date || scope.date === DATE;
      const people = state.people.filter(
        (p) =>
          p.active &&
          (!scope.station || p.station === scope.station) &&
          dateValid &&
          (!scope.workId || scope.workId === "all" || members.has(p.id)),
      );
      const ids = new Set(people.map((p) => p.id));
      const assignedDevices = state.bindings
        .filter((b) => !b.end && ids.has(b.personId))
        .map((b) => device(b.deviceId))
        .filter((d) => d && d.active);
      const devices = assignedDevices.filter(d => demoMode || isRealDevice(d));
      const simulatedWatches = assignedDevices.filter(isSimulatedWatch);
      const events = filter(state.events, scope);
      return {
        people,
        devices,
        simulatedWatches,
        works,
        events,
        assigned: people.filter((p) => members.has(p.id)).length,
        online: devices.filter((d) => d.online).length,
        unresolved: events.filter((e) => e.status !== "已核验").length,
        verified: events.filter((e) => e.status === "已核验").length,
        byType: Object.fromEntries(
          ["H", "B", "W"].map((t) => [
            t,
            {
              total: devices.filter((d) => d.type === t).length,
              online: devices.filter((d) => d.type === t && d.online).length,
            },
          ]),
        ),
        video: {
          available: devices.filter((d) => d.video === "available").length,
          interrupted: devices.filter((d) => d.video === "interrupted").length,
          off: devices.filter((d) => d.video === "off").length,
        },
      };
    }
    function requireItem(list, id) {
      const item = list.find((x) => x.id === id);
      if (!item) throw Error("记录不存在或已归档");
      return item;
    }
    function bind(pid, did) {
      return commit("更新装备领用绑定", (s) => {
        const p = requireItem(s.people, pid),
          d = requireItem(s.devices, did);
        if (!p.active || !d.active) throw Error("停用人员或装备不能绑定");
        if (p.station !== d.station) throw Error("人员和设备必须属于同一厂站");
        const own = s.bindings.find((b) => !b.end && b.deviceId === did);
        if (own && own.personId !== pid)
          throw Error("设备已被其他人员领用，请先归还");
        if (own) return;
        for (const b of s.bindings.filter(
          (b) => !b.end && b.personId === pid,
        )) {
          if (requireItem(s.devices, b.deviceId).type === d.type)
            b.end = now(s);
        }
        s.bindings.push({
          id: "BIND" + ++s.seq,
          deviceId: did,
          personId: pid,
          start: now(s),
          end: null,
          operator: "值守员",
        });
      });
    }
    function release(did) {
      return commit("归还装备 " + did, (s) => {
        const b = s.bindings.find((b) => !b.end && b.deviceId === did);
        if (!b) throw Error("该设备未领用");
        b.end = now(s);
      });
    }
    function updatePerson(id, fields) {
      return commit("保存人员资料", (s) => {
        if (!String(fields.name || "").trim()) throw Error("请输入人员姓名");
        const p = id
          ? requireItem(s.people, id)
          : {
              id: "P" + ++s.seq,
              active: true,
              station: fields.station || "S1",
              position: demoMode ? [50, 50] : null,
              locationValid: demoMode,
              updated: demoMode ? "10:42" : null,
            };
        Object.assign(p, {
          name: fields.name.trim(),
          team: fields.team || "未分组",
          phone: fields.phone || "",
          active: fields.active !== false,
        });
        if (!p.active) {
          s.works.forEach((w) => {
            w.members = w.members.filter((x) => x !== p.id);
            if (w.supervisor === p.id) w.supervisor = w.members[0] || null;
            if (w.leader === p.id) w.leader = w.members[0] || null;
          });
          s.bindings
            .filter((b) => !b.end && b.personId === p.id)
            .forEach((b) => (b.end = now(s)));
          s.groups.forEach(
            (g) => (g.members = g.members.filter((x) => x !== p.id)),
          );
        }
        if (!id) s.people.push(p);
        return p.id;
      });
    }
    function updateDevice(id, fields) {
      return commit("保存装备资料", (s) => {
        const d = requireItem(s.devices, id);
        const battery = Number(fields.battery);
        if (!Number.isFinite(battery) || battery < 0 || battery > 100)
          throw Error("电量应为 0–100");
        Object.assign(d, {
          battery,
          online: !!fields.online,
          active: fields.active !== false,
        });
        if (d.type === "H") d.video = fields.video || d.video;
        if (!d.active)
          s.bindings
            .filter((b) => !b.end && b.deviceId === id)
            .forEach((b) => (b.end = now(s)));
        d.updated = now(s);
      });
    }
    function updateWork() {
      throw Error("作业票信息只读，由两票系统维护");
    }
    function syncWorks() {
      throw Error("两票系统尚未对接，不能模拟同步成功");
    }
    function claim(id) {
      return commit("认领事件", (s) => {
        const e = requireItem(s.events, id);
        if (e.status !== "待认领") throw Error("该事件已认领或已核验");
        e.status = "处理中";
        e.timeline.push({ time: now(s).slice(11), text: "值守员认领事件" });
      });
    }
    function verify(id, form, submit) {
      return commit(submit ? "提交核验记录" : "保存核验草稿", (s) => {
        const e = requireItem(s.events, id);
        if (e.verification) throw Error("该事件已经完成核验，请勿重复提交");
        if (
          submit &&
          (!["设备通信异常", "需现场处理", "暂无法确认"].includes(
            form.conclusion,
          ) ||
            !String(form.situation || "").trim())
        )
          throw Error("请选择核验结论并填写现场情况");
        if (
          (form.situation || "").length > 500 ||
          (form.measures || "").length > 500
        )
          throw Error("填写内容不能超过 500 字");
        e.draft = { ...form, savedAt: now(s) };
        if (submit) {
          e.verification = {
            ...e.draft,
            submittedAt: now(s),
            operator: "值守员",
          };
          e.status = "已核验";
          e.timeline.push({
            time: now(s).slice(11),
            text: "核验记录已提交 · " + form.conclusion,
          });
        }
        return e.id;
      });
    }
    function capture(pid, kind = "photo", duration = 0, options = {}) {
      if (!demoMode) throw Error('暂无真实设备上传，不能生成示例影像记录');
      if (currentDevices(pid).some(d => d.type === 'H' && isRealDevice(d))) throw Error('真实安全帽影像须由设备上传，不能生成示例记录');
      return commit(
        kind === "photo" ? "保存现场照片" : "保存模拟录像记录",
        (s) => {
          const p = requireItem(s.people, pid);
          const b = s.bindings.find(
            (b) =>
              !b.end &&
              b.personId === pid &&
              requireItem(s.devices, b.deviceId).type === "H",
          );
          if (!b) throw Error("该人员未绑定安全帽");
          const w = s.works.find(
            (w) => w.date === DATE && w.members.includes(pid),
          );
          const created = now(s);
          const m = {
            id: (kind === "photo" ? "IMG-" : "VID-") + ++s.seq,
            kind,
            title:
              options.title ||
              p.name + (kind === "photo" ? "现场抓拍" : "模拟录像记录"),
            personId: pid,
            deviceId: b.deviceId,
            workId: w?.id || "",
            eventId: options.eventId || "",
            station: p.station,
            date: demoMode ? DATE : beijingDate(),
            created,
            time: created.slice(11),
            asset: assetForPerson(p.id),
            duration: Math.max(1, duration),
            source: "手动" + (kind === "photo" ? "抓拍" : "录像（图片模拟）"),
            blobId: options.blobId || null,
            snapshot: { personName: p.name, workName: w?.name || "未关联作业" },
          };
          s.media.unshift(m);
          return m.id;
        },
      );
    }
    function addEventPhoto(eid, blobId, title) {
      return commit("添加核验照片", (s) => {
        const e = requireItem(s.events, eid);
        const m = {
          id: "IMG-" + ++s.seq,
          kind: "photo",
          title,
          personId: e.personId,
          deviceId: "本地上传",
          eventDeviceId: e.deviceId,
          workId: e.workId,
          eventId: e.id,
          station: e.station,
          date: demoMode ? DATE : beijingDate(),
          created: now(s),
          time: now(s).slice(11),
          blobId,
          snapshot: clone(e.snapshot),
          source: "核验上传",
        };
        s.media.unshift(m);
        return m.id;
      });
    }
    function saveFence(id, fields) {
      return commit("保存电子围栏", (s) => {
        if (!fields.name?.trim()) throw Error("请填写围栏名称");
        if (!fields.points || fields.points.length < 3)
          throw Error("围栏至少需要 3 个节点");
        if (polygonArea(fields.points) < (fields.coordinateSystem ? 1e-10 : 1)) throw Error("围栏区域过小");
        if (selfIntersects(fields.points)) throw Error("围栏边界不能交叉");
        const f = id
          ? requireItem(s.fences, id)
          : { id: "F" + ++s.seq, station: fields.station || "S1" };
        Object.assign(f, clone(fields));
        if (!id) s.fences.push(f);
        return f.id;
      });
    }
    function toggleFence(id, enabled) {
      return commit(enabled ? "启用围栏" : "停用围栏", (s) => {
        requireItem(s.fences, id).enabled = enabled;
      });
    }
    function deleteFence(id) {
      return commit("归档围栏", (s) => {
        const f = requireItem(s.fences, id);
        f.archived = true;
        f.enabled = false;
      });
    }
    function movePerson(pid, position) {
      return commit("模拟位置更新", (s) => {
        const p = requireItem(s.people, pid);
        if (
          !p.active ||
          !s.bindings.some(
            (b) =>
              b.personId === pid &&
              !b.end &&
              s.devices.some(
                (d) =>
                  d.id === b.deviceId && d.type === "H" && d.online && d.active,
              ),
          )
        )
          throw Error("请先绑定通信在线的安全帽");
        if (
          !Array.isArray(position) ||
          position.length !== 2 ||
          position.some((v) => !Number.isFinite(v) || v < 0 || v > 100)
        )
          throw Error("位置坐标无效");
        for (const f of s.fences.filter(
          (f) =>
            f.enabled &&
            !f.archived &&
            f.station === p.station &&
            f.members.includes(pid),
        )) {
          const before = inside(p.position, f.points),
            after = inside(position, f.points);
          if (before !== after && ((after && f.enter) || (!after && f.leave)))
            s.fenceRecords.unshift({
              id: "FR" + ++s.seq,
              fenceId: f.id,
              fenceName: f.name,
              personId: pid,
              personName: p.name,
              type: after ? "进入" : "离开",
              time: now(s),
              station: p.station,
            });
        }
        p.position = position;
        p.locationValid = true;
      });
    }
    function saveGroup(id, name, members, station) {
      return commit("保存协助分组", (s) => {
        if (!name.trim()) throw Error("请填写分组名称");
        if (!members.length) throw Error("请选择成员");
        members = [...new Set(members)];
        members.forEach((id) => {
          const p = requireItem(s.people, id);
          if (!p.active || p.station !== station)
            throw Error("成员不属于当前厂站");
        });
        const g = id
          ? requireItem(s.groups, id)
          : { id: "G" + ++s.seq, station };
        Object.assign(g, { name: name.trim(), members });
        if (!id) s.groups.push(g);
        return g.id;
      });
    }
    function helmetsFor(ids, action) {
      return ids.map((id) => {
        const wearer = requireItem(state.people, id);
        const helmet = currentDevices(id).find((item) => item.type === "H");
        if (!helmet) throw Error(wearer.name + "没有领用安全帽");
        if (voice && !supportsDeviceAction(helmet, action)) {
          throw Error(wearer.name + (action === "tts" ? "的安全帽尚无可用播报能力或状态待确认" : "的安全帽尚无可用语音协议或状态待确认"));
        }
        // The guardian endpoint resolves the platform ID to physical identity.
        return { hatNumber: helmet.id, name: wearer.name };
      });
    }
    function startCall(members, kind = "群呼", station = "S1", options = {}) {
      communicationGuard.assertAvailable();
      members = [...new Set(members)];
      if (!members.length) throw Error("请选择呼叫人员");
      if (kind === "单呼" && members.length !== 1) throw Error("单呼只能选择一人");
      members.forEach((pid) => {
        const wearer = requireItem(state.people, pid);
        if (!wearer.active || wearer.station !== station) throw Error("呼叫人员无效");
      });
      if (state.calls.some((call) => call.status !== "已结束")) throw Error("请先结束当前通话");
      const hats = helmetsFor(members, "intercom");
      const protocols = new Set(members.map(pid => String(currentDevices(pid).find(d => d.type === 'H')?.communicationProtocol || 'AGORA').toUpperCase()));
      if (voice && protocols.size > 1) throw Error('不同通信协议的安全帽暂不能放在同一通话中');
      const credentials = voice ? voice("/api/guardian/v1/call", { hats, video: options.video === true }) : null;
      const rtc = credentials ? { protocol: credentials.protocol || 'AGORA', channel: credentials.channel, callId: credentials.callId, video: options.video === true, status:credentials.status } : null;
      const id = commit("发起" + kind, (s) => {
        members = [...new Set(members)];
        if (!members.length) throw Error("请选择呼叫人员");
        if (kind === "单呼" && members.length !== 1)
          throw Error("单呼只能选择一人");
        members.forEach((pid) => {
          const p = requireItem(s.people, pid);
          if (!p.active || p.station !== station) throw Error("呼叫人员无效");
        });
        if (s.calls.some((c) => c.status !== "已结束"))
          throw Error("请先结束当前通话");
        const call = {
          id: voice ? 'LOCAL-CALL-' + crypto.randomUUID() : "CALL" + ++s.seq,
          members,
          kind,
          station,
          date: demoMode ? DATE : beijingDate(),
          time: now(s),
          status: "正在呼叫",
          muted: false,
          joined: [],
          ...(voice ? { connectionQuality: credentials?.status==='unknown'?'unknown':"requesting", realCommunication: true,
            ...(credentials?.status==='unknown'?{statusLabel:'云端呼叫结果未确认，请先结束本次会话'}:{}) } : {}),
          rtc,
          history: [{ time: now(s), text: "发起" + kind }],
        };
        s.calls.unshift(call);
        return call.id;
      });
      if (credentials && credentials.status!=='unknown') callCredentials.set(id, credentials);
      return id;
    }
    function updateCall(id, action, pid) {
      if (voice && !applyingVoice && action === "connect") return connectVoice(id);
      if (voice && !applyingVoice && action === "end") return endVoice(id);
      if (voice && !applyingVoice && action === "mute") return muteVoice(id);
      if (voice && action === "invite") throw Error("当前真实通话尚不支持追加成员，请结束后重新选择人员");
      return commit("更新通话", (s) => {
        const c = requireItem(s.calls, id);
        if (c.status === "已结束") throw Error("通话已经结束");
        if (action === "connect") {
          c.status = voice && !c.serverConnected ? "正在呼叫" : "通话中";
          if (voice) c.statusLabel = c.serverConnected ? "设备已接通" : "本端已加入（设备接通待确认）";
          c.joined = voice ? [] : [...c.members];
          if (voice) c.connectionQuality = "local_joined";
        }
        if (action === "media") {
          c.connectionQuality = pid;
          c.statusLabel = pid === "remote_audio" ? (c.serverConnected ? "设备已接通，收到远端音频" : "收到远端音频（设备身份待确认）") : pid === "remote_video" ? (c.serverConnected ? "设备已接通，收到远端视频" : "收到远端视频（设备身份待确认）") :
            pid === "playback_blocked" ? "浏览器未自动播放声音，请点击播放" : pid === "ended" ? "远端媒体已结束" : pid === "failed" ? "媒体连接中断" : "本端已加入（设备接通待确认）";
          c.joined = [];
        }
        if (action === "end") {
          const pending = c.rtc?.protocol==='SIP';
          c.status = pending ? "正在结束" : "已结束";
          if (c.rtc) c.statusLabel = pending ? "已请求结束，等待服务器确认" : "已结束";
          if (!pending)c.endedAt = now(s);
        }
        if (action === "mute") c.muted = !c.muted;
        if (action === "invite") {
          const p = requireItem(s.people, pid);
          if (!p.active || p.station !== c.station) throw Error("邀请成员无效");
          if (!c.members.includes(pid)) c.members.push(pid);
          if (c.status === "通话中" && !c.joined.includes(pid))
            c.joined.push(pid);
        }
        c.history.push({
          time: now(s),
          text: {
            connect: voice ? "本端已加入，等待设备接通证据" : "接通",
            media: c.statusLabel,
            end: c.rtc?.protocol==='SIP' ? "已请求结束，等待服务器确认" : "通话结束",
            mute: "切换静音",
            invite: "邀请成员",
          }[action],
        });
      });
    }
    async function connectVoice(id) {
      communicationGuard.assertAvailable();
      const call = state.calls.find((item) => item.id === id);
      if (!call) throw Error("记录不存在");
      if (call.status === "已结束") throw Error("通话已经结束");
      if (call.rtc?.status==='unknown' || call.status==='正在结束') throw Error('本次呼叫结果未确认或正在结束，请先结束并等待服务器确认');
      const rtcApi = await loadRtc();
      let credentials = callCredentials.get(id);
      if (!credentials && call.rtc?.callId) {
        const { authFetch } = await import('../lib/auth.js');
        const response = await authFetch(`/api/guardian/v1/helmet/calls/${encodeURIComponent(call.rtc.callId)}/credentials`);
        const body = await response.json();
        if (!response.ok) throw Error(body.message || '通话凭据读取失败，请重新发起');
        credentials = body;
        callCredentials.set(id, credentials);
      }
      let mediaQuality = null;
      await rtcApi.joinChannel(credentials ? {...credentials,callId:call.rtc?.callId || credentials.callId} : call.rtc, {
        onMediaState: (quality) => {
          mediaQuality = quality;
          const latest = state.calls.find((item) => item.id === id);
          if (!latest || latest.status === "已结束") return;
          try { updateCall(id, "media", quality); } catch { /* Keep RTC errors from escaping event callbacks. */ }
        },
      });
      applyingVoice = true;
      try {
        updateCall(id, "connect");
        if (mediaQuality) updateCall(id, "media", mediaQuality);
      } finally {
        applyingVoice = false;
      }
    }
    async function endVoice(id) {
      const call = state.calls.find((item) => item.id === id);
      if (!call) throw Error("记录不存在");
      if (call.status === "已结束") throw Error("通话已经结束");
      const rtcApi = await loadRtc();
      await rtcApi.leaveChannel();
      if (call.rtc && (call.rtc.channel || call.rtc.callId)) voice("/api/guardian/v1/call/end", { channel: call.rtc.channel, callId: call.rtc.callId });
      callCredentials.delete(id);
      applyingVoice = true;
      try {
        return updateCall(id, "end");
      } finally {
        applyingVoice = false;
      }
    }
    async function muteVoice(id) {
      const call = state.calls.find((item) => item.id === id);
      if (!call) throw Error("记录不存在");
      const rtcApi = await loadRtc();
      await rtcApi.setMuted(!call.muted);
      applyingVoice = true;
      try {
        return updateCall(id, "mute");
      } finally {
        applyingVoice = false;
      }
    }
    function broadcast(groupId, text) {
      if (!text.trim() || text.length > 200) throw Error("广播内容需为 1–200 字");
      const group = requireItem(state.groups, groupId);
      const hats = helmetsFor(group.members, "tts");
      if (voice) voice("/api/guardian/v1/broadcast", { content: text.trim(), hats });
      return commit("发送文字广播", (s) => {
        const g = requireItem(s.groups, groupId);
        if (!text.trim() || text.length > 200)
          throw Error("广播内容需为 1–200 字");
        s.broadcasts.unshift({
          id: "BC" + ++s.seq,
          groupId,
          members: [...g.members],
          groupName: g.name,
          text: text.trim(),
          station: g.station,
          date: demoMode ? DATE : beijingDate(),
          time: now(s),
          status: voice ? "设备平台已受理（播放未确认）" : "已发送",
        });
      });
    }
    function sos(action, ready) {
      if (voice && !ready && action === "join") return joinSosVoice();
      if (voice && !ready && action === "end") return endSosVoice();
      return commit("SOS 协助操作", (s) => {
        if (s.sos.status === "ended") throw Error("本次协助已结束");
        if (action === "join" && s.sos.members.includes("operator"))
          throw Error("值守员已经加入");
        if (action === "join") {
          s.sos.status = "active";
          if (!s.sos.members.includes("operator"))
            s.sos.members.push("operator");
          if (ready) s.sos.rtc = ready;
          s.sos.timeline.push({
            time: now(s).slice(11),
            text: "值守员加入协助",
          });
        }
        if (action === "end") {
          s.sos.status = "ended";
          s.sos.timeline.push({
            time: now(s).slice(11),
            text: "协助结束，记录已保存",
          });
          s.calls.unshift({
            id: "SOS" + ++s.seq,
            kind: "SOS协助",
            members: [s.sos.personId, ...s.sos.members],
            station: s.sos.station,
            date: demoMode ? DATE : beijingDate(),
            time: now(s),
            status: "已结束",
            history: clone(s.sos.timeline),
          });
        }
      });
    }
    async function joinSosVoice() {
      communicationGuard.assertAvailable();
      if (state.sos.status === "ended") throw Error("本次协助已结束");
      if (state.sos.members.includes("operator")) throw Error("值守员已经加入");
      const wearer = state.people.find((item) => item.id === state.sos.personId);
      const helmet = currentDevices(state.sos.personId).find((item) => item.type === "H");
      const hatNumber = helmet ? helmet.id : state.sos.deviceId;
      if (!hatNumber) throw Error((wearer && wearer.name ? wearer.name : "求助人") + "没有领用安全帽");
      const rtc = voice("/api/guardian/v1/call", {
        hats: [{ hatNumber, name: wearer && wearer.name ? wearer.name : state.sos.personName || "" }],
      });
      const rtcApi = await import("../lib/rtc.js");
      await rtcApi.joinChannel(rtc);
      return sos("join", rtc);
    }
    async function endSosVoice() {
      if (state.sos.status === "ended") throw Error("本次协助已结束");
      const channel = state.sos.rtc && state.sos.rtc.channel;
      const rtcApi = await import("../lib/rtc.js");
      await rtcApi.leaveChannel();
      if (channel) voice("/api/guardian/v1/call/end", { channel });
      return sos("end", true);
    }
    function tracks(pid, date, start, end) {
      if (start >= end) throw Error("结束时间必须晚于开始时间");
      if (!person(pid)) return [];
      // Real histories are loaded through the location API with verified geographic coordinates.
      if (!demoMode) return [];
      const reported = (state.locations || [])
        .filter(
          (item) =>
            item.personId === pid &&
            item.inside &&
            item.x != null &&
            item.y != null &&
            typeof item.time === "string" &&
            item.time.slice(0, 10) === date &&
            item.time.slice(11, 16) >= start &&
            item.time.slice(11, 16) <= end,
        )
        .map((item) => ({
          time: item.time.slice(11, 16),
          x: Number(item.x),
          y: Number(item.y),
          personId: pid,
          deviceId: item.deviceId || deviceAt(pid, item.time)?.id || "未绑定",
        }))
        .sort((a, b) => (a.time < b.time ? -1 : a.time > b.time ? 1 : 0));
      if (reported.length) return reported;
      // Connected mode must never turn an empty device history into a demo path.
      if (remoteCommit || currentDevices(pid).some(isRealDevice)) return [];
      if (date !== DATE) return [];
      const offset = Number(pid.slice(1)) * 2;
      const base = [
        { time: "09:00", x: 79, y: 76 },
        { time: "09:15", x: 86, y: 69 },
        { time: "09:30", x: 84, y: 46 },
        { time: "09:38", x: 71, y: 38 },
        { time: "09:46", x: 47, y: 56, gap: true },
        { time: "10:00", x: 38, y: 58 },
        { time: "10:20", x: 32, y: 44 },
        { time: "10:39", x: 36, y: 37 },
        { time: "10:42", x: 37, y: 35 },
      ];
      return base
        .filter((p) => p.time >= start && p.time <= end)
        .map((p) => ({
          ...p,
          x: Math.min(94, p.x + (offset - 2) / 3),
          personId: pid,
          deviceId: deviceAt(pid, DATE + " " + p.time + ":00")?.id || "未绑定",
        }));
    }
    function reset() {
      if (!demoMode) throw Error('真实模式不能重置为演示数据');
      const next = seed();
      if (storage) storage.setItem(KEY, JSON.stringify(next));
      state = next;
      listeners.forEach((f) => f(state));
    }
    return {
      demoMode,
      get state() {
        return state;
      },
      get loadError() {
        return loadError;
      },
      now: () => now(state),
      subscribe: (fn) => (listeners.add(fn), () => listeners.delete(fn)),
      person,
      device,
      work,
      event,
      currentDevices,
      vitals,
      vitalHistory,
      owner,
      currentWork,
      locationDevice,
      locationValid,
      deviceAt,
      filter,
      stats,
      bind,
      release,
      updatePerson,
      updateDevice,
      updateWork,
      syncWorks,
      claim,
      verify,
      capture,
      addEventPhoto,
      saveFence,
      toggleFence,
      deleteFence,
      movePerson,
      saveGroup,
      startCall,
      updateCall,
      applyServerCallStatus(id, result) {
        const call = state.calls.find(item => item.id === id);
        if (!call?.rtc?.callId) return;
        call.serverStatus = result.status;
        call.rtc.status = result.status;
        call.serverConnected = result.serverConnected === true;
        call.connectedDeviceIds = Array.isArray(result.connectedDeviceIds) ? result.connectedDeviceIds : [];
        call.statusLabel = ({ offered:'设备正在振铃', connected:'设备已接通（服务端确认）', ending:'正在结束通话', ended:'已结束', failed:'设备通话失败', unknown:'设备接通状态待确认' })[result.status] || '设备接通状态待确认';
        if (result.status === 'connected' && call.serverConnected) call.status = '通话中';
        if (result.status === 'ending') call.status = '正在结束';
        if (['ended','failed'].includes(result.status)) { call.status = '已结束'; callCredentials.delete(id); }
        listeners.forEach(fn => fn(state));
      },
      broadcast,
      sos,
      tracks,
      reset,
      revision: () => state.seq || 0,
      replaceRemote(next) {
        if (!next || next.version !== 1) return false;
        if (!/[\u4e00-\u9fff]/.test(next.stations?.[0]?.name || "")) return false;
        state = withoutAdministrativeAreas(demoMode ? next : projectSingleSimulatedWatch(next));
        if (storage) {
          try {
            storage.setItem(KEY, JSON.stringify(withoutAdministrativeAreas(next)));
          } catch {
            /* 浏览器拒绝写入时仍使用这次读到的快照。 */
          }
        }
        listeners.forEach((fn) => fn(state));
        return true;
      },
      setRemoteCommit: (fn) => {
        remoteCommit = fn;
      },
      setVoice: (fn) => {
        voice = fn;
      },
    };
  }
  function validate(s) {
    const unique = (arr) => new Set(arr).size === arr.length;
    for (const list of [
      "people",
      "devices",
      "works",
      "events",
      "media",
      "fences",
      "groups",
    ])
      if (!unique(s[list].map((x) => x.id))) throw Error("重复记录 ID");
    const active = s.bindings.filter((b) => !b.end);
    if (!unique(active.map((b) => b.deviceId))) throw Error("设备重复绑定");
    if (
      !unique(
        active.map(
          (b) =>
            b.personId + ":" + s.devices.find((d) => d.id === b.deviceId)?.type,
        ),
      )
    )
      throw Error("同类设备重复绑定");
    for (const b of active)
      if (
        !s.people.some((p) => p.id === b.personId && p.active) ||
        !s.devices.some((d) => d.id === b.deviceId && d.active)
      )
        throw Error("绑定关系无效");
    for (const w of s.works) {
      if (
        !unique(w.members) ||
        w.members.some((id) => !s.people.some((p) => p.id === id && p.active))
      )
        throw Error("作业成员无效");
    }
  }
  function inside(point, polygon) {
    let yes = false;
    for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      const [xi, yi] = polygon[i],
        [xj, yj] = polygon[j];
      if (
        yi > point[1] !== yj > point[1] &&
        point[0] < ((xj - xi) * (point[1] - yi)) / (yj - yi) + xi
      )
        yes = !yes;
    }
    return yes;
  }
  function polygonArea(points) {
    return Math.abs(
      points.reduce((v, p, i) => {
        const q = points[(i + 1) % points.length];
        return v + p[0] * q[1] - q[0] * p[1];
      }, 0) / 2,
    );
  }
  function selfIntersects(p) {
    const cross = (a, b, c) =>
      (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
    for (let i = 0; i < p.length; i++)
      for (let j = i + 2; j < p.length; j++) {
        if (i === 0 && j === p.length - 1) continue;
        const a = p[i],
          b = p[(i + 1) % p.length],
          c = p[j],
          d = p[(j + 1) % p.length];
        if (
          cross(a, b, c) * cross(a, b, d) < 0 &&
          cross(c, d, a) * cross(c, d, b) < 0
        )
          return true;
      }
    return false;
  }
export {
  DATE,
  KEY,
  seed,
  createStore,
  typeNames,
  assetForPerson,
  inside,
  polygonArea,
  selfIntersects,
};
