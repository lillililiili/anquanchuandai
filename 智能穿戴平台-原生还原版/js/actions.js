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
    personName: pn,
    scope,
    people,
    works,
    events,
    materials,
    modal,
    closeModal,
    toast,
    go,
    render,
    download,
    csv,
  } = R;
  const action = {};
  R.actions = action;
  action["vital-history"] = (id) => {
    const p = db.person(id);
    if (!p || p.station !== s.station) throw Error("人员不在当前厂站");
    const list = db.vitalHistory(id);
    modal(`${p.name} · 生命体征观测记录`,
      `<p class="note">预置观测，非实时测量；手表能力待确认。历史记录保留观测时的人员和设备归属。</p>${list.length ? table(
        ["观测人员 / 手表", "观测时间 / 接收时间", "心率", "血氧", "体温", "血压"],
        list.map(v => ({ cells: [
          `${e(v.personName)}<small>${e(v.deviceId)}</small>`,
          `${e(v.observedAt)}<small>${e(v.receivedAt)}</small>`,
          `${e(v.heartRate)} bpm`, `${e(v.oxygen)} %`, `${e(v.temperature.toFixed(1))} °C`, `${e(v.systolic)} / ${e(v.diastolic)} mmHg`,
        ] })), "compact") : empty("暂无历史观测记录")}`,
      b("关闭", "modal-close"), "wide");
  };
  const recentActions = new Map();
  const durationText = (v) =>
    Math.floor(Number(v) / 60)
      .toString()
      .padStart(2, "0") +
    ":" +
    (Number(v) % 60).toString().padStart(2, "0");
  const formData = (form) => Object.fromEntries(new FormData(form));
  const formError = (form, error) => {
    let box = form.querySelector(".form-error");
    if (!box) {
      box = document.createElement("p");
      box.className = "form-error";
      box.setAttribute("role", "alert");
      form.append(box);
    }
    box.textContent = error.message || error;
  };
  const refresh = (message) => {
    render();
    if (message) toast(message);
  };
  const confirm = (heading, text, fn) => {
    R.pendingConfirm = fn;
    modal(
      heading,
      `<p>${e(text)}</p>`,
      b("取消", "modal-close") + b("确认", "confirm-action", "", "danger"),
    );
  };
  const membersInput = (selected = []) =>
    `<div class="check-grid">${
      people()
        .map(
          (p) =>
            `<label><input type="checkbox" name="members" value="${p.id}" ${selected.includes(p.id) ? "checked" : ""}>${e(p.name)} <small>${e(p.team)}</small></label>`,
        )
        .join("") || empty("当前厂站暂无人员")
    }</div>`;
  function savedDraft() {
    const form = document.querySelector('[data-form="verify"]');
    if (form) s.formDrafts[form.dataset.id] = formData(form);
    const fence = document.querySelector('[data-form="fence"]');
    if (fence && s.fenceDraft) {
      Object.assign(s.fenceDraft, formData(fence), {
        enter: fence.enter.checked,
        leave: fence.leave.checked,
        enabled: fence.enabled.checked,
      });
    }
    const broadcast = document.querySelector('[data-form="broadcast"]');
    if (broadcast) s.broadcastDraft = broadcast.text.value;
  }
  function createWorkForm(id) {
    const w = db.work(id);
    if (!w) throw Error("请选择作业");
    modal(
      "调整作业成员 · " + e(w.name),
      `<form data-form="work" data-id="${w.id}" class="form-stack"><p class="note">每名人员同时只参加一项当前作业；跨作业调整需先从原作业移除。</p>${membersInput(w.members)}${f(
        "监护人",
        sel(
          "supervisor",
          people().map((p) => [p.id, p.name]),
          w.supervisor,
        ),
      )}${f(
        "负责人",
        sel(
          "leader",
          people().map((p) => [p.id, p.name]),
          w.leader,
        ),
      )}${f("开始时间", inp("start", "", w.start, "time", "required"))}${f("结束时间", inp("end", "", w.end, "time", "required"))}<div class="form-actions"><button class="btn primary" type="submit">保存关联</button>${b("取消", "modal-close")}</div><p class="form-error"></p></form>`,
    );
  }
  function createGroupForm(id) {
    const g = db.state.groups.find((g) => g.id === id) || {
      name: "",
      members: [],
    };
    modal(
      id ? "编辑协助分组" : "新建协助分组",
      `<form data-form="group" data-id="${id || ""}" class="form-stack">${f("分组名称", inp("name", "请输入名称", g.name, "text", 'required maxlength="30"'))}${membersInput(g.members)}<div class="form-actions"><button class="btn primary" type="submit">保存分组</button>${b("取消", "modal-close")}</div><p class="form-error"></p></form>`,
    );
  }
  function mediaPreview(id) {
    const m = db.state.media.find((m) => m.id === id);
    if (!m) throw Error("资料不存在");
    modal(
      e(m.title),
      `<div class="media-preview-wrap">${R.mediaImage(m)}</div>${m.kind === "video" ? `<div class="note">图片模拟回放 · 记录时长 ${m.duration} 秒</div><div class="row">${b("播放", "media-play", m.id, "primary", "play-fill")}<input type="range" data-media-progress="${m.id}" value="0" min="0" max="${m.duration}" style="flex:1" aria-label="录像模拟回放进度"><span id="media-play-time">00:00 / ${durationText(m.duration)}</span></div>` : ""}<p class="note">${e(m.snapshot.personName)} · ${e(m.deviceId)} · ${e(m.created)}</p>`,
      b("下载资料", "download-media", m.id, "primary", "download-line") +
        b("关闭", "modal-close"),
      "wide",
    );
  }
  function stopMedia() {
    clearInterval(R.mediaTimer);
    R.mediaTimer = null;
  }
  function imageBlob(asset) {
    const url = window.RollingMedia?.[asset];
    if (url) {
      const [head, data] = url.split(","),
        bytes = Uint8Array.from(atob(data), (c) => c.charCodeAt(0));
      return Promise.resolve(
        new Blob([bytes], { type: head.match(/:(.*?);/)[1] }),
      );
    }
    return fetch("assets/" + asset).then((r) => {
      if (!r.ok) throw Error("无法读取现场图片");
      return r.blob();
    });
  }
  action["modal-close"] = () => {
    stopMedia();
    closeModal();
  };
  action["confirm-action"] = () => {
    const fn = R.pendingConfirm;
    R.pendingConfirm = null;
    if (fn) fn();
  };
  action["password-toggle"] = (_, el) => {
    const input = el.closest(".input-icon").querySelector("input");
    input.type = input.type === "password" ? "text" : "password";
    el.innerHTML = i(input.type === "password" ? "eye-off-line" : "eye-line");
  };
  action["captcha-refresh"] = () => {
    s.captcha = Array.from(
      { length: 4 },
      () => "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"[Math.floor(Math.random() * 31)],
    ).join("");
    document.querySelector(".captcha-code").textContent = s.captcha;
  };
  action["notifications"] = () =>
    modal(
      "待处理通知",
      table(
        ["事件", "人员", "状态", "操作"],
        events()
          .filter((x) => x.status !== "已核验")
          .map((a) => ({
            cells: [
              e(a.title),
              pn(a.personId),
              tag(a.status, "yellow"),
              b("查看", "notification-open", a.id, "small"),
            ],
          })),
      ),
    );
  action["notification-open"] = (id) => {
    closeModal();
    go("event/" + id);
  };
  action["user-menu"] = () =>
    modal(
      "值守员",
      `<dl class="info"><dt>账号</dt><dd>admin</dd><dt>角色</dt><dd>平台值守员</dd><dt>当前厂站</dt><dd>${e(db.state.stations.find((x) => x.id === s.station)?.name)}</dd><dt>运行模式</dt><dd>本地演示</dd></dl>`,
      b("退出登录", "logout", "", "danger"),
    );
  action["logout"] = () => {
    sessionStorage.removeItem("rolling-session");
    closeModal();
    go("login");
  };
  action["go-dispatch"] = () => go("dispatch");
  action["reset-filters"] = () => {
    s.filters[R.route] = {};
    if (R.route === "tracks") {
      s.trackIndex = 0;
      s.trackPlaying = false;
    }
    render();
  };
  action["select-person"] = (id) => {
    s.person = id;
    s.hidePerson = false;
    render();
  };
  action["close-person-detail"] = () => {
    s.hidePerson = true;
    render();
  };
  action["person-tab"] = (id) => {
    s.personTab = id;
    render();
  };
  action["person-events"] = (id) => {
    const list = events().filter((x) => x.personId === id);
    modal(
      "关联事件",
      table(
        ["事件", "状态", "操作"],
        list.map((a) => ({
          cells: [
            e(a.title),
            tag(a.status),
            b("查看", "notification-open", a.id, "small"),
          ],
        })),
      ),
    );
  };
  action["select-work"] = (id) => {
    s.work = id;
    render();
  };
  action["work-camera"] = (id) => {
    s.person = id;
    render();
  };
  action["sync-works"] = () => {
    db.syncWorks(s.station);
    refresh("来源信息已刷新（本地模拟）");
  };
  action["associate-work"] = () =>
    modal(
      "关联已有作业",
      `<p class="muted">选择已有来源作业，维护监护成员和负责人。</p>${table(
        ["作业名称", "工作票号", "状态", "操作"],
        works().map((w) => ({
          cells: [
            e(w.name),
            e(w.id),
            tag(w.synced ? "已关联" : "待同步"),
            b("关联与配置", "edit-work", w.id, "small primary"),
          ],
        })),
      )}`,
    );
  action["edit-work"] = createWorkForm;
  action["risk-info"] = (id) => {
    const w = db.work(id);
    modal(
      "来源风险信息 · " + e(w?.name),
      `<p>${tag("来源摘要 · 只读", "yellow")}</p><dl class="info"><dt>工作票编号</dt><dd>${e(id)}</dd><dt>风险因素</dt><dd>高处作业、临近热表面、设备能量释放、受限通道</dd><dt>现场措施</dt><dd>按作业方案落实安全隔离、个人防护和监护措施；作业前检查装备与通信状态。</dd><dt>工作负责人</dt><dd>${pn(w?.leader)}</dd><dt>监护人</dt><dd>${pn(w?.supervisor)}</dd></dl><p class="note">本页为来源系统摘要，不在本系统进行作业审批。</p>`,
      b("关闭", "modal-close"),
    );
  };
  action["work-records"] = (id) => {
    const list = events().filter((a) => a.workId === id);
    modal(
      "作业现场记录",
      table(
        ["时间", "人员", "事件", "操作"],
        list.map((a) => ({
          cells: [
            a.date + " " + a.time,
            pn(a.personId),
            e(a.title),
            b("查看", "notification-open", a.id, "small"),
          ],
        })),
      ),
    );
  };
  action["select-camera"] = (id) => {
    s.person = id;
    render();
  };
  action["video-layout"] = (id) => {
    s.layout = id;
    render();
  };
  action["rotation"] = () => {
    s.rotation = !s.rotation;
    render();
  };
  action["video-play"] = () => {
    s.playing = !s.playing;
    render();
  };
  action["video-mute"] = () => {
    s.volume = s.volume ? 0 : 50;
    render();
  };
  action["fullscreen"] = async (_, el) => {
    const target =
      el.closest(".video-frame") || document.querySelector(".video-frame");
    if (!target) return;
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else await target.requestFullscreen();
    } catch {
      toast("当前浏览器不支持全屏，请使用窗口最大化", true);
    }
  };
  action["capture"] = async (id) => {
    const d = db.currentDevices(id).find((d) => d.type === "H");
    if (!d || d.video !== "available")
      throw Error("视频通道不可用，暂时无法抓拍");
    const asset = D.assetForArea(db.person(id)?.area),
      blob = await imageBlob(asset),
      blobId = "capture-" + crypto.randomUUID();
    await R.blobPut(blobId, blob);
    const mid = db.capture(id, "photo", 0, { blobId });
    s.media = mid;
    refresh("抓拍已保存，可在现场资料中查看");
  };
  action["record"] = (id) => {
    const d = db.currentDevices(id).find((d) => d.type === "H");
    if (!s.recording && (!d || d.video !== "available"))
      throw Error("视频通道不可用，暂时无法录像");
    if (s.recording) {
      const r = s.recording;
      const mid = db.capture(
        r.person,
        "video",
        Math.max(1, Math.floor((Date.now() - r.start) / 1000)),
      );
      s.media = mid;
      s.recording = null;
      refresh("模拟录像记录已保存（封面及录制时长）");
    } else {
      s.recording = { person: id, start: Date.now() };
      refresh("已开始模拟录像，点击停止保存记录");
    }
  };
  action["call-person"] = (id) => {
    const p = db.person(id);
    if (!p || !p.active) throw Error("人员不可用");
    const existing = db.state.calls.find((c) => c.status !== "已结束");
    if (existing) {
      s.selectedMembers = [...existing.members];
      go("dispatch");
      toast("已打开当前通话，可邀请该人员加入");
      return;
    }
    db.startCall([id], "单呼", p.station);
    s.selectedMembers = [id];
    go("dispatch");
  };
  action["media-tab"] = (id) => {
    s.mediaTab = id;
    render();
  };
  action["select-media"] = (id) => {
    s.media = id;
    render();
  };
  action["open-media"] = (id) => {
    s.filters.materials = {};
    s.mediaTab = "all";
    s.media = id;
    go("materials");
  };
  action["preview-media"] = mediaPreview;
  action["media-play"] = (id, el) => {
    if (R.mediaTimer) {
      stopMedia();
      el.innerHTML = i("play-fill") + " 播放";
      return;
    }
    const range = document.querySelector("[data-media-progress]"),
      m = db.state.media.find((m) => m.id === id);
    if (+range.value >= m.duration) range.value = 0;
    el.innerHTML = i("pause-fill") + " 暂停";
    R.mediaTimer = setInterval(() => {
      if (!range.isConnected) {
        stopMedia();
        return;
      }
      range.value = +range.value + 1;
      document.getElementById("media-play-time").textContent =
        durationText(range.value) + " / " + durationText(m.duration);
      if (+range.value >= m.duration) {
        stopMedia();
        el.innerHTML = i("play-fill") + " 重播";
      }
    }, 1000);
  };
  action["download-media"] = async (id) => {
    const m = db.state.media.find((m) => m.id === id);
    if (!m) throw Error("资料不存在");
    if (m.kind === "video") {
      download(
        m.id + "-模拟录像记录.json",
        JSON.stringify(
          {
            说明: "图片模拟录像记录，不是真实视频文件",
            资料编号: m.id,
            人员: m.snapshot.personName,
            设备: m.deviceId,
            作业: m.snapshot.workName,
            拍摄时间: m.created,
            时长秒: m.duration,
          },
          null,
          2,
        ),
        "application/json;charset=utf-8",
      );
      const blob = m.blobId
        ? await R.blobGet(m.blobId)
        : await imageBlob(m.asset);
      if (blob)
        download(
          m.id + "-封面." + (blob.type === "image/webp" ? "webp" : "png"),
          blob,
        );
    } else {
      const blob = m.blobId
        ? await R.blobGet(m.blobId)
        : await imageBlob(m.asset);
      if (!blob) throw Error("本地照片文件不存在");
      download(
        m.id +
          "." +
          (blob.type === "image/jpeg"
            ? "jpg"
            : blob.type === "image/webp"
              ? "webp"
              : "png"),
        blob,
      );
    }
    toast("资料已下载");
  };
  action["map-person"] = (id) => {
    savedDraft();
    s.person = id;
    if (R.route === "location" || R.route === "overview") render();
    else go("person/" + id);
  };
  action["locate-person"] = (id) => {
    s.person = id;
    render();
  };
  action["map-reset"] =
    action["map-zoom-in"] =
    action["map-zoom-out"] =
      () => {};
  action["track-play"] = () => {
    if (!s.trackPoints.length) throw Error("所选时段无轨迹");
    if (s.trackIndex >= s.trackPoints.length - 1) s.trackIndex = 0;
    s.trackPlaying = !s.trackPlaying;
    render();
  };
  action["track-stop"] = () => {
    s.trackPlaying = false;
    s.trackIndex = 0;
    render();
  };
  action["export-tracks"] = () => {
    if (!s.trackPoints.length) throw Error("没有可导出的轨迹");
    csv(
      "历史轨迹-" + s.person + ".csv",
      [
        "人员",
        "历史关联设备",
        "日期",
        "时间",
        "示意横坐标",
        "示意纵坐标",
        "数据缺口起点",
      ],
      s.trackPoints.map((p) => [
        db.person(s.person)?.name,
        p.deviceId,
        D.DATE,
        p.time,
        p.x,
        p.y,
        p.gap ? "是" : "否",
      ]),
    );
    toast("已导出当前查询的轨迹点");
  };
  action["select-fence"] = (id) => {
    s.fence = id;
    s.fenceDraft = structuredClone(db.state.fences.find((f) => f.id === id));
    s.fenceMode = "select";
    s.fenceUndo = [];
    render();
  };
  action["new-fence"] = () => {
    s.fence = "";
    s.fenceDraft = {
      name: "",
      points: [],
      members: [],
      enabled: true,
      enter: false,
      leave: true,
      department: "设备检修部",
      owner: "",
      station: s.station,
    };
    s.fenceUndo = [];
    s.fenceMode = "draw";
    render();
    toast("请在地图上单击添加节点，双击完成");
  };
  action["fence-mode"] = (id) => {
    savedDraft();
    if (!s.fenceDraft) throw Error("请先新建或选择围栏");
    s.fenceMode = id;
    render();
  };
  action["fence-undo"] = () => {
    savedDraft();
    if (!s.fenceUndo.length) throw Error("没有可撤销的编辑");
    s.fenceDraft.points = s.fenceUndo.pop();
    render();
  };
  action["cancel-fence"] = () => {
    s.fenceDraft = null;
    s.fenceMode = "select";
    s.fenceUndo = [];
    render();
  };
  action["toggle-fence"] = (id) => {
    const f = db.state.fences.find((f) => f.id === id);
    confirm(
      f.enabled ? "停用前确认" : "启用围栏",
      f.enabled
        ? "停用后不再触发该围栏进出提示，历史记录保留。"
        : "启用后，模拟位置变化将按围栏条件记录。",
      () => {
        db.toggleFence(id, !f.enabled);
        s.fenceDraft = null;
        closeModal();
        refresh("围栏状态已更新");
      },
    );
  };
  action["delete-fence"] = (id) =>
    confirm("删除围栏", "该围栏将归档，历史进出记录保留。", () => {
      db.deleteFence(id);
      s.fenceDraft = null;
      s.fence = "";
      closeModal();
      refresh("围栏已归档");
    });
  action["fence-members"] = () => {
    savedDraft();
    modal(
      "选择围栏适用人员",
      `<form data-form="fence-members">${membersInput(s.fenceDraft?.members || [])}<div class="form-actions"><button class="btn primary" type="submit">确认成员</button>${b("取消", "modal-close")}</div></form>`,
    );
  };
  action["fence-records"] = () => {
    const list = db.state.fenceRecords.filter((x) => x.station === s.station);
    modal(
      "围栏进出记录",
      table(
        ["时间", "围栏", "人员", "方向"],
        list.map((x) => ({
          cells: [e(x.time), e(x.fenceName), e(x.personName), tag(x.type)],
        })),
      ) +
        `<div class="detail-section"><h3>位置变化演示</h3><p class="note">仅对已启用围栏及其适用人员生成记录。</p><form data-form="simulate-location" class="form-stack">${f(
          "人员",
          sel(
            "personId",
            people().map((p) => [p.id, p.name]),
            s.person,
          ),
        )}${f(
          "目标位置",
          sel(
            "target",
            [
              ["inside", "锅炉区域内"],
              ["outside", "厂区道路外侧"],
            ],
            "outside",
          ),
        )}<button class="btn primary" type="submit">模拟位置变化</button><p class="form-error"></p></form></div>`,
      "",
      "wide",
    );
  };
  action["select-event"] = (id) => {
    s.event = id;
    render();
  };
  action["open-event"] = (id) => go("event/" + id);
  action["claim"] = (id) => {
    db.claim(id);
    refresh("事件已认领");
  };
  action["save-draft"] = (id) => {
    const form = document.querySelector('[data-form="verify"]');
    const values = formData(form);
    db.verify(id, values, false);
    s.formDrafts[id] = values;
    refresh("核验草稿已保存");
  };
  action["event-materials"] = (id) => {
    const a = db.event(id);
    s.filters.materials = { personId: a.personId, eventId: id };
    s.mediaTab = "all";
    s.media = db.state.media.find((m) => m.eventId === id)?.id || "";
    go("materials");
  };
  action["page-prev"] =
    action["page-next"] =
    action["page-current"] =
      () => toast("当前筛选共 1 页，已显示全部记录");
  action["dispatch-tab"] = (id) => {
    s.dispatchTab = id;
    render();
  };
  action["select-group"] = (id) => {
    savedDraft();
    s.group = id;
    s.selectedMembers = [...db.state.groups.find((g) => g.id === id).members];
    render();
  };
  action["new-group"] = () => createGroupForm("");
  action["edit-group"] = createGroupForm;
  action["start-call"] = (kind) => {
    const ids = s.selectedMembers.filter((id) =>
      people().some((p) => p.id === id),
    );
    db.startCall(ids, kind, s.station);
    refresh("模拟呼叫已发起");
  };
  action["connect-call"] = (id) => {
    db.updateCall(id, "connect");
    refresh("模拟通话已接通");
  };
  action["end-call"] = (id) => {
    db.updateCall(id, "end");
    refresh("通话已结束，记录已保存");
  };
  action["mute-call"] = (id) => {
    db.updateCall(id, "mute");
    render();
  };
  action["invite-member"] = (id) => {
    const c = db.state.calls.find((c) => c.id === id),
      options = people().filter((p) => !c.members.includes(p.id));
    modal(
      "邀请成员",
      options.length
        ? `<form data-form="invite" data-id="${id}" class="form-stack">${f(
            "人员",
            sel(
              "personId",
              options.map((p) => [p.id, p.name]),
            ),
          )}<button class="btn primary" type="submit">邀请加入</button><p class="form-error"></p></form>`
        : empty("当前厂站人员均已在通话中"),
    );
  };
  action["call-records"] = () =>
    modal(
      "通信记录",
      table(
        ["时间", "类型", "参与人员", "状态", "操作"],
        db.state.calls
          .filter((c) => c.station === s.station)
          .map((c) => ({
            cells: [
              e(c.time),
              e(c.kind),
              c.members.map(pn).join("、"),
              tag(c.status),
              b("详情", "call-record-detail", c.id, "small"),
            ],
          })),
      ),
      "",
      "wide",
    );
  action["call-record-detail"] = (id) => {
    const c = db.state.calls.find((c) => c.id === id);
    modal(
      "通信记录详情",
      `<dl class="info"><dt>会话编号</dt><dd>${e(c.id)}</dd><dt>参与人员</dt><dd>${c.members.map(pn).join("、")}</dd><dt>状态</dt><dd>${tag(c.status)}</dd></dl><div class="timeline">${(c.history || []).map((x) => `<div class="timeline-item"><time>${e(x.time)}</time>${e(x.text)}</div>`).join("")}</div>`,
    );
  };
  action["broadcast-records"] = () =>
    modal(
      "广播记录",
      table(
        ["时间", "分组", "内容", "接收人员", "状态"],
        db.state.broadcasts
          .filter((x) => x.station === s.station)
          .map((x) => ({
            cells: [
              e(x.time),
              e(x.groupName),
              e(x.text),
              x.members.map(pn).join("、"),
              tag(x.status, "green"),
            ],
          })),
      ),
      "",
      "wide",
    );
  action["broadcast-preview"] = () => {
    const form = document.querySelector('[data-form="broadcast"]'),
      text = form.text.value.trim();
    if (!text) throw Error("请输入广播内容");
    if (!("speechSynthesis" in window)) {
      modal(
        "广播试听",
        `<p>${e(text)}</p><p class="note">当前浏览器未提供语音合成，可预览广播文字。</p>`,
      );
      return;
    }
    speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(text);
    u.lang = "zh-CN";
    speechSynthesis.speak(u);
    toast("正在试听广播");
  };
  action["sos-join"] = () => {
    db.sos("join");
    refresh("已加入 SOS 演练协助");
  };
  action["sos-end"] = () =>
    confirm("结束前确认", "确认后结束本次演练会话，并保留协助记录。", () => {
      db.sos("end");
      closeModal();
      refresh("SOS 协助已结束，记录已保存");
    });
  action["stats-tab"] = (id) => {
    s.statsTab = id;
    render();
  };
  action["export-statistics"] = () => {
    const st = db.stats(R.statsScope());
    if (s.statsTab === "人员")
      csv(
        "人员追溯.csv",
        ["姓名", "班组", "区域", "当前作业", "装备数量"],
        st.people.map((p) => [
          p.name,
          p.team,
          p.area,
          db.currentWork(p.id)?.name || "待分配",
          db.currentDevices(p.id).length,
        ]),
      );
    else if (s.statsTab === "装备")
      csv(
        "装备追溯.csv",
        ["编号", "类型", "当前领用人", "电量", "通信状态"],
        st.devices.map((d) => [
          d.id,
          D.typeNames[d.type],
          db.owner(d.id)?.name || "未领用",
          d.battery,
          d.online ? "在线" : "连接中断",
        ]),
      );
    else if (s.statsTab === "任务")
      csv(
        "作业追溯.csv",
        ["名称", "编号", "监护人", "人数", "状态"],
        st.works.map((w) => [
          w.name,
          w.id,
          db.person(w.supervisor)?.name,
          w.members.length,
          w.status,
        ]),
      );
    else
      csv(
        "事件追溯.csv",
        [
          "人员",
          "设备",
          "关联作业",
          "事件",
          "发生时间",
          "核验状态",
          "外部系统状态",
        ],
        st.events.map((a) => [
          a.snapshot.personName,
          a.deviceId,
          a.snapshot.workName,
          a.title,
          a.date + " " + a.time,
          a.status,
          a.externalStatus,
        ]),
      );
    toast("已生成当前筛选结果，请查看导出预览");
  };
  document.addEventListener("click", async (ev) => {
    const el = ev.target.closest("[data-action]");
    const routeLink = ev.target.closest('a[href^="#/"]');
    if (routeLink && (!el || el.contains(routeLink))) {
      savedDraft();
      stopMedia();
      closeModal();
      return;
    }
    if (el) {
      if (el.disabled) return;
      ev.preventDefault();
      const name = el.dataset.action;
      if (["capture", "record", "sos-join"].includes(name)) {
        const key = name + el.dataset.id,
          previous = recentActions.get(key) || 0;
        if (Date.now() - previous < 700) return;
        recentActions.set(key, Date.now());
      }
      try {
        if (action[name]) {
          if (el.dataset.busy) return;
          el.dataset.busy = "1";
          await action[name](el.dataset.id || "", el, ev);
        }
      } catch (err) {
        toast(err.message || "操作失败", true);
      } finally {
        delete el.dataset.busy;
      }
      return;
    }
    const link = ev.target.closest('a[href^="#/"]');
    if (link) {
      savedDraft();
      stopMedia();
      closeModal();
    }
    if (ev.target.classList.contains("modal-backdrop")) action["modal-close"]();
  });
  document.addEventListener("submit", async (ev) => {
    const form = ev.target;
    if (!form.dataset.form) return;
    ev.preventDefault();
    if (form.dataset.busy) return;
    form.dataset.busy = "1";
    const values = formData(form),
      kind = form.dataset.form;
    if (kind === "broadcast") {
      const previous = recentActions.get(kind) || 0;
      if (Date.now() - previous < 1000) {
        delete form.dataset.busy;
        return;
      }
      recentActions.set(kind, Date.now());
    }
    try {
      if (kind === "login") {
        if (values.account !== "admin" || values.password !== "123456")
          throw Error("账号或密码错误。演示账号：admin / 123456");
        if (values.captcha.toUpperCase() !== s.captcha)
          throw Error("验证码错误，请重新输入");
        sessionStorage.setItem("rolling-session", "admin");
        go("overview");
      }
      if (kind === "filters") {
        s.filters[R.route] = values;
        render();
      }
      if (kind === "track-filters") {
        if (values.start >= values.end) throw Error("结束时间必须晚于开始时间");
        s.filters.tracks = values;
        s.person = values.personId;
        s.trackPlaying = false;
        s.trackIndex = 0;
        if (R.routeId) go("tracks/" + values.personId);
        else render();
      }
      if (kind === "verify") {
        db.verify(form.dataset.id, values, true);
        delete s.formDrafts[form.dataset.id];
        refresh("核验记录已提交，事件与统计已同步更新");
      }
      if (kind === "fence") {
        savedDraft();
        const d = s.fenceDraft;
        const id = db.saveFence(d.id, {
          ...d,
          name: values.name.trim(),
          department: values.department,
          owner: values.owner,
          enter: form.enter.checked,
          leave: form.leave.checked,
          enabled: form.enabled.checked,
          station: s.station,
        });
        s.fence = id;
        s.fenceDraft = null;
        s.fenceMode = "select";
        refresh("围栏已保存");
      }
      if (kind === "fence-members") {
        s.fenceDraft.members = new FormData(form).getAll("members");
        closeModal();
        render();
      }
      if (kind === "simulate-location") {
        db.movePerson(
          values.personId,
          values.target === "inside" ? [35, 45] : [8, 8],
        );
        closeModal();
        render();
        action["fence-records"]();
        toast("位置已更新，围栏进出条件已检查");
      }
      if (kind === "work") {
        db.updateWork(form.dataset.id, {
          ...values,
          members: new FormData(form).getAll("members"),
        });
        closeModal();
        refresh("作业关联已更新");
      }
      if (kind === "group") {
        s.group = db.saveGroup(
          form.dataset.id || null,
          values.name,
          new FormData(form).getAll("members"),
          s.station,
        );
        closeModal();
        refresh("协助分组已保存");
      }
      if (kind === "invite") {
        db.updateCall(form.dataset.id, "invite", values.personId);
        closeModal();
        refresh("已邀请成员加入模拟通话");
      }
      if (kind === "broadcast") {
        db.broadcast(values.groupId, values.text);
        s.broadcastDraft = "";
        refresh("广播已发送（本地模拟），回执已保存");
      }
    } catch (err) {
      formError(form, err);
    } finally {
      delete form.dataset.busy;
    }
  });
  document.addEventListener("change", async (ev) => {
    const el = ev.target;
    try {
      if (el.dataset.setting) {
        const key = el.dataset.setting;
        if (key === "station") {
          savedDraft();
          s.station = el.value;
          localStorage.setItem("rolling-station", s.station);
          s.fenceDraft = null;
          s.filters = {};
          s.selectedMembers = [];
          s.person = people()[0]?.id || "";
          closeModal();
          if (["person", "work", "single", "event", "sos"].includes(R.route))
            go("overview");
          else render();
        } else if (key === "selectAllMembers") {
          const query = (s.filters.dispatch?.q || "").trim().toLowerCase();
          const visibleIds = people()
            .filter((p) => (p.name + " " + db.currentDevices(p.id).map((d) => d.id).join(" ")).toLowerCase().includes(query))
            .map((p) => p.id);
          s.selectedMembers = el.checked
            ? [...new Set([...s.selectedMembers, ...visibleIds])]
            : s.selectedMembers.filter((id) => !visibleIds.includes(id));
          render();
        } else if (key === "trackIndex") {
          s.trackIndex = +el.value;
          s.trackPlaying = false;
          render();
        } else {
          s[key] = ["volume", "trackSpeed"].includes(key)
            ? +el.value
            : el.value;
          render();
        }
      }
      if (el.dataset.layer) {
        s.layers[el.dataset.layer] = el.checked;
        render();
      }
      if (el.dataset.member) {
        s.selectedMembers = el.checked
          ? [...new Set([...s.selectedMembers, el.dataset.member])]
          : s.selectedMembers.filter((id) => id !== el.dataset.member);
        savedDraft();
        render();
      }
      if (el.dataset.uploadEvent) {
        savedDraft();
        const file = el.files[0];
        if (!file) return;
        if (!["image/png", "image/jpeg"].includes(file.type))
          throw Error("仅支持 JPG、PNG 图片");
        if (file.size > 10 * 1024 * 1024) throw Error("图片不能超过 10MB");
        const blobId = "upload-" + crypto.randomUUID();
        await R.blobPut(blobId, file);
        db.addEventPhoto(el.dataset.uploadEvent, blobId, file.name);
        refresh("核验照片已保存");
      }
      if (el.dataset.mediaProgress) {
        const m = db.state.media.find((m) => m.id === el.dataset.mediaProgress);
        document.getElementById("media-play-time").textContent =
          durationText(el.value) + " / " + durationText(m.duration);
      }
    } catch (err) {
      toast(err.message, true);
    }
  });
  document.addEventListener("input", (ev) => {
    if (ev.target.tagName === "TEXTAREA") {
      const count = ev.target.parentElement.querySelector(".char-count");
      if (count)
        count.textContent = ev.target.value.length + "/" + ev.target.maxLength;
    }
    if (ev.target.closest('[data-form="verify"]')) savedDraft();
  });
  document.addEventListener("keydown", (ev) => {
    if (
      ev.key === "Escape" &&
      document.getElementById("modal-root").innerHTML
    ) {
      action["modal-close"]();
      return;
    }
    if (ev.key === "Tab") {
      const modal = document.querySelector(".modal");
      if (modal) {
        const els = [
            ...modal.querySelectorAll(
              'button,a,input,select,textarea,[tabindex="0"]',
            ),
          ].filter((x) => !x.disabled && x.offsetParent !== null),
          first = els[0],
          last = els.at(-1);
        if (ev.shiftKey && document.activeElement === first) {
          last?.focus();
          ev.preventDefault();
        } else if (!ev.shiftKey && document.activeElement === last) {
          first?.focus();
          ev.preventDefault();
        }
      }
    }
    if (
      (ev.key === "Enter" || ev.key === " ") &&
      ev.target.matches("article[data-action]")
    ) {
      ev.preventDefault();
      ev.target.click();
    }
  });
  window.addEventListener("hashchange", () => {
    stopMedia();
    closeModal();
    render();
  });
  window.addEventListener("storage", (ev) => {
    if (ev.key === D.KEY) location.reload();
  });
  if (!location.hash)
    go(sessionStorage.getItem("rolling-session") ? "overview" : "login");
  else render();
  if (db.loadError) toast(db.loadError, true);
})();
