<script setup>
import { computed, onUnmounted, ref, watch } from 'vue';
import AppButton from '@/components/ui/AppButton.vue';
import AppEmpty from '@/components/ui/AppEmpty.vue';
import AppPanel from '@/components/ui/AppPanel.vue';
import { db } from '@/mock/runtime';
import { session } from '@/stores/session';
import { revision } from '@/lib/queries';
import { authFetch, onAuthCleared } from '@/lib/auth';
import { formatBeijingDateTime } from '@/lib/date-time';
import { createDeviceVoiceApi, isDeviceVoiceMessage, voiceMessagePerson, voiceMessageStatus, voicePlaybackAuthorization } from '@/lib/device-voice-messages';

const api = createDeviceVoiceApi(authFetch);
const rows = ref([]), total = ref(0), page = ref(1), pageSize = 5;
const loading = ref(false), error = ref(''), playbackError = ref(''), preparingId = ref('');
const playback = ref(null), audio = ref(null);
const siteId = computed(() => { revision(); return db.state.stations.find(item => item.id === session.station)?.siteId || ''; });
const pageCount = computed(() => Math.max(1, Math.ceil(total.value / pageSize)));
let generation = 0, listSequence = 0, playSequence = 0, listController, playController, reading = false, disposed = false, authInvalid = false;

function stopPlayback() {
  playSequence++; playController?.abort(); preparingId.value = '';
  if (audio.value) { audio.value.pause(); audio.value.removeAttribute('src'); audio.value.load(); }
  audio.value = null;
  playback.value = null;
}
function setAudio(element) { if (element) audio.value = element; }
function invalidate() {
  generation++; listSequence++; listController?.abort(); reading = false;
  stopPlayback(); rows.value = []; total.value = 0; error.value = ''; playbackError.value = ''; loading.value = false;
}
async function read(background = false) {
  if (disposed || authInvalid || !siteId.value || background && reading) return;
  const current = generation, sequence = ++listSequence, requestedSite = siteId.value;
  listController?.abort(); listController = new AbortController();
  reading = true; loading.value = !background;
  try {
    const result = await api.list({siteId:requestedSite,pageNum:page.value,pageSize}, listController.signal);
    if (disposed || current !== generation || sequence !== listSequence || requestedSite !== siteId.value) return;
    rows.value = (Array.isArray(result.rows) ? result.rows : []).filter(row => isDeviceVoiceMessage(row) && row.siteId === requestedSite);
    total.value = Number.isSafeInteger(result.total) && result.total >= 0 ? result.total : rows.value.length;
    error.value = '';
    if (playback.value && !rows.value.some(row => row.id === playback.value.id && row.assetId === playback.value.assetId && row.status === 'READY' && row.playable === true)) stopPlayback();
    if (page.value > pageCount.value) { page.value = pageCount.value; reading = false; void read(); }
  } catch (reason) {
    if (disposed || current !== generation || sequence !== listSequence || reason.name === 'AbortError') return;
    if ([401,403,404].includes(reason.status)) { stopPlayback(); rows.value = []; total.value = 0; }
    error.value = reason.message || '设备语音消息读取失败';
  } finally {
    if (current === generation && sequence === listSequence) { reading = false; loading.value = false; }
  }
}
async function prepare(row) {
  if (disposed || authInvalid || preparingId.value === row.id || row.status !== 'READY' || row.playable !== true || !row.assetId) return;
  stopPlayback(); playbackError.value = '';
  const current = generation, sequence = ++playSequence;
  playController = new AbortController(); preparingId.value = row.id;
  try {
    const result = await api.playback(row.id, playController.signal);
    if (disposed || current !== generation || sequence !== playSequence || !rows.value.some(item => item.id === row.id && item.assetId === row.assetId && item.status === 'READY' && item.playable === true)) return;
    playback.value = voicePlaybackAuthorization(row, result);
  } catch (reason) {
    if (disposed || current !== generation || sequence !== playSequence || reason.name === 'AbortError') return;
    if ([401,403,404].includes(reason.status)) { listSequence++; listController?.abort(); reading = false; loading.value = false; rows.value = rows.value.filter(item => item.id !== row.id); total.value = Math.max(rows.value.length, total.value - 1); }
    playbackError.value = reason.message || '录音暂不可用';
  } finally { if (current === generation && sequence === playSequence) preparingId.value = ''; }
}
function checkPlayback(event) {
  if (event?.target && event.target !== audio.value) return;
  if (!playback.value || playback.value.expiresAt <= Date.now()) { stopPlayback(); playbackError.value = '录音播放授权已过期，请重新加载'; }
}
function playbackFailed(event) { if (event?.target && event.target !== audio.value) return; stopPlayback(); playbackError.value = '录音未能播放，请重新加载；仍失败时请检查媒体服务或浏览器格式支持。'; }
function changePage(value) { if (value < 1 || value > pageCount.value || value === page.value) return; stopPlayback(); page.value = value; void read(); }
watch(() => { revision(); const operator = db.state.operator; return JSON.stringify([siteId.value,operator?.id,operator?.roleIds,operator?.sites,operator?.permissionsBySite]); }, () => { invalidate(); page.value = 1; void read(); }, { immediate:true, flush:'sync' });
const unsubscribeAuth = onAuthCleared(() => { authInvalid = true; invalidate(); });
const timer = setInterval(() => void read(true), 10000);
onUnmounted(() => { disposed = true; clearInterval(timer); unsubscribeAuth(); invalidate(); });
</script>

