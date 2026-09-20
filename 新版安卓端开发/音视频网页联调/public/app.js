// ROLLING 智能穿戴现场联调平台核心交互逻辑

const state = {
  siteId: '1',
  roster: { people: [], devices: [], tasks: [] },
  labState: { devices: [], people: [], calls: [], messages: [], dispatchers: [], dutyStaff: null },
  activeCall: null,
  selectedScenario: null,
  selectedEvent: null,
  lastEvent: null,
  videoAnimTimer: null,
  pollTimer: null,
  callTimer: null,
  callDurationSeconds: 0,
  expandedPersonIds: new Set(),
};

// 预定义设备自定义告警场景选项
const CUSTOM_STATUSES = {
  helmet: [
    { code: 'normal', label: '🟢 正常佩戴' },
    { code: 'helmet.removal', label: '🔴 员工脱帽 (60s未戴)' },
    { code: 'helmet.fall', label: '🔴 跌落告警' },
    { code: 'helmet.impact', label: '🔴 撞击告警' },
    { code: 'helmet.silent', label: '🟡 静默倒地 (长时间静止)' },
    { code: 'helmet.climb', label: '🔵 登高作业 (5米)' },
    { code: 'helmet.proximity', label: '⚡ 近电预警' },
    { code: 'helmet.battery', label: '🪫 低电量 (<5%)' },
    { code: 'helmet.fence_enter', label: '🚧 进入禁区' },
    { code: 'helmet.fence_exit', label: '🏃 离开指定区域' },
    { code: 'helmet.sos', label: '🚨 SOS 紧急求救' },
    { code: 'offline', label: '⚪ 设备离线 (未在岗)' },
  ],
  belt: [
    { code: 'normal', label: '🟢 正常挂接扣紧' },
    { code: 'belt.unhooked', label: '🔴 安全带摘下 (未挂钩)' },
    { code: 'belt.unfastened', label: '🔴 腰带未扣紧' },
    { code: 'belt.low_anchor', label: '🟡 低挂高用违章' },
    { code: 'belt.fall', label: '🔴 高空坠落' },
    { code: 'belt.battery', label: '🪫 低电量 (<5%)' },
    { code: 'belt.sos', label: '🚨 安全带 SOS 求救' },
    { code: 'offline', label: '⚪ 设备离线 (未在岗)' },
  ],
  watch: [
    { code: 'normal', label: '🟢 正常佩戴' },
    { code: 'watch.off_wrist', label: '🔴 员工离腕 (60s)' },
    { code: 'watch.heart_high', label: '💓 心率偏高 (130次/分)' },
    { code: 'watch.heart_low', label: '💙 心率偏低 (45次/分)' },
    { code: 'watch.oxygen', label: '🩸 血氧偏低 (88%)' },
    { code: 'watch.temperature', label: '🌡️ 体温偏高 (39℃)' },
    { code: 'watch.fall', label: '🔴 人员跌倒' },
    { code: 'watch.fence_exit', label: '🏃 越界离开' },
    { code: 'watch.battery', label: '🪫 低电量 (<5%)' },
    { code: 'watch.sos', label: '🚨 手表 SOS 求救' },
    { code: 'offline', label: '⚪ 设备离线 (未在岗)' },
  ]
};

// 作业任务状态映射 (与管理端及数据库字典一致: draft 草稿, ready 就绪, in_progress 进行中, paused 已暂停, ended 已结束)
const TASK_STATUS_MAP = {
  draft: '草稿',
  ready: '就绪',
  in_progress: '进行中',
  paused: '已暂停',
  ended: '已结束',
  completed: '已完成',
  cancelled: '已取消',
  '草稿': '草稿',
  '就绪': '就绪',
  '进行中': '进行中',
  '已暂停': '已暂停',
  '已结束': '已结束',
  '已完成': '已完成',
  '已取消': '已取消'
};

function getTaskStatusLabel(status) {
  if (!status) return '就绪';
  return TASK_STATUS_MAP[status] || status;
}

// 工具函数
const $ = sel => document.querySelector(sel);
const $$ = sel => document.querySelectorAll(sel);

function showNotice(msg, type = 'info') {
  const el = $('#noticeBanner');
  if (!el) return;
  el.className = `notice-banner ${type}`;
  el.textContent = msg;
  el.hidden = false;
  setTimeout(() => { if (el.textContent === msg) el.hidden = true; }, 5000);
}

