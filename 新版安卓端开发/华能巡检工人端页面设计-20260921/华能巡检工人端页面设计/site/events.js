/**
 * ROLLING 巡检工人端 · 核心系统事件列表与处置交互逻辑
 * 遵循 ROLLING 规范，纯本地静态高保真数据驱动，无缝嵌入当前网页端 UI
 */
(function () {
  'use strict';

  // 初始虚拟事件数据库
  const INITIAL_EVENTS = [
    {
      id: 'EVT-20260921-001',
      title: '1号机组高压配电区未授权进入越界告警',
      type: 'fence',
      typeName: '电子围栏告警',
      severity: 'critical',
      severityLabel: '🔴 紧急告警',
      status: 'pending',
      statusLabel: '待认领',
      time: '今日 10:35:12',
      person: '陈建国 (工号 P-001)',
      dept: '巡检一班 · 汽机房',
      device: '智能安全帽 RL-H001 (电量 86% · 在线)',
      area: '1号机组 · 汽机房高压配电柜东侧',
      latLng: '118.239120°E, 39.921340°N',
      claimant: '未认领',
      handleNote: '',
      photo: 'assets/assets/field-brand/preview/site_photo.jpg',
      actions: [
        {
          time: '10:35:12',
          user: '核心安全系统',
          action: '告警触发',
          desc: '电子围栏系统检测到人员越界进入1号机组高压管控红线区域，触发一级越界告警。',
          type: 'alert'
        }
      ]
    },
    {
      id: 'EVT-20260921-002',
      title: '汽机房2号巡检点作业人员安全帽脱卸告警',
      type: 'off_hat',
      typeName: '脱帽告警',
      severity: 'major',
      severityLabel: '🟠 重要告警',
      status: 'pending',
      statusLabel: '待认领',
      time: '今日 10:25:40',
      person: '李志远 (工号 P-002)',
      dept: '巡检一班',
      device: '智能安全帽 RL-H002 (电量 78% · 在线)',
      area: '汽机房 · 凝汽器B侧管道检修平台',
      latLng: '118.238910°E, 39.921120°N',
      claimant: '未认领',
      handleNote: '',
      photo: 'assets/assets/field-brand/preview/helmet.jpg',
      actions: [
        {
          time: '10:25:40',
          user: '智能安全帽',
          action: '传感器脱帽报警',
          desc: '帽内红外光电传感器与压力开关检测到佩戴断开，持续时间已超30秒。',
          type: 'alert'
        }
      ]
    },
    {
      id: 'EVT-20260921-003',
      title: '循环水泵房主管道轻微震动撞击告警',
      type: 'impact',
      typeName: '撞击告警',
      severity: 'minor',
      severityLabel: '🔵 一般告警',
      status: 'handling',
      statusLabel: '处置中',
      time: '今日 10:00:15',
      person: '陈建国 (工号 P-001)',
      dept: '巡检一班',
      device: '智能手表 RL-W001 (电量 72% · 在线)',
      area: '循环水泵房 · 1号主泵机组侧',
      latLng: '118.239450°E, 39.920800°N',
      claimant: '王班长 (班组长)',
      handleNote: '王班长已到现场核实，为巡检检修工具轻微碰触支架，无管路泄漏及人员受伤，作业正常。',
      photo: 'assets/assets/field-brand/preview/site_photo.jpg',
      actions: [
        {
          time: '10:00:15',
          user: '智能手表',
          action: '瞬时撞击预警',
          desc: '加速度计感应到瞬时冲击（4.2G），触发一般设备状态提示。',
          type: 'alert'
        },
        {
          time: '10:03:20',
          user: '王班长',
          action: '认领事件',
          desc: '责任班长锁定事件处置，赴现场核验管路与作业环境。',
          type: 'claim'
        },
        {
          time: '10:08:45',
          user: '王班长',
          action: '提交现场研判',
          desc: '现场核实为轻微碰触，人员安全、设备运行无异样。',
          type: 'handle'
        }
      ]
    },
    {
      id: 'EVT-20260921-004',
      title: '3号输煤廊道中间段紧急求助（防灾演练）',
      type: 'sos',
      typeName: 'SOS 求助',
      severity: 'critical',
      severityLabel: '🔴 紧急求助',
      status: 'closed',
      statusLabel: '已复核关闭',
      time: '今日 09:15:00',
      person: '周明 (工号 P-003)',
      dept: '巡检一班',
      device: '智能安全带 RL-B001 (电量 48%)',
      area: '3号输煤廊道 · 检修段',
      latLng: '118.240100°E, 39.922000°N',
      claimant: '王班长 (班组长)',
      handleNote: '班组求助联动演练完成，对讲通畅，演练已归档关闭。',
      photo: 'assets/assets/field-brand/preview/site_photo.jpg',
      actions: [
        {
          time: '09:15:00',
          user: '周明',
          action: 'SOS 求助触发',
          desc: '安全带主机长按 3 秒触发紧急求助，广播信标已推达值班室。',
          type: 'alert'
        },
        {
          time: '09:16:10',
          user: '王班长',
          action: '认领求助',
          desc: '班组长接单响应，建立对讲通话。',
          type: 'claim'
        },
        {
          time: '09:20:00',
          user: '王班长',
          action: '现场研判说明',
          desc: '与周明对讲核实，确认为班前紧急求助演练，现场一切正常。',
          type: 'handle'
        },
        {
          time: '09:25:30',
          user: '值班室',
          action: '复核关闭',
          desc: '演练完毕，关闭事件归档（标记为现场演习测试）。',
          type: 'close'
        }
      ]
    }
  ];

  // 本地存储响应式数据库
  let events = JSON.parse(JSON.stringify(INITIAL_EVENTS));
  let currentFilter = 'all'; // all, pending, handling, closed
  let currentType = 'all';   // all, fence, off_hat, impact, sos
  let currentDetailId = null;

  // DOM 节点引用
  let viewLayer = null;
  let topBanner = null;
  let fabBtn = null;
  let toastEl = null;

  function showToast(msg) {
    if (!toastEl) return;
    toastEl.textContent = msg;
    toastEl.classList.add('show');
    setTimeout(() => {
      toastEl.classList.remove('show');
    }, 2200);
  }

  function getPendingCount() {
    return events.filter(e => e.status === 'pending').length;
  }

  function updateBadges() {
    const count = getPendingCount();
    if (topBanner) {
      const countEl = topBanner.querySelector('.events-top-banner-badge');
      if (countEl) countEl.textContent = `${count}条待认领`;
      topBanner.style.display = count > 0 ? 'flex' : 'none';
    }
    if (fabBtn) {
      const badge = fabBtn.querySelector('.badge');
      if (badge) {
        badge.textContent = count;
        badge.style.display = count > 0 ? 'inline-block' : 'none';
      }
    }
  }

  // 初始化 DOM 结构
  function initDOM() {
    const phone = document.getElementById('phone');
    if (!phone) return;

    // 1. 顶部告警提示胶囊
    topBanner = document.createElement('div');
    topBanner.className = 'events-top-banner';
    topBanner.innerHTML = `
      <div class="events-top-banner-content">
        <span class="events-top-banner-badge">${getPendingCount()}条待认领</span>
        <span>核心告警待处置</span>
      </div>
      <div class="events-top-banner-action">研判处置 &rsaquo;</div>
    `;
    topBanner.onclick = () => openEventsView();
    phone.appendChild(topBanner);

    // 2. 悬浮快捷处置入口按钮
    fabBtn = document.createElement('button');
    fabBtn.className = 'events-fab';
    fabBtn.type = 'button';
    fabBtn.innerHTML = `
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10 9 9 9 8 9"/></svg>
      <span>事件处置</span>
      <span class="badge">${getPendingCount()}</span>
    `;
    fabBtn.onclick = () => openEventsView();
    phone.appendChild(fabBtn);

    // 3. 全局 Toast
    toastEl = document.createElement('div');
    toastEl.className = 'events-toast';
    phone.appendChild(toastEl);

    // 4. 事件主视图弹层（408×852 覆盖层）
    viewLayer = document.createElement('div');
    viewLayer.id = 'events-overlay';
    viewLayer.className = 'events-view-layer';
    phone.appendChild(viewLayer);

    // 5. 在左侧导览栏注入一键打开按钮
    const guide = document.querySelector('.guide');
    if (guide) {
      const btn = document.createElement('button');
      btn.style.marginTop = '10px';
      btn.style.width = '100%';
      btn.style.background = '#edf6fe';
      btn.style.border = '1px solid #adc6ff';
      btn.style.color = '#307cff';
      btn.style.fontWeight = 'bold';
      btn.textContent = '核心系统事件处置';
      btn.onclick = () => openEventsView();
      guide.appendChild(btn);
    }

    // 6. 拦截外壳原生返回按钮
    window.addEventListener('rolling-preview-back', function (e) {
      if (viewLayer && viewLayer.classList.contains('active')) {
        e.stopImmediatePropagation();
        e.preventDefault();
        if (currentDetailId) {
          renderListView();
        } else {
          closeEventsView();
        }
      }
    }, true);

    updateBadges();
  }

  // 打开事件视图
  function openEventsView(eventId = null) {
    if (!viewLayer) return;
    viewLayer.classList.add('active');
    if (topBanner) topBanner.style.opacity = '0';
    if (fabBtn) fabBtn.style.opacity = '0';
    if (eventId) {
      renderDetailView(eventId);
    } else {
      renderListView();
    }
  }

  // 关闭事件视图
  function closeEventsView() {
    if (!viewLayer) return;
    viewLayer.classList.remove('active');
    currentDetailId = null;
    if (topBanner) topBanner.style.opacity = '1';
    if (fabBtn) fabBtn.style.opacity = '1';
    updateBadges();
  }

  // 渲染事件列表页面
  function renderListView() {
    currentDetailId = null;
    const filtered = events.filter(e => {
      const matchStatus = currentFilter === 'all' || e.status === currentFilter;
      const matchType = currentType === 'all' || e.type === currentType;
      return matchStatus && matchType;
    });

    const pendingCount = events.filter(e => e.status === 'pending').length;
    const handlingCount = events.filter(e => e.status === 'handling').length;
    const closedCount = events.filter(e => e.status === 'closed').length;

    let html = `
      <div class="events-nav-header">
        <button class="events-nav-btn" id="evt-back-btn">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="m14 5-7 7 7 7"/></svg>
          <span>返回巡检</span>
        </button>
        <span class="events-nav-title">核心系统事件列表</span>
        <button class="events-nav-btn" id="evt-reset-btn" title="恢复初始测试数据" style="font-size:11px;padding:4px 8px;">重置</button>
      </div>

      <div class="events-body">
        <!-- 状态过滤胶囊 -->
        <div class="events-status-chips">
          <button class="events-status-chip ${currentFilter === 'all' ? 'active' : ''}" data-filter="all">全部 <span class="count">(${events.length})</span></button>
          <button class="events-status-chip ${currentFilter === 'pending' ? 'active' : ''}" data-filter="pending">待认领 <span class="count">(${pendingCount})</span></button>
          <button class="events-status-chip ${currentFilter === 'handling' ? 'active' : ''}" data-filter="handling">处置中 <span class="count">(${handlingCount})</span></button>
          <button class="events-status-chip ${currentFilter === 'closed' ? 'active' : ''}" data-filter="closed">已关闭 <span class="count">(${closedCount})</span></button>
        </div>

        <!-- 分类过滤栏 -->
        <div class="events-type-tags">
          <button class="events-type-tag ${currentType === 'all' ? 'active' : ''}" data-type="all">全部类型</button>
          <button class="events-type-tag ${currentType === 'fence' ? 'active' : ''}" data-type="fence">电子围栏</button>
          <button class="events-type-tag ${currentType === 'off_hat' ? 'active' : ''}" data-type="off_hat">脱帽告警</button>
          <button class="events-type-tag ${currentType === 'impact' ? 'active' : ''}" data-type="impact">撞击震动</button>
          <button class="events-type-tag ${currentType === 'sos' ? 'active' : ''}" data-type="sos">SOS求助</button>
        </div>

        <!-- 列表卡片流 -->
        <div style="display:flex;flex-direction:column;gap:12px;">
    `;

    if (filtered.length === 0) {
      html += `
        <div class="events-card" style="text-align:center;padding:40px 16px;color:#8c9bb0;">
          <div style="font-size:32px;margin-bottom:8px;">📋</div>
          <div style="font-size:14px;font-weight:600;">暂无符合条件的现场事件</div>
          <div style="font-size:12px;margin-top:4px;">可切换筛选条件查看其他记录</div>
        </div>
      `;
    } else {
      filtered.forEach(ev => {
        const sevClass = ev.severity === 'critical' ? 'sev-critical' : (ev.severity === 'major' ? 'sev-major' : 'sev-minor');
        const statusClass = ev.status === 'pending' ? 'status-pending' : (ev.status === 'handling' ? 'status-handling' : 'status-closed');

        html += `
          <div class="events-card events-card-clickable" data-evt-id="${ev.id}">
            <div class="events-card-header">
              <span class="events-severity-badge ${sevClass}">${ev.severityLabel}</span>
              <span class="status-pill ${statusClass}">${ev.statusLabel}</span>
            </div>
            <div class="events-card-title">${ev.title}</div>
            
            <div class="events-kv-grid">
              <div class="events-kv-item">
                <span class="events-kv-label">涉事人员</span>
                <span class="events-kv-val">${ev.person}</span>
              </div>
              <div class="events-kv-item">
                <span class="events-kv-label">发生区域</span>
                <span class="events-kv-val">${ev.area}</span>
              </div>
              <div class="events-kv-item">
                <span class="events-kv-label">绑定设备</span>
                <span class="events-kv-val">${ev.device}</span>
              </div>
              <div class="events-kv-item">
                <span class="events-kv-label">处置人员</span>
                <span class="events-kv-val" style="color:${ev.claimant === '未认领' ? '#d46b08' : '#307cff'};">${ev.claimant}</span>
              </div>
            </div>

            <div class="events-card-footer">
              <span class="events-card-time">${ev.time}</span>
              <button class="events-card-btn" type="button">研判与处置 &rsaquo;</button>
            </div>
          </div>
        `;
      });
    }

    html += `
        </div>
        <div style="text-align:center;font-size:12px;color:#8c9bb0;padding:12px 0;">
          核心系统事件直连展示 · 支持现场研判处置演练
        </div>
      </div>
    `;

    viewLayer.innerHTML = html;

    // 绑定事件
    document.getElementById('evt-back-btn').onclick = closeEventsView;
    document.getElementById('evt-reset-btn').onclick = () => {
      events = JSON.parse(JSON.stringify(INITIAL_EVENTS));
      showToast('已重置演示数据');
      updateBadges();
      renderListView();
    };

    // 状态切换
    viewLayer.querySelectorAll('.events-status-chip').forEach(btn => {
      btn.onclick = (e) => {
        currentFilter = e.currentTarget.getAttribute('data-filter');
        renderListView();
      };
    });

    // 类型切换
    viewLayer.querySelectorAll('.events-type-tag').forEach(btn => {
      btn.onclick = (e) => {
        currentType = e.currentTarget.getAttribute('data-type');
        renderListView();
      };
    });

    // 打开详情
    viewLayer.querySelectorAll('.events-card-clickable').forEach(card => {
      card.onclick = (e) => {
        const id = card.getAttribute('data-evt-id');
        renderDetailView(id);
      };
    });
  }

  // 渲染事件研判与处置详情页面
  function renderDetailView(eventId) {
    currentDetailId = eventId;
    const ev = events.find(item => item.id === eventId);
    if (!ev) return renderListView();

    const sevClass = ev.severity === 'critical' ? 'sev-critical' : (ev.severity === 'major' ? 'sev-major' : 'sev-minor');
    const statusClass = ev.status === 'pending' ? 'status-pending' : (ev.status === 'handling' ? 'status-handling' : 'status-closed');
    const guideClass = ev.status === 'pending' ? 'guide-pending' : (ev.status === 'handling' ? 'guide-handling' : 'guide-closed');

    let guideText = '';
    if (ev.status === 'pending') {
      guideText = '⚡ <strong>待认领事件</strong>：请现场作业或责任人员先认领事件，锁定处置人并赴现场进行安全研判。';
    } else if (ev.status === 'handling') {
      guideText = `📝 <strong>当前处置人：${ev.claimant}</strong>。请结合现场实情输入核验处置说明，上传凭证后提交。`;
    } else {
      guideText = '✅ <strong>事件已复核归档</strong>：现场隐患已排除或处置完毕，处置记录全流程已上链留痕。';
    }

    let actionsTimelineHtml = '';
    ev.actions.forEach((act, idx) => {
      const isAlert = act.type === 'alert';
      const isClose = act.type === 'close';
      const dotClass = isAlert ? 'dot-alert' : (isClose ? 'dot-close' : '');
      actionsTimelineHtml += `
        <div class="events-timeline-item">
          <div class="events-timeline-dot ${dotClass}"></div>
          <div class="events-timeline-time">${act.time}</div>
          <div class="events-timeline-title">${act.user} · ${act.action}</div>
          <div class="events-timeline-desc">${act.desc}</div>
        </div>
      `;
    });

    let html = `
      <div class="events-nav-header">
        <button class="events-nav-btn" id="evt-detail-back-btn">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="m14 5-7 7 7 7"/></svg>
          <span>事件列表</span>
        </button>
        <span class="events-nav-title">事件现场处置</span>
        <div style="width:68px;text-align:right;font-size:12px;font-weight:700;color:#307cff;">${ev.typeName}</div>
      </div>

      <div class="events-body">
        <!-- Hero 卡片 -->
        <div class="events-detail-hero">
          <div class="events-hero-tag-row">
            <span class="events-severity-badge ${sevClass}">${ev.severityLabel}</span>
            <span class="events-hero-id">${ev.id}</span>
          </div>
          <div class="events-hero-title">${ev.title}</div>
          <div class="events-hero-meta">发生时间：${ev.time} · ${ev.dept}</div>
        </div>

        <!-- 处置指导横幅 -->
        <div class="events-guide-banner ${guideClass}">
          <div>${guideText}</div>
        </div>

        <!-- 事件要素卡片 -->
        <div class="events-card">
          <div style="font-size:14px;font-weight:700;color:var(--evt-ink);display:flex;justify-content:space-between;">
            <span>事件基本信息</span>
            <span class="status-pill ${statusClass}">${ev.statusLabel}</span>
          </div>
          <div class="events-kv-grid">
            <div class="events-kv-item">
              <span class="events-kv-label">涉事人员</span>
              <span class="events-kv-val">${ev.person}</span>
            </div>
            <div class="events-kv-item">
              <span class="events-kv-label">作业区域</span>
              <span class="events-kv-val">${ev.area}</span>
            </div>
            <div class="events-kv-item">
              <span class="events-kv-label">绑定装备</span>
              <span class="events-kv-val">${ev.device}</span>
            </div>
            <div class="events-kv-item">
              <span class="events-kv-label">处置责任人</span>
              <span class="events-kv-val" style="color:#307cff;font-weight:700;">${ev.claimant}</span>
            </div>
          </div>
        </div>

        <!-- 现场定位卡片 -->
        <div class="events-card">
          <div style="font-size:14px;font-weight:700;color:var(--evt-ink);">现场定位示意</div>
          <div class="events-map-box">
            <img class="events-map-img" src="assets/assets/field-brand/preview/plant_map.jpg" alt="厂区定位示意" onerror="this.src='assets/field-brand/preview/plant_map.jpg'">
            <div class="events-map-pin">📍</div>
          </div>
          <div style="display:flex;justify-content:space-between;font-size:12px;color:var(--evt-muted);">
            <span>WGS84 坐标：${ev.latLng}</span>
            <span style="color:#00b578;font-weight:600;">● 高精度定位正常</span>
          </div>
        </div>

        <!-- 核心处置动作区 -->
        <div class="events-card" style="border: 1px solid #adc6ff;">
          <div style="font-size:15px;font-weight:700;color:var(--evt-ink);">现场处置执行</div>
    `;

    // 状态为待认领：展示认领按钮
    if (ev.status === 'pending') {
      html += `
        <button class="events-btn-primary" id="btn-claim-event" type="button">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M18 11V6a2 2 0 0 0-2-2v0a2 2 0 0 0-2 2v0"/><path d="M14 10V4a2 2 0 0 0-2-2v0a2 2 0 0 0-2 2v2"/><path d="M10 10.5V6a2 2 0 0 0-2-2v0a2 2 0 0 0-2 2v8"/><path d="M18 8a2 2 0 1 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15"/></svg>
          <span>认领此事件（锁定为本人处置）</span>
        </button>
      `;
    }

    // 现场研判说明与提交
    html += `
      <div style="display:flex;flex-direction:column;gap:8px;margin-top:${ev.status === 'pending' ? '8px' : '0'};">
        <label style="font-size:13px;font-weight:600;color:var(--evt-ink);">现场核验与处置意见</label>
        
        <!-- 快捷短语 -->
        <div class="events-quick-phrases">
          <span class="events-phrase-chip" data-phrase="安全帽已重新佩戴紧固，人员已恢复规范作业。">+ 安全帽已佩戴</span>
          <span class="events-phrase-chip" data-phrase="已引导作业人员立即撤出高压管控越界区域，无设备异常。">+ 已撤离越界区域</span>
          <span class="events-phrase-chip" data-phrase="现场复查管路无渗漏无变形，运行参数正常。">+ 管道无异常</span>
          <span class="events-phrase-chip" data-phrase="现场环境安全，人员身体无大碍。">+ 现场环境安全</span>
        </div>

        <textarea class="events-textarea" id="evt-handle-textarea" placeholder="请输入现场核查情况、人员状态及采取的处置措施...">${ev.handleNote}</textarea>

        <!-- 凭证照片 -->
        <div>
          <span style="font-size:12px;font-weight:600;color:var(--evt-muted);">现场核查凭证照片</span>
          <div class="events-photo-grid">
            <div class="events-photo-item">
              <img src="${ev.photo}" alt="现场核验" onerror="this.src='assets/field-brand/preview/site_photo.jpg'">
            </div>
            <div class="events-photo-add" id="btn-add-photo">
              <span style="font-size:16px;">📷</span>
              <span>拍照/凭证</span>
            </div>
          </div>
        </div>

        <button class="events-btn-primary" id="btn-submit-handle" type="button" style="margin-top:6px;">
          <span>提交现场处置说明</span>
        </button>
      </div>

      <!-- 快速联系涉事工人 -->
      <div style="display:flex;gap:8px;margin-top:8px;">
        <button class="events-btn-secondary" id="btn-call-voice" type="button">
          <span>📞 语音呼叫工人</span>
        </button>
        <button class="events-btn-secondary" id="btn-call-video" type="button">
          <span>📹 视频协助核验</span>
        </button>
      </div>
    `;

    // 更多处置折叠卡片
    html += `
      <div class="events-collapse" id="evt-more-collapse" style="margin-top:10px;">
        <div class="events-collapse-header" id="evt-collapse-toggle">
          <span>更多处置操作（复核关闭 / 转交 / 重开）</span>
          <span id="evt-collapse-arrow">▼</span>
        </div>
        <div class="events-collapse-content">
          ${ev.status !== 'closed' ? `
            <div style="display:flex;flex-direction:column;gap:8px;">
              <label style="font-size:12px;font-weight:600;color:var(--evt-ink);">复核关闭说明</label>
              <input class="events-input" id="evt-close-reason" placeholder="输入关闭原因（如：现场隐患已消除，确认安全）" value="现场核验安全，违规行为已纠正，确认无隐患">
              <label style="font-size:12px;color:var(--evt-body);display:flex;align-items:center;gap:6px;cursor:pointer;">
                <input type="checkbox" id="evt-false-alarm"> 标记为现场误触发 / 演习测试 (False Alarm)
              </label>
              <button class="events-btn-danger" id="btn-close-event" type="button">
                <span>确认复核关闭事件</span>
              </button>
            </div>

            <div style="border-top:1px dashed #d8e5f2;padding-top:10px;display:flex;flex-direction:column;gap:8px;">
              <label style="font-size:12px;font-weight:600;color:var(--evt-ink);">转交责任人</label>
              <select class="events-input" id="evt-transfer-select">
                <option value="王班长 (班组长)">转交至：王班长 (班组长)</option>
                <option value="厂区值班室">转交至：厂区值班室</option>
                <option value="李志远">转交至：李志远 (协作人员)</option>
              </select>
              <button class="events-btn-secondary" id="btn-transfer-event" type="button">
                <span>转交责任人并提交说明</span>
              </button>
            </div>
          ` : `
            <div style="display:flex;flex-direction:column;gap:8px;">
              <div style="font-size:12px;color:#00b578;font-weight:bold;">当前事件已复核关闭</div>
              <button class="events-btn-secondary" id="btn-reopen-event" type="button">
                <span>🔄 发现新隐患，重新开启事件处置</span>
              </button>
            </div>
          `}
        </div>
      </div>
    </div>

    <!-- 时间线卡片 -->
    <div class="events-card">
      <div style="font-size:14px;font-weight:700;color:var(--evt-ink);">处置操作全流程时间线</div>
      <div class="events-timeline">
        ${actionsTimelineHtml}
      </div>
    </div>

    <div style="height:20px;"></div>
  </div>
    `;

    viewLayer.innerHTML = html;

    // 绑定详情页事件
    document.getElementById('evt-detail-back-btn').onclick = renderListView;

    // 快捷短语插入
    viewLayer.querySelectorAll('.events-phrase-chip').forEach(chip => {
      chip.onclick = () => {
        const textarea = document.getElementById('evt-handle-textarea');
        if (textarea) {
          const phrase = chip.getAttribute('data-phrase');
          textarea.value = textarea.value ? (textarea.value + ' ' + phrase) : phrase;
          textarea.focus();
        }
      };
    });

    // 认领事件
    const claimBtn = document.getElementById('btn-claim-event');
    if (claimBtn) {
      claimBtn.onclick = () => {
        ev.status = 'handling';
        ev.statusLabel = '处置中';
        ev.claimant = '陈建国 (巡检工人)';
        const nowTime = new Date().toTimeString().slice(0, 8);
        ev.actions.push({
          time: nowTime,
          user: '陈建国',
          action: '认领事件',
          desc: '巡检工人 陈建国 现场认领事件，处置状态变更为“处置中”。',
          type: 'claim'
        });
        showToast('认领成功！责任人已锁定为陈建国');
        updateBadges();
        renderDetailView(eventId);
      };
    }

    // 提交现场处置意见
    const submitBtn = document.getElementById('btn-submit-handle');
    if (submitBtn) {
      submitBtn.onclick = () => {
        const textarea = document.getElementById('evt-handle-textarea');
        const text = textarea ? textarea.value.trim() : '';
        if (!text) {
          showToast('请先输入现场处置意见');
          return;
        }
        ev.handleNote = text;
        if (ev.status === 'pending') {
          ev.status = 'handling';
          ev.statusLabel = '处置中';
          ev.claimant = '陈建国 (巡检工人)';
        }
        const nowTime = new Date().toTimeString().slice(0, 8);
        ev.actions.push({
          time: nowTime,
          user: '陈建国',
          action: '现场研判说明',
          desc: text,
          type: 'handle'
        });
        showToast('现场处置说明提交成功，已记入时间线！');
        updateBadges();
        renderDetailView(eventId);
      };
    }

    // 添加照片模拟
    const photoBtn = document.getElementById('btn-add-photo');
    if (photoBtn) {
      photoBtn.onclick = () => {
        showToast('已从智能安全帽同步现场抓拍凭证');
      };
    }

    // 语音与视频呼叫
    const voiceBtn = document.getElementById('btn-call-voice');
    if (voiceBtn) {
      voiceBtn.onclick = () => {
        showToast('已发起现场语音通话（模拟呼叫中…）');
      };
    }
    const videoBtn = document.getElementById('btn-call-video');
    if (videoBtn) {
      videoBtn.onclick = () => {
        showToast('已请求安全帽现场视频画面（模拟对讲）');
      };
    }

    // 折叠展开
    const collapseToggle = document.getElementById('evt-collapse-toggle');
    const collapseBox = document.getElementById('evt-more-collapse');
    const collapseArrow = document.getElementById('evt-collapse-arrow');
    if (collapseToggle && collapseBox) {
      collapseToggle.onclick = () => {
        collapseBox.classList.toggle('open');
        collapseArrow.textContent = collapseBox.classList.contains('open') ? '▲' : '▼';
      };
    }

    // 复核关闭事件
    const closeBtn = document.getElementById('btn-close-event');
    if (closeBtn) {
      closeBtn.onclick = () => {
        const reasonInput = document.getElementById('evt-close-reason');
        const falseAlarmCheck = document.getElementById('evt-false-alarm');
        const reason = reasonInput ? reasonInput.value.trim() : '现场核验安全';
        const isFalse = falseAlarmCheck ? falseAlarmCheck.checked : false;

        ev.status = 'closed';
        ev.statusLabel = '已复核关闭';
        const nowTime = new Date().toTimeString().slice(0, 8);
        ev.actions.push({
          time: nowTime,
          user: '陈建国',
          action: '复核关闭',
          desc: `复核关闭：${reason}${isFalse ? ' (标记为现场误报/演习)' : ''}。`,
          type: 'close'
        });
        showToast('事件已复核关闭！已归档留痕');
        updateBadges();
        renderDetailView(eventId);
      };
    }

    // 重新开启事件
    const reopenBtn = document.getElementById('btn-reopen-event');
    if (reopenBtn) {
      reopenBtn.onclick = () => {
        ev.status = 'handling';
        ev.statusLabel = '处置中';
        const nowTime = new Date().toTimeString().slice(0, 8);
        ev.actions.push({
          time: nowTime,
          user: '陈建国',
          action: '重开事件',
          desc: '发现潜在隐患，现场重新激活处置流程。',
          type: 'reopen'
        });
        showToast('事件已重新开启处置');
        updateBadges();
        renderDetailView(eventId);
      };
    }

    // 转交责任人
    const transferBtn = document.getElementById('btn-transfer-event');
    if (transferBtn) {
      transferBtn.onclick = () => {
        const select = document.getElementById('evt-transfer-select');
        const toUser = select ? select.value : '王班长';
        ev.claimant = toUser;
        const nowTime = new Date().toTimeString().slice(0, 8);
        ev.actions.push({
          time: nowTime,
          user: '陈建国',
          action: '转交责任人',
          desc: `陈建国 将事件处置责任转交给 ${toUser}。`,
          type: 'transfer'
        });
        showToast(`已成功转交给 ${toUser}`);
        updateBadges();
        renderDetailView(eventId);
      };
    }
  }

  // 暴露给全局调用（可从控制台、导览或 Flutter 消息调用）
  window.openRollingEvents = openEventsView;
  window.closeRollingEvents = closeEventsView;

  // 页面加载完成后挂载 DOM
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initDOM);
  } else {
    initDOM();
  }
})();