<template>
  <AppPanel title="设备语音消息" extra-class="device-voice-messages">
    <template #extra><AppButton tone="small" :disabled="loading" @click="read()">{{ loading ? '正在读取…' : '刷新' }}</AppButton></template>
    <p class="note">设备按键发送的录音，与实时通话分别记录。默认不播放，接收时间为北京时间。</p>
    <p v-if="error" class="form-error" role="alert">{{ error }}</p>
    <p v-if="playbackError" class="form-error" role="alert">{{ playbackError }}</p>
    <ol v-if="rows.length" class="voice-message-list">
      <li v-for="row in rows" :key="row.id">
        <div class="voice-message-heading"><strong>{{ voiceMessagePerson(row) }}</strong><span>{{ voiceMessageStatus(row) }}</span></div>
        <p>来源设备：{{ row.deviceId || '未提供' }}</p>
        <p>平台接收时间：{{ row.timeBasis === 'RECEIVED_AT' ? formatBeijingDateTime(row.receivedAt) : '时间依据未确认' }}</p>
        <AppButton tone="small" :disabled="row.status !== 'READY' || row.playable !== true || !row.assetId || preparingId === row.id" @click="prepare(row)">{{ preparingId === row.id ? '正在获取播放授权…' : playback?.id === row.id ? '重新加载录音' : '加载录音' }}</AppButton>
        <div v-if="playback?.id === row.id" class="voice-message-player">
          <audio :ref="setAudio" :src="playback.url" controls preload="none" :aria-label="voiceMessagePerson(row) + '的设备语音消息'" @play="checkPlayback" @error="playbackFailed" />
          <AppButton tone="small" @click="stopPlayback">停止并关闭录音</AppButton>
          <small>点击播放器开始收听；播放授权过期后可重新加载。</small>
        </div>
      </li>
    </ol>
    <AppEmpty v-else :text="loading ? '正在读取设备语音消息' : '暂无可查看的设备语音消息'" />
    <div v-if="total" class="voice-message-pagination"><span>共 {{ total }} 条 · 第 {{ page }} / {{ pageCount }} 页</span><AppButton tone="small" :disabled="loading || page <= 1" @click="changePage(page - 1)">上一页</AppButton><AppButton tone="small" :disabled="loading || page >= pageCount" @click="changePage(page + 1)">下一页</AppButton></div>
  </AppPanel>
</template>

<style scoped>
.voice-message-list { list-style:none; padding:0; margin:0; }
.voice-message-list > li { padding:12px 0; border-bottom:1px solid var(--theme-divider); }
.voice-message-heading { display:flex; flex-wrap:wrap; align-items:baseline; gap:6px 12px; }
.voice-message-heading > span, .voice-message-list p, .voice-message-player small { color:var(--theme-muted); font-size:12px; line-height:1.5; }
.voice-message-list p { margin:4px 0; overflow-wrap:anywhere; }
.voice-message-player { display:flex; flex-wrap:wrap; align-items:center; gap:8px; margin-top:10px; }
.voice-message-player audio { width:100%; min-width:0; }
.voice-message-player small { flex-basis:100%; }
.voice-message-pagination { display:flex; flex-wrap:wrap; gap:8px; align-items:center; margin-top:12px; font-size:12px; }
.voice-message-pagination > span { margin-right:auto; }
</style>