// API 请求封装 - 无需前端登录，后端自动使用系统级 JWT 保持联调
async function labApi(path, method = 'GET', body = null) {
  const headers = {
    'Content-Type': 'application/json',
    'X-Site-Id': state.siteId,
  };

  const res = await fetch(`/api/v1/lab${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json();
  if (!res.ok || (data.code && data.code !== 200)) {
    throw new Error(data.msg || '联调接口响应异常');
  }
  return data.data;
}

// 初始化与导航切换
function initNavigation() {
  $$('.nav-tab').forEach(tab => {
    tab.addEventListener('click', () => {
      $$('.nav-tab').forEach(t => t.classList.remove('active'));
      $$('.tab-content').forEach(c => c.classList.remove('active'));
      tab.classList.add('active');
      const targetId = tab.dataset.target;
      if ($('#' + targetId)) $('#' + targetId).classList.add('active');
    });
  });

  // 厂站切换
  $('#siteSelect').addEventListener('change', async e => {
    state.siteId = e.target.value;
    showNotice(`已切换到${e.target.options[e.target.selectedIndex].text}，正在刷新数据...`, 'info');
    await loadRoster();
    await pollState();
    await loadEvents();
  });

}

// -------------------------------------------------------------
// 功能模块一：现场人员与装备展示、在岗在线切换、自定义状态
// -------------------------------------------------------------

async function loadRoster() {
  try {
    const data = await labApi('/roster');
    state.roster = data || { people: [], devices: [], tasks: [] };
    renderPeopleToolbar();
    renderPeopleGrid();
  } catch (err) {
    showNotice('加载台账名单失败: ' + err.message, 'danger');
  }
}

function renderPeopleToolbar() {
  const { people, devices, tasks } = state.roster;
  
  // 统计指标计算
  const totalPeople = people.length;
  const onlinePeople = people.filter(p => p.online && (p.assignedDevices || []).some(d => d.typeCode === 'helmet')).length;
  const offlinePeople = totalPeople - onlinePeople;
  const helmets = devices.filter(d => d.typeCode === 'helmet').length;
  const belts = devices.filter(d => d.typeCode === 'belt').length;
  const watches = devices.filter(d => d.typeCode === 'watch').length;
  const abnormalCount = devices.filter(d => d.lab?.abnormal || d.lab?.customStatus).length;

  $('#statTotalPeople').textContent = totalPeople;
  $('#statOnlinePeople').textContent = onlinePeople;
  $('#statOfflinePeople').textContent = offlinePeople;
  $('#statHelmets').textContent = helmets;
  $('#statBelts').textContent = belts;
  $('#statWatches').textContent = watches;
  $('#statAbnormalCount').textContent = abnormalCount;

  // 1. 填充作业任务下拉筛选 (显示状态与任务名称)
  const taskSelect = $('#taskFilter');
  if (taskSelect) {
    const curTaskVal = taskSelect.value;
    const taskMap = new Map();

    const addTask = (t) => {
      if (!t) return;
      const id = String(t.id || t.taskName || t.title || '');
      const name = t.taskName || t.title;
      if (!id || !name) return;
      if (!taskMap.has(id)) {
        taskMap.set(id, {
          id,
          name,
          status: t.status,
          statusLabel: getTaskStatusLabel(t.status)
        });
      } else if (!taskMap.get(id).status && t.status) {
        taskMap.get(id).status = t.status;
        taskMap.get(id).statusLabel = getTaskStatusLabel(t.status);
      }
    };

    tasks.forEach(addTask);
    people.forEach(p => {
      (p.tasks || []).forEach(addTask);
    });

    taskSelect.innerHTML = '<option value="">全部作业任务</option>';
    taskMap.forEach(t => {
      const opt = document.createElement('option');
      opt.value = t.id;
      opt.textContent = `📋 [${t.statusLabel}] ${t.name}`;
      taskSelect.appendChild(opt);
    });

    if (curTaskVal) {
      const matched = [...taskMap.values()].find(t => t.id === curTaskVal || t.name === curTaskVal);
      if (matched) {
        taskSelect.value = matched.id;
      } else {
        taskSelect.value = curTaskVal;
      }
    }
  }

  // 2. 填充人员班组下拉筛选
  const teamSelect = $('#teamFilter');
  if (teamSelect) {
    const curTeamVal = teamSelect.value;
    const teamNames = new Set();
    people.forEach(p => {
      if (p.teamName) teamNames.add(p.teamName);
    });

    teamSelect.innerHTML = '<option value="">全部人员班组</option>';
    teamNames.forEach(t => {
      const opt = document.createElement('option');
      opt.value = t;
      opt.textContent = `🏛️ ${t}`;
      teamSelect.appendChild(opt);
    });
    teamSelect.value = curTeamVal;
  }
}

function renderPeopleGrid() {
  const container = $('#peopleGrid');
  const { people } = state.roster;
  const query = ($('#peopleSearch')?.value || '').trim().toLowerCase();
  const taskQuery = $('#taskFilter')?.value || '';
  const teamQuery = $('#teamFilter')?.value || '';
  const statusQuery = $('#statusFilter')?.value || '';

  if (!people || people.length === 0) {
    container.innerHTML = `<div class="card" style="grid-column: 1 / -1; text-align: center; padding: 3rem; color: var(--ink-muted);">当前厂站暂无现场人员数据</div>`;
    return;
  }

  // 过滤
  const filtered = people.filter(p => {
    if (query) {
      const matchName = (p.name || '').toLowerCase().includes(query);
      const matchCode = (p.personCode || '').toLowerCase().includes(query);
      const matchDevice = (p.assignedDevices || []).some(d => (d.sn || '').toLowerCase().includes(query));
      if (!matchName && !matchCode && !matchDevice) return false;
    }
    if (taskQuery) {
      const matchTask = (p.tasks || []).some(t => String(t.id) === taskQuery || (t.taskName || t.title || '') === taskQuery);
      if (!matchTask) return false;
    }
    if (teamQuery) {
      const matchTeam = (p.teamName || '') === teamQuery;
      if (!matchTeam) return false;
    }
    if (statusQuery === 'online' && !p.online) return false;
    if (statusQuery === 'offline' && p.online) return false;
    if (statusQuery === 'abnormal') {
      const hasAbnormal = (p.assignedDevices || []).some(d => d.lab?.abnormal || d.lab?.customStatus);
      if (!hasAbnormal) return false;
    }
    return true;
  });

  if (filtered.length === 0) {
    container.innerHTML = `<div class="card" style="grid-column: 1 / -1; text-align: center; padding: 3rem; color: var(--ink-muted);">无匹配的人员记录</div>`;
    return;
  }

  container.innerHTML = filtered.map(p => renderPersonCardHtml(p)).join('');

  // 绑定人员卡片事件
  attachPersonCardEvents(container);
}

function renderPersonCardHtml(p) {
  const boundDevices = p.assignedDevices || [];
  const helmet = boundDevices.find(d => d.typeCode === 'helmet');
  const hasHelmet = Boolean(helmet);
  const isOnline = hasHelmet && p.online === true;
  const hasAbnormal = boundDevices.some(d => d.lab?.abnormal || d.lab?.customStatus);
  const isExpanded = state.expandedPersonIds.has(String(p.id));

  // 检查是否有针对此安全帽的来电
  let incomingCall = null;
  let activeCall = null;
  if (helmet) {
    incomingCall = state.labState.calls.find(c =>
      ['ringing', 'connected'].includes(c.state) &&
      c.participants?.some(part => part.deviceId === String(helmet.id) && part.state === 'ringing' && (part.direction || c.direction) === 'outgoing')
    );
    activeCall = state.labState.calls.find(c =>
      !['ended', 'rejected', 'timed_out'].includes(c.state) &&
      c.participants?.some(part => part.deviceId === String(helmet.id))
    );
  }

  // 检查最新 TTS 消息
  let latestTts = null;
  if (helmet) {
    latestTts = state.labState.messages?.find(m =>
      m.receipts?.some(r => r.deviceId === String(helmet.id))
    );
  }

  // 作业任务优化排版：单行仅展示主要任务与计数，完整任务在抽屉中展开展示
  const allTasks = p.tasks || [];
  const primaryTaskObj = allTasks[0];
  const primaryTask = primaryTaskObj ? (primaryTaskObj.taskName || primaryTaskObj.title || '作业任务') : null;
  const primaryStatusLabel = primaryTaskObj ? getTaskStatusLabel(primaryTaskObj.status) : '';
  const moreTasksCount = allTasks.length > 1 ? allTasks.length - 1 : 0;
  const allTaskTitles = allTasks.map(t => `[${getTaskStatusLabel(t.status)}] ${t.taskName || t.title}`).filter(Boolean).join('、');

  // 装备概览标签 (单行展示，结构清晰且绝对不竖排换行)
  const deviceBadgesHtml = boundDevices.length === 0
    ? '<span class="summary-badge empty">⚪ 未领用装备</span>'
    : boundDevices.map(d => {
        const typeCode = d.typeCode || 'helmet';
        const icon = typeCode === 'helmet' ? '🪖' : (typeCode === 'belt' ? '🪢' : '⌚');
        const typeName = typeCode === 'helmet' ? '安全帽' : (typeCode === 'belt' ? '安全带' : '手表');
        const isDevAbnormal = d.lab?.abnormal || (d.lab?.customStatus && d.lab.customStatus.code !== 'normal' && d.lab.customStatus.code !== 'offline');
        const isDevOnline = d.lab?.online === true;
        const cls = isDevAbnormal ? 'abnormal' : (isDevOnline ? 'online' : 'offline');
        let statusLabel = '离线';
        if (isDevAbnormal) {
          statusLabel = (d.lab.customStatus.label || '异常').replace(/^[🟢🔴🟡🔵⚡🪫🚧🏃🚨💓💙🩸🌡️⚪]\s*/, '');
        } else if (isDevOnline) {
          statusLabel = (typeCode === 'helmet' || typeCode === 'watch') ? '正常佩戴' : '正常挂接';
        }
        return `
          <span class="summary-badge ${cls}" title="${typeName} SN: ${d.sn || d.externalCode || d.id}">
            <span class="badge-icon">${icon}</span>
            <span class="badge-name">${typeName}</span>
            <span class="badge-sn">${d.sn || d.externalCode || d.id}</span>
            <span class="badge-status">${statusLabel}</span>
          </span>
        `;
      }).join('');

  return `
    <div class="person-row ${isOnline ? 'online' : ''} ${hasAbnormal ? 'abnormal' : ''} ${isExpanded ? 'expanded' : ''}" data-person-id="${p.id}">
      <!-- 单行主体：左中右清晰三分区 -->
      <div class="person-row-main" data-person-id="${p.id}">
        <!-- 左侧：头像、姓名、编号、班组与主任务 -->
        <div class="person-main-left">
          <div class="person-avatar">${(p.name || '工').slice(-1)}</div>
          <div class="person-meta">
            <div class="person-name-line">
              <span class="person-name">${p.name || '现场人员'}</span>
              <span class="person-code">(${p.personCode || p.id})</span>
            </div>
            <div class="person-tags">
              <span class="tag tag-team">🏛️ ${p.teamName || '现场作业班组'}</span>
              ${primaryTask ? `<span class="tag tag-task" title="${allTaskTitles}">📋 [${primaryStatusLabel}] ${primaryTask}</span>` : ''}
              ${moreTasksCount > 0 ? `<span class="tag tag-task-more" title="全部关联任务 (${allTasks.length}):\n${allTaskTitles}">+${moreTasksCount}项</span>` : ''}
            </div>
          </div>
        </div>

        <!-- 中间：装备概览徽标 (平铺展开，不再挤压成竖列) -->
        <div class="person-main-mid">
          <div class="device-summary-badges">
            ${deviceBadgesHtml}
          </div>
        </div>

        <!-- 右侧：在岗开关与向下展开箭头 -->
        <div class="person-main-right">
          <!-- 在岗开关 (未领用安全帽时不可激活) -->
          <div class="presence-toggle ${!hasHelmet ? 'disabled' : ''}" data-person-id="${p.id}" data-has-helmet="${hasHelmet ? '1' : '0'}" title="${hasHelmet ? (isOnline ? '在岗在线（点击切换为离线）' : '离线（点击切换为在岗）') : '未领用安全帽，在线状态不可激活！请先领用安全帽'}">
            <label class="switch ${!hasHelmet ? 'disabled' : ''}">
              <input type="checkbox" class="person-presence-switch" data-person-id="${p.id}" ${isOnline ? 'checked' : ''} ${!hasHelmet ? 'disabled' : ''}>
              <span class="slider ${!hasHelmet ? 'disabled' : ''}"></span>
            </label>
            <span class="switch-label ${!hasHelmet ? 'disabled' : ''}">${isOnline ? '在岗' : (hasHelmet ? '离线' : '离线 (无安全帽)')}</span>
          </div>

          <!-- 展开/收起箭头按钮 -->
          <button type="button" class="btn-expand-arrow" data-person-id="${p.id}" title="${isExpanded ? '收起详情' : '展开查看设备与联调详情'}">
            <span class="arrow-icon">▼</span>
          </button>
        </div>
      </div>

      <!-- 展开详情抽屉 (包含所有关联任务、领用装备详细卡片、通话与对讲) -->
      <div class="person-row-detail" style="display: ${isExpanded ? 'block' : 'none'};">
        <div class="detail-grid">
          <!-- 关联作业任务列表 (当任务较多时在此完整展现) -->
          ${allTasks.length > 0 ? `
            <div class="drawer-tasks-section">
              <div class="section-subtitle">📋 关联作业任务 (${allTasks.length} 项)</div>
              <div class="drawer-tasks-list">
                ${allTasks.map(t => `<span class="tag tag-task" title="${t.taskName || t.title}">📋 [${getTaskStatusLabel(t.status)}] ${t.taskName || t.title || '作业任务'}</span>`).join('')}
              </div>
            </div>
          ` : ''}

          <!-- 领用设备列表 -->
          <div class="equipments-section">
            <div class="equipments-title">已领用装备与模拟控制 (${boundDevices.length} 件)</div>
            ${boundDevices.length === 0 ? '<div style="font-size:0.75rem;color:var(--ink-muted);margin-top:0.25rem;">暂未领用任何智能装备</div>' : ''}
            <div class="equipments-grid">
              ${boundDevices.map(d => renderDeviceItemHtml(d)).join('')}
            </div>
          </div>

          <!-- 安全帽通话与对讲操作栏 (仅当领用了安全帽时显示) -->
          ${helmet ? `
            <div class="person-call-bar">
              <div class="call-actions-row">
                <button class="btn btn-secondary btn-sm btn-helmet-call" data-device-id="${helmet.id}" data-person-id="${p.id}" ${!isOnline ? 'disabled title="人员需在岗才能呼叫"' : ''}>
                  📞 呼叫值班员
                </button>
                <span class="call-badge ${activeCall ? activeCall.state : 'idle'}">
                  ${activeCall ? (activeCall.state === 'connected' ? '🟢 通话中' : '🟡 振铃中') : '⚪ 待机'}
                </span>
              </div>

              <!-- 来电接听横幅 -->
              ${incomingCall ? `
                <div class="incoming-call-box">
                  <div class="incoming-call-info">
                    <span>🔔 值班员来电...</span>
                  </div>
                  <div class="incoming-call-buttons">
                    <button class="btn btn-success btn-sm btn-accept-call" data-call-id="${incomingCall.id}" data-device-id="${helmet.id}">接听</button>
                    <button class="btn btn-danger btn-sm btn-reject-call" data-call-id="${incomingCall.id}" data-device-id="${helmet.id}">拒接</button>
                  </div>
                </div>
              ` : ''}

              <!-- 被动视频监控提示 -->
              ${activeCall && activeCall.videoEnabled ? `
                <div class="video-alert-box">
                  <span>📷 管理员已开启头盔摄像头视频监控 (画面传输中)</span>
                </div>
              ` : ''}

              <!-- TTS 语音播报卡片 -->
              ${latestTts ? `
                <div class="tts-box">
                  <div class="tts-header">
                    <span>📢 收到安全播报</span>
                    <span style="font-size:0.65rem;color:var(--ink-muted)">${new Date(latestTts.createdAt).toLocaleTimeString()}</span>
                  </div>
                  <div>"${latestTts.text}"</div>
                </div>
              ` : ''}
            </div>
          ` : ''}
        </div>
      </div>
    </div>
  `;
}

function renderDeviceItemHtml(d) {
  const typeCode = d.typeCode || 'helmet';
  const icon = typeCode === 'helmet' ? '🪖' : (typeCode === 'belt' ? '🪢' : '⌚');
  const typeName = typeCode === 'helmet' ? '安全帽' : (typeCode === 'belt' ? '安全带' : '手表');
  const options = CUSTOM_STATUSES[typeCode] || [];
  const isDevOnline = d.lab?.online === true;
  const customStatus = d.lab?.customStatus;
  
  let curCode = 'normal';
  if (!isDevOnline) {
    curCode = 'offline';
  } else if (customStatus && customStatus.code) {
    curCode = customStatus.code;
  } else {
    curCode = 'normal';
  }

  let pillCls = 'offline';
  let pillLabel = '离线';
  if (customStatus && curCode !== 'normal' && curCode !== 'offline') {
    pillCls = 'abnormal';
    pillLabel = customStatus.label;
  } else if (isDevOnline) {
    pillCls = 'online';
    pillLabel = typeCode === 'belt' ? '🟢 正常挂接扣紧' : '🟢 正常佩戴';
  } else {
    pillCls = 'offline';
    pillLabel = '⚪ 离线';
  }

  return `
    <div class="equipment-item" data-device-id="${d.id}">
      <div class="equipment-top">
        <div class="equipment-meta">
          <span class="equipment-icon">${icon}</span>
          <span>${typeName}</span>
          <span class="equipment-sn">${d.sn || d.externalCode || d.id}</span>
        </div>
        <span class="status-pill ${pillCls}">
          <i></i> ${pillLabel}
        </span>
      </div>

      <!-- 自定义状态切换器 -->
      <div class="status-select-wrap">
        <span style="font-size:0.75rem;color:var(--ink-secondary);font-weight:600;white-space:nowrap;">模拟状态:</span>
        <select class="status-select device-status-select ${curCode !== 'normal' && curCode !== 'offline' ? 'active-alarm' : ''}" data-device-id="${d.id}" data-type="${typeCode}">
          ${options.map(opt => `<option value="${opt.code}" ${opt.code === curCode ? 'selected' : ''}>${opt.label}</option>`).join('')}
        </select>
      </div>
    </div>
  `;
}

function attachPersonCardEvents(container) {
  // 点击单行主体或向下箭头，展开/收起详情
  container.querySelectorAll('.person-row-main').forEach(mainRow => {
    mainRow.addEventListener('click', e => {
      // 排除复选框、滑动开关及标签点击，避免与在岗状态切换冲突
      if (e.target.closest('.switch') || e.target.closest('.person-presence-switch') || e.target.closest('.presence-toggle')) {
        return;
      }
      const personId = String(mainRow.dataset.personId);
      const row = mainRow.closest('.person-row');
      const detail = row?.querySelector('.person-row-detail');
      if (!row || !detail) return;

      if (state.expandedPersonIds.has(personId)) {
        state.expandedPersonIds.delete(personId);
        row.classList.remove('expanded');
        detail.style.display = 'none';
        const btnArrow = row.querySelector('.btn-expand-arrow');
        if (btnArrow) btnArrow.title = '展开查看设备与联调详情';
      } else {
        state.expandedPersonIds.add(personId);
        row.classList.add('expanded');
        detail.style.display = 'block';
        const btnArrow = row.querySelector('.btn-expand-arrow');
        if (btnArrow) btnArrow.title = '收起详情';
      }
    });
  });

  // 点击被禁用的在岗开关时，给出明确提示
  container.querySelectorAll('.presence-toggle.disabled').forEach(wrap => {
    wrap.addEventListener('click', e => {
      e.stopPropagation();
      e.preventDefault();
      showNotice('该人员未领用安全帽，在线状态不可激活！请先领用安全帽。', 'warning');
    });
  });

  // 在岗/离线开关
  container.querySelectorAll('.person-presence-switch').forEach(sw => {
    sw.addEventListener('change', async e => {
      if (sw.disabled) {
        e.preventDefault();
        return;
      }
      const personId = e.target.dataset.personId;
      const online = e.target.checked;
      try {
        await labApi('/presence', 'POST', { personId, online });
        showNotice(`已将人员设为: ${online ? '在岗工作 (在线)' : '离线'}`, 'success');
        await loadRoster();
        await pollState();
      } catch (err) {
        showNotice('操作失败: ' + err.message, 'danger');
        e.target.checked = !online;
      }
    });
  });

  // 设备自定义状态选择器
  container.querySelectorAll('.device-status-select').forEach(sel => {
    sel.addEventListener('change', async e => {
      const deviceId = e.target.dataset.deviceId;
      const type = e.target.dataset.type;
      const code = e.target.value;
      const opt = (CUSTOM_STATUSES[type] || []).find(o => o.code === code);
      const label = opt ? opt.label.replace(/^[🟢🔴🟡🔵⚡🪫🚧🏃🚨💓💙🩸🌡️⚪]\s*/, '') : code;
      const isOffline = code === 'offline';
      const isAbnormal = code !== 'normal' && code !== 'offline';

      try {
        const res = await labApi('/presence', 'POST', {
          deviceId,
          customStatus: { code, label },
          online: !isOffline
        });
        const eventId = res?.customStatus?.eventId;
        if (isAbnormal && eventId) {
          showNotice(`⚠️ 已记录并发送告警事件 #${eventId} (${label})，已同步至设备告警中心！`, 'warning');
        } else {
          showNotice(`设备状态已设为: ${label}，已同步至数据库与主系统`, 'success');
        }
        await loadRoster();
        await pollState();
        await loadEvents();
      } catch (err) {
        showNotice('设置状态失败: ' + err.message, 'danger');
        await loadRoster();
      }
    });
  });

  // 安全帽呼叫值班员
  container.querySelectorAll('.btn-helmet-call').forEach(btn => {
    btn.addEventListener('click', async e => {
      const deviceId = e.target.dataset.deviceId;
      try {
        btn.disabled = true;
        btn.textContent = '呼叫中...';
        await labApi('/calls', 'POST', {
          deviceIds: [deviceId],
          direction: 'incoming'
        });
        showNotice('已向值班员发起呼叫，等待接听...', 'info');
        await pollState();
      } catch (err) {
        showNotice('呼叫失败: ' + err.message, 'danger');
      } finally {
        btn.disabled = false;
        btn.textContent = '📞 呼叫值班员';
      }
    });
  });

  // 接听来电
  container.querySelectorAll('.btn-accept-call').forEach(btn => {
    btn.addEventListener('click', async e => {
      const callId = e.target.dataset.callId;
      const deviceId = e.target.dataset.deviceId;
      try {
        await labApi(`/calls/${callId}/accept`, 'POST', { deviceId });
        showNotice('已接听来电，通话建立', 'success');
        await pollState();
      } catch (err) {
        showNotice('接听失败: ' + err.message, 'danger');
      }
    });
  });

  // 拒接来电
  container.querySelectorAll('.btn-reject-call').forEach(btn => {
    btn.addEventListener('click', async e => {
      const callId = e.target.dataset.callId;
      const deviceId = e.target.dataset.deviceId;
      try {
        await labApi(`/calls/${callId}/reject`, 'POST', { deviceId });
        showNotice('已拒绝来电', 'info');
        await pollState();
      } catch (err) {
        showNotice('操作失败: ' + err.message, 'danger');
      }
    });
  });
}

