/* Native UI primitives, routing and reusable spatial/media components. */
(function () {
  "use strict";
  const D = RollingData,
    db = D.createStore(localStorage);
  const R = (window.R = {
    D,
    db,
    views: {},
    s: {
      station: localStorage.getItem("rolling-station") || "S1",
      person: "P1",
      work: "GL-20260915-018",
      event: "RL-E-0915-001",
      media: "IMG-0915-001",
      fence: "F1",
      group: "G1",
      layout: "1+7",
      playing: true,
      volume: 50,
      rotation: false,
      recording: null,
      trackPlaying: false,
      trackIndex: 0,
      trackSpeed: 1,
      trackPoints: [],
      selectedMembers: ["P1", "P2", "P3"],
      layers: { people: true, areas: true, fences: false },
      filters: {},
      fenceDraft: null,
      fenceMode: "select",
      fenceUndo: [],
      formDrafts: {},
      videoTick: 12,
      mediaTab: "all",
      personTab: "人员信息",
      statsTab: "综合",
      sosConfirm: false,
    },
    timers: [],
    esc,
    icon,
    btn,
    link,
    tag,
    dot,
    field,
    select,
    input,
    title,
    panel,
    table,
    avatar,
    empty,
    statCards,
    personName,
    deviceStrip,
    workInfo,
    map,
    video,
    modal,
    closeModal,
    toast,
    go,
    render,
    scope,
    people,
    works,
    events,
    materials,
    mediaImage,
    download,
    csv,
    blobPut,
    blobGet,
    setupMaps,
    setupMedia,
  });
  try {
    const saved = JSON.parse(sessionStorage.getItem("rolling-view") || "null");
    if (saved) {
      Object.assign(R.s, saved);
      R.s.station = localStorage.getItem("rolling-station") || "S1";
      R.s.recording = null;
      R.s.trackPlaying = false;
    }
  } catch {}
  function esc(v) {
    return String(v ?? "").replace(
      /[&<>"']/g,
      (c) =>
        ({
          "&": "&amp;",
          "<": "&lt;",
          ">": "&gt;",
          '"': "&quot;",
          "'": "&#39;",
        })[c],
    );
  }
  function icon(n, cl = "") {
    if (n.startsWith("alarm-warning")) n = n.replace("alarm-warning", "alert");
    return `<i class="ri-${n} ${cl}" aria-hidden="true"></i>`;
  }
  function btn(text, action = "", id = "", cl = "", ic = "") {
    const names = {
      "map-reset": "重置地图",
      "map-zoom-in": "放大地图",
      "map-zoom-out": "缩小地图",
      "track-play": "播放或暂停轨迹",
      "track-stop": "停止轨迹回放",
      "video-play": "播放或暂停视频",
      "video-mute": "切换视频静音",
      "modal-close": "关闭弹窗",
      "page-prev": "上一页",
      "page-next": "下一页",
      "close-person-detail": "关闭人员详情",
      "password-toggle": "显示或隐藏密码",
      "captcha-refresh": "刷新验证码",
    };
    return `<button type="button" class="btn ${cl}" ${!text ? `aria-label="${esc(names[action] || action)}"` : ""} ${action ? `data-action="${action}"` : ""} ${id ? `data-id="${esc(id)}"` : ""}>${ic ? icon(ic) : ""}${text}</button>`;
  }
  function link(text, route, cl = "") {
    return `<a href="#/${route}" class="${cl}">${text}</a>`;
  }
  function tag(text, color = "blue") {
    return `<span class="tag ${color}">${esc(text)}</span>`;
  }
  function dot(text, cl = "green") {
    return `<span class="status ${cl}"><b></b>${esc(text)}</span>`;
  }
  function input(
    name,
    placeholder = "",
    value = "",
    type = "text",
    extra = "",
  ) {
    return `<input name="${name}" type="${type}" value="${esc(value)}" placeholder="${esc(placeholder)}" ${extra}>`;
  }
  function select(name, items, value = "", extra = "") {
    return `<select name="${name}" ${extra}>${items
      .map((o) => {
        const [v, t] = Array.isArray(o) ? o : [o, o];
        return `<option value="${esc(v)}" ${String(v) === String(value) ? "selected" : ""}>${esc(t)}</option>`;
      })
      .join("")}</select>`;
  }
  function field(label, control) {
    return `<label class="field"><span>${label}</span>${control}</label>`;
  }
  function title(text, sub = "", right = "") {
    return `<div class="page-heading"><div><h1>${text}</h1>${sub ? `<p>${sub}</p>` : ""}</div><div class="heading-actions">${right}</div></div>`;
  }
  function panel(text, body, right = "", cl = "") {
    return `<section class="panel ${cl}"><div class="panel-heading"><h2>${text}</h2><div>${right}</div></div><div class="panel-body">${body}</div></section>`;
  }
  function table(head, rows, cl = "") {
    return `<div class="table-scroll"><table class="${cl}"><thead><tr>${head.map((h) => `<th>${h}</th>`).join("")}</tr></thead><tbody>${rows.length ? rows.map((r) => `<tr ${r.attrs || ""}>${r.cells.map((c) => `<td>${c}</td>`).join("")}</tr>`).join("") : `<tr><td colspan="${head.length}">${empty("暂无符合条件的记录")}</td></tr>`}</tbody></table></div>`;
  }
  function avatar(p, photo = false) {
    return photo
      ? `<img class="avatar photo" src="assets/avatar.png" alt="${esc(p?.name || "人员")}">`
      : `<span class="avatar">${esc(p?.name?.slice(0, 1) || "人")}</span>`;
  }
  function empty(text = "暂无数据") {
    return `<div class="empty">${icon("inbox-2-line")}<span>${text}</span></div>`;
  }
  function scope(extra = {}) {
    return { station: R.s.station, ...extra };
  }
  function people() {
    return db.state.people.filter((p) => p.station === R.s.station && p.active);
  }
  function works() {
    return db.filter(db.state.works, scope());
  }
  function events() {
    return db.filter(db.state.events, scope());
  }
  function materials() {
    return db.filter(db.state.media, scope());
  }
  function personName(id) {
    return id === "operator" ? "值守员" : esc(db.person(id)?.name || "未分配");
  }
  function statCards(items, cl = "") {
    return `<div class="stats ${cl}">${items.map(([ic, label, value, unit = "", color = "cyan", detail = ""]) => `<div class="stat">${icon(ic, color)}<div><span>${label}</span><strong>${value} <small>${unit}</small></strong>${detail ? `<em>${detail}</em>` : ""}</div></div>`).join("")}</div>`;
  }
  function deviceStrip(pid, large = false) {
    const devices = db.currentDevices(pid);
    return `<div class="device-strip ${large ? "large" : ""}">${["H", "B", "W"]
      .map((type) => {
        const d = devices.find((x) => x.type === type);
        return `<div class="device-item">${d ? `<img src="assets/${{ H: "helmet", B: "harness", W: "watch" }[type]}.png?v=transparent-20260921" alt="${D.typeNames[type]}">` : icon("link-unlink")}<div>${large ? `<b>${D.typeNames[type]}</b>` : ""}<small>${esc(d?.id || "未领用")}</small>${d ? dot(!d.online ? "连接中断" : d.battery <= 20 ? "电量 " + d.battery + "%" : "在线", !d.online ? "red" : d.battery <= 20 ? "yellow" : "green") : tag("未领用", "muted")}${large && d ? `<small>末次上报<br>${esc(d.updated)}</small><small>${icon("battery-line")} 电量 ${d.battery}%</small>` : ""}</div></div>`;
      })
      .join("")}</div>`;
  }
  function workInfo(w) {
    if (!w) return empty("暂无关联作业");
    return `<dl class="info"><dt>工作票号</dt><dd>${esc(w.id)} ${tag("只读", "muted")}</dd><dt>作业名称</dt><dd>${esc(w.name)}</dd><dt>作业区域</dt><dd>${esc(w.area)}</dd><dt>监护人</dt><dd>${personName(w.supervisor)}</dd><dt>工作负责人</dt><dd>${personName(w.leader)}</dd><dt>作业时段</dt><dd>${w.date} ${w.start} ～ ${w.end}</dd><dt>作业人员</dt><dd>${w.members.length} 人 · ${w.members.map(personName).join(" / ")}</dd><dt>作业状态</dt><dd>${tag(w.status)}</dd></dl>`;
  }
  function map(opts = {}) {
    const mode = opts.mode || "live",
      pid = opts.person || "",
      id = "map-" + Math.random().toString(36).slice(2);
    const filtered = (
      pid ? people().filter((p) => p.id === pid) : people()
    ).filter((p) => !opts.personIds || opts.personIds.includes(p.id));
    const showMarkers = opts.markers !== false && mode !== "fence";
    const selected = db.person(pid || R.s.person);
    return `<div class="map ${opts.class || ""}" data-map="${mode}" data-person="${esc(pid)}" id="${id}"><div class="map-world"><img src="assets/plant-map.png" alt="厂区示意底图"><canvas aria-label="作业区域与轨迹图层"></canvas><div class="map-labels">${[
      ["锅炉区", 34, 31],
      ["配电区", 20, 73],
      ["汽机厂房", 52, 73],
      ["循环水区", 81, 35],
    ]
      .map(
        ([t, x, y]) =>
          `<span class="map-zone" style="left:${x}%;top:${y}%">${t}</span>`,
      )
      .join(
        "",
      )}</div>${showMarkers && R.s.layers.people ? filtered.map((p) => `<button class="map-person ${db.locationValid(p.id) ? "" : "warning"} ${selected?.id === p.id ? "selected" : ""}" data-action="map-person" data-id="${p.id}" style="left:${p.position[0]}%;top:${p.position[1]}%" aria-label="定位 ${esc(p.name)}">${icon("user-fill")}</button>`).join("") : ""}${opts.popup && selected ? `<div class="map-popup" style="left:${Math.min(60, selected.position[0] + 3)}%;top:${Math.max(3, selected.position[1] - 31)}%"><b>${esc(selected.name)}</b>　${esc(db.currentDevices(selected.id).find((d) => d.type === "H")?.id || "未绑定")}<p>作业：${esc(db.currentWork(selected.id)?.name || "待分配")}</p><p>位置：${esc(selected.area)}　${dot(db.locationValid(selected.id) ? "位置有效" : "待核验", db.locationValid(selected.id) ? "green" : "yellow")}</p><div class="row">${link("历史轨迹 →", "tracks/" + selected.id, "text-link")}${link("查看人员", "person/" + selected.id, "text-link")}</div></div>` : ""}</div><div class="map-caption">厂区示意 · 非实测</div><div class="map-compass">N<br>${icon("navigation-fill")}</div><div class="map-tools">${btn("", "map-reset", "", "icon-only", "crosshair-2-line")}${btn("", "map-zoom-in", "", "icon-only", "add-line")}${btn("", "map-zoom-out", "", "icon-only", "subtract-line")}</div>${opts.legend !== false ? `<div class="map-legend">图例<br>${icon("user-fill", "blue")} 人员位置<br>${icon("checkbox-blank-line", "cyan")} 作业区域<br>${icon("error-warning-line", "yellow")} 待核验位置</div>` : ""}<div class="map-scale">0　　　　 250　　　500 m<hr></div>${mode === "fence" ? `<div class="map-editbar">${btn("选择", "fence-mode", "select", R.s.fenceMode === "select" ? "primary" : "", "cursor-line")}${btn("绘制区域", "fence-mode", "draw", R.s.fenceMode === "draw" ? "primary" : "", "shape-line")}${btn("编辑节点", "fence-mode", "edit", R.s.fenceMode === "edit" ? "primary" : "", "node-tree")}${btn("撤销", "fence-undo", "", "", "arrow-go-back-line")}</div><div class="map-instruction">${R.s.fenceMode === "draw" ? "单击添加节点，双击完成绘制" : R.s.fenceMode === "edit" ? "拖动节点调整区域，保存后生效" : "拖动地图平移，使用右侧按钮缩放"}</div>` : ""}</div>`;
  }
  function video(pid = "P1", opts = {}) {
    const p = db.person(pid),
      d = db.currentDevices(pid).find((d) => d.type === "H"),
      asset = opts.asset || D.assetForArea(p?.area),
      unavailable = !opts.asset && (!d || d.video !== "available");
    return `<div class="video-frame ${opts.class || ""}" data-video-person="${esc(pid)}"><img src="assets/${asset}" alt="${esc(p?.area || "现场")}第一人称现场画面">${unavailable ? `<div class="video-unavailable">${icon("vidicon-off-line")}<strong>${!d ? "未绑定安全帽" : d?.video === "off" ? "视频未开启" : "回传中断"}</strong><small>${!d ? "请先领用并绑定安全帽" : d?.video === "off" ? "视频通道尚未开启" : "保留最后画面 · 请联系现场人员"}</small></div>` : ""}<span class="video-label">${opts.label || "示例画面 · 非实时"}</span>${opts.name ? `<div class="video-name"><b>${esc(p?.name)}</b>　${esc(d?.id || "未绑定")}<small>${esc(p?.area)} · ${esc(db.currentWork(pid)?.name || "待分配")}</small></div>` : ""}<span class="video-time">${D.DATE} 10:42:18</span>${opts.controls ? `<div class="video-controls">${btn("", "video-play", "", "icon-only", R.s.playing ? "pause-fill" : "play-fill")}${btn("", "video-mute", "", "icon-only", R.s.volume ? "volume-up-line" : "volume-mute-line")}<input aria-label="音量" data-setting="volume" type="range" min="0" max="100" value="${R.s.volume}"><span data-video-time>00:${String(R.s.videoTick % 60).padStart(2, "0")} / --:--</span><div class="spacer"></div>${btn("抓拍", "capture", pid, "plain", "camera-line")}${btn(R.s.recording ? "停止录像" : "录像", "record", pid, R.s.recording ? "red plain" : "plain", "record-circle-line")}${link(icon("map-pin-line") + "轨迹", "tracks/" + pid, "btn plain")}${btn("对讲", "call-person", pid, "plain", "mic-line")}${btn("全屏", "fullscreen", "", "plain", "fullscreen-line")}</div>` : ""}</div>`;
  }
  function mediaImage(m) {
    return `<img ${m.blobId ? `data-blob="${esc(m.blobId)}"` : `src="assets/${esc(m.asset || "scene-boiler.png")}"`} alt="${esc(m.title)}">`;
  }
  function modal(title, body, footer = "", cl = "") {
    const root = document.getElementById("modal-root");
    R.returnFocus = document.activeElement;
    root.innerHTML = `<div class="modal-backdrop"><section class="modal ${cl}" role="dialog" aria-modal="true" aria-label="${esc(title)}"><header><h2>${title}</h2>${btn("", "modal-close", "", "icon-only", "close-line")}</header><div class="modal-body">${body}</div>${footer ? `<footer>${footer}</footer>` : ""}</section></div>`;
    root.querySelector("input,select,textarea,button")?.focus();
    setupMedia();
  }
  function closeModal() {
    document.getElementById("modal-root").innerHTML = "";
    R.returnFocus?.focus?.();
  }
  function toast(text, error = false) {
    const el = document.createElement("div");
    el.className = "toast " + (error ? "error" : "");
    el.innerHTML =
      icon(error ? "error-warning-line" : "checkbox-circle-line") + esc(text);
    document.getElementById("toasts").append(el);
    setTimeout(() => el.remove(), 4200);
  }
  function go(route) {
    location.hash = "#/" + route;
  }
  function updateHeaderClock() {
    const clock = document.querySelector("[data-header-clock]");
    if (!clock) return;
    const now = new Date();
    const pad = (value) => String(value).padStart(2, "0");
    clock.dateTime = now.toISOString();
    clock.textContent = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
  }
  function render() {
    R.screen?.destroy();
    document.documentElement.classList.remove("screen-mode");
    const callPlayback = new Map();
    document.querySelectorAll("video[data-call-video]").forEach((player) => {
      callPlayback.set(player.dataset.callVideo, {time: player.currentTime, paused: player.paused});
      player.pause();
      player.removeAttribute("src");
      player.load();
    });
    R.timers.forEach(clearInterval);
    R.timers = [];
    const [path = "overview", id = "", tab = ""] = location.hash
      .replace(/^#\/?/, "")
      .split("/");
    R.route = path;
    R.routeId = decodeURIComponent(id);
    R.routeTab = tab;
    const authenticated = sessionStorage.getItem("rolling-session");
    if (!authenticated && path !== "login") {
      location.hash = "#/login";
      return;
    }
    if (path === "login") {
      document.getElementById("app").innerHTML = R.views.login();
      return;
    }
    if (!R.views[path]) {
      go("overview");
      return;
    }
    R.s.filters[path] ??= {};
    const owner =
      {
        person: "personnel",
        work: "works",
        single: "video",
        tracks: "location",
        fences: "location",
        event: "alarms",
        sos: "dispatch",
      }[path] || path;
    const nav = [
      ["overview", "综合总览", "layout-grid-line"],
      ["personnel", "人员与装备", "user-line"],
      ["works", "作业监护", "clipboard-line"],
      ["video", "视频监看", "vidicon-line"],
      ["dispatch", "调度通信", "mic-line"],
      ["location", "定位与轨迹", "map-pin-line"],
      ["alarms", "告警与核验", "alarm-warning-line"],
      ["materials", "现场资料", "file-list-3-line"],
      ["statistics", "统计追溯", "bar-chart-box-line"],
    ];
    const page = R.views[path]();
    if (path === "screen") {
      document.documentElement.classList.add("screen-mode");
      document.getElementById("app").innerHTML = page;
      R.screen.mount();
      return;
    }
    document.getElementById("app").innerHTML =
      `<header class="topbar"><a class="brand" href="#/overview"><img src="assets/logo.png" alt="ROLLING"></a><span class="brand-divider"></span><strong>融瓴智能穿戴安全监护平台</strong><div class="top-actions">${link(icon("dashboard-3-line") + "数据大屏", "screen", "screen-entry")}${icon("building-2-line", "blue")}${select(
        "station",
        db.state.stations.map((s) => [s.id, s.name]),
        R.s.station,
        'aria-label="选择厂站" data-setting="station"',
      )}<span class="top-divider"></span>${btn(`<span class="notification-count">${db.stats(scope()).unresolved}</span>`, "notifications", "", "icon-only notification", "notification-3-line")}${btn("值守员 " + icon("arrow-down-s-line"), "user-menu", "", "plain", "user-fill")}<time data-header-clock aria-label="当前时间"></time></div></header><aside class="sidebar"><nav>${nav.map(([p, t, ic]) => link(icon(ic) + `<span>${t}</span>`, p, owner === p ? "active" : "")).join("")}</nav><div class="sidebar-bottom"><small>示例数据</small></div></aside><main class="main ${path}-page" id="main">${page}</main><div class="page-foot">示例数据</div>`;
    updateHeaderClock();
    R.timers.push(setInterval(updateHeaderClock, 1000));
    setupMaps();
    setupMedia();
    document.querySelectorAll("video[data-call-video]").forEach((player) => {
      player.muted = true;
      const previous = callPlayback.get(player.dataset.callVideo);
      player.addEventListener("loadedmetadata", () => {
        if (previous) {
          player.currentTime = Number.isFinite(player.duration) && player.duration > 0
            ? previous.time % player.duration : previous.time;
          if (previous.paused) { player.pause(); return; }
        }
        player.play().catch(() => { /* Native controls allow manual playback. */ });
      }, {once: true});
      player.addEventListener("error", () => {
        player.parentElement.querySelector(".call-video-error").hidden = false;
      }, {once: true});
    });
    try {
      sessionStorage.setItem("rolling-view", JSON.stringify(R.s));
    } catch {}
    if (R.s.rotation && path === "video")
      R.timers.push(
        setInterval(() => {
          const a = R.videoPeople().filter((p) =>
            db.currentDevices(p.id).some((d) => d.video === "available"),
          );
          if (a.length) {
            R.s.person =
              a[(a.findIndex((p) => p.id === R.s.person) + 1) % a.length].id;
            render();
          }
        }, 30000),
      );
    if (["single", "work"].includes(path) && R.s.playing)
      R.timers.push(
        setInterval(() => {
          R.s.videoTick++;
          document
            .querySelectorAll("[data-video-time]")
            .forEach(
              (el) =>
                (el.textContent = `${String(Math.floor(R.s.videoTick / 60)).padStart(2, "0")}:${String(R.s.videoTick % 60).padStart(2, "0")} / --:--`),
            );
        }, 1000),
      );
    if (path === "tracks" && R.s.trackPlaying)
      R.timers.push(
        setInterval(() => {
          R.s.trackIndex++;
          if (R.s.trackIndex >= R.s.trackPoints.length) {
            R.s.trackIndex = Math.max(0, R.s.trackPoints.length - 1);
            R.s.trackPlaying = false;
          }
          render();
        }, 1500 / R.s.trackSpeed),
      );
  }
  function download(filename, content, type = "text/plain;charset=utf-8") {
    const blob =
      content instanceof Blob ? content : new Blob([content], { type });
    const url = URL.createObjectURL(blob),
      a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.append(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 60000);
  }
  function csv(filename, headers, rows) {
    const cell = (v) =>
      '"' +
      String(v ?? "")
        .replace(/^[=+@-]/, "'$&")
        .replace(/"/g, '""') +
      '"';
    const content =
      "\ufeff" +
      [headers, ...rows].map((r) => r.map(cell).join(",")).join("\r\n");
    download(filename, content, "text/csv;charset=utf-8");
    modal(
      "导出预览 · " + esc(filename),
      `<p class="note">按当前筛选生成 ${rows.length} 条记录。如浏览器未自动下载，请点击下方保存 CSV。</p>${table(
        headers,
        rows.map((row) => ({ cells: row.map(esc) })),
      )}`,
      `<a class="btn primary" download="${esc(filename)}" href="data:text/csv;charset=utf-8,${encodeURIComponent(content)}">保存 CSV</a>${btn("关闭", "modal-close")}`,
      "wide",
    );
  }
  let idb;
  function blobDB() {
    return (
      idb ||
      (idb = new Promise((resolve, reject) => {
        const r = indexedDB.open("rolling-native-files", 1);
        r.onupgradeneeded = () => r.result.createObjectStore("files");
        r.onsuccess = () => resolve(r.result);
        r.onerror = () => reject(Error("无法访问本地文件存储"));
      }))
    );
  }
  async function blobPut(id, blob) {
    const d = await blobDB();
    return new Promise((resolve, reject) => {
      const t = d.transaction("files", "readwrite");
      t.objectStore("files").put(blob, id);
      t.oncomplete = () => resolve(id);
      t.onerror = () => reject(Error("照片保存失败，请检查磁盘空间"));
      t.onabort = () => reject(Error("照片保存事务已取消"));
    });
  }
  async function blobGet(id) {
    const d = await blobDB();
    return new Promise((resolve, reject) => {
      const r = d.transaction("files").objectStore("files").get(id);
      r.onsuccess = () => resolve(r.result);
      r.onerror = () => reject(Error("照片读取失败"));
    });
  }
  async function setupMedia() {
    for (const img of document.querySelectorAll("img[data-blob]")) {
      try {
        const blob = await blobGet(img.dataset.blob);
        if (blob) {
          const url = URL.createObjectURL(blob);
          img.src = url;
          img.onload = () => URL.revokeObjectURL(url);
        } else img.alt = "本地照片文件不存在";
      } catch (e) {
        img.alt = e.message;
      }
    }
  }
  function setupMaps() {
    document.querySelectorAll("[data-map]").forEach((el) => {
      const world = el.querySelector(".map-world"),
        canvas = el.querySelector("canvas"),
        mode = el.dataset.map;
      let zoom = 1,
        pan = [0, 0],
        drag = null;
      const ctx = canvas.getContext("2d");
      function paint() {
        const w = el.clientWidth,
          h = el.clientHeight;
        canvas.width = w * devicePixelRatio;
        canvas.height = h * devicePixelRatio;
        ctx.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0);
        ctx.clearRect(0, 0, w, h);
        const poly = (pts, color, fill, dash = []) => {
          if (!pts.length) return;
          ctx.beginPath();
          pts.forEach((p, i) =>
            i
              ? ctx.lineTo((p[0] * w) / 100, (p[1] * h) / 100)
              : ctx.moveTo((p[0] * w) / 100, (p[1] * h) / 100),
          );
          ctx.closePath();
          ctx.strokeStyle = color;
          ctx.fillStyle = fill;
          ctx.lineWidth = 2.5;
          ctx.setLineDash(dash);
          ctx.fill();
          ctx.stroke();
          ctx.setLineDash([]);
        };
        if (R.s.layers.areas && mode !== "fence")
          [
            [
              [29, 20],
              [43, 20],
              [43, 58],
              [29, 58],
            ],
            [
              [13, 61],
              [29, 61],
              [29, 87],
              [13, 87],
            ],
            [
              [40, 64],
              [65, 64],
              [65, 83],
              [40, 83],
            ],
            [
              [73, 27],
              [90, 27],
              [90, 75],
              [73, 75],
            ],
          ].forEach((p, i) =>
            poly(
              p,
              i ? "#00e9dd" : "#ffcc42",
              i ? "#00dac00b" : "#ffcc420a",
              [6, 4],
            ),
          );
        if (R.s.layers.fences && mode !== "fence")
          db.state.fences
            .filter(
              (f) => f.station === R.s.station && f.enabled && !f.archived,
            )
            .forEach((f) => poly(f.points, "#15e1be", "#00bfa021", [7, 3]));
        if (mode === "fence" && R.s.fenceDraft) {
          poly(R.s.fenceDraft.points, "#20b9ff", "#1294fa44", [5, 4]);
          R.s.fenceDraft.points.forEach((p) => {
            ctx.beginPath();
            ctx.arc((p[0] * w) / 100, (p[1] * h) / 100, 7, 0, Math.PI * 2);
            ctx.fillStyle = "#168bff";
            ctx.fill();
            ctx.strokeStyle = "#e7faff";
            ctx.lineWidth = 3;
            ctx.stroke();
          });
        }
        if (mode === "tracks") {
          const pts = R.s.trackPoints;
          ctx.lineWidth = 4;
          ctx.strokeStyle = "#09d9ff";
          ctx.shadowColor = "#00aaff";
          ctx.shadowBlur = 7;
          ctx.beginPath();
          pts.forEach((p, i) => {
            const x = (p.x * w) / 100,
              y = (p.y * h) / 100;
            if (!i || p.gap) {
              ctx.moveTo(x, y);
            } else ctx.lineTo(x, y);
          });
          ctx.stroke();
          ctx.shadowBlur = 0;
          pts.forEach((p) => {
            ctx.beginPath();
            ctx.arc((p.x * w) / 100, (p.y * h) / 100, 5, 0, Math.PI * 2);
            ctx.fillStyle = "#def9ff";
            ctx.fill();
            ctx.strokeStyle = "#00bfff";
            ctx.lineWidth = 2;
            ctx.stroke();
          });
          const p = pts[R.s.trackIndex];
          if (p) {
            ctx.beginPath();
            ctx.arc((p.x * w) / 100, (p.y * h) / 100, 13, 0, Math.PI * 2);
            ctx.fillStyle = "#008fff";
            ctx.fill();
            ctx.strokeStyle = "white";
            ctx.stroke();
          }
        }
      }
      paint();
      const observer = new ResizeObserver(paint);
      observer.observe(el);
      setTimeout(() => {
        if (!el.isConnected) observer.disconnect();
      }, 5000);
      const point = (e) => {
        const b = world.getBoundingClientRect();
        return [
          Math.max(0, Math.min(100, ((e.clientX - b.left) / b.width) * 100)),
          Math.max(0, Math.min(100, ((e.clientY - b.top) / b.height) * 100)),
        ];
      };
      el.addEventListener("pointerdown", (e) => {
        if (e.target.closest("button,.map-popup,.map-editbar")) return;
        if (mode === "fence" && R.s.fenceDraft && R.s.fenceMode === "draw") {
          if (e.detail > 1) return;
          R.s.fenceUndo.push(structuredClone(R.s.fenceDraft.points));
          R.s.fenceDraft.points.push(point(e));
          paint();
          return;
        }
        if (mode === "fence" && R.s.fenceDraft && R.s.fenceMode === "edit") {
          const p = point(e),
            i = R.s.fenceDraft.points.findIndex(
              (q) => Math.hypot(q[0] - p[0], q[1] - p[1]) < 3,
            );
          if (i >= 0) {
            R.s.fenceUndo.push(structuredClone(R.s.fenceDraft.points));
            drag = { node: i };
          }
        } else drag = { start: [e.clientX, e.clientY], pan: [...pan] };
        if (drag) el.setPointerCapture(e.pointerId);
      });
      el.addEventListener("pointermove", (e) => {
        if (!drag) return;
        if (drag.node !== undefined) {
          R.s.fenceDraft.points[drag.node] = point(e);
          paint();
        } else {
          pan = [
            drag.pan[0] + e.clientX - drag.start[0],
            drag.pan[1] + e.clientY - drag.start[1],
          ];
          world.style.transform = `translate(${pan[0]}px,${pan[1]}px) scale(${zoom})`;
        }
      });
      el.addEventListener("pointerup", () => (drag = null));
      el.addEventListener("dblclick", () => {
        if (mode === "fence" && R.s.fenceMode === "draw") {
          R.s.fenceMode = "edit";
          R.toast("绘制完成，可拖动节点调整");
          R.render();
        }
      });
      el.addEventListener("click", (e) => {
        const a = e.target.closest("[data-action]")?.dataset.action;
        if (!a?.startsWith("map-") || a === "map-person") return;
        if (a === "map-reset") {
          zoom = 1;
          pan = [0, 0];
        }
        if (a === "map-zoom-in") zoom = Math.min(3, zoom + 0.2);
        if (a === "map-zoom-out") zoom = Math.max(1, zoom - 0.2);
        world.style.transform = `translate(${pan[0]}px,${pan[1]}px) scale(${zoom})`;
      });
    });
  }
})();
