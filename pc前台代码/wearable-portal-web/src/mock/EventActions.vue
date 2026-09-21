<script setup>
import { ref, computed, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { useWorkspaceStore } from '@/store/workspace'
import { useLocalEditor } from './useLocalEditor'
import { command } from './event-provider'
const props = defineProps({ event: { type: Object, required: true }, siteId: String })
const description = ref(''), version = ref(0), operationId = ref(''), lastInput = ref('')
const workspace = useWorkspaceStore()
const { user, open, dirty, busy, error, clear, close, run } = useLocalEditor(() => { description.value = ''; lastInput.value = '' })
const allowed = computed(() => ['owner', 'verifier'].some(r => user.roles.includes(r)) && props.event.handlingStatus === 'UNHANDLED')
watch(() => props.event.eventId, clear)
function start() { clear(); version.value = props.event.version; operationId.value = crypto.randomUUID(); open.value = true }
async function submit() {
  const note = description.value.trim()
  if (!note || [...note].length > 1000) { error.value = '请填写1—1000字的处理说明'; return }
  if (lastInput.value && lastInput.value !== note) operationId.value = crypto.randomUUID()
  lastInput.value = note
  await run(async signal => {
    const r = await command('handle', { siteId: props.siteId, eventId: props.event.eventId, expectedVersion: version.value, operationId: operationId.value, description: note }, signal)
    if (signal.aborted) return
    dirty.value = false; clear()
    ElMessage.success('告警已标记为已处理')
    workspace.invalidate(r.data.changedEntities)
  })
}
</script>
<template>
  <button v-if="event.handlingStatus !== 'HANDLED'" type="button" class="alarm-handle-button" :disabled="!allowed || busy" :title="allowed ? '填写处理说明' : '当前身份无处理权限或状态未知'" @click="start"><svg aria-hidden="true" viewBox="0 0 24 24" fill="none"><path d="M8 12l3 3 5-6" /><circle cx="12" cy="12" r="9" /></svg><span>处理</span></button>
  <el-dialog :model-value="open" title="处理告警" width="min(560px, 94vw)" append-to-body :close-on-click-modal="false" :before-close="close">
    <form class="alarm-handle-form" @submit.prevent="submit">
      <p>{{ event.eventTypeName || event.title }} · {{ event.deviceCode }}</p>
      <label :for="'alarm-handling-note-' + event.eventId">处理说明 <span aria-hidden="true">*</span></label>
      <textarea :id="'alarm-handling-note-' + event.eventId" v-model="description" rows="5" :disabled="busy" placeholder="填写现场检查情况与已采取的措施" @input="dirty = true; error = ''" />
      <small>{{ [...description.trim()].length }} / 1000 字；标记已处理不代表设备异常已恢复。</small>
      <p v-if="error" role="alert">{{ error }}</p>
      <div class="alarm-form-actions"><button type="button" class="event-button" :disabled="busy" @click="close">取消</button><button class="event-button primary" :disabled="busy">{{ busy ? '正在提交…' : '确认处理' }}</button></div>
    </form>
  </el-dialog>
</template>
<style scoped>
.alarm-handle-button {
  display:inline-flex; align-items:center; justify-content:center; gap:8px;
  height:40px; min-width:88px; box-sizing:border-box; padding:0 16px;
  border:1px solid #e9b44e; border-radius:6px;
  background:#f4bd50; color:#182536; font:inherit; font-size:14px;
  font-weight:600; line-height:1; white-space:nowrap; cursor:pointer;
  box-shadow:0 2px 5px #0000001f;
  transition:background-color 150ms, border-color 150ms, box-shadow 150ms;
}
.alarm-handle-button svg { width:16px; height:16px; flex:none; stroke:currentColor; stroke-width:1.8; stroke-linecap:round; stroke-linejoin:round; }
.alarm-handle-button:hover:not(:disabled) { background:#ffd27b; border-color:#ffd27b; box-shadow:0 3px 8px #00000029; }
.alarm-handle-button:active:not(:disabled) { background:#e5aa36; box-shadow:inset 0 1px 3px #00000026; }
.alarm-handle-button:focus-visible { outline:2px solid var(--cyan, #2efff0); outline-offset:3px; }
.alarm-handle-button:disabled { background:#243549; border-color:#425267; color:#91a2b5; box-shadow:none; cursor:not-allowed; }
@media (prefers-reduced-motion:reduce) { .alarm-handle-button { transition:none; } }

.alarm-handle-form { display:grid; gap:14px; }
textarea { width:100%; box-sizing:border-box; padding:12px; font:inherit; color:var(--text-primary); background:var(--input-bg); border:1px solid var(--border); border-radius:8px; resize:vertical; }
textarea:focus-visible { outline:2px solid var(--cyan); }
.alarm-form-actions { display:flex; justify-content:flex-end; gap:12px; }
[role="alert"] { color:var(--danger, #e45757); overflow-wrap:anywhere; }
</style>