// 批量上线/离线
function initBatchButtons() {
  $('#btnAllOnline').addEventListener('click', async () => {
    const people = state.roster.people || [];
    if (!people.length) return;
    const eligible = people.filter(p => (p.assignedDevices || []).some(d => d.typeCode === 'helmet'));
    const unequipped = people.length - eligible.length;
    if (eligible.length === 0) {
      showNotice('当前没有领用安全帽的人员，无法激活在岗！', 'warning');
      return;
    }
    try {
      await labApi('/presence', 'POST', {
        batch: eligible.map(p => ({ personId: p.id, online: true }))
      });
      if (unequipped > 0) {
        showNotice(`已将 ${eligible.length} 位领用安全帽的人员设为【在岗工作】（${unequipped} 位未领用安全帽的人员保持离线）`, 'success');
      } else {
        showNotice('已将全部人员一键设为【在岗工作】！', 'success');
      }
      await loadRoster();
      await pollState();
    } catch (err) {
      showNotice('批量上线失败: ' + err.message, 'danger');
    }
  });

  $('#btnAllOffline').addEventListener('click', async () => {
    const people = state.roster.people || [];
    if (!people.length) return;
    try {
      await labApi('/presence', 'POST', {
        batch: people.map(p => ({ personId: p.id, online: false }))
      });
      showNotice('已将全部人员一键设为【离线】！', 'info');
      await loadRoster();
      await pollState();
    } catch (err) {
      showNotice('批量离线失败: ' + err.message, 'danger');
    }
  });

  $('#btnRefreshRoster').addEventListener('click', async () => {
    await loadRoster();
    showNotice('台账与人员名单已刷新', 'info');
  });

  $('#peopleSearch').addEventListener('input', renderPeopleGrid);
  $('#taskFilter')?.addEventListener('change', renderPeopleGrid);
  $('#teamFilter').addEventListener('change', renderPeopleGrid);
  $('#statusFilter').addEventListener('change', renderPeopleGrid);
}

