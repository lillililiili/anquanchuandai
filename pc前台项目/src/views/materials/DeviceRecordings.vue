<script setup>
import { computed, onUnmounted, ref, watch } from 'vue';
import { formatBeijingDateTime } from '@/lib/date-time';
import AppButton from '@/components/ui/AppButton.vue';
import AppPanel from '@/components/ui/AppPanel.vue';
import DeviceLocalRecording from '@/components/domain/DeviceLocalRecording.vue';
import { db, tick, connection } from '@/mock/runtime';
import { authFetch } from '@/lib/auth';
import { beijingDate } from '@/lib/location';
import { COMMAND_LABELS, COMMAND_STATUSES, createHelmetMediaApi } from '@/lib/helmet-media';
import { personFeature, operationContext } from '@/lib/person-equipment';

const props = defineProps({ personId: { type: String, required: true } });
const emit = defineEmits(['refresh', 'media']);
const feature = computed(() => { tick.value; return personFeature(db, props.personId, 'recording'); });
const photoFeature = computed(() => { tick.value; return personFeature(db, props.personId, 'photo'); });
const device = computed(() => { tick.value; return db.currentDevices(props.personId).find(item => item.type === 'H' && item.active !== false && item.source === 'DIRECT_HELMET' && item.simulated !== true && item.demo !== true); });
const api = createHelmetMediaApi(authFetch);
const data = ref({ recordings: [], commands: [] });
const date = ref(beijingDate()), start = ref('00:00'), end = ref('23:59');
const selected = ref([]), busy = ref(''), error = ref(''), notice = ref('');
let controller, timer, generation = 0, readSequence = 0;
const retryKeys = new Map();
const recordings = computed(() => Array.isArray(data.value.recordings) ? data.value.recordings : []);
const commands = computed(() => (data.value.commands || []).filter(command => ['take_photo', 'list_recordings', 'upload_recording'].includes(command.action)));
const autoSyncTasks = computed(() => (Array.isArray(data.value.autoSyncTasks) ? data.value.autoSyncTasks : []).filter(task => task.deviceId === device.value?.id));
const autoSyncStatus = task => ({ recording:'正在录像', queued:'等待上传', querying:'正在获取录像', waiting_device:'等待设备连接', uploading:'上传中', completed:'已上传', failed:'上传失败' })[String(task.status).toLowerCase()] || '同步状态待确认';
const linkedFiles = command => (data.value.items || []).filter(item => item.status === 'ready' && item.requestId === command.id && item.deviceId === device.value?.id).length;
const status = command => COMMAND_STATUSES[String(command.status).toLowerCase()] || '执行状态待确认';
const unavailable = computed(() => {
  if (connection.value.status !== 'online') return '业务连接中断，实时操作不可用';
  if (!device.value || feature.value.deviceId !== device.value.id) return '领用关系已变化，请刷新';
  return feature.value.available ? '' : feature.value.reason || '设备录像操作当前不可用';
});
// These are implemented direct-helmet commands. The authorized per-person
// feature already checks current assignment, device freshness and permissions;
// the legacy telemetry capability list does not include file-query commands.
const enabled = action => ['list_recordings', 'upload_recording'].includes(action) && !unavailable.value;
async function read() {
  const current = generation, sequence = ++readSequence, deviceId = device.value?.id;
  if (!deviceId || !controller) return;
  try {
    const result = await api.read(deviceId, controller.signal);
    if (current === generation && sequence === readSequence) {
      if (result.itemsAvailable === false) {
        // Progress can advance while the file service is temporarily unavailable.
        // Only an authoritative file response may replace the existing preview.
        data.value = { ...result, items: data.value.items || [] };
        error.value = '资料暂时无法刷新，正在自动重试';
      } else {
        data.value = result; error.value = '';
        emit('media', { deviceId, items: result.items || [] });
      }
    }
  }
  catch (reason) { if (current === generation && sequence === readSequence && reason.name !== 'AbortError') { error.value = reason.message || '设备资料记录读取失败'; if ([401,403].includes(reason.status)) { data.value = { recordings: [], commands: [], items: [] }; emit('media', { deviceId, items: [], accessDenied: true }); } } }
}
watch(() => { const f = feature.value, p = photoFeature.value, operator = db.state.operator; return JSON.stringify([props.personId, device.value?.id, f.assignmentId, f.assignmentVersion, p.assignmentId, p.assignmentVersion, operator?.id, operator?.roleIds, operator?.sites, operator?.permissionsBySite]); }, () => {
  generation++; controller?.abort(); clearInterval(timer); controller = new AbortController();
  data.value = { recordings: [], commands: [] }; selected.value = []; busy.value = ''; error.value = ''; notice.value = ''; retryKeys.clear();
  if (device.value) { void read(); timer = setInterval(read, 5000); }
}, { immediate: true, flush: 'sync' });
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
  <AppPanel v-if="device" title="设备影像与回执">
    <p>{{ db.person(personId)?.name }} · {{ device.id }}</p>
    <DeviceLocalRecording :device="device" />
    <template v-if="autoSyncTasks.length">
      <h3>自动同步</h3>
      <ul class="media-command-list" aria-label="设备资料自动同步进度">
        <li v-for="task in autoSyncTasks" :key="task.id">
          <span>{{ task.kind === 'photo' ? '照片' : '录像' }} · {{ autoSyncStatus(task) }} · {{ formatBeijingDateTime(task.updatedAt) }}</span>
          <small v-if="task.message" :class="{ 'form-error': task.status === 'failed' }">{{ task.message }}</small>
          <small v-if="Number.isInteger(task.fileCount) && task.fileCount > 0 && Number.isInteger(task.receivedCount)">已收到 {{ task.receivedCount }} / {{ task.fileCount }} 个文件</small>
        </li>
      </ul>
    </template>
    <template v-if="feature.supported">
    <h3>设备内录像与上传</h3>
    <p>{{ unavailable || '按当前领用关系查询设备内文件' }}</p>
    <div class="recording-controls">
      <label>日期（北京时间）<input v-model="date" type="date" /></label>
      <label>开始<input v-model="start" type="time" /></label>
      <label>结束<input v-model="end" type="time" /></label>
      <AppButton :disabled="!!busy || !enabled('list_recordings')" :title="unavailable" @click="query">查询设备录像</AppButton>
    </div>
    <label v-for="item in recordings" :key="item.fileName || item.name || item.id" class="recording-file"><input v-model="selected" type="checkbox" :value="item.fileName || item.name || item.id" :disabled="!feature.available" />{{ item.name || item.fileName || item.id }} · {{ formatBeijingDateTime(item.createdAt) }}</label>
    <p v-if="!recordings.length" class="muted">暂无设备返回的录像列表。查询后等待设备回执。</p>
    <AppButton :disabled="!!busy || !selected.length || !enabled('upload_recording')" :title="unavailable" @click="upload">上传选中录像</AppButton>
    <p class="note">查询和上传需要当前人员领用且设备在线；历史上传资料可在资料列表中查看。请求受理不表示文件已经上传。</p>
    </template>
    <p v-if="error" role="alert" class="form-error">{{ error }}</p>
    <p v-if="notice" role="status">{{ notice }}</p>
    <h3>平台请求回执</h3>
    <ul v-if="commands.length" class="media-command-list"><li v-for="command in commands" :key="command.id"><span>{{ COMMAND_LABELS[command.action] }} · {{ status(command) }} · {{ formatBeijingDateTime(command.createdAt) }}</span><small v-if="command.action === 'take_photo'">{{ linkedFiles(command) ? '已关联回传照片：' + linkedFiles(command) + ' 份' : '尚无关联回传照片；不表示设备未拍摄' }}</small></li></ul>
    <p v-else class="muted">暂无平台拍照、录像查询或上传请求。</p>
    <p class="note">平台请求结果与收到的文件分别记录。未关联平台请求的文件仍在现场资料中展示，不据此判断触发方式。</p>
  </AppPanel>
</template>

<style scoped>
.recording-controls { display:flex; flex-wrap:wrap; align-items:flex-end; gap:12px; }
.recording-controls label { display:grid; gap:6px; }
.recording-controls input { min-height:40px; color:var(--theme-text); background:var(--theme-card); border:1px solid var(--theme-border); padding:6px; }
.recording-file { display:flex; gap:8px; align-items:center; min-height:44px; }
.media-command-list { padding-left:20px; }
.media-command-list li { margin:10px 0; overflow-wrap:anywhere; line-height:1.5; }
.media-command-list small { display:block; color:var(--theme-muted); margin-top:3px; }
</style>
