import { iconMarkup } from "@ui-spec/icons";
import { DATE } from "@/mock/data";
import { beijingDate, beijingTime } from "@/lib/location";
import { db } from "@/mock/runtime";
import { isRealDevice, isCurrentDevice } from "@/lib/device-telemetry";
import { events, people as stationPeople, scope } from "@/lib/queries";
import { session } from "@/stores/session";
import { testSiteName } from '../../../../shared/test-site.mjs';
import { INTERVALS, currentVital, eventWindow, isVitalAlert, nextPerson, videoPeople } from "./screen-model";

const esc = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);

const symbols = Object.fromEntries(["factory","chain","battery","pin","document","antenna","warning","worker","heart","oxygen","temperature"].map(name => [name,iconMarkup(name)]));

function title(text, right = "") {
  return `<header class="screen-panel-title"><h2>${text}</h2>${right}</header>`;
}

function frame() {
  const station = testSiteName(db.state.stations.find((item) => item.id === session.station)) || "未选择电厂";
  return `<div class="screen-stage"><main class="screen" aria-label="数据大屏">
      <header class="screen-head"><div class="screen-brand rl-brand rl-brand-light" role="img" aria-label="融瓴 ROLLING"><img class="rl-brand-mark" src="/assets/brand-mark.svg" alt="" width="42" height="42" /><span class="rl-brand-type" aria-hidden="true"><b class="rl-brand-name">融瓴</b><span class="rl-brand-en">ROLLING</span></span></div>
        <h1>融瓴智能穿戴安全监护中心</h1>
        <img class="screen-head-decoration" src="/assets/sketch/navigation-artwork.svg" alt="" aria-hidden="true">
        <div class="screen-station">${symbols.factory}<span>${esc(station)}</span></div><div class="screen-clock"><time data-screen-clock></time><small>北京时间</small></div>
      </header>
      <section class="screen-stats" aria-label="台账与真实设备概况"></section>
      <section class="screen-panel screen-equipment">${title(db.demoMode ? "领用装备（演示）" : "真实领用装备", "<small>在线 / 佩戴待核验</small>")}<div data-equipment></div></section>
      <section class="screen-panel screen-vitals" aria-label="人员生命体征轮播">${title("人员生命体征", `<small data-person-mode>自动轮播 · ${INTERVALS.person / 1000}秒</small>`)}
        <div class="screen-vital-identity"><span class="screen-person-name" data-screen-person></span><span data-person-page></span></div>
        <div class="screen-vital-data"><div class="screen-person-meta"><span data-person-device></span><span data-person-status></span></div>
        <div class="screen-human-grid"></div><img class="screen-human" src="/assets/screen-worker.png" alt="佩戴安全帽、安全带及智能手表的工作人员示意">
        <svg class="screen-vital-lines" viewBox="0 0 103 178" aria-hidden="true"><g fill="none" stroke="#25556f" stroke-width=".8"><path d="M0 12H84V20H103M5 48H78V88H103M22 93H84V155H103"/></g><g fill="#d1dae5" stroke="#4faff7" stroke-width="3"><circle cx="0" cy="12" r="5"/><circle cx="5" cy="48" r="5"/><circle cx="22" cy="93" r="4"/></g></svg>
        <div class="screen-vital-metrics">${[["heart", "心率", "次/分"], ["oxygen", "血氧", "%"], ["temperature", "皮肤温度", "℃"]].map(([key, label, unit], index) => `<div class="screen-metric">${symbols[key]}<div><h3>${label}</h3><p><strong data-metric="${index}">—</strong><span>${unit}</span></p></div></div>`).join("")}</div></div>

      </section>
      <section class="screen-panel screen-map" aria-label="厂区人员定位"><div data-screen-map></div></section>
      <section class="screen-panel screen-events" aria-label="重点事件轮播">${title("台账待核验事件")}<div class="screen-events-list"></div><div class="screen-event-summary"></div></section>
      <section class="screen-panel screen-trend">${title('心率趋势 <span class="screen-trend-person"></span>')}<div data-screen-trend></div></section>
      <section class="screen-panel screen-videos" aria-label="现场视频轮播">${title("现场视频", `<div class="screen-video-meta"><span>现场画面</span><span data-video-page></span></div>`)}<div class="screen-video-grid" data-screen-videos></div></section>
      <footer class="screen-footer"><span data-platform-summary></span><span>数据刷新时间<time data-screen-refresh></time></span></footer>
    </main></div>`;
}