// -------------------------------------------------------------
// 功能模块二：音视频对讲、群呼、视频监控提示与语音播报
// -------------------------------------------------------------

function initCommsModule() {
  // 一键全员接听群聊
  $('#btnAcceptAllCalls').addEventListener('click', async () => {
    const active = state.labState.calls.find(c => ['ringing','connected'].includes(c.state) && c.participants?.some(p => p.state === 'ringing'));
    if (!active) return;
    try {
      await labApi(`/calls/${active.id}/accept`, 'POST', { all: true });
      showNotice('已一键接听所有响铃设备！', 'success');
      await pollState();
    } catch (err) {
      showNotice('接听失败: ' + err.message, 'danger');
    }
  });

  // 全员挂断
  $('#btnEndAllCalls').addEventListener('click', async () => {
    const active = state.labState.calls.find(c => ['ringing', 'connected'].includes(c.state));
    if (!active) return;
    try {
      await labApi(`/calls/${active.id}/end`, 'POST', { all: true });
      showNotice('通话已全部挂断', 'info');
      await pollState();
    } catch (err) {
      showNotice('挂断失败: ' + err.message, 'danger');
    }
  });

  // 发起呼叫 (安全帽端发起)
  $('#btnStartHelmetCall').addEventListener('click', async () => {
    const helmetId = $('#callSourceHelmet').value;
    if (!helmetId) return showNotice('请选择发起呼叫的安全帽', 'warning');
    try {
      await labApi('/calls', 'POST', {
        deviceIds: [helmetId],
        direction: 'incoming'
      });
      showNotice('呼叫已发起，正向主项目值班员呼入，等待安卓端接听...', 'success');
      await pollState();
    } catch (err) {
      showNotice('发起呼叫失败: ' + err.message, 'danger');
    }
  });

  // 发起 SOS 紧急呼叫
  $('#btnStartHelmetSosCall').addEventListener('click', async () => {
    const helmetId = $('#callSourceHelmet').value;
    if (!helmetId) return showNotice('请选择发起 SOS 的安全帽', 'warning');
    try {
      await labApi('/calls', 'POST', {
        deviceIds: [helmetId],
        direction: 'incoming',
        sos: true
      });
      showNotice('🚨 SOS 紧急呼叫已发起，已向主系统生成紧急事件！', 'danger');
      await pollState();
    } catch (err) {
      showNotice('SOS 发起失败: ' + err.message, 'danger');
    }
  });

  // 视频流预览控制
  let isManualVideoStream = false;
  const btnToggleStream = $('#btnToggleVideoStream');
  if (btnToggleStream) {
    btnToggleStream.addEventListener('click', () => {
      isManualVideoStream = !isManualVideoStream;
      applyVideoStreamState();
    });
  }

  initVideoHudTimer();
}

