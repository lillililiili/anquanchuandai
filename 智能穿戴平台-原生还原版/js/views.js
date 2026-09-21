(function () {
  "use strict";
  const {
    db,
    D,
    s,
    esc: e,
    icon: i,
    btn: b,
    link: l,
    tag,
    dot,
    field: f,
    select: sel,
    input: inp,
    title,
    panel,
    table,
    avatar,
    empty,
    statCards: stats,
    personName: pn,
    deviceStrip: ds,
    workInfo: wi,
    map,
    video,
    scope,
    people,
    works,
    events,
    materials,
    mediaImage,
  } = R;
  const filter = () => s.filters[R.route] || {},
    search = (value, term) =>
      String(value || "")
        .toLowerCase()
        .includes(
          String(term || "")
            .trim()
            .toLowerCase(),
        );
  const personOpts = () => [
      ["", "全部人员"],
      ...people().map((p) => [p.id, p.name]),
    ],
    workOpts = () => [["", "全部作业"], ...works().map((w) => [w.id, w.name])];
  const deviceOpts = () => [
    ["", "全部设备"],
    ...db.state.devices
      .filter((d) => d.station === s.station)
      .map((d) => [d.id, d.id]),
  ];
  const dateField = () =>
    f("日期", inp("date", "", filter().date || D.DATE, "date"));
  const filterForm = (body) =>
    `<form class="filters" data-form="filters">${body}${b("查询", "", "", "primary", "search-line").replace('type="button"', 'type="submit"')}${b("重置", "reset-filters", "", "", "refresh-line")}</form>`;
  const statusColor = (t) =>
    t === "已核验"
      ? "green"
      : t === "处理中"
        ? "blue"
        : t === "待认领"
          ? "red"
          : "yellow";
  const tabs = (items, current, action) =>
    `<div class="tabs">${items.map(([id, text]) => b(text, action, id, current === id ? "active" : "")).join("")}</div>`;
  const locationTabs = () =>
    `<div class="tabs">${[
      ["location", "实时定位"],
      ["tracks", "历史轨迹"],
      ["fences", "电子围栏"],
    ]
      .map(([p, t]) => l(t, p, R.route === p ? "active" : ""))
      .join("")}</div>`;
  const eventRows = (list) =>
    list.map((a) => ({
      attrs: `data-action="select-event" data-id="${a.id}" class="${s.event === a.id ? "selected" : ""}"`,
      cells: [
        e(a.id),
        `${i(a.type === "位置异常" ? "map-pin-line" : "alarm-warning-fill", statusColor(a.status))}　${e(a.title)}`,
        e(a.snapshot.personName),
        e(a.deviceId),
        a.time,
        tag(a.status, statusColor(a.status)),
        a.status === "待认领"
          ? b("认领", "claim", a.id, "small")
          : l("查看核验", "event/" + a.id, "btn small"),
      ],
    }));
  const missing = () =>
    title("暂无记录") +
    empty("当前厂站没有对应记录") +
    l("返回综合总览", "overview", "btn");
  const personValid = (id) => {
    const p = db.person(id);
    return p?.station === s.station ? p : null;
  };
  const personStat = (p) =>
    `${avatar(p)}<div><strong>${e(p.name)}</strong><small>${e(db.currentDevices(p.id).find((d) => d.type === "H")?.id || "未绑定")} | ${e(p.team)}</small></div>`;
  function relatedEvent(pid) {
    return events().find((x) => x.personId === pid && x.status !== "已核验");
  }
  function personDetail(p) {
    const w = db.currentWork(p.id),
      a = relatedEvent(p.id);
    return `<div class="detail-heading">${avatar(p)}<div><h3>${e(p.name)} <small>${e(db.currentDevices(p.id).find((d) => d.type === "H")?.id || "未绑定")}</small></h3><small>${e(p.team)}　|　手机：${e(p.phone || "—")}</small></div>${b("", "close-person-detail", "", "icon-only", "close-line")}</div>${tabs(
      ["人员信息", "装备信息", "作业信息", "事件信息"].map((x) => [x, x]),
      s.personTab,
      "person-tab",
    )}${s.personTab === "人员信息" ? `<dl class="info compact"><dt>所属区域</dt><dd>${e(p.area)}</dd><dt>当前作业</dt><dd>${e(w?.name || "待分配")}</dd><dt>当前监护人</dt><dd>${pn(w?.supervisor)}</dd><dt>当前负责人</dt><dd>${pn(w?.leader)}</dd></dl>` : ""}${["人员信息", "装备信息"].includes(s.personTab) ? `<div class="detail-section"><h3>装备状态 <small>（以领用记录为准）</small></h3>${ds(p.id)}${l("查看领用记录 ›", "person/" + p.id, "text-link")}</div>` : ""}${["人员信息", "作业信息"].includes(s.personTab) ? `<div class="detail-section"><h3>关联作业</h3>${w ? `<b>${e(w.name)}</b><p><small>${e(w.id)}</small></p><p>作业区域　${e(w.area)}</p><p>监护人　${pn(w.supervisor)}</p>${l("查看作业详情 ›", "work/" + w.id, "text-link")}` : empty("待分配作业")}</div>` : ""}${["人员信息", "事件信息"].includes(s.personTab) ? `<div class="detail-section"><h3>待核验事件（${events().filter((x) => x.personId === p.id && x.status !== "已核验").length}）</h3>${a ? `${l(i("error-warning-fill", "yellow") + "　" + e(a.title), "event/" + a.id)}<p>${tag(a.status, statusColor(a.status))}</p>` : dot("暂无待核验事件")}</div>` : ""}<div class="detail-section detail-media"><div class="grid equal"><div class="detail-video"><h3>现场视频</h3>${l(video(p.id), "single/" + p.id)}</div><div class="detail-call"><h3>语音对讲</h3>${b(i("mic-line") + " 发起对讲", "call-person", p.id, "primary wide")}<small>与 ${e(p.name)} 进行模拟通话</small></div></div></div>`;
  }
  R.views.login = () => {
    s.captcha ??= "K7M2";
    return `<div class="login-page"><img class="login-logo" src="assets/logo.png" alt="ROLLING"><div class="login-copy"><h1>融瓴智能穿戴安全监护平台</h1><p>现场人员 · 智能装备 · 作业监护</p></div><form class="login-card" data-form="login"><h2>工作账号登录</h2><label class="field"><span>账号</span><div class="input-icon">${i("user-line")}${inp("account", "请输入工作账号", "", "text", 'autocomplete="username" required')}</div></label><label class="field"><span>密码</span><div class="input-icon">${i("lock-line")}${inp("password", "", "", "password", 'autocomplete="current-password" required')}${b("", "password-toggle", "", "icon-only plain", "eye-off-line")}</div></label><label class="field"><span>图形验证码</span><div class="captcha-row"><div class="input-icon">${i("shield-check-line")}${inp("captcha", "请输入验证码", "", "text", 'maxlength="4" required autocomplete="off"')}</div><span class="captcha-code" aria-label="验证码">${s.captcha}</span>${b("", "captcha-refresh", "", "", "refresh-line")}</div></label><button class="btn primary" type="submit">登录</button><small>账号由管理员授权</small><div class="form-error" role="alert"></div></form><div class="login-footer">为电力行业现场作业安全保驾护航<small>更安全 · 更高效 · 更可持续</small></div><div class="login-help">演示账号：admin　密码：123456　｜　演示环境 · 非真实登录页</div></div>`;
  };
  R.views.overview = () => {
    const st = db.stats(scope()),
      ws = works(),
      ev = events().filter((a) => a.status !== "已核验"),
      p = people().find((p) => p.id === s.person) || people()[0];
    return (
      stats(
        [
          ["user-line", "当班人员", st.people.length, "人", "blue"],
          [
            "clipboard-line",
            "监护作业",
            st.works.length,
            "项",
            "cyan",
            `${st.assigned} 人参与　${st.people.length - st.assigned} 人待分配`,
          ],
          [
            "wifi-line",
            "通信在线",
            st.online + " / " + st.devices.length,
            "",
            "cyan",
          ],
          ["alarm-warning-line", "待核验事件", st.unresolved, "起", "yellow"],
        ],
        "flat",
      ) +
      `<div class="overview-layout"><div class="overview-map">${map({ person: "", popup: !!p })}</div><div class="stack">${panel(
        "当前重点事件",
        table(
          ["时间", "事件", "人员 / 装备", "状态"],
          ev.map((a) => ({
            attrs: `data-action="open-event" data-id="${a.id}"`,
            cells: [
              a.time,
              `${i(a.type === "位置异常" ? "map-pin-fill" : "error-warning-fill", a.type === "位置异常" ? "blue" : "yellow")}　${e(a.title)}`,
              `${pn(a.personId)} · ${e(a.deviceId)}`,
              tag(a.status, statusColor(a.status)),
            ],
          })),
          "compact",
        ),
        l("查看全部 ›", "alarms", "text-link"),
      )}${panel(
        "装备接入概况",
        Object.entries(st.byType)
          .map(
            ([t, n]) =>
              `<div class="progress-row"><img src="assets/${{ H: "helmet", B: "harness", W: "watch" }[t]}.png?v=transparent-20260921" alt="${D.typeNames[t]}"><span>${D.typeNames[t]}</span><div class="bar"><span style="width:${n.total ? (n.online / n.total) * 100 : 0}%"></span></div><b>${n.online} / ${n.total}</b></div>`,
          )
          .join("") +
          '<p class="note" style="text-align:right">通信在线不代表佩戴合规</p>',
        `总计 ${st.devices.length}　|　在线 ${st.online}`,
      )}</div></div><div class="overview-bottom">${panel(
        "当班作业",
        table(
          ["作业名称", "人数", "负责人", "来源", "同步状态", "操作"],
          ws.map((w) => ({
            cells: [
              e(w.name),
              w.members.length + " 人",
              pn(w.leader),
              `${e(w.source)}　${e(w.id)}`,
              dot(
                w.synced ? "已同步" : "待同步",
                w.synced ? "green" : "yellow",
              ),
              l("查看监护", "work/" + w.id, "btn small"),
            ],
          })),
          "compact",
        ),
      )}${panel(
        "现场视频预览",
        p
          ? `<div class="overview-videos">${l(video(p.id), "single/" + p.id)}<div class="stack">${people()
              .slice(3, 4)
              .map((q) => l(video(q.id), "single/" + q.id))
              .join("")}${people()
              .slice(5, 6)
              .map((q) => l(video(q.id), "single/" + q.id))
              .join("")}</div></div>`
          : empty(),
        l("更多 ›", "video", "text-link"),
      )}</div>`
    );
  };
  R.views.personnel = () => {
    const q = filter(),
      list = people().filter(
        (p) =>
          search(
            p.name +
              " " +
              p.id +
              " " +
              db
                .currentDevices(p.id)
                .map((d) => d.id)
                .join(" "),
            q.q,
          ) &&
          (!q.team || p.team === q.team) &&
          (!q.workStatus ||
            (q.workStatus === "assigned"
              ? !!db.currentWork(p.id)
              : !db.currentWork(p.id))),
      );
    let p = list.find((p) => p.id === s.person) || list[0];
    if (p) s.person = p.id;
    return `<div class="split-detail" style="${s.hidePerson ? "grid-template-columns:1fr" : ""}"><div>${title("当班人员与装备", "以人员查看三类装备与当前作业")}${filterForm(
      `<div class="searchbox">${i("search-line")}${inp("q", "搜索姓名或人员编号", q.q || "")}</div>${f("班组", sel("team", [["", "全部"], ...[...new Set(people().map((p) => p.team))].map((x) => [x, x])], q.team))}${f(
        "作业状态",
        sel(
          "workStatus",
          [
            ["", "全部"],
            ["assigned", "作业中"],
            ["idle", "待分配"],
          ],
          q.workStatus,
        ),
      )}`,
    )}<div class="panel">${table(
      [
        "序号",
        "人员信息",
        "所属区域",
        "当前作业",
        "装备状态<br><small>（安全帽 / 安全带 / 智能手表）</small>",
        "最近更新时间",
        "操作",
      ],
      list.map((p, k) => ({
        attrs: `data-action="select-person" data-id="${p.id}" class="${s.person === p.id ? "selected" : ""}"`,
        cells: [
          k + 1,
          `<div class="person-cell">${personStat(p)}</div>`,
          e(p.area),
          `${e(db.currentWork(p.id)?.name || "待分配")}<small>${db.currentWork(p.id) ? "（监护人：" + pn(db.currentWork(p.id).supervisor) + "）" : ""}</small>`,
          ds(p.id),
          p.updated,
          l("查看详情", "person/" + p.id, "btn small"),
        ],
      })),
      "personnel-list",
    )}</div></div>${!s.hidePerson ? `<aside class="panel ${s.personTab !== "人员信息" ? "person-detail-focused" : ""}" data-detail-tab="${e(s.personTab)}"><div class="panel-body">${p ? personDetail(p) : empty()}</div></aside>` : ""}</div>`;
  };
  const vitalPanel = (p) => {
    const { watch, record: v, status } = db.vitals(p.id);
    const metrics = [
      ["heart", "心率", "heart-pulse-line", v?.heartRate, "bpm"],
      ["oxygen", "血氧", "drop-line", v?.oxygen, "%"],
      ["temperature", "体温", "temp-hot-line", v?.temperature?.toFixed(1), "°C"],
      ["pressure", "血压", "pulse-line", v ? `${v.systolic} / ${v.diastolic}` : null, "mmHg"],
    ];
    return panel("生命体征 <small>（智能手表）</small>", `
      <div class="vitals-meta"><span>${watch ? `${e(watch.id)}　${dot(watch.online ? "在线" : "离线", watch.online ? "green" : "muted")}` : "未绑定智能手表"}</span>${tag(status, watch?.online ? "blue" : "muted")}</div>
      <div class="vitals-body">
        <div class="vitals-human"><img src="assets/vitals-human.webp" alt="蓝色人体示意图"><span>人体示意</span></div>
        ${metrics.map(([key, label, icon, value, unit]) => `<article class="vital-card vital-${key}"><h3>${i(icon)} ${label}</h3><p><strong>${value == null ? "—" : e(value)}</strong><span>${unit}</span></p><small>${v ? "本地样例 · 非实时测量" : "暂无观测数据"}</small></article>`).join("")}
      </div>
      <div class="vitals-footer"><span>观测时间：${v ? e(v.observedAt) : "—"}</span><span>演示数据 · 非诊断</span></div>`,
      b("观测记录", "vital-history", p.id, "small plain", "history-line"), "person-vitals");
  };
  R.views.person = () => {
    const p = personValid(R.routeId || s.person);
    if (!p) return missing();
    const w = db.currentWork(p.id),
      a = relatedEvent(p.id),
      history = db.state.bindings
        .filter((x) => x.personId === p.id)
        .sort((a, b) => b.start.localeCompare(a.start));
    return `<div class="grid cols-2 person-main"><div class="stack"><section class="panel person-summary">${l(i("arrow-left-line") + " 返回人员列表", "personnel", "text-link")}<div class="row">${avatar(p, true)}<div><h1>${e(p.name)}</h1><p>${e(p.team)}　|　${e(db.state.stations.find((x) => x.id === p.station)?.name)}</p><p>${dot("在岗")}　当前在：${e(w?.name || "待分配")} ${w ? "（" + e(w.id) + "）" : ""}</p></div></div></section>${panel("人员装备", ds(p.id, true))}${vitalPanel(p)}</div><div class="stack">${panel("作业信息", wi(w))}${panel("待现场核验事件", a ? `<div class="warning-box"><h3>${i("alarm-warning-fill")}　${e(a.title)}</h3><dl class="info compact"><dt>涉及人员</dt><dd>${e(p.name)}</dd><dt>设备编号</dt><dd>${e(a.deviceId)}</dd><dt>发生时间</dt><dd>${a.date} ${a.time}</dd></dl><p>设备通信状态不直接判定作业违规，需结合现场核验。</p></div>` : empty("暂无待核验事件"))}${panel("现场视频（来自安全帽）", `<div class="side-video">${video(p.id)}<div class="stack">${l(i("play-circle-fill") + " 查看视频", "single/" + p.id, "btn primary")}${b("发起对讲", "call-person", p.id, "", "mic-line")}${a ? l(i("file-list-line") + " 查看事件", "event/" + a.id, "btn") : b("查看事件", "person-events", p.id, "", "file-list-line")}</div></div>`, "示例画面 · 非实时")}</div></div><div class="person-lower">${panel("当前位置", `<div class="person-map">${map({ person: p.id, popup: true, legend: false })}</div>`, "", "flush")}${panel(
      "领用绑定历史",
      table(
        [
          "序号",
          "操作类型",
          "装备类型",
          "设备编号",
          "经办人",
          "开始时间",
          "结束时间",
          "状态",
        ],
        history.map((h, k) => ({
          cells: [
            k + 1,
            "领取",
            D.typeNames[db.device(h.deviceId)?.type] || "装备",
            e(h.deviceId),
            e(h.operator),
            e(h.start),
            e(h.end || "—"),
            dot(h.end ? "已归还" : "使用中", h.end ? "muted" : "green"),
          ],
        })),
        "compact",
      ),
    )}</div>`;
  };
  R.views.works = () => {
    const q = filter(),
      list = works().filter(
        (w) =>
          search(w.name + " " + w.id, q.q) &&
          (!q.area || w.area === q.area) &&
          (!q.date || w.date === q.date) &&
          (!q.sync || (q.sync === "yes" ? w.synced : !w.synced)) &&
          (!q.status || w.status === q.status),
      );
    let w = list.find((x) => x.id === s.work) || list[0];
    if (w) s.work = w.id;
    return (
      title("作业监护", "对现场作业进行人员、装备和状态的实时监护") +
      '<div class="works-toolbar">' +
      filterForm(
        `${f("作业名 / 工作票号", inp("q", "请输入作业名或工作票号", q.q || ""))}${f("区域", sel("area", [["", "全部区域"], ...D.areas], q.area))}${dateField()}${f("监护状态", sel("status", [["", "全部"], "监护中", "已结束"], q.status))}${f(
          "同步状态",
          sel(
            "sync",
            [
              ["", "全部"],
              ["yes", "已同步"],
              ["no", "待同步"],
            ],
            q.sync,
          ),
        )}`,
      ) +
      `<div class="works-actions" role="group" aria-label="作业管理操作">${b("关联已有作业", "associate-work", "", "primary")}${b("刷新来源", "sync-works", "", "", "refresh-line")}</div></div><div class="grid cols-2"><div class="stack">${panel(
        "作业列表 <small>（共 " + list.length + " 条）</small>",
        table(
          [
            "作业名称",
            "来源编号",
            "监护人",
            "区域",
            "人员数",
            "装备在线",
            "待核验数",
            "来源状态",
            "操作",
          ],
          list.map((x) => {
            const ds = x.members.flatMap((p) => db.currentDevices(p));
            return {
              attrs: `data-action="select-work" data-id="${x.id}" class="${w?.id === x.id ? "selected" : ""}"`,
              cells: [
                e(x.name),
                e(x.id),
                pn(x.supervisor),
                e(x.area),
                x.members.length + " 人",
                ds.filter((d) => d.online).length + " / " + ds.length,
                `<b class="yellow">${events().filter((a) => a.workId === x.id && a.status !== "已核验").length}</b>`,
                dot(
                  x.synced ? "已同步" : "待同步",
                  x.synced ? "green" : "yellow",
                ),
                l("查看", "work/" + x.id, "btn small"),
              ],
            };
          }),
        ),
        "",
        "work-list",
      )}${panel(
        "当日作业时间窗 <small>" + e(q.date || D.DATE) + "</small>",
        `<div class="work-timeline"><div class="time-axis"><span></span><div>${["06:00", "08:00", "10:00", "12:00", "14:00", "16:00", "18:00"].map((x) => `<span>${x}</span>`).join("")}</div></div>${list
          .map((x) => {
            const mins = (t) =>
              Number(t.split(":")[0]) * 60 + Number(t.split(":")[1]);
            return `<div class="work-time-row"><span>${e(x.name)}（${x.members.length}人）</span><div class="work-time-track">${l(x.start + " – " + x.end, "work/" + x.id, ``).replace("<a ", `<a style="left:${((mins(x.start) - 360) / 720) * 100}%;width:${((mins(x.end) - mins(x.start)) / 720) * 100}%" `)}</div></div>`;
          })
          .join("")}</div>`,
      )}</div>${panel("作业详情", w ? `<h3>${e(w.name)}　${tag("进行中", "green")}</h3>${wi(w)}<div class="detail-section"><h3>作业区域示意图</h3><div style="height:220px">${map({ person: w.members[0], markers: true, legend: false })}</div></div><p class="note">${i("information-line")}许可及摘要以原工作票系统为准。</p>` : empty(), w ? l("进入作业监护　›", "work/" + w.id, "btn primary") : "")}</div>`
    );
  };
  R.views.work = () => {
    const w = db.work(R.routeId || s.work);
    if (!w || w.station !== s.station) return missing();
    const p =
      personValid(s.person) && w.members.includes(s.person)
        ? db.person(s.person)
        : db.person(w.members[0]);
    const devices = w.members.flatMap((pid) => db.currentDevices(pid)),
      ev = events().filter((a) => a.workId === w.id && a.status !== "已核验"),
      a = ev[0];
    return (
      title(
        `${l(i("arrow-left-line") + " 返回作业列表", "works", "text-link")}　${e(w.name)}　${tag("进行中")}`,
        "",
        stats(
          [
            ["", "作业人数", w.members.length, "人"],
            ["", "装备数量", devices.length, "件"],
            ["", "在线装备", devices.filter((d) => d.online).length, "件"],
          ],
          "mini",
        ),
      ) +
      `<div class="row muted" style="margin-bottom:18px">工作票编号　${e(w.id)}　${tag("只读（来源：作业管理系统）", "muted")}<span class="spacer"></span>负责人　${pn(w.leader)}　|　监护人　${pn(w.supervisor)}　|　作业时间　${w.date} ${w.start} – ${w.end}</div><div class="grid cols-2"><div class="stack">${p ? video(p.id, { controls: true, class: "work-media" }) : empty("作业暂无成员")}<div class="row">${w.members.map((pid, k) => b("镜头 " + (k + 1) + " · " + db.person(pid)?.name, "work-camera", pid, s.person === pid ? "active" : "")).join("")}</div>${panel(
        "作业人员与装备状态（" + w.members.length + " 人）",
        table(
          [
            "姓名",
            "岗位",
            "三类装备状态（安全帽 / 安全带 / 智能手表）",
            "位置",
            "最后上报",
            "操作",
          ],
          w.members.map((pid) => {
            const p = db.person(pid);
            return {
              cells: [
                `<div class="person-cell">${avatar(p, true)}${pn(pid)}</div>`,
                tag(
                  pid === w.supervisor
                    ? "现场监护人"
                    : pid === w.leader
                      ? "作业负责人"
                      : "作业人员",
                ),
                ds(pid),
                e(p.area),
                p.updated,
                `<div class="inline-buttons">${l("查看轨迹", "tracks/" + pid, "btn small")}${b("发起对讲", "call-person", pid, "small")}</div>`,
              ],
            };
          }),
        ),
        "",
        "",
      )}</div><div class="stack">${panel(a ? i("alarm-warning-fill", "yellow") + "　" + e(a.title) : "事件状态", a ? `<dl class="info compact"><dt>涉及人员</dt><dd>${pn(a.personId)}</dd><dt>设备编号</dt><dd>${a.deviceId}</dd><dt>发生时间</dt><dd>${a.date} ${a.time}</dd><dt>事件描述</dt><dd>${e(a.title)}，需联系现场核验。</dd></dl><div class="form-actions">${l("查看事件详情", "event/" + a.id, "btn primary")}${b("联系监护人（" + db.person(w.supervisor)?.name + "）", "call-person", w.supervisor)}</div>` : dot("暂无待核验事项"), a ? tag(a.status, "yellow") : "")}${panel("作业区域示意", `<div style="height:220px">${map({ person: p?.id, legend: false })}</div><div class="detail-section"><h3>来源风险提示　${tag("来源摘要（示例）", "yellow")}</h3><p class="note">本作业存在高处作业、受限空间临近、热表面等风险，请按作业方案落实安全防护措施。</p>${b("查看完整风险信息 ›", "risk-info", w.id, "plain blue")}</div>`, "厂区示意 · 非实测")}${panel(
        "现场记录",
        `<div class="timeline">${[
          ...events()
            .filter((a) => a.workId === w.id)
            .map((a) => ({
              time: a.time,
              text: pn(a.personId) + "　" + e(a.title),
            })),
          { time: "09:12:33", text: pn(w.leader) + " 开始设备检查" },
          {
            time: w.start,
            text: w.members.length + " 人到达作业区域，开始监护",
          },
        ]
          .map(
            (t) =>
              `<div class="timeline-item"><time>${t.time}</time>${t.text}</div>`,
          )
          .join("")}</div>`,
        b("全部记录", "work-records", w.id, "small"),
      )}</div></div>`
    );
  };
  R.videoPeople = () => {
    const q = s.filters.video || {};
    return people().filter(
      (p) =>
        (!q.area || p.area === q.area) &&
        (!q.workId || db.currentWork(p.id)?.id === q.workId),
    );
  };
  R.views.video = () => {
    const q = filter(),
      list = R.videoPeople();
    const p = list.find((p) => p.id === s.person) || list[0];
    if (p) s.person = p.id;
    const st = db.stats(scope()),
      count = { available: 0, interrupted: 0, off: 0 };
    list.forEach((p) => {
      const d = db.currentDevices(p.id).find((d) => d.type === "H");
      if (d?.video) count[d.video]++;
    });
    const thumb = (p) =>
      `<button class="video-thumb ${p.id === s.person ? "selected" : ""}" data-action="select-camera" data-id="${p.id}">${video(p.id)}<strong>${e(p.name)}　<small>${e(db.currentDevices(p.id).find((d) => d.type === "H")?.id || "未绑定")}</small></strong><small>${e(p.area)}</small></button>`;
    return (
      title(
        "现场视频墙",
        "来自安全帽的第一视角，支持多路视频同步查看",
        stats(
          [
            [
              "vidicon-line",
              "帽机设备总数",
              list.filter((p) =>
                db.currentDevices(p.id).some((d) => d.type === "H"),
              ).length,
            ],
            ["record-circle-fill", "视频可用", count.available, "", "green"],
            ["record-circle-fill", "回传中断", count.interrupted, "", "red"],
            ["record-circle-fill", "未开启", count.off, "", "muted"],
          ],
          "mini",
        ),
      ) +
      `<div class="video-toolbar"><div class="layout-control">布局切换：${["1+7", "2×4", "3×3"].map((x) => b(x, "video-layout", x, s.layout === x ? "active" : "")).join("")}</div><form class="filters" data-form="filters" style="margin:0">${f("厂区区域", sel("area", [["", "全部区域"], ...D.areas], q.area))}${f("作业筛选", sel("workId", workOpts(), q.workId))}<button type="submit" class="btn small">筛选</button></form><span class="spacer"></span>轮播控制：${b("", "rotation", "", "icon-only", s.rotation ? "pause-fill" : "play-fill")}<span class="blue">30秒 / ${s.rotation ? "已开启" : "已暂停"}</span></div>${s.layout === "1+7" ? `<div class="video-wall">${p ? video(p.id, { name: true }) : empty()}${panel("当前选中设备", p ? `<div class="detail-heading">${avatar(p)}<h3>${e(p.name)}　<small>${e(db.currentDevices(p.id).find((d) => d.type === "H")?.id || "未绑定")}</small></h3>${dot("在岗")}</div><dl class="info"><dt>所属区域</dt><dd>${e(p.area)}</dd><dt>关联作业</dt><dd>${e(db.currentWork(p.id)?.name || "待分配")}</dd><dt>监护人</dt><dd>${pn(db.currentWork(p.id)?.supervisor)}</dd><dt>工作负责人</dt><dd>${pn(db.currentWork(p.id)?.leader)}</dd></dl><div class="detail-section"><h3>穿戴设备状态</h3>${ds(p.id)}</div><div class="form-actions" style="margin-top:28px">${b("声音", "video-mute", "", "primary", "volume-up-line")}${b("全屏", "fullscreen", "", "", "fullscreen-line")}${l("查看轨迹", "tracks/" + p.id, "btn")}${l("单路查看", "single/" + p.id, "btn primary")}</div>` : empty())}</div><h3 style="margin:17px 0 0">全部视频（${list.length}）</h3><div class="video-thumbs">${list.map(thumb).join("")}</div>` : `<div class="video-grid-wall ${s.layout === "3×3" ? "nine" : ""}">${list.map(thumb).join("")}${s.layout === "3×3" && list.length < 9 ? `<div class="panel">${empty("无更多视频通道")}</div>` : ""}</div>`}`
    );
  };
  R.views.single = () => {
    const p = personValid(R.routeId || s.person);
    if (!p) return missing();
    const a = relatedEvent(p.id),
      m = materials()
        .filter((m) => m.personId === p.id)
        .slice(0, 3),
      call = db.state.calls.find(
        (c) => c.status !== "已结束" && c.members.includes(p.id),
      );
    return `<p class="muted" style="margin:4px 0 20px">${l("视频监看", "video")}　›　${e(p.name)} · 单路监看</p><div class="grid cols-2">${panel(`${e(p.name)} · 单路监看　 <small>${e(db.currentDevices(p.id).find((d) => d.type === "H")?.id || "未绑定")}　|　${e(p.area)}</small>`, video(p.id, { controls: true }), b("全屏查看", "fullscreen", "", "small", "fullscreen-line"), "flush")}${panel("远程指导", `<div class="remote-box">${i("vidicon-off-line")}<h3>${call ? e(call.status) : "未发起通话"}</h3><p>可与现场人员进行音视频通话，指导作业或核实异常情况。</p>${b(call ? "查看当前通话" : "发起音视频通话", call ? "go-dispatch" : "call-person", p.id, "primary wide", "vidicon-fill")}</div><h3>参与者</h3><div class="participant">${avatar({ name: "值守" })}<div>值守员（我）<small style="display:block">调度中心</small></div>${dot(call?.status === "通话中" ? "已接入" : "待接入", call?.status === "通话中" ? "green" : "yellow")}</div><div class="participant">${avatar(p)}<div>${e(p.name)}<small style="display:block">${e(p.area)}</small></div>${dot(call?.status === "通话中" ? "已接入" : "待接入", call?.status === "通话中" ? "green" : "yellow")}</div>${a ? `<div class="warning-box" style="margin-top:15px">${l(i("error-warning-fill") + "　" + e(a.title) + "　›", "event/" + a.id)}<small style="display:block;margin-top:8px">${a.time} 发生，${e(a.status)}</small></div>` : ""}<div class="detail-section"><h3>最近影像 / 记录</h3>${m.map((x) => `<div class="recent-media" data-action="open-media" data-id="${x.id}">${mediaImage(x)}<div>${e(x.created)}<p class="blue">${pn(p.id)} · ${e(x.deviceId)}</p><small>${e(x.source)}</small></div></div>`).join("")}${l("查看全部 ›", "materials", "text-link")}</div>`)}</div><p class="note">${i("information-line")}图片模拟现场视频；连接成功后显示通话状态，录像记录保留封面与时长。</p>`;
  };
  R.materialList = () => {
    const q = filter();
    return materials().filter(
      (m) =>
        (!q.eventId || m.eventId === q.eventId) &&
        (s.mediaTab === "all" || m.kind === s.mediaTab) &&
        (!q.personId || m.personId === q.personId) &&
        (!q.deviceId || m.deviceId === q.deviceId) &&
        (!q.workId || m.workId === q.workId) &&
        (!q.date || m.date === q.date),
    );
  };
  R.views.materials = () => {
    const q = filter(),
      list = R.materialList(),
      m = list.find((x) => x.id === s.media) || list[0];
    if (m) s.media = m.id;
    return (
      title("现场影像资料", "设备回传照片与录像的检索、查看和归档") +
      `<div class="split-detail"><div>${filterForm(`${q.eventId ? `<span class="tag">事件 ${e(q.eventId)}</span><input type="hidden" name="eventId" value="${e(q.eventId)}">` : ""}${f("设备编号", sel("deviceId", deviceOpts(), q.deviceId))}${f("人员", sel("personId", personOpts(), q.personId))}${f("关联作业", sel("workId", workOpts(), q.workId))}${dateField()}`)}${tabs(
        [
          ["all", "全部资料"],
          ["photo", "照片"],
          ["video", "录像"],
        ],
        s.mediaTab,
        "media-tab",
      )}<div class="media-grid">${list.map((x) => `<article class="media-card ${x.id === m?.id ? "selected" : ""}" tabindex="0" role="button" data-action="select-media" data-id="${x.id}"><div class="preview">${mediaImage(x)}<span class="video-label">示例画面 · 非实时</span>${x.kind === "video" ? `<span class="play-overlay">${i("play-fill")}</span><span class="video-time">${String(Math.floor(x.duration / 60)).padStart(2, "0")}:${String(x.duration % 60).padStart(2, "0")}</span>` : ""}</div><h3>${e(x.title)}　${tag(x.kind === "photo" ? "照片" : "录像 " + x.duration + "秒")}</h3><p><span>${i("user-line")} ${e(x.deviceId)} · ${e(x.snapshot.personName)}</span><span>${i("time-line")} ${e(x.created)}</span></p></article>`).join("") || empty()}</div><p class="count-label">共 ${list.length} 条</p></div>${panel("资料详情", m ? `${mediaImage(m)}<h3 style="margin-top:18px">${e(m.title)}　${tag(m.kind === "photo" ? "照片" : "模拟录像")}</h3><dl class="info"><dt>资料编号</dt><dd>${e(m.id)}</dd><dt>来源</dt><dd>${e(m.source)}</dd><dt>拍摄设备</dt><dd>${e(m.deviceId)}</dd><dt>关联人员</dt><dd>${e(m.snapshot.personName)}</dd><dt>关联作业</dt><dd>${e(m.workId || "—")}</dd><dt>关联事件</dt><dd>${e(m.eventId || "—")}</dd><dt>拍摄时间</dt><dd>${e(m.created)}</dd><dt>核验引用</dt><dd>${m.eventId ? tag(db.event(m.eventId)?.status || "待提交", "yellow") : "—"}</dd></dl><div class="form-actions">${b(m.kind === "photo" ? "查看原图" : "模拟回放", "preview-media", m.id, "primary", "image-line")}${b("下载资料", "download-media", m.id, "", "download-line")}</div>${m.eventId ? `<p style="margin-top:16px">${l("查看关联事件 ›", "event/" + m.eventId, "text-link")}</p>` : ""}` : empty(), "", "media-detail")}</div>`
    );
  };
  R.views.location = () => {
    const q = filter(),
      list = people().filter(
        (p) =>
          search(
            p.name +
              " " +
              db
                .currentDevices(p.id)
                .map((d) => d.id)
                .join(" "),
            q.q,
          ) &&
          (!q.workId || db.currentWork(p.id)?.id === q.workId),
      );
    const p = list.find((p) => p.id === s.person) || list[0];
    if (p) s.person = p.id;
    return (
      title(
        "实时定位",
        "按人员查看关联安全帽位置",
        stats(
          [
            ["user-line", "当班人员", list.length],
            [
              "map-pin-line",
              "位置可查看",
              list.filter((p) => db.locationValid(p.id)).length,
              "",
              "cyan",
            ],
            [
              "alarm-warning-line",
              "位置待核验",
              list.filter((p) => !db.locationValid(p.id)).length,
              "",
              "yellow",
            ],
          ],
          "mini",
        ),
      ) +
      locationTabs() +
      `<div class="location-layout">${panel(
        "当班人员",
        filterForm(
          `<div class="searchbox">${i("search-line")}${inp("q", "姓名 / 安全帽编号", q.q || "")}</div>${f("作业分组", sel("workId", workOpts(), q.workId))}`,
        ) +
          table(
            ["姓名", "安全帽编号", "作业区域", "状态"],
            list.map((p) => ({
              attrs: `data-action="locate-person" data-id="${p.id}" class="${p.id === s.person ? "selected" : ""}"`,
              cells: [
                `${i("user-fill")}　${e(p.name)}`,
                e(
                  db.currentDevices(p.id).find((d) => d.type === "H")?.id ||
                    "未绑定",
                ),
                e(db.locationValid(p.id) ? p.area : "位置待核验"),
                dot(
                  db.locationValid(p.id) ? "在线" : "待核验",
                  db.locationValid(p.id) ? "green" : "yellow",
                ),
              ],
            })),
          ),
      )}${map({ popup: !!p, personIds: list.map((x) => x.id) })}</div><div class="layer-controls">${[
        ["people", "人员"],
        ["areas", "作业区域"],
        ["fences", "电子围栏"],
      ]
        .map(
          ([key, name]) =>
            `<label><input type="checkbox" data-layer="${key}" ${s.layers[key] ? "checked" : ""}>${name}</label>`,
        )
        .join(
          "",
        )}</div><p class="note">${i("information-line")}人员位置由关联安全帽提供；位置滞后或缺失需现场核验，不表示室内精度。</p>`
    );
  };
  R.views.tracks = () => {
    const q = filter(),
      p = personValid(R.routeId || q.personId || s.person) || people()[0];
    if (p) s.person = p.id;
    const date = q.date || D.DATE,
      start = q.start || "09:00",
      end = q.end || "10:42";
    try {
      s.trackPoints = p ? db.tracks(p.id, date, start, end) : [];
    } catch {
      s.trackPoints = [];
    }
    s.trackIndex = Math.min(
      s.trackIndex,
      Math.max(0, s.trackPoints.length - 1),
    );
    const current = s.trackPoints[s.trackIndex],
      a = p ? relatedEvent(p.id) : null,
      hasGap =
        s.trackPoints.some((t) => t.gap) &&
        s.trackPoints.some((t) => t.time < "09:46");
    return (
      title("历史轨迹") +
      locationTabs() +
      `<form class="filters" data-form="track-filters">${f(
        "设备",
        sel(
          "personId",
          people().map((p) => [
            p.id,
            (db.currentDevices(p.id).find((d) => d.type === "H")?.id ||
              "未绑定") +
              " / " +
              p.name,
          ]),
          p?.id,
        ),
      )}${f("日期", inp("date", "", date, "date"))}${f("时间范围", inp("start", "", start, "time"))}<span>—</span>${inp("end", "", end, "time")}<button type="submit" class="btn primary">查询轨迹</button>${b("导出轨迹", "export-tracks", "", "", "download-line")}<span class="spacer"></span><small>${i("information-line")}位置来源：关联安全帽</small></form><div class="tracks-layout">${panel(
        "轨迹片段与事件",
        s.trackPoints.length
          ? `${[
              s.trackPoints.filter((t) => t.time <= "09:38"),
              s.trackPoints.filter((t) => t.time >= "09:46"),
            ]
              .filter((g) => g.length)
              .map(
                (g, idx) =>
                  `${idx && hasGap ? `<div class="track-segment"><b class="yellow">09:38 — 09:46</b><small class="yellow">数据缺口</small><small>缺口时段无可靠位置，不插值连线。</small></div>` : ""}<div class="track-segment"><b>${tag(idx + 1)}　${g[0].time} — ${g.at(-1).time}</b><small class="blue">有效片段</small><small>轨迹点　${g.length} 个</small></div>`,
              )
              .join(
                "",
              )}<div class="detail-section"><h3>事件记录</h3>${a ? `<p class="yellow">${a.time}　${e(a.title)}</p><p><small>关联事件　${e(a.id)}</small></p>${l("查看核验", "event/" + a.id, "btn wide")}` : empty("无关联事件")}</div>`
          : empty("所选时段无轨迹"),
      )}<div class="stack"><div class="track-map">${map({ mode: "tracks", markers: false })}</div>${panel(
        "轨迹回放",
        `<div class="track-controls"><input type="range" class="track-progress" min="0" max="${Math.max(0, s.trackPoints.length - 1)}" value="${s.trackIndex}" data-setting="trackIndex" aria-label="轨迹回放进度"><div class="track-labels"><span>${e(start)}</span>${hasGap ? '<span class="yellow">09:38 — 09:46 数据缺口</span>' : ""}<span>${e(end)}</span></div><div class="row">${b("", "track-play", "", "primary icon-only", s.trackPlaying ? "pause-fill" : "play-fill")}${b("", "track-stop", "", "icon-only", "stop-fill")}${sel(
          "speed",
          [
            ["1", "1×"],
            ["2", "2×"],
            ["4", "4×"],
          ],
          s.trackSpeed,
          'data-setting="trackSpeed" aria-label="回放速度"',
        )}<span>${date} ${current?.time || "--:--"}:00</span><span class="spacer"></span><small>当前采样点信息　${current ? e(current.deviceId) : "—"}</small></div></div>`,
      )}</div></div>`
    );
  };
  R.views.fences = () => {
    const list = db.state.fences.filter(
      (x) =>
        x.station === s.station &&
        !x.archived &&
        (!filter().status ||
          (filter().status === "on" ? x.enabled : !x.enabled)),
    );
    let selected = list.find((x) => x.id === s.fence) || list[0];
    if (!s.fenceDraft && selected) {
      s.fence = selected.id;
      s.fenceDraft = structuredClone(selected);
    }
    const d = s.fenceDraft;
    return (
      title(
        "电子围栏",
        "",
        b("新建围栏", "new-fence", "", "primary", "add-line") +
          b("查看进出记录", "fence-records", "", "", "file-list-3-line"),
      ) +
      locationTabs() +
      `<div class="fence-layout">${panel(
        "围栏列表",
        `<form class="filters" data-form="filters">${sel(
          "status",
          [
            ["", "全部状态"],
            ["on", "启用"],
            ["off", "停用"],
          ],
          filter().status,
        )}<button class="btn small" type="submit">筛选</button></form>${list.map((x) => `<div class="fence-row ${d?.id === x.id ? "selected" : ""}" data-action="select-fence" data-id="${x.id}"><h3>${e(x.name)}</h3><div class="row space-between"><small>关联厂站：${e(db.state.stations.find((a) => a.id === x.station)?.name)}</small>${dot(x.enabled ? "启用" : "停用", x.enabled ? "green" : "muted")}</div></div>`).join("") || empty()}${d?.id ? `<div class="form-actions" style="margin:24px 0 8px">${b("编辑", "fence-mode", "edit", "", "edit-line")}${b(d.enabled ? "停用" : "启用", "toggle-fence", d.id, "", "pause-circle-line")}${b("删除", "delete-fence", d.id, "danger", "delete-bin-line")}</div>` : ""}`,
      )}${map({ mode: "fence", markers: false })}${panel(
        d?.id ? "编辑围栏" : "新建围栏",
        d
          ? `<form class="form-stack" data-form="fence">${f("围栏名称", inp("name", "请输入名称", d.name || "", "text", 'required maxlength="40"'))}${f(
              "关联厂站",
              sel(
                "station",
                db.state.stations.map((x) => [x.id, x.name]),
                s.station,
                "disabled",
              ),
            )}<div class="field"><span>进出条件</span><div class="stack"><label class="row"><input type="checkbox" name="enter" ${d.enter ? "checked" : ""}>进入时提示</label><label class="row"><input type="checkbox" name="leave" ${d.leave ? "checked" : ""}>离开时提示</label></div></div>${f("适用人员", b((d.members || []).length + " 人 · 选择成员", "fence-members", "", "wide"))}${f("责任部门", inp("department", "", d.department || ""))}${f("责任人", inp("owner", "", d.owner || ""))}<div class="field"><span>状态</span><label class="row"><input type="checkbox" name="enabled" ${d.enabled ? "checked" : ""}>启用</label></div><div class="form-actions">${b("取消", "cancel-fence")}<button type="submit" class="btn primary">保存围栏</button></div><p class="form-error" role="alert"></p></form>`
          : empty("请新建围栏"),
      )}</div><p class="note" style="text-align:center">${i("information-line")}围栏判断依赖位置数据，位置异常时需现场核验。</p>`
    );
  };
  R.alarmList = () => {
    const q = filter();
    return events().filter(
      (a) =>
        search(a.deviceId, q.q) &&
        (!q.date || a.date === q.date) &&
        (!q.type || a.type === q.type) &&
        (!q.status || a.status === q.status),
    );
  };
  R.views.alarms = () => {
    const q = filter(),
      list = R.alarmList(),
      a = list.find((x) => x.id === s.event) || list[0];
    if (a) s.event = a.id;
    const st = (t) => list.filter((x) => x.status === t).length;
    return `<div class="split-detail"><div>${title(
      "告警与核验",
      "设备异常与现场核验协同",
      stats(
        [
          ["alarm-warning-line", "待现场核验", st("待现场核验"), "", "yellow"],
          ["file-list-3-line", "待认领", st("待认领")],
          ["settings-3-line", "处理中", st("处理中")],
        ],
        "mini",
      ),
    )}${filterForm(`${f("设备编号", inp("q", "请输入设备编号", q.q || ""))}${dateField()}${f("事件类型", sel("type", [["", "全部"], "设备通信", "低电量", "位置异常"], q.type))}${f("核验状态", sel("status", [["", "全部"], "待现场核验", "待认领", "处理中", "已核验"], q.status))}`)}<div class="panel alarms-table">${table(["事件编号", "类型", "人员", "设备编号", "发生时间", "状态", "操作"], eventRows(list))}</div><div class="pagination"><span>共 ${list.length} 条</span><div class="row">${b("", "page-prev", "", "small", "arrow-left-s-line")}${b("1", "page-current", "", "primary small")}${b("", "page-next", "", "small", "arrow-right-s-line")}</div></div></div>${panel("事件摘要", a ? `<h3>${i("alarm-warning-line", "yellow")}　${e(a.title)}</h3><dl class="info compact"><dt>人员 · 设备</dt><dd>${e(a.snapshot.personName)} · ${e(a.deviceId)}</dd><dt>作业名称</dt><dd>${e(a.snapshot.workName)}</dd><dt>作业编号</dt><dd>${e(a.workId)}</dd><dt>当前监护人</dt><dd>${pn(db.work(a.workId)?.supervisor)}</dd><dt>发生时间</dt><dd>${a.date} ${a.time}</dd></dl><div class="warning-box" style="margin-top:15px"><h3 style="font-size:15px">连接中断不直接判定穿戴违规</h3><small>平台仅进行监测、通信、核验与记录，不作为违规判定依据。</small></div><div class="detail-section"><h3>事件来源</h3><dl class="info compact"><dt>原安监事件</dt><dd>${e(a.externalId)}</dd><dt>当前状态</dt><dd class="blue">${e(a.externalStatus)}</dd></dl></div><div class="detail-section"><h3>现场位置</h3>${map({ person: a.personId, legend: false })}</div><div class="detail-section"><h3>现场视频</h3>${l(video(a.personId), "single/" + a.personId)}</div><div class="form-actions">${l("进入现场核验", "event/" + a.id, "btn primary wide")}</div><p class="note cyan">${i("checkbox-circle-fill")}摘要回传（示例） · ${a.verification ? "核验记录已提交" : "核验记录未提交"}</p>` : empty(), "", "alarm-detail")}</div>`;
  };
  R.views.event = () => {
    const a = db.event(R.routeId || s.event);
    if (!a || a.station !== s.station) return missing();
    const w = db.work(a.workId),
      m = materials().filter((m) => m.eventId === a.id),
      draft = s.formDrafts[a.id] || a.draft || {},
      verified = !!a.verification;
    return (
      title(
        "事件核验详情",
        "",
        l(i("arrow-left-line") + " 返回列表", "alarms", "btn"),
      ) +
      `<div class="grid cols-2"><div class="stack"><div class="panel event-banner">${i("alarm-warning-line", "yellow")}<h1>${e(a.title)}</h1>${tag(a.status, statusColor(a.status))}<small>${e(a.snapshot.personName)} · ${e(a.deviceId)} · ${a.date} ${a.time}</small></div>${panel("事件关联信息", `<div class="grid equal"><dl class="info compact"><dt>关联作业</dt><dd>${e(a.snapshot.workName)}</dd><dt>工作票</dt><dd>${e(a.workId)}（只读）</dd></dl><dl class="info compact"><dt>当前监护人</dt><dd>${pn(w?.supervisor)}</dd><dt>当前负责人</dt><dd>${pn(w?.leader)}</dd></dl></div>`)}<div class="grid equal evidence">${panel("现场影像证据", m[0] ? `<div class="media-preview-wrap" data-action="preview-media" data-id="${m[0].id}" style="cursor:pointer">${mediaImage(m[0])}<span class="video-label">示例画面 · 非实时</span></div>` : video(a.personId))}${panel("关联装备当前状态", ds(a.personId) + `<div class="detail-section">${dot("挂接及受力信息　待协议确认", "yellow")}<p class="note">安全带连接中断不等于挂接违规，需现场核验确认。</p></div>`)}</div><div class="grid equal">${panel("处置时间线", `<div class="timeline">${a.timeline.map((t) => `<div class="timeline-item"><time>${e(t.time)}</time>${e(t.text)}</div>`).join("")}<div class="timeline-item">${verified ? "核验记录已提交" : "核验记录尚未提交"}</div></div>`)}${panel("相关资料", `<div class="grid equal">${m.map((x) => `<div data-action="preview-media" data-id="${x.id}" style="cursor:pointer">${mediaImage(x)}<small>${e(x.title)}</small></div>`).join("")}</div><div class="form-actions">${b("查看原始资料", "event-materials", a.id, "", "folder-line")}</div>`)}</div></div><div class="stack">${panel(verified ? "已提交核验结果" : "填写核验结果", `<form class="form-stack" data-form="verify" data-id="${a.id}">${f('核验结论 <span class="red">*</span>', sel("conclusion", [["", "请选择"], "设备通信异常", "需现场处理", "暂无法确认"], draft.conclusion || "", verified ? "disabled" : ""))}${f('现场情况 <span class="red">*</span>', `<div><textarea name="situation" maxlength="500" placeholder="请描述现场核验情况" ${verified ? "readonly" : ""}>${e(draft.situation || "")}</textarea><div class="char-count">${(draft.situation || "").length}/500</div></div>`)}${f("后续措施", `<div><textarea name="measures" maxlength="500" placeholder="填写安排与责任人" ${verified ? "readonly" : ""}>${e(draft.measures || "")}</textarea><div class="char-count">${(draft.measures || "").length}/500</div></div>`)}${!verified ? `<div class="field"><span>现场照片</span><label class="upload-area">${i("camera-fill")}添加现场照片<small>支持 JPG、PNG，单张不超过 10MB</small><input type="file" accept="image/png,image/jpeg" data-upload-event="${a.id}" aria-label="添加现场照片"></label></div><div class="form-actions">${b("保存草稿", "save-draft", a.id)}<button type="submit" class="btn primary">提交核验记录</button></div>` : `<div class="warning-box"><p>${i("checkbox-circle-line")} ${e(a.verification.submittedAt)}　值守员已提交</p></div>`}<p class="form-error" role="alert"></p></form>`)}${panel("原安监系统", `<dl class="info compact"><dt>${i("lock-fill")} ${e(a.externalId)}</dt><dd class="yellow">状态：${e(a.externalStatus)}</dd><dt>摘要</dt><dd>${a.externalStatus === "待回传" ? "待回传" : "回传成功（示例）"}</dd><dt>核验记录</dt><dd>${verified ? "已提交" : "未提交"}</dd></dl><p class="note">${i("information-line")}原系统状态只读，正式结案在原安监系统完成。</p>`)}</div></div>`
    );
  };
  function callVideos(call) {
    return `<div class="call-videos ${call.members.length > 1 ? "multiple" : ""}">${call.members.map((pid) => {
      const person = db.person(pid);
      const helmet = db.currentDevices(pid).find((d) => d.type === "H");
      const poster = D.assetForArea(person?.area);
      const source = poster.replace("scene-", "call-").replace(".png", ".webm");
      const available = helmet?.video === "available";
      const status = !helmet ? "未绑定安全帽" : helmet.video === "off" ? "视频未开启" : "视频回传中断";
      return `<figure class="call-video-tile"><div class="call-video-frame">${available ? `<video data-call-video="${e(call.id + ":" + pid)}" src="assets/${e(source)}" poster="assets/${e(poster)}" autoplay muted loop playsinline controls preload="auto" aria-label="${e(person?.name)}的模拟现场视频"></video><span class="call-video-badge">模拟视频 · 非实时</span><div class="call-video-error" hidden>模拟视频暂不可用，请刷新后重试</div>` : `<img src="assets/${e(poster)}" alt="${e(person?.area)}示例场景"><div class="call-video-unavailable">${i("vidicon-off-line")}<strong>${status}</strong></div>`}</div><figcaption><strong>${pn(pid)}</strong><small>${e(helmet?.id || "未绑定")} · ${e(person?.area || "—")}</small><span class="${call.status === "通话中" ? "green" : "yellow"}">${call.status === "通话中" ? "已接通" : "等待接听 · 画面预览"}</span></figcaption></figure>`;
    }).join("")}</div>`;
  }
  R.views.dispatch = () => {
    const groups = db.state.groups.filter((g) => g.station === s.station),
      g = groups.find((g) => g.id === s.group) || groups[0];
    if (g) s.group = g.id;
    const q = filter(),
      list = people().filter((p) =>
        search(
          p.name +
            " " +
            db
              .currentDevices(p.id)
              .map((d) => d.id)
              .join(" "),
          q.q,
        ),
      ),
      call = db.state.calls.find(
        (c) => c.station === s.station && c.status !== "已结束",
      ),
      recent = db.state.calls
        .filter((c) => c.station === s.station)
        .slice(0, 3),
      broadcasts = db.state.broadcasts
        .filter((x) => x.station === s.station)
        .slice(0, 3);
    return (
      title(
        "人员联络、协助分组与广播",
        "调度通信 / 调度台",
        b("通信记录", "call-records", "", "", "file-list-3-line") +
          l(i("alarm-warning-line") + " SOS协同", "sos", "btn danger"),
      ) +
      `<div class="grid dispatch-layout">${panel(
        "人员与分组",
        `${tabs(
          [
            ["people", "人员"],
            ["groups", "协助分组"],
          ],
          s.dispatchTab || "people",
          "dispatch-tab",
        )}${filterForm(`<div class="searchbox">${i("search-line")}${inp("q", "姓名 / 安全帽编号", q.q || "")}</div>`)}<div class="row space-between"><span class="muted">协助分组</span>${b("新建分组", "new-group", "", "plain blue", "add-line")}</div>${groups.map((x) => `<div class="group-row ${x.id === g?.id ? "selected" : ""}" data-action="select-group" data-id="${x.id}">${i("group-line")}${e(x.name)}<small>${x.members.length} 人</small></div>`).join("")}${g && s.dispatchTab === "groups" ? `<div class="form-actions">${b("编辑分组成员", "edit-group", g.id, "wide", "edit-line")}</div>` : ""}<div class="row space-between" style="margin:20px 0 8px"><span>人员（${list.length}人）</span><label class="row"><input type="checkbox" data-setting="selectAllMembers" ${list.length && list.every((p) => s.selectedMembers.includes(p.id)) ? "checked" : ""}>全选</label></div><div class="member-list">${list.map((p) => `<label class="member-row"><input type="checkbox" data-member="${p.id}" ${s.selectedMembers.includes(p.id) ? "checked" : ""}>${avatar(p)}<span>${e(p.name)}<small style="display:block">${e(db.currentDevices(p.id).find((d) => d.type === "H")?.id || "未绑定")}</small></span>${dot(db.currentDevices(p.id).find((d) => d.type === "H")?.online ? "在线" : db.currentDevices(p.id).some((d) => d.type === "H") ? "连接中断" : "未绑定", db.currentDevices(p.id).find((d) => d.type === "H")?.online ? "green" : "muted")}</label>`).join("")}</div><div class="form-actions"><span class="muted">已选 ${s.selectedMembers.filter((id) => people().some((p) => p.id === id)).length} 人</span>${b("单呼", "start-call", "单呼")}${b("发起群呼", "start-call", "群呼", "primary")}</div>`,
      )}<div class="stack">${panel("当前通话：" + (call ? e(call.kind) : "未发起"), call ? `<div class="call-status">${i(call.status === "通话中" ? "phone-fill" : "phone-find-line")}　${e(call.status)}${call.status === "通话中" ? " · 模拟接通" : " · 等待接听"}</div>${callVideos(call)}${call.members.map((pid) => `<div class="call-member">${avatar(db.person(pid))}<div>${pn(pid)}　<small>${e(db.currentDevices(pid).find((d) => d.type === "H")?.id || "未绑定")}</small></div>${dot(call.joined?.includes(pid) ? "已接通（示例）" : "振铃中（示例）", call.joined?.includes(pid) ? "green" : "yellow")}${i("voiceprint-line")}</div>`).join("")}<div class="form-actions">${b(call.status === "正在呼叫" ? "取消呼叫" : "结束通话", "end-call", call.id, "danger", "phone-fill")}${b(call.muted ? "取消静音" : "静音", "mute-call", call.id, "", "mic-off-line")}${b("邀请成员", "invite-member", call.id, "", "user-add-line")}</div>${call.status === "正在呼叫" ? `<div class="form-actions">${b("模拟接通", "connect-call", call.id, "primary wide", "phone-line")}</div>` : ""}` : `${empty("选择人员后发起单呼或群呼")}<p class="note">会话状态为交互示例，通信通道兼容性待联调。</p>`)}${panel(
        "文字广播",
        `<form class="broadcast-box" data-form="broadcast">${f(
          "广播对象",
          sel(
            "groupId",
            groups.map((x) => [x.id, x.name]),
            g?.id,
          ),
        )}<textarea name="text" maxlength="200" placeholder="请输入广播内容">${e(s.broadcastDraft || "请锅炉平台作业人员检查随身装备，保持通信畅通。")}</textarea><div class="char-count">最多 200 字</div><div class="form-actions">${b("试听", "broadcast-preview", "", "", "play-fill")}<button class="btn primary" type="submit">${i("send-plane-fill")} 发送广播</button></div></form>`,
      )}</div><div class="stack">${panel("最近会话", recent.length ? recent.map((c) => `<div class="record-entry"><time>${e(c.time.slice(11, 16))}</time><h3>${i("user-voice-line", "blue")}　${e(c.kind)} · ${c.members.map(pn).join("、")}</h3><p>${dot(c.status, c.status === "已结束" ? "green" : "yellow")}</p></div>`).join("") : empty("暂无通信记录"), b("更多 ›", "call-records", "", "plain"))}${panel("广播记录", broadcasts.length ? broadcasts.map((c) => `<div class="record-entry"><time>${e(c.time.slice(11, 16))}</time><h3>${i("volume-up-fill")}　${e(c.groupName)}</h3><p>${e(c.text)}</p>${tag(c.status, "green")}</div>`).join("") : empty("暂无广播记录"), b("更多 ›", "broadcast-records", "", "plain"))}<p class="note">${i("information-line")}通话记录与广播回执分别留存。</p></div></div>`
    );
  };
  R.views.sos = () => {
    const a = db.state.sos;
    if (a.station !== s.station) return missing();
    const p = db.person(a.personId);
    return (
      title(
        "SOS协同　" + tag("SOS演练", "red"),
        "独立演练场景，不计入首页待处理事件",
        `<small>演练编号：${a.id}</small>`,
      ) +
      `<div class="panel sos-banner">${i("alarm-warning-fill")}<div><h2>来自安全帽 ${e(a.deviceId || "RL-H008")} 的 SOS 请求</h2><p>人员：${e(a.personName || p.name)}　请求时间：${D.DATE} 10:42:08</p></div><span class="session-badge">${{ waiting: "等待值守员加入", active: "正在协助", ended: "协助已结束" }[a.status]}</span><div class="heading-actions">${b("加入协助", "sos-join", "", "primary", "user-add-fill")}${b("结束协助", "sos-end", "", "danger", "stop-circle-line")}${b("查看通信记录", "call-records", "", "", "file-list-3-line")}</div></div><div class="grid sos-layout">${panel("求助位置", map({ person: p.id, legend: false }) + `<p class="note">${i("map-pin-fill")}位置来源：安全帽　${tag("位置需现场确认", "yellow")}</p>`)}${panel("现场视频", video(p.id, { label: a.status === "waiting" ? "待接入" : "示例画面 · 非实时" }))}${panel("协助分组", `<h3>循环水应急协助组</h3><div class="detail-section"><h3>已加入　${a.members.length}</h3>${a.members.map((pid) => `<div class="participant">${i("user-line")} ${pid === "operator" ? "值守员" : pn(pid)}<span class="spacer"></span>${dot("已加入", "green")}</div>`).join("")}</div><div class="detail-section"><h3>${a.status === "ended" ? "会话状态" : "待加入"}</h3>${a.status === "ended" ? dot("协助已结束，记录保留") : a.members.includes("operator") ? dot("所有值守人员已接入") : `<div class="participant">${i("user-line")} 值守员<span class="spacer"></span>${dot("未加入", "yellow")}</div>`}</div>`)}</div><div style="margin-top:15px">${panel("事件时间线", `<div class="timeline horizontal">${a.timeline.map((t) => `<div class="timeline-item"><time>${e(t.time)}</time>${e(t.text)}</div>`).join("")}</div>`)}</div>`
    );
  };
  R.statsScope = () =>
    scope({ date: filter().date || D.DATE, workId: filter().workId || "" });
  R.views.statistics = () => {
    const q = filter(),
      st = db.stats(R.statsScope()),
      ev = st.events,
      chartMax = Math.max(10, ...Object.values(st.byType).map((n) => n.total)),
      states = ["待现场核验", "待认领", "处理中", "已核验"],
      rows = ev.map((a) => ({
        cells: [
          e(a.snapshot.personName),
          e(a.deviceId),
          e(a.snapshot.workName),
          e(a.title) + " " + a.time,
          tag(a.status, statusColor(a.status)),
          a.externalStatus === "待回传"
            ? dot("待回传", "muted")
            : dot("摘要成功（示例）"),
          l("查看", "event/" + a.id, "btn small"),
        ],
      }));
    let detail;
    if (s.statsTab === "人员")
      detail = table(
        ["人员", "班组", "所属区域", "当前作业", "已领用装备", "操作"],
        st.people.map((p) => ({
          cells: [
            pn(p.id),
            e(p.team),
            e(p.area),
            e(db.currentWork(p.id)?.name || "待分配"),
            db.currentDevices(p.id).length,
            l("查看", "person/" + p.id, "btn small"),
          ],
        })),
      );
    else if (s.statsTab === "装备")
      detail = table(
        ["设备", "类型", "当前领用人", "电量", "状态"],
        st.devices.map((d) => ({
          cells: [
            e(d.id),
            D.typeNames[d.type],
            pn(db.owner(d.id)?.id),
            d.battery + "%",
            dot(d.online ? "在线" : "连接中断", d.online ? "green" : "red"),
          ],
        })),
      );
    else if (s.statsTab === "任务")
      detail = table(
        ["作业名称", "编号", "监护人", "人数", "状态", "操作"],
        st.works.map((w) => ({
          cells: [
            e(w.name),
            e(w.id),
            pn(w.supervisor),
            w.members.length,
            tag(w.status),
            l("查看", "work/" + w.id, "btn small"),
          ],
        })),
      );
    else
      detail = table(
        ["人员", "设备", "关联作业", "事件", "核验状态", "回传状态", "操作"],
        rows,
        "compact",
      );
    return (
      title(
        "统计与追溯",
        "按人员、装备、作业与事件追溯监护记录",
        `<form class="filters" data-form="filters" style="margin:0">${dateField()}${f("作业范围", sel("workId", workOpts(), q.workId))}<button class="btn primary" type="submit">查询</button>${b("导出详细记录", "export-statistics", "", "primary", "download-line")}</form>`,
      ) +
      `<div class="row space-between"><div class="tabs box">${["综合", "人员", "装备", "任务", "事件"].map((t) => b(t, "stats-tab", t, s.statsTab === t ? "active" : "")).join("")}</div><small class="stats-notice">${i("information-line")}本页为示例数据，所有统计均按当前筛选计算。</small></div>` +
      stats([
        ["user-line", "当班人员", st.people.length, "人", "blue"],
        ["shield-user-line", "已领用装备", st.devices.length, "件", "cyan"],
        ["clipboard-line", "监护作业", st.works.length, "项", "cyan"],
        ["alarm-warning-line", "待处理事件", st.unresolved, "起", "yellow"],
      ]) +
      `<div class="grid equal">${panel(
        "三类装备连接状态（示例）",
        `<div class="bars-chart">${Object.entries(st.byType)
          .map(
            ([t, n]) =>
              `<div class="chart-line"><span>${{ H: "安全帽", B: "安全带", W: "手表" }[t]}</span><div class="chart-bars"><div style="width:${(n.total / chartMax) * 95}%"><span>${n.total}</span></div><div style="width:${(n.online / chartMax) * 95}%"><span>${n.online}</span></div></div></div>`,
          )
          .join(
            "",
          )}<div class="axis">${[0, 0.2, 0.4, 0.6, 0.8, 1].map((v) => `<span>${Math.round(v * chartMax)}</span>`).join("")}</div></div>`,
        `<div class="legend"><span><b></b>已领用</span><span class="cyan"><b></b>在线</span><small>单位：件</small></div>`,
      )}${panel(
        "事件核验进度（示例）",
        `<div style="padding:12px 18px"><div class="row space-between"><div>已核验<h1>${st.verified}</h1></div><div>未完成核验<h1>${st.unresolved}</h1></div></div><div class="segmented-bar">${
          states
            .map((t) => {
              const n = ev.filter((a) => a.status === t).length;
              return n
                ? `<span style="flex:${n};background:${{ 待现场核验: "#f3b744", 待认领: "#ee786b", 处理中: "#318add", 已核验: "#27baa8" }[t]}">${n}</span>`
                : "";
            })
            .join("") ||
          '<span style="flex:1;background:#163e59">暂无事件</span>'
        }</div><div class="row space-between">${states.map((t) => `<div>${dot(t, statusColor(t))}<h3 style="margin:8px 0">${ev.filter((a) => a.status === t).length}</h3></div>`).join("")}</div><p class="note">核验记录提交后计入已核验。</p></div>`,
        "单位：起",
      )}</div><div style="margin-top:14px">${panel("详细追溯记录", detail)}</div><p class="note">统计口径：当前筛选 ${st.people.length} 人，3 类装备共 ${st.devices.length} 件；正式事件结案以原安监系统为准。</p>`
    );
  };
})();
