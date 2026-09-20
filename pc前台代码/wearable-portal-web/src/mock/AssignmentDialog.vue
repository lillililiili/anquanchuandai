<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate } from 'vue-router'
import { ElMessageBox, ElMessage } from 'element-plus'
import { useUserStore } from '@/store/user'
import { useContextStore } from '@/store/context'
import { getAssignmentOptions, issueEquipment, returnEquipment } from '@/api/equipment'
import { equipmentTypes, assignmentLabels } from '@/utils/equipment-route'
import { labels } from '@/utils/portal-contract'
const props = defineProps({ siteId: { type: String, required: true }, personId: { type: String, default: '' }, deviceId: { type: String, default: '' }, type: { type: String, default: 'HELMET' }, state: { type: String, default: '' } })
const user = useUserStore(), context = useContextStore()
const opened = ref(false), loading = ref(false), busy = ref(false), data = ref(null), error = ref(''), conflict = ref(false)
const selectedType = ref(props.type), choice = ref(''), dirty = ref(false)
let controller, sequence = 0, operationId = '', fingerprint = ''
const allowed = computed(() => user.roles.includes('owner'))
const disabledReason = computed(() => !allowed.value ? '仅负责人可办理领用归还' : ['UNKNOWN', 'CONFLICT'].includes(props.state) ? '领用关系未知或冲突，请先核实；本阶段不支持修复' : '')
const title = computed(() => (props.state === 'ASSIGNED' ? '归还' : '领用') + equipmentTypes[props.type])
const relationState = computed(() => data.value?.device?.assignmentState || data.value?.person?.equipment.data[({ HELMET: 'helmet', BELT: 'belt', WATCH: 'watch' })[selectedType.value]]?.assignmentState)
const returning = computed(() => relationState.value === 'ASSIGNED')
const pairId = p => p.person.personId + ':' + p.device.deviceId
const selected = computed(() => returning.value ? data.value?.current[0] : data.value?.choices.find(p => pairId(p) === choice.value))
const warning = computed(() => {
  const d = selected.value?.device
  if (!d) return ''
  return [d.communication.state !== 'ONLINE' ? '通信' + (labels[d.communication.state] || '未知') : '', d.communication.freshness !== 'FRESH' ? '数据' + (labels[d.communication.freshness] || '未知') : '', d.type !== 'HELMET' ? '厂家协议待确认' : ''].filter(Boolean).join('；')
})
function clear() { sequence++; controller?.abort(); opened.value = false; data.value = null; error.value = ''; loading.value = false; busy.value = false; choice.value = ''; dirty.value = false; operationId = ''; fingerprint = ''; conflict.value = false }
async function load(preserve = true) {
  controller?.abort(); controller = new AbortController(); const current = ++sequence
  loading.value = true; error.value = ''; conflict.value = false
  if (!preserve) { choice.value = ''; data.value = null; dirty.value = false; operationId = ''; fingerprint = '' }
  try {
    const response = await getAssignmentOptions({ siteId: props.siteId, ...(props.personId ? { personId: props.personId, type: selectedType.value } : { deviceId: props.deviceId }) }, controller.signal)
    if (current !== sequence) return
    data.value = response.data
    if (choice.value && !data.value.choices.some(p => pairId(p) === choice.value)) { error.value = '之前的选择已不可用，请重新选择；没有自动替换装备或人员'; choice.value = '' }
  } catch (e) { if (current === sequence && e.code !== 'ERR_CANCELED') { error.value = e.message; conflict.value = true } }
  finally { if (current === sequence) loading.value = false }
}
async function open() { if (disabledReason.value) return; opened.value = true; selectedType.value = props.type; await load(false) }
async function mayLeave() {
  if (!opened.value || !dirty.value || !user.token) return true
  if (busy.value) return false
  try { await ElMessageBox.confirm('离开将丢弃尚未提交的选择，已完成的本地操作不会回滚。', '放弃未提交选择？', { confirmButtonText: '放弃选择', cancelButtonText: '继续编辑' }); return true } catch { return false }
}
async function close() { if (busy.value) return; if (await mayLeave()) clear() }
onBeforeRouteLeave(mayLeave)
onBeforeRouteUpdate(mayLeave)
function beforeUnload(event) { if (opened.value && dirty.value) { event.preventDefault(); event.returnValue = '' } }
window.addEventListener('beforeunload', beforeUnload)
onBeforeUnmount(() => { clear(); window.removeEventListener('beforeunload', beforeUnload) })
watch(() => [props.siteId, props.personId, props.deviceId, user.token, context.selectedSiteId], clear)
watch(choice, () => { dirty.value = !!choice.value })
async function changeType(event) {
  const next = event.target.value
  if (!await mayLeave()) { event.target.value = selectedType.value; return }
  selectedType.value = next; await load(false)
}
async function submit() {
  if (!selected.value || busy.value || loading.value || conflict.value || !allowed.value) return
  const pair = selected.value, payload = { siteId: props.siteId, personId: pair.person.personId, deviceId: pair.device.deviceId, expectedVersion: pair.expectedVersion, ...(returning.value ? { assignmentId: pair.assignment.assignmentId } : {}) }
  const next = JSON.stringify(payload)
  if (fingerprint !== next) { operationId = crypto.randomUUID(); fingerprint = next }
  payload.operationId = operationId
  const current = sequence; busy.value = true; error.value = ''
  const action = returning.value ? returnEquipment : issueEquipment
  try {
    await action(payload, controller.signal)
    if (current !== sequence) return
    dirty.value = false; clear(); ElMessage.success('操作已在本地完成，仅保存在本页内存；刷新恢复初始数据')
  } catch (e) {
    if (current !== sequence || e.code === 'ERR_CANCELED') return
    error.value = e.message + (e.requestId ? '（' + e.requestId + '）' : '')
    conflict.value = e.code === 409
  } finally { if (current === sequence) busy.value = false }
}
</script>
<template>
  <div class="assignment-entry"><el-button :disabled="!!disabledReason" @click="open">{{ title }}</el-button><small>{{ disabledReason || '前端本地台账，不发送设备命令' }}</small></div>
  <el-dialog class="v3-assignment-dialog" :model-value="opened" :title="'本地装备' + (returning ? '归还' : '领用')" width="min(660px, 94vw)" append-to-body :close-on-click-modal="false" :before-close="close">
    <div class="assignment-form">
      <p>只更新当前页面内存，刷新恢复初始数据。不是设备下发或真实业务入库。</p>
      <label v-if="personId">装备类型<select :value="selectedType" :disabled="busy || loading" @change="changeType"><option v-for="(label, key) in equipmentTypes" :key="key" :value="key">{{ label }}</option></select></label>
      <p v-if="loading" role="status">正在核对领用关系…</p>
      <template v-else-if="data">
        <h3>{{ data.person?.name || data.device?.deviceCode }}</h3>
        <p>当前关系：{{ assignmentLabels[relationState] || '未知' }}</p>
        <label v-if="relationState === 'UNASSIGNED'">{{ personId ? '可领用装备' : '领用人员' }}<select v-model="choice" :disabled="busy"><option value="">请选择{{ personId ? '装备' : '人员' }}</option><option v-for="p in data.choices" :key="pairId(p)" :value="pairId(p)">{{ personId ? p.device.deviceCode + ' · ' + p.device.name : p.person.name + ' · ' + p.person.personCode }}</option></select></label>
        <p v-if="relationState === 'UNASSIGNED' && !data.choices.length">没有符合条件的{{ personId ? '可领用装备' : '人员' }}，不能提交。</p>
        <p v-if="['UNKNOWN', 'CONFLICT'].includes(relationState)" class="assignment-warning">关系未知或冲突，需先核实。本阶段不提供修复或强制解绑。</p>
        <dl v-if="selected"><dt>确认人员</dt><dd>{{ selected.person.name }} · {{ selected.person.personCode }}</dd><dt>确认装备</dt><dd>{{ selected.device.deviceCode }} · {{ equipmentTypes[selected.device.type] }}</dd><template v-if="returning"><dt>有效关系</dt><dd>{{ selected.assignment.assignmentId }}<small>开始时间：{{ selected.assignment.startedAt || '未知（种子快照，非领用流水）' }}</small></dd></template></dl>
        <p v-if="warning" class="assignment-warning">{{ warning }}。允许办理本地台账，不代表设备状态正常。</p>
      </template>
      <p v-if="error" role="alert" class="assignment-error">{{ error }}</p>
      <el-button v-if="error" :disabled="busy || loading" @click="load(true)">重新读取并核对</el-button>
    </div>
    <template #footer><el-button :disabled="busy" @click="close">取消</el-button><el-button type="primary" :disabled="!selected || busy || loading || conflict || !['ASSIGNED', 'UNASSIGNED'].includes(relationState)" :loading="busy" @click="submit">{{ returning ? '确认归还' : '确认领用' }}</el-button></template>
  </el-dialog>
</template>
<style scoped>
.assignment-entry { display:flex; flex-wrap:wrap; align-items:center; gap:8px; margin:10px 0 }.assignment-entry small { color:var(--text-secondary); font-size:12px }
.assignment-form { display:grid; gap:16px; overflow-wrap:anywhere }.assignment-form p { color:var(--text-secondary) }.assignment-form label { display:grid; gap:8px }.assignment-form select { width:100%; padding:12px; color:var(--text-primary); border:1px solid var(--border); background:var(--input-bg); border-radius:4px }.assignment-form dl { display:grid; grid-template-columns:90px minmax(0,1fr); margin:0; padding:16px; gap:12px; background:var(--page-bg); border-left:3px solid var(--cyan) }.assignment-form dd { margin:0 }.assignment-form small { display:block }.assignment-form .assignment-warning { padding:12px; border:1px solid var(--border); color:var(--text-primary) }.assignment-form .assignment-error { color:var(--error) }
</style>