function applyVideoStreamState() {
  const { calls } = state.labState;
  const activeCalls = calls.filter(c => ['ringing', 'connected'].includes(c.state));
  const videoCall = activeCalls.find(c => c.videoEnabled);
  const shouldStream = isManualVideoStream || !!videoCall;

  const videoEl = $('#videoPov');
  const placeholderEl = $('#videoPlaceholder');
  const cameraPill = $('#cameraPill');
  const videoStatusText = $('#videoStatusText');
  const hudHelmetSn = $('#hudHelmetSn');
  const btnToggleStream = $('#btnToggleVideoStream');

  if (shouldStream) {
    if (videoEl && !videoEl.src.includes('/api/v1/lab/video/stream')) {
      videoEl.src = '/api/v1/lab/video/stream?t=' + Date.now();
      videoEl.style.display = 'block';
      if (placeholderEl) placeholderEl.style.display = 'none';
      videoEl.play().catch(() => {});
    }
    if (cameraPill) {
      cameraPill.className = 'status-pill online';
      cameraPill.innerHTML = '<i></i> 监控推流中';
    }
    if (videoStatusText) {
      videoStatusText.textContent = videoCall
        ? '值班人员已请求开启安全帽画面，正在单向推流中'
        : '手动预览监控推流中 (单向模拟)';
    }
    if (hudHelmetSn) {
      hudHelmetSn.textContent = videoCall ? `HELMET: ${videoCall.participants?.[0]?.sn || 'ACTIVE'}` : 'HELMET: LIVE_POV';
    }
    if (btnToggleStream) btnToggleStream.textContent = '⏹️ 停止画面推流';
  } else {
    if (videoEl && videoEl.src) {
      videoEl.pause();
      videoEl.removeAttribute('src');
      videoEl.load();
      videoEl.style.display = 'none';
      if (placeholderEl) placeholderEl.style.display = 'flex';
    }
    if (cameraPill) {
      cameraPill.className = 'status-pill offline';
      cameraPill.innerHTML = '<i></i> 待机';
    }
    if (videoStatusText) {
      videoStatusText.textContent = '当前未处于视频推送状态';
    }
    if (hudHelmetSn) {
      hudHelmetSn.textContent = 'HELMET: STANDBY';
    }
    if (btnToggleStream) btnToggleStream.textContent = '🎥 模拟开启画面推流';
  }
}

