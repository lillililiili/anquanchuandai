<script setup>
import { sceneFor } from '@/utils/demo-scenes'
import { computed, reactive, ref, watch, onBeforeUnmount } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { usePortalQuery } from '@/composables/usePortalQuery'
import { useVideoWorkspace } from '@/composables/useVideoWorkspace'
import { useBusinessRevision } from '@/composables/useBusinessRevision'
import { getVideoSources } from '@/api/video'
import { videoQuery, layouts } from '@/utils/video-route'
import { wallSlots } from '@/utils/video-contract'
import WorkspaceState from '@/components/spatial/WorkspaceState.vue'
import DataState from '@/components/personnel/DataState.vue'
import VideoPlayer from '@portal-video-player'
import { enabled as localMode } from '@spatial-actions'
import VideoRelated from '@/components/video/VideoRelated.vue'
import VideoEquipment from '@/components/video/VideoEquipment.vue'
import VideoDeviceInfo from '@/components/video/VideoDeviceInfo.vue'
const router = useRouter(), route = useRoute(), list = reactive(usePortalQuery())
const query = computed(() => videoQuery(route.query)), selectedId = computed(() => query.value.selectedId || '')
const { context, user, siteId, availableSite, detail, reloadDetail } = useVideoWorkspace(selectedId)
const layout = computed(() => query.value.layout || '1+7'), keyword = ref(''), carousel = ref(false)
const params = computed(() => ({ siteId: siteId.value, keyword: query.value.keyword, areaId: query.value.areaId, workId: query.value.workId, pageNum: Number(query.value.pageNum || 1), pageSize: Number(query.value.pageSize || (layout.value === '3x3' ? 9 : 8)) }))
const items = computed(() => list.data?.items || []), slots = computed(() => wallSlots(items.value, selectedId.value, layout.value))
const selected = computed(() => items.value.find(d => d.deviceId === selectedId.value))
let carouselTimer
function stopCarousel() { clearInterval(carouselTimer); carouselTimer = null; carousel.value = false }
function select(id, manual = true) { if (manual) stopCarousel(); router.replace({ path: '/video', query: { ...query.value, siteId: siteId.value, selectedId: id } }) }
function toggleCarousel() { if (carousel.value) return stopCarousel(); if (items.value.length < 2) return; carousel.value = true; carouselTimer = setInterval(() => { if (!document.hidden && items.value.length) select(items.value[(items.value.findIndex(d => d.deviceId === selectedId.value) + 1) % items.value.length].deviceId, false) }, 30000) }
function patch(values, clearSelection = true) { stopCarousel(); const q = { ...query.value, siteId: siteId.value, ...values }; if (clearSelection) delete q.selectedId; router.push({ path: '/video', query: videoQuery(q) }) }
async function reload() {
  stopCarousel(); detail.clear()
  if (!availableSite.value) { list.clear(); return }
  await list.run(s => getVideoSources(params.value, s))
  if (list.state === 'READY' && items.value.length && !selectedId.value) select(items.value[0].deviceId, false)
  else if (list.state === 'READY' && selectedId.value && selected.value) reloadDetail()
}
watch(() => JSON.stringify([params.value, availableSite.value, user.token]), reload, { immediate: true })
useBusinessRevision(['video'], reload)
watch(() => query.value.keyword, v => { keyword.value = v || '' }, { immediate: true })
watch(layout, stopCarousel)
const visibility = () => { if (document.hidden) stopCarousel() }
document.addEventListener('visibilitychange', visibility)
onBeforeUnmount(() => { stopCarousel(); document.removeEventListener('visibilitychange', visibility) })
</script>

