import { DATE } from "@/mock/data";
import { db } from "@/mock/runtime";
import { events, people as stationPeople, scope } from "@/lib/queries";
import { session } from "@/stores/session";
import { INTERVALS, currentVital, eventWindow, isVitalAlert, nextPerson, videoPeople } from "./screen-model";

const esc = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);

const svg = (body, viewBox = "0 0 48 48") =>
  `<svg viewBox="${viewBox}" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;

const symbols = {
  factory: svg('<path d="M3 44h42M8 44V27l10-5v22M18 34l11-6v16M29 44V8h6v36M32 8V3h4M10 31h3M10 36h3M22 35v4M38 34h4v10"/>'),
  chain: svg('<path d="m20 16 8-8a7 7 0 0 1 10 10l-8 8M28 32l-8 8a7 7 0 0 1-10-10l8-8M17 31l14-14"/>'),
  battery: svg('<rect x="5" y="13" width="33" height="23" rx="2"/><path d="M42 19v11"/><rect x="9" y="17" width="10" height="15" rx="1" fill="currentColor" stroke="none"/>'),
  pin: svg('<path d="M24 46C21 40 8 25 8 17a16 16 0 0 1 32 0c0 8-13 23-16 29Z" fill="#03caf2" stroke="none"/><circle cx="24" cy="17" r="8" fill="#063657" stroke="#65e6ff" stroke-width="2"/><circle cx="24" cy="17" r="4.5" fill="#12b9e9" stroke="none"/>'),
  document: svg('<rect x="12" y="8" width="25" height="34" rx="2"/><path d="M20 8V5h9v6h-9ZM18 18h13M18 24h13M18 30h13M18 36h9"/>'),
  antenna: svg('<circle cx="24" cy="20" r="3"/><path d="M24 23v20M17 14a9 9 0 0 0 0 13M31 14a9 9 0 0 1 0 13M11 8a17 17 0 0 0 0 25M37 8a17 17 0 0 1 0 25"/>'),
  warning: svg('<path d="M21 7a3 3 0 0 1 6 0L43 37c1 3 0 5-3 5H8c-3 0-4-2-3-5Z"/><path d="M24 17v12"/><circle cx="24" cy="35" r="1.5" fill="currentColor" stroke="none"/>'),
  worker: svg('<path d="M14 20v-6a10 10 0 0 1 20 0v6M22 5V2h4v3M11 21c7 3 19 3 26 0M15 24c0 13 18 13 18 0M17 33C7 37 7 41 7 48h34c0-7 0-11-10-15"/>', "0 0 48 52"),
  heart: svg('<path d="M24 41 7 24C-4 12 13 0 24 14 35 0 52 12 41 24Z"/><path d="m5 26 9 0 5-8 7 15 5-9 10 0"/>'),
  oxygen: svg('<path d="M24 3C20 12 10 24 10 31a14 14 0 0 0 28 0C38 24 28 12 24 3Z"/><path d="M18 28c-4 7 2 12 7 11"/>'),
  temperature: svg('<path d="M18 29V9a6 6 0 0 1 12 0v20a11 11 0 1 1-12 0Z"/><path d="M24 12v23"/><circle cx="24" cy="37" r="4"/>'),
};

function title(text, right = "") {
  return `<header class="screen-panel-title"><h2>${text}</h2>${right}</header>`;
}

function frame() {
  const station = db.state.stations.find((item) => item.id === session.station)?.name || "未选择电厂";
  return `<div class="screen-stage"><main class="screen" aria-label="数据大屏">
      <header class="screen-head"><div class="screen-brand">${svg('<path stroke="#00ebef" stroke-width="6" d="M19 5a19 19 0 1 0 10 0M24 1v16"/><circle cx="24" cy="25" r="7" fill="#00ebef" stroke="none"/>')}<span>ROLLING</span></div>
        <h1>融瓴智能穿戴安全监护中心</h1>
        <svg class="screen-head-decoration" viewBox="0 0 1672 33" preserveAspectRatio="none" aria-hidden="true"><defs><linearGradient id="screen-line"><stop stop-color="#007db0"/><stop offset=".5" stop-color="#00e5ff"/><stop offset="1" stop-color="#007db0"/></linearGradient><pattern id="screen-dots" width="8" height="6" patternUnits="userSpaceOnUse"><circle cx="1" cy="1" r=".8" fill="#0087ce"/></pattern></defs><path d="M0 1H487L515 23H556L568 30H1104L1117 23H1156L1183 1H1672" fill="none" stroke="#007aaf"/><path d="M0 30H505L489 14H252M1672 30H1173L1189 14H1290" fill="none" stroke="#008bd1"/><path d="M0 30H507L489 8H247M1672 30H1165L1186 8H1290" fill="none" stroke="#00abda" stroke-dasharray="3 7"/><path d="M0 30H568L561 22H520L493 2M1672 30H1104L1112 22H1152L1179 2" fill="none" stroke="url(#screen-line)"/><path d="M560 30H1107" stroke="#39deff" stroke-width="2"/><path d="M245 5H487V23H245ZM1188 5H1300V23H1188Z" fill="url(#screen-dots)"/></svg>
        <div class="screen-station">${symbols.factory}<span>${esc(station)}</span></div><div class="screen-clock"><time data-screen-clock></time><small>白班 08:00 — 16:00</small></div>
      </header>
      <section class="screen-stats" aria-label="当班概况"></section>
      <section class="screen-panel screen-equipment">${title("三类装备接入", "<small>在线 / 佩戴合规</small>")}<div data-equipment></div></section>
      <section class="screen-panel screen-vitals" aria-label="人员生命体征轮播">${title("人员生命体征", `<small data-person-mode>自动轮播 · ${INTERVALS.person / 1000}秒</small>`)}
        <div class="screen-vital-identity"><span class="screen-person-name" data-screen-person></span><span data-person-page></span></div>
        <div class="screen-vital-data"><div class="screen-person-meta"><span data-person-device></span><span data-person-status></span></div>
        <div class="screen-human-grid"></div><img class="screen-human" src="/assets/screen-worker.png" alt="佩戴安全帽、安全带及智能手表的工作人员示意">
        <svg class="screen-vital-lines" viewBox="0 0 103 178" aria-hidden="true"><g fill="none" stroke="#217b9f" stroke-width=".8"><path d="M0 12H84V20H103M5 48H78V88H103M22 93H84V155H103"/></g><g fill="#c8ffff" stroke="#00a8ee" stroke-width="3"><circle cx="0" cy="12" r="5"/><circle cx="5" cy="48" r="5"/><circle cx="22" cy="93" r="4"/></g></svg>
        <div class="screen-vital-metrics">${[["heart", "心率", "次/分"], ["oxygen", "血氧", "%"], ["temperature", "皮肤温度", "℃"]].map(([key, label, unit], index) => `<div class="screen-metric">${symbols[key]}<div><h3>${label}</h3><p><strong data-metric="${index}">—</strong><span>${unit}</span></p></div></div>`).join("")}</div></div>

      </section>
      <section class="screen-panel screen-map" aria-label="厂区态势"><img src="/assets/screen-plant.png" alt="电厂夜景三维示意图"><h2>厂区态势</h2><div data-screen-pins></div></section>
      <section class="screen-panel screen-events" aria-label="重点事件轮播">${title("重点事件")}<div class="screen-events-list"></div><div class="screen-event-summary"></div></section>
      <section class="screen-panel screen-trend">${title('心率趋势 <span class="screen-trend-person"></span>')}<div data-screen-trend></div></section>
      <section class="screen-panel screen-videos" aria-label="现场视频轮播">${title("现场视频", `<div class="screen-video-meta"><span>演示画面</span><span data-video-page></span></div>`)}<div class="screen-video-grid"></div></section>
      <footer class="screen-footer"><span>本地演示数据 / 场景示意</span><span>数据刷新时间<time data-screen-refresh></time></span></footer>
    </main></div>`;
}

export function mountScreen(root) {
  root.innerHTML = frame();
  const host = root.querySelector(".screen-stage");
  const query = (selector) => host?.querySelector(selector);
  let clockTimer;
  const timers = [];
  const now = performance.now();
  const state = { personId: "", eventOffset: 0, videoPage: 0, lastPerson: now, lastEvent: now, lastVideo: now, eventsHtml: "", videosHtml: "", statsSignature: "" };

  function onDuty() {
    return stationPeople();
  }
  function nowForData() {
    return DATE + " " + new Date(db.state.clock * 1000).toISOString().slice(11, 19);
  }
  function mask(name) {
    return name.length > 2 ? name[0] + "*" + name.at(-1) : name[0] + "*";
  }
  function scene(person) {
    return { 锅炉区: "screen-boiler.png", 汽机厂房: "screen-turbine.png", 配电区: "screen-electric.png", 循环水区: "scene-water.png" }[person.area] || "screen-boiler.png";
  }
  function gearRing(percent, color, radius, width) {
    const length = 2 * Math.PI * radius;
    const drawn = (Math.max(0, Math.min(100, percent)) / 100) * length;
    return `<circle cx="44" cy="44" r="${radius}" fill="none" stroke="${color}" stroke-width="${width}" stroke-linecap="round" stroke-dasharray="${drawn} ${length}" transform="rotate(-90 44 44)"/>`;
  }
  function equipmentPanel(stats) {
    const openHooks = new Set(
      events()
        .filter((item) => item.status !== "已核验" && item.type === "安全带挂接")
        .map((item) => item.deviceId),
    );
    const rows = [
      ["H", "安全帽", "智能安全帽", "#19d7ff", "#2ad58a"],
      ["B", "安全带", "智能安全带", "#ff9a2e", "#ff7a22"],
      ["W", "手表", "智能手表", "#19d7ff", "#2ad58a"],
    ].map(([key, short, name, outer, inner]) => {
      const list = stats.devices.filter((device) => device.type === key);
      const total = list.length;
      const online = list.filter((device) => device.online).length;
      const compliant = list.filter((device) => device.online && !openHooks.has(device.id)).length;
      const low = list.filter((device) => device.battery <= 20).length;
      const missing = total - online;
      const onlineRate = total ? (online / total) * 100 : 0;
      const compliantRate = total ? (compliant / total) * 100 : 0;
      const outerColor = missing ? "#ff9a2e" : outer;
      const innerColor = compliant < total ? "#ff7a22" : inner;
      return { key, short, name, total, online, compliant, low, missing, onlineRate, compliantRate, outerColor, innerColor };
    });
    query("[data-equipment]").innerHTML = `<div class="screen-gear-rings">${rows
      .map(
        (row) => `<div class="screen-gear-item">
          <div class="screen-gear-ring" aria-label="${row.name} 佩戴合规 ${row.compliant}/${row.total || "—"}">
            <svg viewBox="0 0 88 88" aria-hidden="true">
              <circle cx="44" cy="44" r="36" fill="none" stroke="#16384c" stroke-width="7"/>
              ${gearRing(row.onlineRate, row.outerColor, 36, 7)}
              <circle cx="44" cy="44" r="26" fill="none" stroke="#10283a" stroke-width="6"/>
              ${gearRing(row.compliantRate, row.innerColor, 26, 6)}
            </svg>
            <div><strong>${row.total ? row.compliant + "/" + row.total : "—"}</strong><small>合规</small></div>
          </div>
          <b>${row.name}</b>
          <span>${row.total ? `在线 <em class="${row.missing ? "warn" : ""}">${row.online}/${row.total}</em>${row.missing ? ` · <i>缺 ${row.missing}</i>` : ""}` : "暂无装备"}</span>
        </div>`,
      )
      .join("")}</div>
      <table class="screen-gear-table">
        <thead><tr><th></th><th>在线</th><th>佩戴合规</th><th>电量&lt;20%</th><th>信号</th></tr></thead>
        <tbody>${rows
          .map(
            (row) => `<tr>
              <td>${row.short}</td>
              <td class="${row.missing ? "warn" : "ok"}">${row.total ? row.online + "/" + row.total : "—"}</td>
              <td class="${row.compliant < row.total ? "warn" : "ok"}">${row.total ? row.compliant + "/" + row.total : "—"}</td>
              <td class="${row.low ? "warn" : "muted"}">${row.low || "—"}</td>
              <td class="${row.missing ? "bad" : "good"}">${row.missing ? row.missing + " 中断" : "正常"}</td>
            </tr>`,
          )
          .join("")}</tbody>
      </table>`;
  }
  function statistics(stats) {
    const wearKey = events()
      .filter((item) => item.status !== "已核验" && item.type === "安全带挂接")
      .map((item) => item.id)
      .join();
    const signature = JSON.stringify(stats) + wearKey;
    if (signature === state.statsSignature) return;
    state.statsSignature = signature;
    query(".screen-stats").innerHTML = [
      [symbols.worker, "当班人员", `${stats.people.length}<span class="unit">人</span><span class="detail">作业关联 ${stats.assigned} · 待分配 ${stats.people.length - stats.assigned}</span>`, ""],
      [symbols.document, "监护作业", `${stats.works.filter((work) => work.status !== "已结束").length}<span class="unit">项</span>`, "hex cyan"],
      [symbols.antenna, "装备在线", `<span class="fraction">${stats.online} / ${stats.devices.length}</span><span class="unit">台</span>`, "hex"],
      [symbols.warning, "待核验事件", `${stats.unresolved}<span class="unit">项</span>`, "hex warn"],
    ]
      .map(
        ([icon, label, value, tone]) =>
          `<div class="screen-stat ${tone.includes("warn") ? "warn" : ""}"><div class="screen-stat-icon ${tone}">${tone.includes("hex") ? '<svg class="screen-hex" viewBox="0 0 72 80" aria-hidden="true"><path d="M36 2 67 20V60L36 78 5 60V20Z" fill="#002541" stroke="#03121f" stroke-width="3"/><path d="M36 6 64 22V58L36 74 8 58V22Z" fill="none" stroke="currentColor" stroke-opacity=".25"/></svg>' : ""}${icon}</div><div><h2>${label}</h2><p><strong>${value}</strong></p></div></div>`,
      )
      .join("");
    equipmentPanel(stats);
    query("[data-screen-pins]").innerHTML = stats.people.length
      ? [["锅炉区", 36.2, 34.1], ["配电区", 20.4, 67], ["汽机厂房", 57.5, 68], ["循环水区", 84.5, 43.5]]
          .map(([area, x, y]) => {
            const list = stats.people.filter((person) => person.area === area);
            const idle = list.filter((person) => !db.currentWork(person.id)).length;
            return `<div class="screen-pin" style="left:${x}%;top:${y}%" aria-label="${esc(area)} ${list.length} 人"><span class="screen-pin-label">${esc(area)}<br><strong>${list.length}</strong> <small>${idle === list.length && idle ? "人待分配" : "人"}</small></span><span class="screen-pin-triangle"></span><span class="screen-pin-dot"></span></div>`;
          })
          .join("")
      : '<div class="screen-map-empty">当前电厂暂无当班人员</div>';
  }
  function trend(vital) {
    if (!vital.trend.length) return `<div class="screen-chart-empty">${esc(vital.status === "正常" ? "暂无心率观测" : vital.status)}</div>`;
    const values = vital.trend.map((point) => point.value);
    const lo = Math.min(60, Math.floor(Math.min(...values) / 10) * 10);
    const hi = Math.max(100, Math.ceil(Math.max(...values) / 10) * 10);
    const y = (value) => 139 - ((value - lo) / (hi - lo)) * 116;
    const points = vital.trend.map((point, index) => [55 + (index * 262) / Math.max(1, vital.trend.length - 1), y(point.value)]);
    return `<svg class="screen-chart" viewBox="0 0 346 164" role="img" aria-label="${esc(db.person(state.personId)?.name)}心率趋势${vital.demo ? "，示例曲线" : ""}"><defs><linearGradient id="heart-fill" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#009ffe" stop-opacity=".48"/><stop offset="1" stop-color="#0062bd" stop-opacity=".08"/></linearGradient></defs><text x="4" y="10">次/分</text>${Array.from({ length: 5 }, (_, index) => {
      const value = lo + (index * (hi - lo)) / 4;
      return `<path class="grid" d="M35 ${y(value)}H345"/><text x="3" y="${y(value) + 5}">${Math.round(value)}</text>`;
    }).join("")}${points.map(([x]) => `<path class="grid" d="M${x} 23V139"/>`).join("")}<path d="M${points[0][0]} 139L${points.map((point) => point.join(" ")).join("L")}L${points.at(-1)[0]} 139Z" fill="url(#heart-fill)"/><path d="M${points.map((point) => point.join(" ")).join("L")}" fill="none" stroke="#1ce4ff" stroke-width="2.2"/>${points
      .map(
        ([x, yPoint], index) =>
          `<circle cx="${x}" cy="${yPoint}" r="4" fill="#e6ffff" stroke="#09c8ff"/><text class="value" text-anchor="middle" x="${x}" y="${yPoint - 12}">${vital.trend[index].value}</text><text text-anchor="middle" x="${x}" y="160">${vital.trend[index].time}</text>`,
      )
      .join("")}</svg>`;
  }
  function renderPerson(animate = false) {
    const list = onDuty();
    if (!list.some((person) => person.id === state.personId)) state.personId = list[0]?.id || "";
    const person = list.find((item) => item.id === state.personId);
    const vital = currentVital(db, person, nowForData());
    query("[data-screen-person]").textContent = person ? `${person.name} · ${person.area}` : "暂无当班人员";
    query("[data-person-page]").textContent = list.length ? `${list.findIndex((item) => item.id === state.personId) + 1} / ${list.length}` : "0 / 0";
    query("[data-person-mode]").textContent = `自动轮播 · ${INTERVALS.person / 1000}秒`;
    query("[data-person-device]").textContent = vital.deviceId;
    query("[data-person-status]").textContent = vital.status === "正常" ? "样例观测" : vital.status;
    query("[data-person-status]").className = vital.status === "正常" ? "" : "invalid";
    vital.values.forEach((value, index) => {
      query(`[data-metric="${index}"]`).textContent = value == null ? "—" : index === 2 ? value.toFixed(1) : String(value);
    });
    query(".screen-trend-person").textContent = person ? "· " + person.name : "";
    query("[data-screen-trend]").innerHTML = trend(vital);
    query(".screen-vital-data").dataset.personId = state.personId;
    query("[data-screen-trend]").dataset.personId = state.personId;
    if (animate) query(".screen-vital-data").animate([{ opacity: 0.3 }, { opacity: 1 }], { duration: matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 250 });
  }
  function unresolved() {
    return events().filter((event) => event.status !== "已核验");
  }
  function renderEvents() {
    const all = unresolved();
    const shown = eventWindow(all, state.eventOffset);
    const html =
      shown
        .map(
          (event) =>
            `<div class="screen-event" data-event-id="${esc(event.id)}" aria-label="${esc(event.title)}"><span class="screen-event-icon">${event.type === "低电量" ? symbols.battery : event.type === "位置异常" ? symbols.pin : isVitalAlert(event) ? symbols.heart : symbols.chain}</span><span class="screen-event-main"><strong>${esc(event.title)}</strong><small>${esc(mask(db.person(event.personId)?.name || event.snapshot?.personName || "未知人员"))} · ${esc(event.deviceId)}</small></span><span class="screen-event-state">${esc(event.time)}<strong>${esc(event.status)}</strong></span></div>`,
        )
        .join("") || '<div class="screen-no-data">暂无待核验事件</div>';
    if (html !== state.eventsHtml) {
      query(".screen-events-list").innerHTML = html;
      state.eventsHtml = html;
    }
    query(".screen-event-summary").innerHTML = ["待认领", "待现场核验", "处理中"]
      .map((status) => `<span>${status}<strong>${all.filter((event) => event.status === status).length}</strong></span>`)
      .join("<em>·</em>");
  }
  function renderVideos() {
    const list = videoPeople(db, onDuty());
    const pages = Math.ceil(list.length / 3);
    state.videoPage = pages ? ((state.videoPage % pages) + pages) % pages : 0;
    const shown = list.slice(state.videoPage * 3, state.videoPage * 3 + 3);
    const html =
      shown
        .map((person) => {
          const helmet = db.currentDevices(person.id).find((device) => device.type === "H");
          return `<div class="screen-video-tile" data-person-id="${esc(person.id)}" aria-label="${esc(person.area)} ${esc(helmet.id)}演示画面"><img src="/assets/${scene(person)}" alt="${esc(person.area)}现场场景"><span class="screen-video-label">${esc(person.area === "锅炉区" ? "锅炉平台" : person.area)} · ${esc(helmet.id)}<small>演示画面</small></span></div>`;
        })
        .join("") || '<div class="screen-no-data">暂无可用视频通道</div>';
    if (html !== state.videosHtml) {
      query(".screen-video-grid").innerHTML = html;
      state.videosHtml = html;
    }
    query("[data-video-page]").textContent = `${pages ? state.videoPage + 1 : 0} / ${pages}`;
  }
  function refresh() {
    statistics(db.stats(scope()));
    renderPerson();
    renderEvents();
    renderVideos();
    query("[data-screen-refresh]").textContent = new Date().toTimeString().slice(0, 8);
  }
  function tick() {
    if (!host || document.hidden) return;
    const time = performance.now();
    if (time - state.lastPerson >= INTERVALS.person) {
      state.personId = nextPerson(onDuty(), state.personId);
      state.lastPerson = time;
      renderPerson(true);
    }
    if (time - state.lastEvent >= INTERVALS.events) {
      state.eventOffset += 1;
      state.lastEvent = time;
      renderEvents();
    }
    if (time - state.lastVideo >= INTERVALS.video) {
      state.videoPage += 1;
      state.lastVideo = time;
      renderVideos();
    }
  }
  function resize() {
    const screen = query(".screen");
    if (!screen) return;
    screen.style.setProperty("--screen-scale-x", String(innerWidth / 1672));
    screen.style.setProperty("--screen-scale-y", String(innerHeight / 941));
  }
  function clock() {
    const current = new Date();
    const pad = (value) => String(value).padStart(2, "0");
    query("[data-screen-clock]").textContent = `${current.getFullYear()}-${pad(current.getMonth() + 1)}-${pad(current.getDate())} ${pad(current.getHours())}:${pad(current.getMinutes())}`;
  }
  function visibility() {
    if (!document.hidden) {
      state.lastPerson = state.lastEvent = state.lastVideo = performance.now();
      refresh();
    }
  }
  window.addEventListener("resize", resize);
  document.addEventListener("fullscreenchange", resize);
  document.addEventListener("visibilitychange", visibility);
  resize();
  refresh();
  clock();
  clockTimer = setInterval(clock, 1000);
  timers.push(setInterval(tick, 250), setInterval(() => { if (!document.hidden) refresh(); }, INTERVALS.refresh));
  return () => {
    clearInterval(clockTimer);
    timers.splice(0).forEach(clearInterval);
    window.removeEventListener("resize", resize);
    document.removeEventListener("fullscreenchange", resize);
    document.removeEventListener("visibilitychange", visibility);
  };
}