function updateCommsView() {
  const { calls, dispatchers } = state.labState;
  const { devices } = state.roster;
  const onlineHelmets = devices.filter(d => d.typeCode === 'helmet' && d.lab?.online);

  // 更新呼叫源安全帽下拉列表
  const helmetSelect = $('#callSourceHelmet');
  if (helmetSelect) {
    const curHelmet = helmetSelect.value;
    helmetSelect.innerHTML = onlineHelmets.length ? '' : '<option value="">暂无在线安全帽</option>';
    onlineHelmets.forEach(h => {
      const opt = document.createElement('option');
      opt.value = h.id;
      opt.textContent = `${h.sn || h.id} (${h.currentAssignment?.personName || '未绑定人'})`;
      helmetSelect.appendChild(opt);
    });
    if (curHelmet && onlineHelmets.some(h => String(h.id) === curHelmet)) helmetSelect.value = curHelmet;
  }

  // 渲染安全帽文字播报接收箱 (被动接收)
  renderHelmetTtsInbox();

  // 活跃通话渲染
  const activeCalls = calls.filter(c => ['ringing', 'connected'].includes(c.state));
  const activeCallsContainer = $('#activeCallsList');
  if ($('#btnAcceptAllCalls')) $('#btnAcceptAllCalls').disabled = !activeCalls.some(c => c.participants?.some(p => p.state === 'ringing'));
  if ($('#btnEndAllCalls')) $('#btnEndAllCalls').disabled = activeCalls.length === 0;

  if (activeCallsContainer) {
    if (activeCalls.length === 0) {
      activeCallsContainer.innerHTML = `<div style="color: var(--ink-muted); font-size: 0.875rem; text-align: center; padding: 1.5rem 0;">暂无进行中的通话</div>`;
    } else {
      activeCallsContainer.innerHTML = activeCalls.map(c => `
        <div style="background: var(--surface-subtle); border: 1px solid var(--line); border-radius: var(--radius-sm); padding: 0.75rem;">
          <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.5rem;">
            <div>
              <strong>${c.direction === 'incoming' ? '🪖 安全帽呼出' : '📱 值班端呼入'}</strong>
              <span class="tag ${c.video ? 'tag-task' : 'tag-team'}">${c.video ? '视频通话' : '语音通话'}</span>
              ${c.sos ? '<span class="tag" style="background:#fee2e2;color:#b91c1c;">🚨 SOS</span>' : ''}
              ${c.videoEnabled ? '<span class="tag" style="background:#dcfce7;color:#15803d;">📷 画面传输中</span>' : ''}
            </div>
            <span class="call-badge ${c.state}">${c.state === 'connected' ? '🟢 通话中' : '🟡 振铃中'}</span>
          </div>
          <div style="font-size:0.8125rem; color:var(--ink-secondary); margin-bottom:0.5rem;">
            参与成员: ${c.participants?.map(p => `${p.sn || p.deviceId} [${p.state}]`).join('、 ')}
          </div>
          <div style="display:flex; justify-content:space-between; align-items:center;">
            <span style="font-size:0.75rem; color:var(--ink-muted);">创建时间: ${new Date(c.createdAt).toLocaleTimeString()}</span>
            <div style="display:flex; gap:0.35rem;">
              ${c.participants?.some(p => p.state === 'ringing') ? `<button class="btn btn-success btn-sm btn-accept-all-this" data-call-id="${c.id}">接听待接人员</button>` : ''}
              <button class="btn btn-danger btn-sm btn-end-this" data-call-id="${c.id}">挂断</button>
            </div>
          </div>
        </div>
      `).join('');

      activeCallsContainer.querySelectorAll('.btn-accept-all-this').forEach(b => {
        b.addEventListener('click', async () => {
          await labApi(`/calls/${b.dataset.callId}/accept`, 'POST', { all: true });
          await pollState();
        });
      });
      activeCallsContainer.querySelectorAll('.btn-end-this').forEach(b => {
        b.addEventListener('click', async () => {
          await labApi(`/calls/${b.dataset.callId}/end`, 'POST', { all: true });
          await pollState();
        });
      });
    }
  }

  // 应用视频流状态
  applyVideoStreamState();

  // 历史记录渲染
  renderCommsHistory();
}

// 渲染安全帽播报接收箱
function renderHelmetTtsInbox() {
  const container = $('#helmetTtsInbox');
  if (!container) return;
  const msgs = state.labState.messages || [];
  if (msgs.length === 0) {
    container.innerHTML = `
      <div style="color: var(--ink-muted); font-size: 0.8125rem; text-align: center; padding: 1.5rem 0;">
        暂无接收到的文字语音播报。主系统值班端下发播报后，此处将即时呈现接收内容。
      </div>
    `;
    return;
  }

  container.innerHTML = msgs.slice(0, 10).map(m => {
    const hasAck = m.receipts?.some(r => r.state === 'acknowledged');
    return `
      <div style="background: var(--surface-subtle); border: 1px solid var(--line); border-radius: var(--radius-sm); padding: 0.65rem 0.85rem;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.35rem;">
          <span style="font-weight: 700; font-size: 0.8125rem; color: var(--brand);">📢 收到调度播报</span>
          <span style="font-size: 0.7rem; color: var(--ink-muted);">${new Date(m.createdAt).toLocaleTimeString()}</span>
        </div>
        <div style="font-size: 0.85rem; color: var(--ink); margin-bottom: 0.4rem; font-weight: 500;">
          "${m.text}"
        </div>
        <div style="display: flex; justify-content: space-between; align-items: center;">
          <span style="font-size: 0.725rem; color: var(--ink-secondary);">
            接收安全帽: ${m.receipts?.map(r => r.deviceId).join(', ') || '当前安全帽'}
          </span>
          <span class="status-pill ${hasAck ? 'online' : 'abnormal'}" style="font-size: 0.7rem; padding: 0.1rem 0.4rem;">
            ${hasAck ? '✓ 安全帽已播报回执' : '未回执'}
          </span>
        </div>
      </div>
    `;
  }).join('');
}

function renderCommsHistory() {
  const tbody = $('#commsHistoryBody');
  const calls = state.labState.calls || [];
  const msgs = state.labState.messages || [];

  const items = [
    ...calls.map(c => ({
      time: c.createdAt,
      type: c.direction === 'incoming' ? '安全帽呼叫' : '值班端呼入',
      target: c.participants?.map(p => p.sn || p.deviceId).join(',') || '对讲组',
      detail: `状态: ${c.state} ${c.videoEnabled ? '[视频推流]' : ''} ${c.reason ? '(' + c.reason + ')' : ''}`
    })),
    ...msgs.map(m => ({
      time: m.createdAt,
      type: '语音播报(TTS)',
      target: `${m.receipts?.length || 0} 顶安全帽`,
      detail: `"${m.text}"`
    }))
  ].sort((a, b) => b.time - a.time).slice(0, 30);

  if (items.length === 0) {
    tbody.innerHTML = `<tr><td colspan="4" style="text-align: center; color: var(--ink-muted); padding: 2rem;">暂无历史记录</td></tr>`;
    return;
  }

  tbody.innerHTML = items.map(it => `
    <tr>
      <td>${new Date(it.time).toLocaleTimeString()}</td>
      <td><span class="tag tag-team">${it.type}</span></td>
      <td>${it.target}</td>
      <td style="max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${it.detail}</td>
    </tr>
  `).join('');
}

function initVideoHudTimer() {
  setInterval(() => {
    const timeEl = $('#hudTimestamp');
    if (timeEl) timeEl.textContent = new Date().toLocaleString();
  }, 1000);
}

// -------------------------------------------------------------
// 功能模块三：告警场景测试与处置闭环
// -------------------------------------------------------------

