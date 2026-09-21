(function (root) {
  "use strict";
  const DATE = "2026-09-15",
    KEY = "rolling-native-v1";
  const clone = (x) => JSON.parse(JSON.stringify(x));
  const typeNames = { H: "智能安全帽", B: "智能安全带", W: "智能手表" };
  const areas = ["锅炉区", "汽机厂房", "配电区", "循环水区"];
  const assetForArea = (a) =>
    ({
      锅炉区: "scene-boiler.png",
      汽机厂房: "scene-turbine.png",
      配电区: "scene-electric.png",
      循环水区: "scene-water.png",
    })[a] || "scene-boiler.png";
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
      area: i < 3 ? areas[0] : i < 5 ? areas[1] : i < 7 ? areas[2] : areas[3],
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
        area: areas[0],
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
        area: areas[1],
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
        area: areas[2],
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
        externalStatus: "处理中（同步示例）",
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
    ].map((e, i) => ({
      ...e,
      station: "S1",
      date: DATE,
      externalId: "AQ-20260915-" + String(17 + i).padStart(3, "0"),
      snapshot: {
        personName: people.find((p) => p.id === e.personId).name,
        deviceId: e.deviceId,
        workName: works.find((w) => w.id === e.workId).name,
      },
      draft: null,
      verification: null,
      timeline: [
        { time: e.time, text: "检测到" + e.title },
        { time: "10:41", text: i === 0 ? "周明开始现场核验" : "事件已登记" },
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
      source: "设备回传（示例）",
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
        personId: "P8",
        deviceId: "RL-H008",
        personName: "何平",
        station: "S1",
        status: "waiting",
        members: ["P3"],
        timeline: [
          { time: "10:42:08", text: "收到 SOS 演练请求" },
          { time: "10:42:10", text: "发送分组邀请" },
          { time: "10:42:14", text: "周明加入（演练示例）" },
        ],
      },
      audit: [],
    };
  }
  function createStore(storage) {
    let state = seed(),
      loadError = "";
    try {
      const raw = storage && storage.getItem(KEY);
      if (raw) {
        const parsed = JSON.parse(raw);
        if (parsed.version === 1) state = parsed;
        else throw Error("版本不匹配");
      }
    } catch (e) {
      loadError = "本地数据读取失败，已载入初始数据：" + e.message;
    }
    // Upgrade older saves without replacing business changes or inventing new bindings.
    if (!Array.isArray(state.vitals)) {
      state.vitals = seed().vitals.filter((v) => state.bindings.some((b) =>
        b.id === v.bindingId && b.personId === v.personId && b.deviceId === v.deviceId &&
        b.start <= v.observedAt && (!b.end || b.end > v.observedAt)));
    }
    const listeners = new Set();
    const now = (s) =>
      DATE +
      " " +
      [
        Math.floor(s.clock / 3600) % 24,
        Math.floor(s.clock / 60) % 60,
        s.clock % 60,
      ]
        .map((v) => String(v).padStart(2, "0"))
        .join(":");
    function commit(label, fn) {
      const next = clone(state);
      next.clock++;
      const value = fn(next);
      validate(next);
      next.audit.push({ id: "A" + ++next.seq, time: now(next), text: label });
      if (storage) storage.setItem(KEY, JSON.stringify(next));
      state = next;
      listeners.forEach((fn) => fn(state));
      return value;
    }
    function person(id) {
      return state.people.find((p) => p.id === id);
    }
    function device(id) {
      return state.devices.find((d) => d.id === id);
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
      return state.vitals.filter((v) => v.personId === pid)
        .sort((a, b) => b.observedAt.localeCompare(a.observedAt));
    }
    function vitals(pid) {
      const p = person(pid);
      const watch = currentDevices(pid).find((d) => d.type === "W" && d.active);
      const binding = watch && state.bindings.find((b) => !b.end && b.personId === pid && b.deviceId === watch.id);
      const record = p?.active && binding ? vitalHistory(pid).find((v) =>
        v.bindingId === binding.id && v.deviceId === watch.id && v.observedAt >= binding.start) || null : null;
      const status = !p?.active ? "人员已停用" : !watch ? "未绑定手表" : !watch.online ? "手表离线 · 最近观测" : !record ? "暂无本次领用观测" : "预置观测";
      return { watch, record, status };
    }
    function locationValid(pid) {
      const p = person(pid),
        h = currentDevices(pid).find((d) => d.type === "H");
      return !!(p && p.active && p.locationValid && h && h.online && h.active);
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
          w.date === DATE && w.members.includes(pid) && w.status !== "已结束",
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
      const dateValid = !scope.date || scope.date === DATE;
      const people = state.people.filter(
        (p) =>
          p.active &&
          (!scope.station || p.station === scope.station) &&
          dateValid &&
          (!scope.workId || scope.workId === "all" || members.has(p.id)),
      );
      const ids = new Set(people.map((p) => p.id));
      const devices = state.bindings
        .filter((b) => !b.end && ids.has(b.personId))
        .map((b) => device(b.deviceId))
        .filter((d) => d && d.active);
      const events = filter(state.events, scope);
      return {
        people,
        devices,
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
              position: [50, 50],
              locationValid: true,
              updated: "10:42",
              area: areas[0],
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
    function updateWork(id, fields) {
      return commit("保存作业成员", (s) => {
        const w = requireItem(s.works, id);
        const members = [...new Set(fields.members || [])];
        for (const pid of members) {
          const p = requireItem(s.people, pid);
          if (!p.active || p.station !== w.station) throw Error("作业成员无效");
          if (
            s.works.some(
              (other) =>
                other.id !== id &&
                other.date === w.date &&
                other.status !== "已结束" &&
                other.members.includes(pid),
            )
          )
            throw Error(p.name + " 已参加其他作业");
        }
        if (fields.start && fields.end && fields.start >= fields.end)
          throw Error("结束时间必须晚于开始时间");
        w.members = members;
        w.supervisor = members.includes(fields.supervisor)
          ? fields.supervisor
          : members[0] || null;
        w.leader = members.includes(fields.leader)
          ? fields.leader
          : members[0] || null;
        if (fields.start) w.start = fields.start;
        if (fields.end) w.end = fields.end;
      });
    }
    function syncWorks(station) {
      return commit("刷新作业来源（本地模拟）", (s) =>
        s.works
          .filter((w) => w.station === station)
          .forEach((w) => {
            w.synced = true;
            w.syncedAt = now(s);
          }),
      );
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
              p.area + (kind === "photo" ? "现场抓拍" : "模拟录像记录"),
            personId: pid,
            deviceId: b.deviceId,
            workId: w?.id || "",
            eventId: options.eventId || "",
            station: p.station,
            date: DATE,
            created,
            time: created.slice(11),
            asset: assetForArea(p.area),
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
          date: DATE,
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
        if (polygonArea(fields.points) < 1) throw Error("围栏区域过小");
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
    function startCall(members, kind = "群呼", station = "S1") {
      return commit("发起" + kind, (s) => {
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
          id: "CALL" + ++s.seq,
          members,
          kind,
          station,
          date: DATE,
          time: now(s),
          status: "正在呼叫",
          muted: false,
          joined: [],
          history: [{ time: now(s), text: "发起" + kind }],
        };
        s.calls.unshift(call);
        return call.id;
      });
    }
    function updateCall(id, action, pid) {
      return commit("更新模拟通话", (s) => {
        const c = requireItem(s.calls, id);
        if (c.status === "已结束") throw Error("通话已经结束");
        if (action === "connect") {
          c.status = "通话中";
          c.joined = [...c.members];
        }
        if (action === "end") {
          c.status = "已结束";
          c.endedAt = now(s);
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
            connect: "模拟接通",
            end: "通话结束",
            mute: "切换静音",
            invite: "邀请成员",
          }[action],
        });
      });
    }
    function broadcast(groupId, text) {
      return commit("发送模拟文字广播", (s) => {
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
          date: DATE,
          time: now(s),
          status: "已发送（模拟）",
        });
      });
    }
    function sos(action) {
      return commit("SOS 演练操作", (s) => {
        if (s.sos.status === "ended") throw Error("本次协助已结束");
        if (action === "join" && s.sos.members.includes("operator"))
          throw Error("值守员已经加入");
        if (action === "join") {
          s.sos.status = "active";
          if (!s.sos.members.includes("operator"))
            s.sos.members.push("operator");
          s.sos.timeline.push({
            time: now(s).slice(11),
            text: "值守员加入协助（模拟）",
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
            kind: "SOS 演练",
            members: [s.sos.personId, ...s.sos.members],
            station: s.sos.station,
            date: DATE,
            time: now(s),
            status: "已结束",
            history: clone(s.sos.timeline),
          });
        }
      });
    }
    function tracks(pid, date, start, end) {
      if (start >= end) throw Error("结束时间必须晚于开始时间");
      if (date !== DATE || !person(pid)) return [];
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
      const next = seed();
      if (storage) storage.setItem(KEY, JSON.stringify(next));
      state = next;
      listeners.forEach((f) => f(state));
    }
    return {
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
      broadcast,
      sos,
      tracks,
      reset,
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
  const api = {
    DATE,
    KEY,
    seed,
    createStore,
    typeNames,
    areas,
    assetForArea,
    inside,
    polygonArea,
    selfIntersects,
  };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.RollingData = api;
})(typeof window !== "undefined" ? window : globalThis);
