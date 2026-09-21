<script setup>
import DemoScene from '@/components/DemoScene.vue'
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute } from 'vue-router'
import { ElMessageBox } from 'element-plus'
import { useUserStore } from '@/store/user'
import { useContextStore } from '@/store/context'
import { useWorkspaceStore } from '@/store/workspace'
import { capabilityDecision } from '@/utils/device-profile'
import { createVideoPlayer, playerLabels } from '@/utils/video-player'
import { createMediaAdapter } from '@/utils/video-adapters'
import { formatTime } from '@/utils/portal-contract'
import { mockMediaProvider } from './video-provider'
import { captureImage, recordMedia, recorderType } from './video-capture'
import { command } from './spatial-provider'
import request from './request'
const props = defineProps({ device: { type: Object, default: null }, compact: Boolean, captureEnabled: Boolean })
const user = useUserStore(), context = useContextStore(), workspace = useWorkspaceStore(), route = useRoute()
const media = ref(null), panel = ref(null), state = ref({ state: 'IDLE', muted: true }), recording = ref(false), seconds = ref(0), pending = ref(null), busy = ref(false), error = ref(''), saved = ref('')
const previewUrl = ref('')
watch(pending, value => { if (previewUrl.value) URL.revokeObjectURL(previewUrl.value); previewUrl.value = value ? URL.createObjectURL(value.blob) : '' }, { flush: 'sync' })
const captureReason = computed(() => !captureAccess.value.allowed ? captureAccess.value.reason : !videoAccess.value.allowed ? videoAccess.value.reason : pending.value ? '请先保存或丢弃已生成的媒体' : recording.value ? '请先停止录像' : '')
const recordReason = computed(() => !recordAccess.value.allowed ? recordAccess.value.reason : !videoAccess.value.allowed ? videoAccess.value.reason : !canRecord ? '浏览器不支持本地录像' : pending.value ? '请先保存或丢弃已生成的媒体' : recording.value ? '正在录像' : '')
let player, recorder, controller = new AbortController(), generation = 0
const siteId = computed(() => String(route.query.siteId || context.selectedSiteId || ''))
const access = key => capabilityDecision(props.device, key, { mock: true, permitted: key === 'video' ? user.permissions.includes('portal:video:read') || user.permissions.includes('*:*:*') : user.roles.includes('owner'), moduleEnabled: true })
const videoAccess = computed(() => access('video')), captureAccess = computed(() => access('capture')), recordAccess = computed(() => access('record'))
const canRecord = !!recorderType() && !!HTMLCanvasElement.prototype.captureStream
const advancing = computed(() => state.value.state === 'PLAYING')
function discard() { recorder?.dispose(); recorder = null; recording.value = false; pending.value = null }
function clean() { generation++; controller.abort(); controller = new AbortController(); discard(); player?.pause(); busy.value = false; saved.value = ''; error.value = '' }
async function leave() {
  if (!user.token) { clean(); return true }
  if (busy.value) return false
  if (!pending.value && !recording.value) return true
  try { await ElMessageBox.confirm('未保存的本地录像或抓拍将丢弃，不会自动生成资料。', '放弃未保存媒体？', { confirmButtonText: '丢弃并离开', cancelButtonText: '继续查看', closeOnHashChange: false }); clean(); return true } catch { return false }
}
onBeforeRouteLeave(leave); onBeforeRouteUpdate(leave)
const hidden = () => { if (document.hidden) { clean(); error.value = '页面隐藏，已释放媒体并丢弃未保存内容；返回后请手动播放。' } }
const unload = e => { if (pending.value || recording.value) { e.preventDefault(); e.returnValue = '' } }
onMounted(() => {
  player = createVideoPlayer({ media: media.value, provider: mockMediaProvider, createAdapter: createMediaAdapter, context: () => ({ siteId: siteId.value, deviceId: props.device?.deviceId }), onChange: value => { state.value = value; if (recording.value && ['ERROR', 'INTERRUPTED', 'FORBIDDEN', 'NOT_INTEGRATED'].includes(value.state)) { discard(); error.value = '画面中断，未保存录像已丢弃' } } })
  document.addEventListener('visibilitychange', hidden); window.addEventListener('beforeunload', unload)
})
watch(() => [props.device?.deviceId, props.device?.profile?.privacy, siteId.value, user.token], clean)
onBeforeUnmount(() => { clean(); player?.destroy(); document.removeEventListener('visibilitychange', hidden); window.removeEventListener('beforeunload', unload) })
async function play() { if (!videoAccess.value.allowed || busy.value || pending.value || recording.value) return; error.value = ''; media.value.loop = true; await player.start() }
async function fullscreen() { if (!await player.fullscreen(panel.value)) error.value = '浏览器拒绝全屏，请使用窗口查看' }
function stage(blob, method) { pending.value = { blob, method, generatedAt: new Date().toISOString(), operationId: crypto.randomUUID(), deviceId: props.device.deviceId, siteId: siteId.value }; saved.value = '' }
async function ensurePlayback(signal) {
  if (advancing.value) return
  media.value.loop = true
  await new Promise((resolve, reject) => {
    let unwatch
    const finish = failure => { clearTimeout(timer); unwatch?.(); signal.removeEventListener('abort', abort); failure ? reject(failure) : resolve() }
    const abort = () => finish(new Error('操作已取消'))
    const timer = setTimeout(() => finish(new Error('视频未能开始播放，请重试')), 10000)
    unwatch = watch(() => state.value.state, value => {
      if (value === 'PLAYING') finish()
      else if (['ERROR', 'FORBIDDEN', 'NOT_INTEGRATED', 'INTERRUPTED'].includes(value)) finish(new Error(state.value.reason || '画面不可用，请重试'))
    }, { flush: 'sync' })
    signal.addEventListener('abort', abort, { once: true })
    if (signal.aborted) abort()
    else if (state.value.state !== 'CONNECTING') player.start().catch(finish)
  })
}
async function capture() {
  if (captureReason.value || busy.value) return
  const current = generation; busy.value = true; error.value = ''
  try {
    await ensurePlayback(controller.signal)
    if (generation !== current) return
    const blob = await captureImage(media.value)
    if (generation === current) stage(blob, 'MOCK_CAPTURE')
  } catch (e) { if (generation === current) error.value = e.message }
  finally { if (generation === current) busy.value = false }
}
async function record() {
  if (recordReason.value || busy.value) return
  const current = generation; busy.value = true; error.value = ''; seconds.value = 0
  try {
    await ensurePlayback(controller.signal)
    if (generation !== current) return
    recorder = recordMedia(media.value,
      blob => { if (generation === current) { recording.value = false; stage(blob, 'MOCK_RECORD') } },
      e => { if (generation === current) { recording.value = false; error.value = e.message } },
      n => { if (generation === current) seconds.value = n })
    recording.value = true
  } catch (e) { if (generation === current) error.value = e.message }
  finally { if (generation === current) busy.value = false }
}
async function save() {
  if (!pending.value || busy.value) return
  const target = pending.value, signal = controller.signal
  busy.value = true; error.value = ''
  try {
    const ext = target.method === 'MOCK_CAPTURE' ? 'png' : 'webm'
    const result = await command('material-import', { siteId: target.siteId, deviceId: target.deviceId, generationMethod: target.method, generatedAt: target.generatedAt, capturedAt: null, operationId: target.operationId, file: new File([target.blob], `本地${ext === 'png' ? '抓拍' : '录像'}-${target.deviceId}.${ext}`, { type: target.blob.type }), name: `本地${ext === 'png' ? '抓拍' : '录像'}-${target.deviceId}.${ext}` }, signal)
    if (!signal.aborted) { saved.value = result.data.id; pending.value = null }
  } catch (e) { if (!signal.aborted) error.value = e.message } finally { if (!signal.aborted) busy.value = false }
}
async function privacy() {
  if (!user.roles.includes('owner') || busy.value) return
  const target = { siteId: siteId.value, deviceId: props.device.deviceId, expectedPrivacy: props.device.profile.privacy, privacy: props.device.profile.privacy === 'ON' ? 'OFF' : 'ON' }
  if (!await leave()) return
  clean(); const signal = controller.signal; busy.value = true
  try { const r = await request.post('/mock-video/privacy', target, { signal }); if (!signal.aborted) workspace.invalidate(r.data.changedEntities) } catch (e) { if (!signal.aborted) error.value = e.message } finally { if (!signal.aborted) busy.value = false }
}
</script>
<template>
  <div class="mock-monitor" :class="{ compact }">
    <section ref="panel" class="video-player" :class="{ compact }" aria-label="本地监看面板">
      <DemoScene v-if="!state.lastDisplayedAt || ['PAUSED', 'ERROR', 'NOT_INTEGRATED'].includes(state.state)" :identity="device?.deviceId || device?.name" />
      <video ref="media" muted playsinline preload="none" aria-label="本地视频画面" />
      <header><span>{{ device?.name || '未分配' }}</span><span class="video-tag">{{ device ? playerLabels[state.state] : '未分配槽位' }}</span></header>
      <div v-if="!state.lastDisplayedAt || ['PAUSED', 'ERROR', 'NOT_INTEGRATED'].includes(state.state)" class="video-screen-message"><strong>本地视频 · 非现场画面</strong><span>{{ !device ? '未分配监看设备' : !videoAccess.allowed ? videoAccess.reason : state.reason || '点击播放本地合成视频，不连接设备' }}</span></div>
      <footer><small v-if="!compact">源拍摄时间：未知<br>本机最后显示：{{ state.lastDisplayedAt ? formatTime(state.lastDisplayedAt) : '尚无画面' }}</small><button class="video-button" aria-label="全屏本地监看面板" @click="fullscreen">全屏</button></footer>
    </section>
    <div v-if="device" class="mock-play-controls">
      <button class="video-button" :disabled="!videoAccess.allowed || busy || !!pending || recording || state.state === 'CONNECTING'" @click="play">{{ ['ERROR', 'INTERRUPTED'].includes(state.state) ? '重试本地播放' : '播放本地视频' }}</button>
      <button class="video-button" :disabled="!advancing || recording" @click="player.pause()">暂停</button>
      <button v-if="!compact" class="video-button" :aria-pressed="state.muted" @click="player.mute(!state.muted)">{{ state.muted ? '取消静音' : '静音' }}</button>
    </div>
    <template v-if="captureEnabled && device">
      <p class="video-note">仅本地合成片段，无声音；播放状态不代表设备在线。抓拍/录像不等于设备远程拍摄或设备本地录像。</p>
      <div class="mock-play-controls"><button class="video-button" :disabled="!!captureReason || busy" :title="captureReason || '自动播放本地视频并抓拍'" @click="capture">预置抓拍</button><button class="video-button" :disabled="!!recordReason || busy" :title="recordReason || '自动播放本地视频并开始录像'" @click="record">开始预置录像</button><button v-if="recording" class="video-button" @click="recorder.stop()">停止录像</button><span v-if="recording" role="status">录像中 {{ seconds }} / 60 秒 · 最多50MB</span><button class="video-button" :disabled="!user.roles.includes('owner') || busy" @click="privacy">本地隐私上报：{{ device.profile?.privacy === 'ON' ? '关闭' : '开启' }}</button></div>
      <p class="video-note">抓拍：{{ captureReason || '点击后自动播放并生成图片' }}；录像：{{ recordReason || '点击开始，停止后可预览和保存，最长60秒' }}。隐私仅本地上报，不发送远程开关。</p>
      <p v-if="busy" role="status" class="video-note">正在处理，请稍候…</p>
      <section v-if="pending" class="mock-pending" aria-label="待保存媒体"><img v-if="pending.method === 'MOCK_CAPTURE'" :src="previewUrl" alt="本地抓拍预览（非现场画面）" class="capture-preview" /><video v-else :src="previewUrl" controls playsinline preload="metadata" aria-label="本地录像预览" class="capture-preview" /><strong>{{ pending.method === 'MOCK_CAPTURE' ? '抓拍' : '录像' }}已生成，尚未保存</strong><p>{{ (pending.blob.size / 1024).toFixed(1) }} KB · 保存计入200MB总预算 · 刷新清空</p><button class="video-button" :disabled="busy" @click="save">{{ busy ? '保存中' : '保存为现场资料' }}</button><a class="video-button" :href="previewUrl" :download="pending.method === 'MOCK_CAPTURE' ? '本地抓拍.png' : '本地录像.webm'">下载到本机</a><button class="video-button" :disabled="busy" @click="discard">丢弃</button></section>
      <router-link v-if="saved" class="video-button" :to="{ path: '/materials', query: { siteId, selectedId: saved } }">查看生成资料</router-link>
    </template>
    <p v-if="device && !videoAccess.allowed" class="video-note">{{ videoAccess.reason }}</p><p v-if="error" role="alert" class="video-note">{{ error }}</p>
  </div>
</template>
<style scoped>
.capture-preview { display:block; width:100%; max-height:320px; object-fit:contain; background:#001322; border-radius:6px; margin-bottom:12px; }
.mock-monitor { min-width: 0; }.mock-play-controls { display:flex;flex-wrap:wrap;align-items:center;gap:8px;padding:8px; }.mock-pending { border:1px solid var(--cyan);padding:14px;margin:12px 0;background:var(--panel-bg); }.mock-pending button { margin-right:8px; }.compact .mock-play-controls { gap:4px;padding:4px; }.compact .video-button { min-height:30px;font-size:12px;padding:4px; }.video-player header,.video-player footer { background:#001d30dd; }.video-note { padding:0 8px;overflow-wrap:anywhere; }
</style>