// 获取当前激活方案下所选中的设备对象
function getActiveAlarmTarget() {
  const isPersonMode = $('#modePersonDevice')?.checked;
  const devSelect = isPersonMode ? $('#alarmPersonDeviceSelect') : $('#alarmDeviceSelect');
  if (!devSelect || !devSelect.value) return null;
  const deviceId = devSelect.value;
  const opt = devSelect.options[devSelect.selectedIndex];
  const devType = opt?.dataset?.type || 'helmet';
  const personName = opt?.dataset?.person || '';
  const devSn = opt?.dataset?.sn || opt?.textContent || deviceId;
  return { id: deviceId, typeCode: devType, personName, sn: devSn };
}

// 刷新当前选中的设备与责任人员信息提示
function updateSelectedAlarmDeviceInfo() {
  const target = getActiveAlarmTarget();
  const textEl = $('#alarmSelectedDeviceText');
  const personEl = $('#alarmSelectedPersonText');
  if (!target) {
    if (textEl) textEl.textContent = '🎯 目标设备: 未选择设备';
    if (personEl) personEl.style.display = 'none';
    return;
  }
  const typeName = target.typeCode === 'helmet' ? '安全帽' : (target.typeCode === 'belt' ? '安全带' : '手表');
  const icon = target.typeCode === 'helmet' ? '🪖' : (target.typeCode === 'belt' ? '🪢' : '⌚');
  if (textEl) textEl.innerHTML = `🎯 目标: <strong>${icon} ${typeName} (${target.sn})</strong>`;
  if (personEl) {
    if (target.personName && target.personName !== '未分配') {
      personEl.textContent = `👤 领用人: ${target.personName}`;
      personEl.style.display = 'inline-block';
    } else {
      personEl.textContent = '⚪ 暂无领用人 (库存/独立设备)';
      personEl.style.display = 'inline-block';
    }
  }
}

// 渲染方案一的联动设备下拉框
function updatePersonDeviceSelect(personId) {
  const pDevSelect = $('#alarmPersonDeviceSelect');
  if (!pDevSelect) return;
  const people = state.roster.people || [];
  const devices = state.roster.devices || [];

  if (personId) {
    const person = people.find(p => String(p.id) === String(personId));
    const bound = person?.assignedDevices || [];
    if (bound.length === 0) {
      pDevSelect.innerHTML = `<option value="">该人员暂未领用任何设备</option>`;
      pDevSelect.disabled = true;
    } else {
      pDevSelect.disabled = false;
      pDevSelect.innerHTML = bound.map(d => {
        const icon = d.typeCode === 'helmet' ? '🪖' : (d.typeCode === 'belt' ? '🪢' : '⌚');
        const typeName = d.typeCode === 'helmet' ? '安全帽' : (d.typeCode === 'belt' ? '安全带' : '手表');
        return `<option value="${d.id}" data-type="${d.typeCode}" data-person="${person.name}" data-sn="${d.sn || d.id}">${icon} ${typeName} · ${d.sn || d.id}</option>`;
      }).join('');
    }
  } else {
    // 全部人员时，展现所有已绑定或可用的设备，并标注所属人员
    pDevSelect.disabled = false;
    pDevSelect.innerHTML = devices.map(d => {
      const pName = d.currentAssignment?.personName || '未分配';
      const icon = d.typeCode === 'helmet' ? '🪖' : (d.typeCode === 'belt' ? '🪢' : '⌚');
      const typeName = d.typeCode === 'helmet' ? '安全帽' : (d.typeCode === 'belt' ? '安全带' : '手表');
      return `<option value="${d.id}" data-type="${d.typeCode}" data-person="${pName}" data-sn="${d.sn || d.id}">${icon} ${typeName} · ${d.sn || d.id} (${pName})</option>`;
    }).join('');
  }
}

async function loadAlarmsModule() {
  try {
    const people = state.roster.people || [];
    const devices = state.roster.devices || [];

    // 1. 填充方案一：人员下拉列表
    const pSelect = $('#alarmPersonSelect');
    if (pSelect) {
      const curP = pSelect.value;
      pSelect.innerHTML = `
        <option value="">全部人员 (${people.length} 人)</option>
        ${people.map(p => {
          const devCount = (p.assignedDevices || []).length;
          return `<option value="${p.id}">${p.name} (${p.personCode || p.id}) · ${p.teamName || '现场人员'} [${devCount}件装备]</option>`;
        }).join('')}
      `;
      if (curP) pSelect.value = curP;
      updatePersonDeviceSelect(pSelect.value);
    }

    // 2. 填充方案二：直接设备下拉列表 (全部设备)
    const devSelect = $('#alarmDeviceSelect');
    if (devSelect) {
      const curDev = devSelect.value;
      devSelect.innerHTML = devices.map(d => {
        const pName = d.currentAssignment?.personName || '未分配';
        const icon = d.typeCode === 'helmet' ? '🪖' : (d.typeCode === 'belt' ? '🪢' : '⌚');
        const typeName = d.typeCode === 'helmet' ? '安全帽' : (d.typeCode === 'belt' ? '安全带' : '手表');
        return `<option value="${d.id}" data-type="${d.typeCode}" data-person="${pName}" data-sn="${d.sn || d.id}">${icon} ${typeName} · ${d.sn || d.id} (${pName})</option>`;
      }).join('');
      if (curDev) devSelect.value = curDev;
    }

    updateSelectedAlarmDeviceInfo();
    renderScenarioList();
    await loadEvents();
  } catch (err) {
    console.error(err);
  }
}

function renderScenarioList() {
  const container = $('#alarmScenarioList');
  const target = getActiveAlarmTarget();
  const devType = target ? target.typeCode : 'helmet';
  const scenarios = CUSTOM_STATUSES[devType] || [];

  const available = scenarios.filter(s => s.code !== 'normal' && s.code !== 'offline');
  if (available.length === 0) {
    container.innerHTML = `<div style="color: var(--ink-muted); font-size: 0.8125rem;">暂无可测试场景</div>`;
    state.selectedScenario = null;
    return;
  }

  container.innerHTML = available.map((s, idx) => `
    <div class="scenario-item ${idx === 0 ? 'selected' : ''}" data-code="${s.code}" data-label="${s.label}">
      <div style="font-weight:700;font-size:0.875rem;">${s.label}</div>
      <div style="font-size:0.75rem;color:var(--ink-secondary)">代码: ${s.code}</div>
    </div>
  `).join('');

  state.selectedScenario = available[0] || null;

  container.querySelectorAll('.scenario-item').forEach(item => {
    item.addEventListener('click', () => {
      container.querySelectorAll('.scenario-item').forEach(i => i.classList.remove('selected'));
      item.classList.add('selected');
      state.selectedScenario = { code: item.dataset.code, label: item.dataset.label };
    });
  });
}