<template>
  <div class="video-workspace">
    <p v-if="selectedId && list.state === 'READY' && !selected" class="video-note" role="status">所选设备不在当前页或没有可用的视频映射，未替换为第一台设备。可调整分页/筛选或明确选择另一台设备。</p>
    <header class="video-heading"><div><h1>现场视频墙</h1><p>授权设备视角 · 只读元数据与监看基础</p></div><dl class="video-statistics"><div v-for="(label, key) in { devices: '授权设备总数', available: '来源确认可用', interrupted: '来源报告中断', notStarted: '来源报告未开启' }" :key="key"><dt>{{ label }}</dt><dd>{{ list.data?.statistics.state === 'AVAILABLE' ? list.data.statistics.data[key] : '待接入' }}</dd></div></dl></header>
    <form class="video-toolbar" @submit.prevent="patch({ keyword, pageNum: '1' })"><span>布局切换</span><div role="group" aria-label="视频墙布局"><button v-for="value in layouts" :key="value" type="button" class="video-button" :aria-pressed="layout === value" @click="patch({ layout: value, pageSize: value === '3x3' ? '9' : '8', pageNum: '1' })">{{ value.replace('x', '×') }}</button></div><label>区域<select :value="query.areaId || ''" :disabled="list.data?.filters.areas.state !== 'AVAILABLE'" @change="patch({ areaId: $event.target.value, pageNum: '1' })"><option value="">{{ list.data?.filters.areas.state === 'AVAILABLE' ? '全部授权区域' : '区域待接入' }}</option><option v-for="o in list.data?.filters.areas.data || []" :key="o.id" :value="o.id">{{ o.name }}</option></select></label><label>作业<select :value="query.workId || ''" :disabled="list.data?.filters.works.state !== 'AVAILABLE'" @change="patch({ workId: $event.target.value, pageNum: '1' })"><option value="">{{ list.data?.filters.works.state === 'AVAILABLE' ? '全部授权作业' : '作业待接入' }}</option><option v-for="o in list.data?.filters.works.data || []" :key="o.id" :value="o.id">{{ o.name }}</option></select></label><label class="video-search">设备<input v-model="keyword" maxlength="100" placeholder="名称 / 标识" :disabled="!availableSite"></label><button class="video-button" :disabled="!availableSite">查询</button><button type="button" class="video-button" :disabled="items.length < 2" :aria-pressed="carousel" @click="toggleCarousel">{{ carousel ? '停止轮播' : '开启轮播' }}</button><small>30 秒 / {{ carousel ? '已开启' : '已关闭' }}</small></form>
    <WorkspaceState :context="context" :site-id="siteId" :available-site="availableSite" :query="list" @retry="reload">
      <DataState v-if="!items.length" state="EMPTY" message="当前筛选范围暂无授权视频设备" />
      <template v-else>
        <div class="video-columns"><div class="video-grid" :class="'layout-' + layout.replace('+', '-').replace('x', '-')" :key="siteId + layout + selectedId + user.token">
          <div v-for="(device, i) in slots" :key="device?.deviceId || 'empty-' + i" class="video-slot" :class="{ 'is-main': i === 0, 'is-selected': device?.deviceId === selectedId }"><VideoPlayer :device="device" :compact="layout !== '1+7' || i > 0" /><button v-if="device" class="video-slot-select" :aria-pressed="device.deviceId === selectedId" @click="select(device.deviceId)">{{ device.deviceCode || device.deviceId }} · 选择设备</button></div>
        </div><aside class="video-aside"><h2>当前选中设备</h2><DataState v-if="detail.state === 'LOADING'" state="LOADING" compact /><DataState v-else-if="detail.error" :state="detail.state" :message="detail.error.message" retry @retry="reloadDetail" /><template v-else-if="detail.data"><VideoDeviceInfo :device="detail.data.device" /><VideoRelated title="关联人员" :section="detail.data.person" person-links :site-id="siteId" :return-to="route.fullPath" /><VideoEquipment :section="detail.data.equipment" /><VideoRelated title="关联作业" :section="detail.data.works" /></template><DataState v-else state="IDLE" message="请选择设备" compact /><div class="video-actions"><button v-if="!localMode" class="video-button" disabled title="真实媒体访问未开放">声音 / 播放</button><button class="video-button" disabled title="通信会话留待 S6 接入">发起对讲</button><router-link v-if="selected" class="video-button" :to="{ path: '/video/' + selectedId, query: { siteId, returnTo: route.fullPath } }">单路监看</router-link></div><p class="video-note">{{ localMode ? '各画面手动播放；抓拍录像请进入单路监看。对讲尚未接入。' : '声音与播放未开放；对讲留待通信阶段接入。' }}</p></aside></div>
        <section v-if="layout === '1+7'" class="video-device-strip"><h2>当前页设备 <small>主画面与设备条共用设备标识，不重复拉流</small></h2><div><button v-for="device in items" :key="device.deviceId" class="video-device-tab" :aria-pressed="device.deviceId === selectedId" @click="select(device.deviceId)"><img class="device-scene-thumb" :src="sceneFor(device.deviceId).image" alt="AI 场景示意" loading="lazy" /><strong>{{ device.name }}</strong><span>{{ device.deviceCode || device.deviceId }}</span><small>{{ localMode ? '本地媒体 · 不自动播放' : '媒体未开放' }}</small></button></div></section>
        <AppPagination :current-page="params.pageNum" :page-size="params.pageSize" :total="list.data.total" @current-change="patch({ pageNum: String($event) })" />
      </template>
    </WorkspaceState>
    <p class="video-note">本阶段不建立真实拉流、RTC 或设备命令连接。来源流状态、设备通信状态和本机播放状态分别表达。</p>
  </div>
</template>