export function mountScreen(root, { onVideos = () => {} } = {}) {
  root.innerHTML = frame();
  const host = root.querySelector(".screen-stage");
  const query = (selector) => host?.querySelector(selector);
  let clockTimer;
  const timers = [];
  const now = performance.now();
  const state = { personId: "", eventOffset: 0, videoPage: 0, lastPerson: now, lastEvent: now, lastVideo: now, eventsHtml: "", videosHtml: "", statsSignature: "" };

  function onDuty() {
    const list = stationPeople();
    return db.demoMode ? list : list.filter(person => db.currentDevices(person.id).some(device => device.type === 'W' && device.active));
  }
  function nowForData() {
    return db.demoMode ? DATE + " " + new Date(db.state.clock * 1000).toISOString().slice(11, 19) : beijingDate() + " " + beijingTime(new Date().toISOString());
  }
  function mask(name) {
    return name.length > 2 ? name[0] + "*" + name.at(-1) : name[0] + "*";
  }
  function gearRing(percent, color, radius, width) {
    const length = 2 * Math.PI * radius;
    const drawn = (Math.max(0, Math.min(100, percent)) / 100) * length;
    return `<circle cx="44" cy="44" r="${radius}" fill="none" stroke="${color}" stroke-width="${width}" stroke-linecap="round" stroke-dasharray="${drawn} ${length}" transform="rotate(-90 44 44)"/>`;
  }
  function equipmentPanel(stats) {
    const rows = [
      ["H", "安全帽", "智能安全帽", "#83f6fd", "#71e96f"],
      ["B", "安全带", "智能安全带", "#f09840", "#f09840"],
      ["W", "手表", "智能手表", "#83f6fd", "#71e96f"],
    ].filter(([key]) => key !== 'W' || stats.devices.some(device => device.type === 'W')).map(([key, short, name, outer, inner]) => {
      const list = stats.devices.filter((device) => device.type === key);
      const total = list.length;
      const online = list.filter((device) => device.online).length;
      // No verified wear telemetry is available; alarm closure is not wear evidence.
      const low = list.filter((device) => Number.isFinite(device.battery) && device.battery < 20).length;
      const missing = total - online;
      const onlineRate = total ? (online / total) * 100 : 0;
      const outerColor = missing ? "#f09840" : outer;
      return { key, short, name, total, online, low, missing, onlineRate, outerColor };
    });
    query("[data-equipment]").innerHTML = `<div class="screen-gear-rings">${rows
      .map(
        (row) => `<div class="screen-gear-item">
          <div class="screen-gear-ring" aria-label="${row.name} 在线 ${row.online}/${row.total || "—"}，佩戴状态待核验">
            <svg viewBox="0 0 88 88" aria-hidden="true">
              <circle cx="44" cy="44" r="36" fill="none" stroke="#25556f" stroke-width="7"/>
              ${gearRing(row.onlineRate, row.outerColor, 36, 7)}
              <circle cx="44" cy="44" r="26" fill="none" stroke="#121e37" stroke-width="6"/>

            </svg>
            <div><strong>${row.total ? row.online + "/" + row.total : "—"}</strong><small>在线</small></div>
          </div>
          <b>${row.name}</b>
          <span>${row.total ? `在线 <em class="${row.missing ? "warn" : ""}">${row.online}/${row.total}</em>${row.missing ? ` · <i>缺 ${row.missing}</i>` : ""}` : "暂无装备"}</span>
        </div>`,
      )
      .join("")}</div>
      <table class="screen-gear-table">
        <thead><tr><th></th><th>在线</th><th>佩戴状态</th><th>电量&lt;20%</th><th>信号</th></tr></thead>
        <tbody>${rows
          .map(
            (row) => `<tr>
              <td>${row.short}</td>
              <td class="${row.missing ? "warn" : "ok"}">${row.total ? row.online + "/" + row.total : "—"}</td>
              <td class="muted">${row.total ? "待核验" : "—"}</td>
              <td class="${row.low ? "warn" : "muted"}">${row.low || "—"}</td>
              <td class="${row.missing ? "bad" : "good"}">${row.total ? "待核验" : "—"}</td>
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
      [symbols.worker, "在册人员", `${stats.people.length}<span class="unit">人</span><span class="detail">作业关联 ${stats.assigned} · 待分配 ${stats.people.length - stats.assigned}</span>`, ""],
      [symbols.document, "台账作业", `${stats.works.filter((work) => work.status !== "已结束").length}<span class="unit">项</span>`, "hex cyan"],
      [symbols.antenna, "真实领用装备在线", `<span class="fraction">${stats.online} / ${stats.devices.length}</span><span class="unit">台</span>`, "hex"],
      [symbols.warning, "待核验事件", `${stats.unresolved}<span class="unit">项</span>`, "hex warn"],
    ]
      .map(
        ([icon, label, value, tone]) =>
          `<div class="screen-stat ${tone.includes("warn") ? "warn" : ""}"><div class="screen-stat-icon ${tone}">${icon}</div><div><h2>${label}</h2><p><strong>${value}</strong></p></div></div>`,
      )
      .join("");
    equipmentPanel(stats);
  }
  function trend(vital) {
    if (!vital.trend.length) return `<div class="screen-chart-empty">${esc(vital.status === "正常" ? "暂无心率观测" : vital.status)}</div>`;
    const values = vital.trend.map((point) => point.value);
    const lo = Math.min(60, Math.floor(Math.min(...values) / 10) * 10);
    const hi = Math.max(100, Math.ceil(Math.max(...values) / 10) * 10);
    const y = (value) => 139 - ((value - lo) / (hi - lo)) * 116;
    const points = vital.trend.map((point, index) => [55 + (index * 262) / Math.max(1, vital.trend.length - 1), y(point.value)]);
    return `<svg class="screen-chart" viewBox="0 0 346 164" role="img" aria-label="${esc(db.person(state.personId)?.name)}心率趋势${vital.demo ? "（模拟数据）" : ""}"><defs><linearGradient id="heart-fill" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#4faff7" stop-opacity=".48"/><stop offset="1" stop-color="#4faff7" stop-opacity=".08"/></linearGradient></defs><text x="4" y="10">次/分</text>${Array.from({ length: 5 }, (_, index) => {
      const value = lo + (index * (hi - lo)) / 4;
      return `<path class="grid" d="M35 ${y(value)}H345"/><text x="3" y="${y(value) + 5}">${Math.round(value)}</text>`;
    }).join("")}${points.map(([x]) => `<path class="grid" d="M${x} 23V139"/>`).join("")}<path d="M${points[0][0]} 139L${points.map((point) => point.join(" ")).join("L")}L${points.at(-1)[0]} 139Z" fill="url(#heart-fill)"/><path d="M${points.map((point) => point.join(" ")).join("L")}" fill="none" stroke="#83f6fd" stroke-width="2.2"/>${points
      .map(
        ([x, yPoint], index) =>
          `<circle cx="${x}" cy="${yPoint}" r="4" fill="#ffffff" stroke="#4faff7"/><text class="value" text-anchor="middle" x="${x}" y="${yPoint - 12}">${vital.trend[index].value}</text><text text-anchor="middle" x="${x}" y="160">${vital.trend[index].time}</text>`,
      )
      .join("")}</svg>`;
  }
  function renderPerson(animate = false) {
    const showVitals = db.state.businessConfig?.simulatedWatchVisible !== false && onDuty().length > 0;
    for (const selector of ['.screen-vitals', '.screen-trend']) query(selector).style.display = showVitals ? '' : 'none';
    const list = onDuty();
    if (!list.some((person) => person.id === state.personId)) state.personId = list[0]?.id || "";
    const person = list.find((item) => item.id === state.personId);
    const vital = currentVital(db, person, nowForData());
    query("[data-screen-person]").textContent = person ? person.name : "暂无在册人员";
    query("[data-person-page]").textContent = list.length ? `${list.findIndex((item) => item.id === state.personId) + 1} / ${list.length}` : "0 / 0";
    query("[data-person-mode]").textContent = `自动轮播 · ${INTERVALS.person / 1000}秒`;
    query("[data-person-device]").textContent = vital.deviceId;
    query("[data-person-status]").textContent = vital.demo ? "模拟数据 · 非实时测量" : vital.status;
    query("[data-person-status]").className = vital.status === "正常" ? "" : "invalid";
    vital.values.forEach((value, index) => {
      query(`[data-metric="${index}"]`).textContent = value == null ? "—" : index === 2 ? value.toFixed(1) : String(value);
    });
    query(".screen-trend-person").textContent = person ? "· " + person.name + (vital.demo ? "（模拟）" : "") : "";
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
            `<div class="screen-event" data-event-id="${esc(event.id)}" aria-label="${esc(event.title)}"><span class="screen-event-icon">${event.type === "低电量" ? symbols.battery : event.type === "位置异常" ? symbols.pin : isVitalAlert(event) ? symbols.heart : symbols.chain}</span><span class="screen-event-main"><strong>${esc(event.title)}</strong><small>${esc(event.personId ? mask(event.snapshot?.personName || db.person(event.personId)?.name || "未知人员") : "未关联人员")} · ${esc(event.deviceId)}</small></span><span class="screen-event-state"><time>${esc(event.date)}<br>${esc(event.time)}</time><strong>${esc(event.status)}</strong></span></div>`,
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
    const list = videoPeople(db, stationPeople());
    const pages = Math.ceil(list.length / 3);
    state.videoPage = pages ? ((state.videoPage % pages) + pages) % pages : 0;
    onVideos(list.slice(state.videoPage * 3, state.videoPage * 3 + 3));
    query('.screen-videos').style.display = list.length ? '' : 'none';
    query('[data-video-page]').textContent = `${pages ? state.videoPage + 1 : 0} / ${pages}`;
  }
  function refresh() {
    statistics(db.stats(scope()));
    const factory = db.state.devices.filter(d => isRealDevice(d) && d.station === session.station);
    const current = factory.filter(d => isCurrentDevice(d) && typeof d.online === "boolean");
    const online = current.filter(d => d.online).length;
    const offline = factory.filter(d => d.online === false).length;
    const footer = query("[data-platform-summary]");
    if (footer) footer.textContent = `真实设备资产：共 ${factory.length} 台 · 在线 ${online} · 离线 ${offline} · 待刷新 ${factory.length - online - offline}；人员、作业、事件为保留台账；实时状态仅使用真实上报`;
    renderPerson();
    renderEvents();
    renderVideos();
    query("[data-screen-refresh]").textContent = beijingTime(new Date().toISOString());
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
    query("[data-screen-clock]").textContent = beijingDate() + ' ' + beijingTime(new Date().toISOString()).slice(0, 5);
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
