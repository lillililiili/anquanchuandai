<script setup>
import { computed, ref, watch } from 'vue'
import { queryDispatch, commandDispatch, useDispatchStore } from './dispatch-runtime'
import { participantLabels } from './dispatch-service'
import { useLocalEditor } from './useLocalEditor'
const props = defineProps({ siteId: String, deviceId: String, disabled: Boolean, mode: { type: String, default: 'VOICE', validator: value => ['VOICE', 'VIDEO'].includes(value) } })
const isVideo = computed(() => props.mode === 'VIDEO')
const callTitle = computed(() => isVideo.value ? '音视频通话' : '设备对讲')
const data = ref(null), sessionId = ref('')
const { user, open, busy, error, clear, close, run } = useLocalEditor(() => { data.value = null; sessionId.value = '' })
const store = useDispatchStore()
const allowed = computed(() => user.roles.includes('owner'))
const target = computed(() => data.value?.suggested.find(c => c.deviceId === props.deviceId))
const session = computed(() => store.data.sessions.find(s => s.id === sessionId.value && s.siteId === props.siteId))
const otherActive = computed(() => store.active && store.active.id !== session.value?.id)
const reason = computed(() => !allowed.value ? '当前账号无发起通话权限' : !props.siteId || !props.deviceId || props.disabled ? '请先选择并加载设备' : '')
watch(() => [props.siteId, props.deviceId, props.mode], clear)
async function load(signal) {
  const result = await queryDispatch({ siteId: props.siteId, deviceId: props.deviceId }, signal)
  if (signal.aborted) return
  data.value = result
  if (result.active?.mode === props.mode && result.active.participants.some(p => p.deviceId === props.deviceId)) sessionId.value = result.active.id
}
async function show() { if (reason.value || busy.value) return; clear(); open.value = true; await run(load) }
async function execute(action, extra = {}) {
  if (!allowed.value || busy.value || !data.value) return
  await run(async signal => {
    const result = await commandDispatch(action, {
      siteId: props.siteId, expectedVersion: data.value.version,
      operationId: crypto.randomUUID(), ...extra
    }, signal)
    if (signal.aborted) return
    if (action === 'start') sessionId.value = result.id
    await load(signal)
  })
}
</script>

<template>
  <button class="video-button" :disabled="!!reason" :title="reason || '打开当前设备的本地通话面板'" @click="show">{{ isVideo ? '发起音视频通话' : '发起对讲' }}</button>
  <el-dialog :model-value="open" :title="callTitle" width="min(600px, 94vw)" append-to-body :close-on-click-modal="false" :before-close="close" @update:model-value="v => { if (!v) close() }">
    <div class="intercom-panel" :aria-busy="busy">
      <p class="intercom-boundary">通信服务未接入。当前为本地会话流程，不采集摄像头或麦克风、不传输设备音视频；本地接听不代表设备已接通。</p>
      <p v-if="error" role="alert" class="intercom-error">{{ error }}</p>
      <button v-if="error" class="video-button" :disabled="busy" @click="run(load)">重新读取状态</button>
      <p v-if="busy" role="status">正在处理，请稍候…</p>
      <template v-if="target">
        <h3>{{ target.name }}</h3>
        <p>{{ target.deviceCode }} · {{ target.personName }}</p>
        <p>设备通信：{{ { ONLINE: '在线', OFFLINE: '离线', UNKNOWN: '未知' }[target.communication] || '未知' }}，不代表通话连接状态。</p>
        <p v-if="target.communication !== 'ONLINE'" class="intercom-warning">设备离线或通信状态未知，请先核实设备；本地呼叫不会改变通信状态。</p>
        <p v-if="!target.modes.includes(mode)">{{ target.reason }}</p>
        <div v-if="isVideo" class="video-call-preview" aria-label="本地音视频会话状态">
          <svg aria-hidden="true" viewBox="0 0 24 24" fill="none"><rect x="3" y="6" width="12" height="12" rx="2" /><path d="m15 10 6-3v10l-6-3" /></svg>
          <strong>{{ session?.state === 'ACTIVE' ? (session.participants.some(p => p.state === 'CONNECTED') ? '本地会话就绪' : '等待本地接听') : session ? '通话已结束' : '准备发起本地音视频通话' }}</strong>
          <span>远端音视频未接入，暂无通话画面</span>
        </div>
        <template v-if="session">
          <h3>会话{{ session.state === 'ACTIVE' ? '进行中' : '已结束' }}</h3>
          <div v-for="p in session.participants" :key="p.deviceId" class="intercom-participant">
            <p role="status">{{ p.name }} · {{ participantLabels[p.state] }}</p>
            <div v-if="session.state === 'ACTIVE' && p.state === 'RINGING'" class="intercom-actions">
              <button v-for="(label, state) in { CONNECTED: '本地接听', REJECTED: '本地拒接', TIMED_OUT: '本地超时' }" :key="state" class="video-button" :disabled="busy" @click="execute('participant', { sessionId: session.id, deviceId: p.deviceId, state })">{{ label }}</button>
            </div>
          </div>
          <button v-if="session.state === 'ACTIVE'" class="video-button" :disabled="busy" @click="execute('end', { sessionId: session.id })">{{ isVideo ? '结束通话' : '结束对讲' }}</button>
        </template>
        <p v-if="!isVideo && otherActive" role="status">已有其他活动会话，请到调度协同处理，不会自动中断或重复呼叫。</p>
        <button v-if="!store.active" class="video-button" :disabled="busy || !target.modes.includes(mode)" :title="target.modes.includes(mode) ? '只建立本地会话' : target.reason" @click="execute('start', { deviceIds: [deviceId], mode })">{{ session ? '重新呼叫' : '确认发起' }}</button>
      </template>
    </div>
    <p v-if="session?.state === 'ACTIVE'" class="video-note">关闭面板不会挂断会话；可重新打开或进入调度协同继续操作。</p>
    <template #footer><router-link v-if="!isVideo" class="video-button" :to="{ path: '/dispatch', query: { siteId, deviceId } }">进入调度协同</router-link><button class="video-button" :disabled="busy" @click="close">关闭面板</button></template>
  </el-dialog>
</template>

<style scoped>
.intercom-panel { display:grid; gap:12px; max-height:60vh; overflow:auto; overflow-wrap:anywhere; }
.intercom-panel p,.intercom-panel h3 { margin:0; line-height:1.7; }
.intercom-boundary { padding:12px; background:rgba(42,158,230,.12); border-left:3px solid var(--cyan); }
.intercom-actions { display:flex; gap:8px; flex-wrap:wrap; }
.intercom-participant { border-bottom:1px solid var(--border); padding:10px 0; }
.intercom-error { color:#ff9393; }.intercom-warning { color:#ffd08a; }
</style>

<style scoped>
.video-call-preview { display:flex; flex-direction:column; align-items:center; justify-content:center; gap:12px; min-height:180px; padding:20px; text-align:center; border:1px solid var(--border); border-radius:10px; background:var(--input-bg); }
.video-call-preview svg { width:32px; height:32px; stroke:var(--cyan); stroke-width:1.5; }
.video-call-preview span { color:var(--text-secondary); font-size:13px; }
.intercom-panel .video-button { min-height:40px; }
</style>
