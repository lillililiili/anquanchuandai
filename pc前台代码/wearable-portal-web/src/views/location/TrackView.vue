<script setup>
import { computed, reactive, ref, watch, onMounted, onBeforeUnmount } from 'vue'
import { useS2Workspace } from '@/composables/useS2Workspace'
import { getTracks } from '@/api/spatial'
import { trackGeometry } from '@/utils/spatial-contract'
import { formatTime } from '@/utils/portal-contract'
import { createTrackPlayer } from '@/utils/track-player'
import { useWorkspaceStore } from '@/store/workspace'
import VectorMap from '@/components/spatial/VectorMap.vue'
import WorkspaceState from '@/components/spatial/WorkspaceState.vue'
import DevicePicker from '@/components/spatial/DevicePicker.vue'
const { route, router, context, list, query, siteId, availableSite, reload, search } = useS2Workspace('tracks', getTracks)
const workspace = useWorkspaceStore()
const defaultRange = () => {
  const to = new Date(Math.ceil(Date.now() / 60000) * 60000)
  return { from: new Date(to.getTime() - 24 * 60 * 60000).toISOString(), to: to.toISOString() }
}
const filters = reactive({ deviceId: '', from: '', to: '' }), error = ref(''), active = ref(null), index = ref(0), playing = ref(false), speed = ref('1')
watch([query, availableSite, siteId], ([q]) => {
  const range = q.from && q.to ? q : defaultRange()
  const deviceId = q.deviceId || (workspace.selection.siteId === siteId.value ? workspace.selection.deviceId : '') || ''
  filters.deviceId = deviceId; filters.from = range.from.slice(0, 16); filters.to = range.to.slice(0, 16)
  if (availableSite.value && deviceId && (!q.deviceId || !q.from || !q.to)) {
    router.replace({ path: route.path, query: { ...route.query, deviceId, siteId: siteId.value, from: range.from, to: range.to } })
  }
}, { immediate: true })
const track = computed(() => list.data?.state === 'AVAILABLE' ? list.data.data : null)
const geometry = computed(() => trackGeometry(track.value))
const playbackPoints = computed(() => geometry.value.points.filter(p => p.sourceTime))
const player = createTrackPlayer((p, i, running) => { active.value = p; index.value = i; playing.value = running })
watch(playbackPoints, points => player.load(points), { immediate: true })
watch(speed, v => player.speed(v))
function hidden() { if (document.hidden) player.pause() }
onMounted(() => document.addEventListener('visibilitychange', hidden))
onBeforeUnmount(() => { document.removeEventListener('visibilitychange', hidden); player.dispose() })
function submit() {
  error.value = ''
  if (!filters.deviceId || !filters.from || !filters.to || Date.parse(filters.from + 'Z') >= Date.parse(filters.to + 'Z')) { error.value = '请选择设备及有效的起止时间'; return }
  player.stop()
  const values = { deviceId: filters.deviceId, from: new Date(filters.from + 'Z').toISOString(), to: new Date(filters.to + 'Z').toISOString(), personId: filters.deviceId === query.value.deviceId ? query.value.personId : undefined }
  workspace.select(siteId.value, filters.deviceId)
  if (query.value.deviceId === values.deviceId && query.value.from === values.from && query.value.to === values.to) reload(); else search(values)
}
</script>
<template>
  <form class="s2-filterbar" @submit.prevent="submit"><DevicePicker v-model="filters.deviceId" :site-id="siteId" :enabled="availableSite" /><label>开始时间（UTC）<input v-model="filters.from" type="datetime-local" :disabled="!availableSite" /></label><label>结束时间（UTC）<input v-model="filters.to" type="datetime-local" :disabled="!availableSite" /></label><el-button native-type="submit" type="primary" :disabled="!availableSite || list.state === 'LOADING'">查询轨迹</el-button><el-button disabled title="轨迹导出暂未开放">导出轨迹</el-button></form><p class="s2-note">默认查询最近 24 小时，可调整时间范围；时间统一为 UTC。</p><p v-if="error" class="s2-error" role="alert">{{ error }}</p>
  <div class="s2-location-grid"><section class="s2-panel s2-list"><h2>轨迹片段与缺口</h2><WorkspaceState :context="context" :available-site="availableSite" :site-id="siteId" :query="list" idle="请选择设备和时间后查询" @retry="reload"><template v-if="track"><p class="s2-note">{{ track.attribution === 'CONFIRMED' ? '历史归属已确认' : '历史归属未知' }}</p><p v-if="!track.complete" class="s2-warning">结果不完整：{{ track.incompleteReason }}</p><article v-for="s in track.segments" :key="s.segmentId" class="s2-segment"><h3>{{ s.continuity === 'CONFIRMED' ? '来源确认片段' : '连续性未知 · 仅离散点' }}</h3><p>{{ s.points.length }} 个源采样点</p><small>{{ formatTime(s.points[0]?.sourceTime) }}<br />至 {{ formatTime(s.points.at(-1)?.sourceTime) }}</small></article><article v-for="(gap, i) in track.gaps" :key="i" class="s2-segment s2-warning"><h3>数据缺口</h3><p>{{ formatTime(gap.from) }}<br />至 {{ formatTime(gap.to) }}</p><small>{{ gap.reason || '缺口原因未知' }}，不插值连线</small></article><p v-if="!track.segments.length" class="s2-note">该时段暂无轨迹记录</p></template></WorkspaceState><div class="s2-note">事件节点待接入<br /><el-button disabled title="事件来源尚未接入">查看核验</el-button></div></section><div class="s2-map-column"><VectorMap trajectory :points="geometry.points" :lines="geometry.lines" :active="active" /><section class="s2-panel s2-playback"><h2>轨迹回放 <small>沿轨迹采样点回放</small></h2><label>当前采样点<input type="range" min="0" :max="Math.max(0, playbackPoints.length - 1)" :value="index" :disabled="!playbackPoints.length" @input="player.seek($event.target.value)" /></label><div class="s2-actions"><el-button :disabled="!playbackPoints.length" type="primary" @click="playing ? player.pause() : player.play()">{{ playing ? '暂停' : '播放' }}</el-button><el-button :disabled="!playbackPoints.length" @click="player.stop()">停止</el-button><label>倍速<select v-model="speed"><option>1</option><option>2</option><option>4</option></select></label><span>{{ formatTime(active?.sourceTime) }} · {{ playbackPoints.length ? index + 1 : '—' }} / {{ playbackPoints.length || '—' }}</span></div><p class="s2-note">无源时间的点不参与回放；缺口不补点，片段之间不连线。</p></section></div></div>
</template>
