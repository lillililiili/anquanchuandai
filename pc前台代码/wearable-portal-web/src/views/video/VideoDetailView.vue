<script setup>
import IntercomEntry from '@intercom-entry'
import ContactEntry from '@contact-entry'
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { useVideoWorkspace } from '@/composables/useVideoWorkspace'
import { safeVideoReturn } from '@/utils/video-route'
import { personIdPattern } from '@/utils/portal-route'
import WorkspaceState from '@/components/spatial/WorkspaceState.vue'
import VideoPlayer from '@portal-video-player'
import { enabled as localMode } from '@spatial-actions'
import VideoRelated from '@/components/video/VideoRelated.vue'
const route = useRoute(), deviceId = computed(() => personIdPattern.test(String(route.params.deviceId)) ? String(route.params.deviceId) : '')
const { context, user, siteId, availableSite, detail, reloadDetail } = useVideoWorkspace(deviceId)
const returnTo = computed(() => safeVideoReturn(route.query.returnTo))
const canTrack = computed(() => user.permissions.includes('*:*:*') || user.permissions.includes('portal:track:read'))
</script>
<template>
  <div class="video-workspace single-monitor-page">
    <header class="video-heading">
      <div><router-link :to="returnTo">← 返回来源页面</router-link><h1>单路监看</h1></div>
      <button class="video-button" :disabled="!availableSite || detail.state === 'LOADING'" @click="reloadDetail">刷新详情</button>
    </header>
    <WorkspaceState :context="context" :site-id="siteId" :available-site="availableSite" :query="detail" @retry="reloadDetail">
      <div v-if="detail.data" class="monitor-layout single-video">
          <section class="monitor-card monitor-toolbar" aria-label="监看辅助操作">
            <h2>远程指导</h2>
            <div class="monitor-commands">
              <IntercomEntry :site-id="siteId" :device-id="deviceId" />
              <ContactEntry :site-id="siteId" :device-id="deviceId" />
              <IntercomEntry :site-id="siteId" :device-id="deviceId" mode="VIDEO" />
            </div>
            <p class="video-note">通信服务未接入，本地会话不代表设备接通。</p>
            <div class="monitor-track">
              <router-link v-if="canTrack" class="video-button" :to="{ path: '/location', query: { tab: 'tracks', siteId, deviceId } }">查看轨迹</router-link>
              <button v-else class="video-button" disabled title="无轨迹读取权限">查看轨迹</button>
              <p class="video-note">按设备查看历史轨迹。</p>
            </div>
          </section>
        <section class="monitor-stage" aria-label="视频监看">
          <VideoPlayer :key="siteId + deviceId + user.token" :device="detail.data.device" :capture-enabled="localMode" />
          <div v-if="!localMode" class="video-actions">
            <button v-for="label in ['播放', '声音', '抓拍', '录像']" :key="label" class="video-button" disabled title="真实媒体及设备控制未开放">{{ label }}</button>
          </div>
          <p class="video-note monitor-footnote">{{ localMode ? '本地抓拍及录像保存后，可在现场资料中查看。' : '真实媒体及设备控制未接入。' }}</p>
        </section>
          <section class="monitor-card monitor-resources">
            <h2>相关记录</h2>
            <details>
              <summary>关联告警</summary>
              <VideoRelated title="关联告警" :section="detail.data.events" />
            </details>
            <details>
              <summary>最近资料</summary>
              <VideoRelated title="最近资料" :section="detail.data.materials" />
              <p class="video-note">{{ localMode ? '本地生成文件请到现场资料预览。' : '仅显示授权元数据，文件访问未开放。' }}</p>
            </details>
          </section>
      </div>
    </WorkspaceState>
  </div>
</template>
<style scoped>
.single-monitor-page { min-width:0; }
.monitor-layout { display:flex; flex-direction:column; gap:14px; min-width:0; }
.monitor-stage { min-width:0; padding:14px; border:1px solid var(--border); border-radius:12px; background:var(--panel-bg); }
.monitor-toolbar { display:flex; align-items:center; flex-wrap:wrap; gap:12px 18px; }
.monitor-card.monitor-toolbar h2 { margin:0; }
.monitor-toolbar > .video-note { flex-basis:100%; margin:0; order:3; }
.monitor-toolbar .monitor-commands { display:flex; flex-wrap:wrap; gap:10px; }
.monitor-toolbar .monitor-track { display:flex; align-items:center; gap:10px; margin:0 0 0 auto; padding:0; border:0; }
.monitor-toolbar .monitor-track .video-button { width:auto; }
.monitor-toolbar .monitor-track .video-note { margin:0; }
.monitor-card { padding:20px; border:1px solid var(--border); border-radius:12px; background:var(--panel-bg); min-width:0; }
.monitor-card h2 { margin:0 0 16px; font-size:16px; line-height:1.5; }
.monitor-commands { display:grid; gap:10px; }
.single-monitor-page :deep(.video-button), .monitor-commands :deep(.dispatch-entry) { min-height:44px; box-sizing:border-box; border-radius:6px; }
.monitor-commands :deep(.dispatch-entry) { display:flex; align-items:center; justify-content:center; margin:0; padding:8px 12px; line-height:1.5; }
.monitor-track { margin-top:18px; padding-top:18px; border-top:1px solid var(--border); }
.monitor-track .video-button { width:100%; }
.single-monitor-page .video-note { font-size:12px; line-height:1.8; overflow-wrap:anywhere; }
.monitor-footnote { margin:12px 0 0; padding-top:12px; border-top:1px solid var(--border); }
.monitor-stage :deep(.video-player:not(:fullscreen)) { aspect-ratio:auto; height:clamp(280px, 58vh, 680px); min-height:240px; border-radius:8px; }
.monitor-stage :deep(.mock-play-controls) { padding:12px 0 4px; gap:10px; }
.monitor-stage :deep(.mock-monitor > .video-note) { padding:0; margin:8px 0; }
.monitor-resources details + details { border-top:1px solid var(--border); }
.monitor-resources summary { padding:14px 0; cursor:pointer; color:var(--text-secondary); font-size:14px; }
.monitor-resources summary:hover { color:var(--cyan); }
.monitor-resources summary:focus-visible { outline:2px solid var(--cyan); outline-offset:3px; }
.monitor-resources :deep(.video-related) { border:0; border-radius:0; padding:0 0 12px; background:transparent; box-shadow:none; }
.monitor-resources :deep(.video-related > h3) { display:none; }
@media (max-width:1100px) {
  .monitor-toolbar .monitor-track { margin-left:0; }
}
@media (max-width:600px) {
  .monitor-stage, .monitor-card { padding:12px; }
  .monitor-toolbar .monitor-commands { width:100%; }
  .monitor-stage :deep(.video-player:not(:fullscreen)) { min-height:220px; aspect-ratio:auto; }
}
</style>
