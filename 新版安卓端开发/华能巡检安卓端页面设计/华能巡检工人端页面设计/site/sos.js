/**
 * ROLLING 现场紧急求助 (SOS) 核心控制逻辑
 * 提供全局超醒目入口、全屏应急响应弹窗与多级联锁处置动作
 */
(function () {
  'use strict';

  let sosFab = null;
  let sosModal = null;

  function initSOS() {
    const phone = document.getElementById('phone');
    if (!phone) return;

    // 1. 注入全屏紧急求助响应抽屉 (408×852 覆盖层)
    sosModal = document.createElement('div');
    sosModal.className = 'sos-modal-layer';
    sosModal.id = 'sos-modal';
    sosModal.innerHTML = `
      <div class="sos-modal-header">
        <button class="events-nav-btn" id="sos-close-btn" type="button">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="m14 5-7 7 7 7"/></svg>
          <span>返回</span>
        </button>
        <span class="sos-modal-title">
          <span>🚨 紧急求助 (SOS) 响应</span>
        </span>
        <span class="sos-badge-critical">🔴 优先级 TOP1</span>
      </div>

      <div class="sos-modal-body">
        <!-- 一、遇险报警状态横幅 -->
        <div class="sos-alert-banner">
          <div class="sos-alert-top">
            <span class="sos-alert-title">⚠️ 紧急求救信标已联锁广播</span>
            <span style="font-size:11px;color:#cf1322;font-weight:800;">信道抢占中</span>
          </div>
          <div class="sos-alert-desc">
            已向厂区应急值班室、带班班长及周边 50 米内协作人员下发最高级别求救信标，附带人员高精度 UWB 坐标与穿戴装备状态。
          </div>
        </div>

        <!-- 二、求助要素卡片 -->
        <div class="events-card" style="border: 1.5px solid #ffa39e;">
          <div style="font-size:14px;font-weight:800;color:#cf1322;display:flex;justify-content:space-between;">
            <span>遇险求助人员信息</span>
            <span style="font-size:12px;color:#d46b08;font-weight:bold;">高精度定位正常</span>
          </div>
          <div class="events-kv-grid">
            <div class="events-kv-item">
              <span class="events-kv-label">求助人员</span>
              <span class="events-kv-val" style="font-weight:800;color:#cf1322;">陈建国 (工号 P-001)</span>
            </div>
            <div class="events-kv-item">
              <span class="events-kv-label">所属班组</span>
              <span class="events-kv-val">巡检一班 · 汽机房检修</span>
            </div>
            <div class="events-kv-item">
              <span class="events-kv-label">当前位置</span>
              <span class="events-kv-val">1号机组 · 汽机房高压配电区</span>
            </div>
            <div class="events-kv-item">
              <span class="events-kv-label">空间坐标</span>
              <span class="events-kv-val">118.239120°E, 39.921340°N</span>
            </div>
            <div class="events-kv-item">
              <span class="events-kv-label">穿戴装备</span>
              <span class="events-kv-val">智能安全帽 RL-H001 (86%) · 安全带</span>
            </div>
            <div class="events-kv-item">
              <span class="events-kv-label">接警中枢</span>
              <span class="events-kv-val" style="color:#307cff;font-weight:700;">厂区值班室 · 责任班长</span>
            </div>
          </div>
        </div>

        <!-- 三、核心处置行动大按钮组 (针对现场大字大按钮操作) -->
        <div class="sos-action-card">
          <div style="font-size:14px;font-weight:800;color:#101f43;">现场快速处置指令</div>
          
          <!-- 1. 一键直通值班室 -->
          <button class="sos-btn-giant sos-btn-green" id="sos-btn-call" type="button">
            <span style="font-size:18px;">📞</span>
            <span>直拨厂区值班室 (应急对讲直通)</span>
          </button>

          <!-- 2. 一键开启安全帽视频 -->
          <button class="sos-btn-giant sos-btn-blue" id="sos-btn-video" type="button">
            <span style="font-size:18px;">📹</span>
            <span>开启安全帽现场突发画面协助</span>
          </button>

          <!-- 3. 呼叫周边工友增援 -->
          <button class="sos-btn-giant sos-btn-orange" id="sos-btn-nearby" type="button">
            <span style="font-size:18px;">📢</span>
            <span>呼叫周边 50 米内工友就近增援</span>
          </button>

          <!-- 4. 撤销 -->
<button class="sos-btn-giant sos-btn-gray" id="sos-btn-cancel" type="button" style="border-color:#ffa39e;color:#cf1322;">
            <span>✕ 误触撤销 / 现场演练测试完成</span>
          </button>
        </div>

        <div style="text-align:center;font-size:11px;color:#8c9bb0;padding:4px 0 16px 0;">
          安全第一 · 遇险请优先通过智能安全帽实体 SOS 键或本界面一键呼救
        </div>
      </div>
    `;
    phone.appendChild(sosModal);

    // 3. 绑定内部按钮
    document.getElementById('sos-close-btn').onclick = closeSosModal;
    document.getElementById('sos-btn-cancel').onclick = () => {
      alert('已撤销本次 SOS 紧急求助，已记录为“现场演练测试”，报警已复位。');
      closeSosModal();
    };

    document.getElementById('sos-btn-call').onclick = () => {
      alert('📞 正在以最高抢占优先级直拨厂区应急值班室…\n【已接通！】已向值班调度员通报：陈建国在 1号机组汽机房 发起紧急求助！');
    };

    document.getElementById('sos-btn-video').onclick = () => {
      alert('📹 智能安全帽突发险情上行视频流已建立！\n现场画面已实时分发推送至厂区集中控制室应急指挥大屏！');
    };

    document.getElementById('sos-btn-nearby').onclick = () => {
      alert('📢 已触发周边协作人员蜂鸣联动！\n已向周边 50 米内李志远、周明智能安全帽下发强震动与就近救援广播！');
    };


    // 4. 外壳原生返回键监听
    window.addEventListener('rolling-preview-back', function (e) {
      if (sosModal && sosModal.classList.contains('active')) {
        e.stopImmediatePropagation();
        e.preventDefault();
        closeSosModal();
      }
    }, true);
  }

  function openSosModal() {
    if (!sosModal) return;
    sosModal.classList.add('active');
    const topBanner = document.querySelector('.lead-hud-banner');
    if (topBanner) topBanner.style.opacity = '0';
  }

  function closeSosModal() {
    if (!sosModal) return;
    sosModal.classList.remove('active');
    const topBanner = document.querySelector('.lead-hud-banner');
    if (topBanner) topBanner.style.opacity = '1';
  }

  // 暴露全局入口
  window.triggerEmergencySOS = openSosModal;
  window.closeEmergencySOS = closeSosModal;

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initSOS);
  } else {
    initSOS();
  }
})();
