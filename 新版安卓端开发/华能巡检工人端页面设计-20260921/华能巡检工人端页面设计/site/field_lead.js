/**
 * ROLLING 现场领导与指挥全局态势层
 * 核心目标：看清全局、掌握电子围栏出入与问题位置、快速电话沟通到人员
 * 零样式侵入，原生兼容 Flutter Web 底座
 */
(function () {
  'use strict';

  let hudBanner = null;
  let leadPanel = null;

  function initFieldLead() {
    const phone = document.getElementById('phone');
    if (!phone) return;

    // 1. 顶部置顶管理态势与研判双联胶囊条（管理员专享，内页常驻入口）
    hudBanner = document.createElement('div');
    hudBanner.className = 'lead-hud-banner';
    hudBanner.id = 'lead-hud-banner';
    hudBanner.innerHTML = `
      <div class="lead-hud-title" onclick="window.openLeadPanel && window.openLeadPanel()" title="点击查看电子围栏告警态势">
        <span class="lead-hud-badge">电子围栏</span>
        <span>2起越界待处置</span>
      </div>
      <div class="lead-hud-right">
        <button class="lead-hud-btn lead-hud-btn-lead" type="button" title="打开现场全局态势与指挥调度" onclick="event.stopPropagation(); window.openLeadPanel && window.openLeadPanel();">
          <span>🚨 全局态势</span>
        </button>
        <button class="lead-hud-btn lead-hud-btn-evt" type="button" title="打开核心系统事件研判与处置" onclick="event.stopPropagation(); window.openRollingEvents && window.openRollingEvents();">
          <span>📋 作业研判</span>
        </button>
      </div>
    `;
    hudBanner.onclick = openLeadPanel;
    phone.appendChild(hudBanner);

    // 2. 领导态势与指挥全景抽屉
    leadPanel = document.createElement('div');
    leadPanel.className = 'lead-panel';
    leadPanel.id = 'lead-panel';
    leadPanel.innerHTML = `
      <div class="lead-panel-header">
        <button class="events-nav-btn" id="lead-close-btn" type="button">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="m14 5-7 7 7 7"/></svg>
          <span>返回现场</span>
        </button>
        <span class="lead-panel-title">现场全局态势与指挥调度</span>
        <div style="width:58px;"></div>
      </div>

      <div class="lead-panel-body">
        <!-- 一、全局看板四宫格 (领导一眼看清现场全局) -->
        <div class="lead-stat-grid">
          <div class="lead-stat-box">
            <span class="lead-stat-num" style="color:#00b578;">4</span>
            <span class="lead-stat-lbl">现场在岗</span>
          </div>
          <div class="lead-stat-box">
            <span class="lead-stat-num" style="color:#307cff;">1</span>
            <span class="lead-stat-lbl">当前作业</span>
          </div>
          <div class="lead-stat-box">
            <span class="lead-stat-num" style="color:#f53f3f;">2</span>
            <span class="lead-stat-lbl">围栏出入告警</span>
          </div>
          <div class="lead-stat-box">
            <span class="lead-stat-num" style="color:#24529a;">88%</span>
            <span class="lead-stat-lbl">装备在线率</span>
          </div>
        </div>

        <!-- 二、问题位置实景地图与电子围栏出入告警 -->
        <div class="lead-map-card">
          <div style="display:flex;align-items:center;justify-content:space-between;">
            <span style="font-size:15px;font-weight:800;color:var(--lead-ink);">📍 电子围栏出入与现场定位</span>
            <span style="font-size:11px;color:#d46b08;font-weight:bold;">高精度UWB空间标定</span>
          </div>
          
          <div class="lead-map-container">
            <img class="lead-map-img" src="assets/assets/field-brand/preview/plant_map.jpg" alt="厂区平面图" onerror="this.src='assets/field-brand/preview/plant_map.jpg'">
            <!-- 告警点 1: 汽机房高压配电区电子围栏 (越界进入) -->
            <div class="lead-map-pin" style="top:32%;left:44%;" onclick="alert('📍 告警点 1：1号机组高压管控围栏(EF-01)\n涉事人：陈建国\n出入动作：【越界进入】闯入高压红线带电区\n时间：10:35:12')">
              <span>●</span> [进入] 越界闯入(陈建国)
            </div>
            <!-- 告警点 2: 凝汽器安全作业围栏 (违规离开) -->
            <div class="lead-map-pin" style="top:62%;left:60%;background:#ff8f1f;" onclick="alert('📍 告警点 2：汽机房巡检安全围栏(EF-02)\n涉事人：李志远\n出入动作：【违规离开】擅自脱离指定安全区\n时间：10:40:18')">
              <span>●</span> [离开] 擅离安全区(李志远)
            </div>
          </div>

          <!-- 围栏出入告警 1: 越界进入 -->
          <div class="lead-issue-item">
            <div class="lead-issue-top">
              <span class="lead-issue-loc">⚠️ 告警 1：【电子围栏 · 越界进入】高压管控区</span>
              <span class="lead-fence-badge-in">🔴 越界进入</span>
            </div>
            <div class="lead-fence-info-row">
              <div><strong>电子围栏：</strong>1号发电机高压红线禁入管控围栏 (EF-01)</div>
              <div><strong>出入动作：</strong><span style="color:#f53f3f;font-weight:bold;">未授权进入 (闯入红线区)</span> · 发生时间 10:35:12</div>
              <div><strong>涉事人员：</strong>陈建国 (工号 P-001 · 巡检一班)</div>
              <div><strong>触发装备：</strong>智能安全帽 RL-H001 (电量 86% · UWB定位)</div>
              <div><strong>触发点位：</strong>汽机房东侧高压配电区A门进线柜</div>
            </div>
            <div style="display:flex;gap:6px;margin-top:2px;">
              <button class="lead-btn-call" type="button" onclick="alert('📞 正在一键直拨陈建国安全帽对讲…\n已呼通！已责令作业人员立即退出高压红线区！')">
                <span>📞 一键呼叫陈建国</span>
              </button>
              <button class="lead-btn-video" type="button" onclick="window.openRollingEvents && window.openRollingEvents('EVT-20260921-001')">
                <span>📝 现场研判处置</span>
              </button>
            </div>
          </div>

          <!-- 围栏出入告警 2: 违规离开 -->
          <div class="lead-issue-item" style="border-color:#ffd591;background:#fffaf0;">
            <div class="lead-issue-top">
              <span class="lead-issue-loc" style="color:#d46b08;">⚠️ 告警 2：【电子围栏 · 违规离开】安全作业区</span>
              <span class="lead-fence-badge-out">🟠 擅自离开</span>
            </div>
            <div class="lead-fence-info-row">
              <div><strong>电子围栏：</strong>汽机房2号机组巡检指定安全作业围栏 (EF-02)</div>
              <div><strong>出入动作：</strong><span style="color:#d46b08;font-weight:bold;">擅自脱离 (超出安全范围)</span> · 发生时间 10:40:18</div>
              <div><strong>涉事人员：</strong>李志远 (工号 P-002 · 巡检一班)</div>
              <div><strong>触发装备：</strong>智能安全帽 RL-H002 (电量 78% · UWB定位)</div>
              <div><strong>触发点位：</strong>汽机房南侧通道出口安全界线</div>
            </div>
            <div style="display:flex;gap:6px;margin-top:2px;">
              <button class="lead-btn-call" type="button" onclick="alert('📞 正在一键直拨李志远安全帽对讲…\n已呼通！已要求人员立即返回指定检修安全围栏！')">
                <span>📞 一键呼叫李志远</span>
              </button>
              <button class="lead-btn-video" type="button" onclick="window.openRollingEvents && window.openRollingEvents('EVT-20260921-002')">
                <span>📝 现场研判处置</span>
              </button>
            </div>
          </div>
        </div>

        <!-- 三、快速电话沟通到人员 (全员直拨呼叫) -->
        <div class="lead-map-card">
          <div style="font-size:15px;font-weight:800;color:var(--lead-ink);">📞 现场快速电话与对讲沟通</div>
          
          <div style="display:flex;flex-direction:column;gap:8px;">
            <!-- 王班长 -->
            <div style="display:flex;align-items:center;justify-content:space-between;padding:8px 10px;background:#f8fbfe;border-radius:10px;border:1px solid #e0ecf7;">
              <div>
                <div style="font-weight:800;font-size:14px;color:var(--lead-ink);">王班长 (班组长 · 现场负责人)</div>
                <div style="font-size:11px;color:var(--lead-muted);">值班控制室 · 在线</div>
              </div>
              <div style="display:flex;gap:4px;">
                <button class="lead-btn-call" style="height:32px;font-size:12px;padding:0 8px;" onclick="alert('📞 正在直拨王班长…已接通！')">📞 电话</button>
                <button class="lead-btn-video" style="height:32px;font-size:12px;padding:0 8px;" onclick="alert('📹 正在请求王班长视频协助…')">📹 视频</button>
              </div>
            </div>

            <!-- 陈建国 -->
            <div style="display:flex;align-items:center;justify-content:space-between;padding:8px 10px;background:#f8fbfe;border-radius:10px;border:1px solid #e0ecf7;">
              <div>
                <div style="font-weight:800;font-size:14px;color:var(--lead-ink);">陈建国 (涉事人员 · 越界进入)</div>
                <div style="font-size:11px;color:#f53f3f;font-weight:bold;">高压管控红线区 · 越界中</div>
              </div>
              <div style="display:flex;gap:4px;">
                <button class="lead-btn-call" style="height:32px;font-size:12px;padding:0 8px;" onclick="alert('📞 正在直拨陈建国安全帽…已接通！')">📞 电话</button>
                <button class="lead-btn-video" style="height:32px;font-size:12px;padding:0 8px;" onclick="alert('📹 正在调取陈建国安全帽现场画面…')">📹 视频</button>
              </div>
            </div>

            <!-- 李志远 -->
            <div style="display:flex;align-items:center;justify-content:space-between;padding:8px 10px;background:#f8fbfe;border-radius:10px;border:1px solid #e0ecf7;">
              <div>
                <div style="font-weight:800;font-size:14px;color:var(--lead-ink);">李志远 (涉事人员 · 违规离开)</div>
                <div style="font-size:11px;color:#d46b08;font-weight:bold;">安全作业区脱出 · 未受控</div>
              </div>
              <div style="display:flex;gap:4px;">
                <button class="lead-btn-call" style="height:32px;font-size:12px;padding:0 8px;background:#ff8f1f;" onclick="alert('📞 正在直拨李志远安全帽…已接通！')">📞 呼叫</button>
              </div>
            </div>

            <!-- 周明 -->
            <div style="display:flex;align-items:center;justify-content:space-between;padding:8px 10px;background:#f8fbfe;border-radius:10px;border:1px solid #e0ecf7;">
              <div>
                <div style="font-weight:800;font-size:14px;color:var(--lead-ink);">周明 (巡检工人 · 凝汽器)</div>
                <div style="font-size:11px;color:var(--lead-muted);">汽机房东侧 · 在线正常</div>
              </div>
              <div style="display:flex;gap:4px;">
                <button class="lead-btn-call" style="height:32px;font-size:12px;padding:0 8px;" onclick="alert('📞 正在直拨周明…已接通！')">📞 电话</button>
                <button class="lead-btn-video" style="height:32px;font-size:12px;padding:0 8px;" onclick="alert('📹 正在调取周明现场画面…')">📹 视频</button>
              </div>
            </div>
          </div>
        </div>

        <!-- 四、紧急求助 (SOS) 联动与全员应急通道 -->
        <div class="lead-map-card" style="border:1.5px solid #ffa39e;background:#fff1f0;">
          <div style="display:flex;align-items:center;justify-content:space-between;">
            <span style="font-size:15px;font-weight:800;color:#cf1322;">🆘 现场紧急求助 (SOS) 联锁保障</span>
            <span class="sos-badge-critical">🔴 应急值守</span>
          </div>
          <div style="font-size:12px;color:#5c1d1d;line-height:1.5;">
            遇人身突发险情优先抢占最高无线信道，直通值班室、现场班长及周边 50 米内工友联动救援。
          </div>
          <div style="display:flex;gap:6px;margin-top:2px;">
            <button class="sos-btn-giant sos-btn-green" style="height:40px;font-size:13px;" type="button" onclick="window.triggerEmergencySOS && window.triggerEmergencySOS()">
              <span>🚨 查验 / 响应紧急 SOS 求助</span>
            </button>
          </div>
        </div>

        <div style="height:20px;"></div>
      </div>
    `;

    phone.appendChild(leadPanel);

    document.getElementById('lead-close-btn').onclick = closeLeadPanel;

    // 拦截外壳返回按键：如果抽屉打开，优先平滑关闭抽屉
    window.addEventListener('rolling-preview-back', function (e) {
      if (leadPanel && leadPanel.classList.contains('active')) {
        e.stopImmediatePropagation();
        e.preventDefault();
        closeLeadPanel();
      }
    }, true);

    updateLeadVisibility();
  }

  function updateLeadVisibility() {
    const isLogin = location.hash === '#/login' || location.hash === '/login';
    const role = window.currentUserRole || (sessionStorage.getItem('rolling_role') || 'admin');
    const isAdmin = (role === 'admin') && !isLogin;
    if (hudBanner) {
      hudBanner.style.display = isAdmin ? 'flex' : 'none';
    }
    const guideLeadBtn = document.getElementById('guide-field-lead-btn');
    if (guideLeadBtn) {
      guideLeadBtn.style.display = isAdmin ? 'block' : 'none';
    }
    if (!isAdmin && leadPanel && leadPanel.classList.contains('active')) {
      closeLeadPanel();
    }
  }

  function openLeadPanel() {
    const role = window.currentUserRole || (sessionStorage.getItem('rolling_role') || 'admin');
    if (role !== 'admin') {
      alert('当前系统为普通巡检人员端，无权限访问现场全局态势与指挥。');
      return;
    }
    if (!leadPanel) return;
    leadPanel.classList.add('active');
    if (hudBanner) hudBanner.style.opacity = '0';
  }

  function closeLeadPanel() {
    if (!leadPanel) return;
    leadPanel.classList.remove('active');
    const role = window.currentUserRole || (sessionStorage.getItem('rolling_role') || 'admin');
    const isLogin = location.hash === '#/login' || location.hash === '/login';
    if (hudBanner && role === 'admin' && !isLogin) {
      hudBanner.style.opacity = '1';
    }
  }

  window.openFieldLead = openLeadPanel;
  window.closeFieldLead = closeLeadPanel;
  window.updateLeadVisibility = updateLeadVisibility;
  window.addEventListener('hashchange', updateLeadVisibility);
  window.addEventListener('rolling-role-changed', updateLeadVisibility);

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initFieldLead);
  } else {
    initFieldLead();
  }
})();