function initAlarmsActions() {
  // 方案模式切换: 人员与设备联动 VS 单独直接选择设备
  const modePerson = $('#modePersonDevice');
  const modeDevice = $('#modeDeviceDirect');
  const personRow = $('#alarmPersonFilterRow');
  const deviceRow = $('#alarmDeviceDirectRow');

  const onModeChange = () => {
    if (modePerson?.checked) {
      if (personRow) personRow.style.display = 'grid';
      if (deviceRow) deviceRow.style.display = 'none';
    } else {
      if (personRow) personRow.style.display = 'none';
      if (deviceRow) deviceRow.style.display = 'block';
    }
    updateSelectedAlarmDeviceInfo();
    renderScenarioList();
  };

  modePerson?.addEventListener('change', onModeChange);
  modeDevice?.addEventListener('change', onModeChange);

  // 方案一人选变动 -> 联动筛选装备
  $('#alarmPersonSelect')?.addEventListener('change', e => {
    updatePersonDeviceSelect(e.target.value);
    updateSelectedAlarmDeviceInfo();
    renderScenarioList();
  });

  // 方案一设备变动
  $('#alarmPersonDeviceSelect')?.addEventListener('change', () => {
    updateSelectedAlarmDeviceInfo();
    renderScenarioList();
  });

  // 方案二设备变动
  $('#alarmDeviceSelect')?.addEventListener('change', () => {
    updateSelectedAlarmDeviceInfo();
    renderScenarioList();
  });

  $('#btnInjectAlarm')?.addEventListener('click', async () => {
    const target = getActiveAlarmTarget();
    if (!target || !target.id || !state.selectedScenario) {
      return showNotice('请选择目标设备与告警测试场景', 'warning');
    }
    const deviceId = target.id;
    const { code, label } = state.selectedScenario;

    try {
      const cleanLabel = label.replace(/^[🟢🔴🟡🔵⚡🪫🚧🏃🚨💓💙🩸🌡️⚪]\s*/, '');
      await labApi('/presence', 'POST', {
        deviceId,
        customStatus: { code, label: cleanLabel }
      });
      showNotice(`已成功向【${target.sn} (${target.personName})】注入告警: ${cleanLabel}，已生成主系统事件并通知安卓端！`, 'success');
      state.lastEvent = { deviceId, code, label: cleanLabel, target };
      const btnRepeat = $('#btnRepeatAlarm');
      if (btnRepeat) btnRepeat.disabled = false;
      await loadRoster();
      await pollState();
      await loadEvents();
    } catch (err) {
      showNotice('注入告警失败: ' + err.message, 'danger');
    }
  });

  $('#btnRepeatAlarm')?.addEventListener('click', async () => {
    if (!state.lastEvent) return;
    try {
      await labApi('/presence', 'POST', {
        deviceId: state.lastEvent.deviceId,
        customStatus: { code: state.lastEvent.code, label: state.lastEvent.label }
      });
      showNotice('已重发相同告警事件测试去重', 'info');
      await loadEvents();
    } catch (err) {
      showNotice('重发失败: ' + err.message, 'danger');
    }
  });

  $('#btnRefreshEvents')?.addEventListener('click', loadEvents);

}

async function loadEvents() {
  const tbody = $('#eventsTableBody');
  const badge = $('#navAlarmsBadge');
  try {
    const data = await labApi('/events?current=1&size=20');
    const rows = data?.records || [];
    const openCount = rows.filter(r => r.status === 'open').length;

    if (badge) {
      if (openCount > 0) {
        badge.textContent = openCount;
        badge.style.display = 'inline-block';
      } else {
        badge.style.display = 'none';
      }
    }

    if (rows.length === 0) {
      tbody.innerHTML = `<tr><td colspan="5" style="text-align: center; color: var(--ink-muted); padding: 2rem;">当前厂站暂无告警事件</td></tr>`;
      return;
    }

    tbody.innerHTML = rows.map(ev => `
      <tr data-event-id="${ev.id}">
        <td><strong>#${ev.id}</strong></td>
        <td><span class="tag ${ev.severity === 'high' ? 'tag-task' : 'tag-team'}" style="${ev.type === 'sos' ? 'background:#fee2e2;color:#b91c1c;' : ''}">${ev.type}</span></td>
        <td>${ev.sn || ev.deviceId} · ${ev.personName || '无佩戴人'}</td>
        <td>${new Date(ev.occurredAt).toLocaleTimeString()}</td>
        <td><span class="status-pill ${ev.status === 'closed' ? 'offline' : 'abnormal'}"><i></i> ${ev.status}</span></td>
      </tr>
    `).join('');
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="5" style="text-align: center; color: var(--danger); padding: 1.5rem;">读取事件列表失败: ${err.message}</td></tr>`;
  }
}

// -------------------------------------------------------------
// 实时轮询与心跳维持
// -------------------------------------------------------------

async function pollState() {
  try {
    const data = await labApi('/state?client=console');
    state.labState = data || { devices: [], people: [], calls: [], messages: [], dispatchers: [], dutyStaff: null };

    // 自动检测并展示主项目值班员状态
    const duty = data.dutyStaff || {};
    const dutyNameEl = $('#dutyStaffName');
    const dutyStatusEl = $('#dutyStaffStatus');
    const targetDutyDisplay = $('#callTargetDutyDisplay');

    if (dutyNameEl && dutyStatusEl) {
      const displayName = duty.name ? `${duty.name} (${duty.userName || duty.userId})` : (duty.userName || '未检测到');
      dutyNameEl.textContent = displayName;
      if (duty.online) {
        dutyStatusEl.className = 'status-pill online';
        dutyStatusEl.innerHTML = '<i></i> 在线 (安卓已连接)';
      } else {
        dutyStatusEl.className = 'status-pill offline';
        dutyStatusEl.innerHTML = '<i></i> 待机 (等待安卓端登录)';
      }
    }

    if (targetDutyDisplay) {
      if (duty.online) {
        targetDutyDisplay.innerHTML = `<span style="color:var(--success); font-weight:700;">🟢 ${duty.name || duty.userName} (${duty.userName})</span> <span style="font-size:0.75rem; color:var(--ink-secondary); margin-left:0.5rem;">[主项目安卓在线，可直接呼入]</span>`;
      } else {
        targetDutyDisplay.innerHTML = `<span style="color:var(--ink-secondary); font-weight:600;">🟡 ${duty.name || duty.userName || '值班员'} (${duty.userName || 'siteA_duty'})</span> <span style="font-size:0.75rem; color:var(--ink-muted); margin-left:0.5rem;">[待机中，呼叫自动路由]</span>`;
      }
    }

    // 顶部状态栏提示
    const dutyPill = $('#dispatcherPill');
    if (dutyPill) {
      if (duty.online) {
        dutyPill.className = 'status-pill online';
        dutyPill.innerHTML = `<i></i> 主值班在线 (${duty.name || duty.userName})`;
      } else {
        dutyPill.className = 'status-pill offline';
        dutyPill.innerHTML = '<i></i> 无在线值班员';
      }
    }

    // 更新人员卡片与通讯面板
    renderPeopleGrid();
    updateCommsView();
  } catch (err) {
    console.warn('Poll state warning:', err);
  }
}

// 启动入口
window.addEventListener('DOMContentLoaded', async () => {
  initNavigation();
  initBatchButtons();
  initCommsModule();
  initAlarmsActions();

  // 初次加载数据 (无需用户登录，直接载入主业务数据与台账)
  await loadRoster();
  await loadAlarmsModule();
  await pollState();

  // 定时轮询
  state.pollTimer = setInterval(pollState, 2500);

  // URL 参数支持自动激活 Tab
  const urlTab = new URLSearchParams(window.location.search).get('tab');
  if (urlTab === 'comms') $('#navComms')?.click();
  else if (urlTab === 'alarms') $('#navAlarms')?.click();
});
