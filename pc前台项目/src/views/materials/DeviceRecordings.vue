<script setup>
import { computed, onUnmounted, ref, watch } from 'vue';
import AppButton from '@/components/ui/AppButton.vue';
import AppPanel from '@/components/ui/AppPanel.vue';
import { db, tick, connection } from '@/mock/runtime';
import { authFetch } from '@/lib/auth';
import { beijingDate } from '@/lib/location';
import { COMMAND_LABELS, COMMAND_STATUSES, createHelmetMediaApi } from '@/lib/helmet-media';
import { personFeature, operationContext } from '@/lib/person-equipment';
import { supportsDeviceAction } from '@/lib/device-telemetry';

const props = defineProps({ personId: { type: String, required: true } });
const emit = defineEmits(['refresh']);
const feature = computed(() => { tick.value; return personFeature(db, props.personId, 'recording'); });
const api = createHelmetMediaApi(authFetch);
const data = ref({ recordings: [], commands: [] });
const date = ref(beijingDate()), start = ref('00:00'), end = ref('23:59');
const selected = ref([]), busy = ref(''), error = ref(''), notice = ref('');
let controller, timer, generation = 0, readSequence = 0;
const retryKeys = new Map();
const recordings = computed(() => Array.isArray(data.value.recordings) ? data.value.recordings : []);
const commands = computed(() => (data.value.commands || []).filter(command => ['list_recordings', 'upload_recording'].includes(command.action)));
const status = command => COMMAND_STATUSES[String(command.status).toLowerCase()] || '执行状态待确认';
const enabled = action => connection.value.status === 'online' && feature.value.available && supportsDeviceAction(db.device(feature.value.deviceId), action);
async function read() {
  const current = generation, sequence = ++readSequence, deviceId = feature.value.deviceId;
  if (!deviceId || !controller) return;
  try { const result = await api.read(deviceId, controller.signal); if (current === generation && sequence === readSequence) { data.value = result; error.value = ''; } }
  catch (reason) { if (current === generation && sequence === readSequence && reason.name !== 'AbortError') error.value = reason.message || '设备录像记录读取失败'; }
}
watch(() => { const f = feature.value; return [props.personId, f.deviceId, f.assignmentId, f.assignmentVersion, f.available].join('|'); }, () => {
  generation++; controller?.abort(); clearInterval(timer); controller = new AbortController();
  data.value = { recordings: [], commands: [] }; selected.value = []; busy.value = ''; error.value = ''; notice.value = ''; retryKeys.clear();
  if (feature.value.supported) { void read(); timer = setInterval(read, 5000); }
}, { immediate: true });
onUnmounted(() => { generation++; controller?.abort(); clearInterval(timer); });
async function send(action, parameters) {
  if (busy.value || !enabled(action)) return;
  const current = generation, target = feature.value;
  const retryId = JSON.stringify([target.deviceId, target.assignmentId, target.assignmentVersion, action, parameters]);
  const key = retryKeys.get(retryId) || crypto.randomUUID(); retryKeys.set(retryId, key);
  busy.value = action; error.value = ''; notice.value = '';
  try {
    const result = await api.command(target.deviceId, action, parameters, key, controller.signal, operationContext(target));
    if (current !== generation) return;
    if (!['unknown', 'requesting'].includes(String(result.status).toLowerCase())) retryKeys.delete(retryId);
    notice.value = `${COMMAND_LABELS[action]}：${status(result)}。请以设备回执和返回文件为准。`;
    await read(); emit('refresh');
  } catch (reason) { if (current === generation && reason.name !== 'AbortError') error.value = reason.message || '请求失败，可重试查询结果'; }
  finally { if (current === generation) busy.value = ''; }
}
function query() {
  if (!date.value || !start.value || !end.value || start.value >= end.value) { error.value = '请选择有效日期，结束时间须晚于开始时间'; return; }
  void send('list_recordings', { startTime: `${date.value} ${start.value}:00`, endTime: `${date.value} ${end.value}:59` });
}
function upload() {
  const listed = new Set(recordings.value.map(item => item.fileName || item.name || item.id));
  const files = selected.value.filter(file => listed.has(file));
  if (!files.length) { error.value = '请先选择设备返回的录像'; return; }
  void send('upload_recording', { files });
}
</script>

<template>
  <AppPanel v-if="feature.supported" :title="feature.verified ? '设备内录像与上传' : '设备内录像与上传 · 待联调'">
    <p>{{ db.person(personId)?.name }} · {{ feature.deviceId }} · {{ connection.status !== 'online' ? '业务连接中断，实时操作不可用' : feature.reason || '按当前领用关系查询设备内文件' }}</p>
    <div class="recording-controls">
      <label>日期（北京时间）<input v-model="date" type="date" /></label>
      <label>开始<input v-model="start" type="time" /></label>
      <label>结束<input v-model="end" type="time" /></label>
      <AppButton :disabled="!!busy || !enabled('list_recordings')" :title="feature.reason" @click="query">查询设备录像</AppButton>
    </div>
    <label v-for="item in recordings" :key="item.fileName || item.name || item.id" class="recording-file"><input v-model="selected" type="checkbox" :value="item.fileName || item.name || item.id" :disabled="!feature.available" />{{ item.name || item.fileName || item.id }} · {{ item.createdAt || '时间未提供' }}</label>
    <p v-if="!recordings.length" class="muted">暂无设备返回的录像列表。查询后等待设备回执。</p>
    <AppButton :disabled="!!busy || !selected.length || !enabled('upload_recording')" :title="feature.reason" @click="upload">上传选中录像</AppButton>
    <p v-if="error" role="alert" class="form-error">{{ error }}</p>
    <p v-if="notice" role="status">{{ notice }}</p>
    <ul v-if="commands.length"><li v-for="command in commands" :key="command.id">{{ COMMAND_LABELS[command.action] }} · {{ status(command) }} · {{ command.createdAt || '时间未提供' }}</li></ul>
    <p class="note">查询和上传需要当前人员领用且设备在线；历史上传资料仍可在下方查看。请求受理不表示文件已经上传。</p>
  </AppPanel>
</template>

<style scoped>
.recording-controls { display:flex; flex-wrap:wrap; align-items:flex-end; gap:12px; }
.recording-controls label { display:grid; gap:6px; }
.recording-controls input { min-height:40px; color:var(--theme-text); background:var(--theme-card); border:1px solid var(--theme-border); padding:6px; }
.recording-file { display:flex; gap:8px; align-items:center; min-height:44px; }
</style>
