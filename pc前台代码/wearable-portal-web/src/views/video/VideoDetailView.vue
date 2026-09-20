<script setup>
import ContactEntry from '@contact-entry'
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { useVideoWorkspace } from '@/composables/useVideoWorkspace'
import { safeVideoReturn } from '@/utils/video-route'
import { personIdPattern } from '@/utils/portal-route'
import WorkspaceState from '@/components/spatial/WorkspaceState.vue'
import DataState from '@/components/personnel/DataState.vue'
import VideoPlayer from '@portal-video-player'
import { enabled as localMode } from '@spatial-actions'
import VideoRelated from '@/components/video/VideoRelated.vue'
import VideoEquipment from '@/components/video/VideoEquipment.vue'
import VideoDeviceInfo from '@/components/video/VideoDeviceInfo.vue'
const route = useRoute(), deviceId = computed(() => personIdPattern.test(String(route.params.deviceId)) ? String(route.params.deviceId) : '')
const { context, user, siteId, availableSite, detail, reloadDetail } = useVideoWorkspace(deviceId)
const returnTo = computed(() => safeVideoReturn(route.query.returnTo))
const canTrack = computed(() => user.permissions.includes('*:*:*') || user.permissions.includes('portal:track:read'))
</script>
<template><div class="video-workspace"><header class="video-heading"><div><router-link :to="returnTo">← 返回来源页面</router-link><h1>单路监看</h1></div><button class="video-button" :disabled="!availableSite || detail.state === 'LOADING'" @click="reloadDetail">刷新详情</button></header>
  <WorkspaceState :context="context" :site-id="siteId" :available-site="availableSite" :query="detail" @retry="reloadDetail"><div v-if="detail.data" class="video-columns single-video"><div class="video-primary"><VideoPlayer :key="siteId + deviceId + user.token" :device="detail.data.device" :capture-enabled="localMode" /><div class="video-actions"><button v-for="label in (localMode ? ['发起通话'] : ['播放', '声音', '抓拍', '录像', '发起通话'])" :key="label" class="video-button" disabled :title="label === '发起通话' ? '真实通信未接入；本地协同使用右侧联系协助入口' : '真实媒体及设备控制未开放'">{{ label }}</button><router-link v-if="canTrack" class="video-button" :to="{ path: '/location', query: { tab: 'tracks', siteId, deviceId } }">查看轨迹</router-link><button v-else class="video-button" disabled title="无轨迹读取权限">查看轨迹</button></div><p class="video-note">{{ localMode ? '本地媒体，保存后可在现场资料查看；历史轨迹不推定佩戴人。' : '抓拍、录像、播放未开放；历史轨迹不使用当前绑定推定佩戴人。' }}</p><VideoDeviceInfo :device="detail.data.device" /><div class="video-summary-grid"><VideoRelated title="关联人员" :section="detail.data.person" person-links :site-id="siteId" :return-to="route.fullPath" /><VideoEquipment :section="detail.data.equipment" /><VideoRelated title="关联作业" :section="detail.data.works" /><VideoRelated title="位置摘要" :section="detail.data.location" /></div></div><aside class="video-aside"><h2>远程指导</h2><ContactEntry :site-id="siteId" :device-id="deviceId" /><DataState state="NOT_INTEGRATED" message="真实通信未接入，本地协同使用联系协助入口" compact /><button class="video-button" disabled title="真实音视频与设备控制仍未接入">发起音视频通话</button><p class="video-note">真实通话未开放；本地协同在统一会话页查看，不代表设备接通。</p><VideoRelated title="关联事件" :section="detail.data.events" /><button class="video-button" disabled title="事件目标页面尚未开放">查看事件</button><VideoRelated title="最近资料" :section="detail.data.materials" /><p class="video-note">{{ localMode ? '元数据仅列明确来源；本地生成文件请到现场资料预览。' : '仅显示授权元数据；原图、播放、下载及引用未开放。' }}</p></aside></div></WorkspaceState>
</div></template>
