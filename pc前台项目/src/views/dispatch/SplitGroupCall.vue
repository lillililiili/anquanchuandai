<script setup>
import { computed, onUnmounted, ref } from 'vue';
import AppPanel from '@/components/ui/AppPanel.vue';
import AppButton from '@/components/ui/AppButton.vue';
import { db, tick, connection } from '@/mock/runtime';
import { authFetch, captureAuthRequest, onAuthCleared } from '@/lib/auth';
import { personFeature, operationContext } from '@/lib/person-equipment';
import { deviceCallUnavailable } from '@/lib/helmet-device-call';
import { createSplitGroupCall } from '@/lib/split-group-call';
const props = defineProps({ members: { type: Array, default: () => [] } });
const state = ref({ phase: 'idle', devices: {}, error: '', muted: false }), error = ref(''), participants = ref([]);
const streams = new Map(), videos = new Map();
let closeRequest;
const call = createSplitGroupCall({ fetchImpl: authFetch, onChange: value => { state.value = value; }, onStream: (stream, id) => { streams.set(id, stream); const video = videos.get(id); if (video) video.srcObject = stream; } });
const active = computed(() => !['idle','failed','ended'].includes(state.value.phase));
const showingVideo = ref(false);
const blocked = computed(() => {
  tick.value;
  if (connection.value.status !== 'online') return '业务后台未连接';
  if (props.members.length < 2 || props.members.length > 8) return '请选择 2 至 8 名已领用分体帽的人员';
  const sites = new Set();
  for (const id of props.members) {
    const feature = personFeature(db, id, 'voice'), device = db.device(feature.deviceId);
    if (device?.source !== 'SPLIT_HELMET') return '多帽调度仅支持同一厂站的分体帽，请分别联系其他型号';
    sites.add(device.siteId || device.station);
    try { const reason = deviceCallUnavailable(device, feature, false, operationContext(feature)); if (reason) return `${db.person(id)?.name || id}：${reason}`; }
    catch (reason) { return reason.message; }
  }
  return sites.size === 1 ? '' : '请仅选择同一厂站的人员';
});
const videoBlocked = computed(() => {
  if (blocked.value) return blocked.value;
  for (const id of props.members) {
    const voice = personFeature(db,id,'voice'), video = personFeature(db,id,'videoCall');
    if (!video.available || video.deviceId !== voice.deviceId || video.assignmentId !== voice.assignmentId ||
        video.assignmentVersion !== voice.assignmentVersion) return video.reason || '所选人员的分体帽视频对讲不可用';
  }
  return '';
});
function bindVideo(id, element) { if (element) { videos.set(id, element); element.srcObject = streams.get(id) || null; } else videos.delete(id); }
async function act(action) { error.value = ''; try { await action(); } catch (reason) { error.value = reason.message; } }
async function start(video) {
  if (blocked.value || (video && videoBlocked.value) || active.value) return;
  clear();
  showingVideo.value = video;
  closeRequest = captureAuthRequest();
  participants.value = props.members.map(id => ({ ...operationContext(personFeature(db, id, 'voice')), name: db.person(id)?.name || id }));
  await act(() => call.start(participants.value.map(({ name, ...context }) => context), { video }));
}
const status = value => ({ connecting: '连接中', connected: '媒体已连接', disconnected: '网络中断', failed: '连接失败', timeout: '连接超时' })[value] || '等待连接';
const clear = () => { videos.forEach(video => { video.srcObject = null; }); streams.clear(); };
async function end() { await act(() => call.end(closeRequest)); clear(); }
const unsubscribe = onAuthCleared(({ request }) => { void call.revoke(closeRequest || request); clear(); });
onUnmounted(() => { unsubscribe(); void call.revoke(closeRequest); clear(); });
</script>
<template>
  <AppPanel v-if="members.length > 1 || active" title="分体帽多路调度">
    <p class="muted">最多 8 顶分体帽与调度员通话，设备之间不互听。播放和对讲分别显示连接结果。</p>
    <p v-if="blocked && !active" role="status">{{ blocked }}</p>
    <div v-if="!active" class="form-actions">
      <AppButton tone="primary" :disabled="!!videoBlocked" :title="videoBlocked" @click="start(true)">多帽视频对讲</AppButton>
      <AppButton :disabled="!!blocked" @click="start(false)">仅语音群呼</AppButton>
    </div>
    <div v-if="active" class="split-calls">
      <article v-for="person in participants" :key="person.deviceId">
        <video v-if="showingVideo" :ref="element => bindVideo(person.deviceId, element)" autoplay muted playsinline controls :aria-label="person.name + '的分体帽视频'" />
        <p>{{ person.name }} · {{ person.deviceId }}</p><p role="status">播放：{{ status(state.devices[person.deviceId + ':play']) }}；对讲：{{ status(state.devices[person.deviceId + ':talk']) }}</p>
      </article>
    </div>
    <div v-if="active" class="form-actions"><AppButton tone="danger" @click="end">{{ state.phase === 'unknown' ? '重试结束' : '结束全部会话' }}</AppButton><AppButton :disabled="!['active','connecting'].includes(state.phase)" @click="act(() => call.setMuted(!state.muted))">{{ state.muted ? '开启麦克风' : '麦克风静音' }}</AppButton><AppButton @click="act(() => call.retry())">重试失败连接</AppButton><AppButton @click="act(() => call.resumeAudio())">播放声音</AppButton></div>
    <p v-if="state.error || error" class="form-error" role="alert">{{ error || state.error }}</p>
  </AppPanel>
</template>
<style scoped>.split-calls{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(220px,100%),1fr));gap:12px}.split-calls video{width:100%;max-height:220px;background:var(--theme-card)}.split-calls article{min-width:0}.split-calls p{overflow-wrap:anywhere}</style>
