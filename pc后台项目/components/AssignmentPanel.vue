<template><ModalPanel :open="!!intent" :size="intent?.deviceId ? 'compact' : 'wide'" layout="form" heading-id="assignment-heading" :title="intent?.mode === 'issue' ? '装备领用' : '装备归还'" @close="close">
  <form v-if="intent" ref="formRef" novalidate class="master-form assignment-form dialog-form" :class="{ 'assignment-form--return': isReturn, 'assignment-form--fixed-issue': knownDeviceIssue }" @submit.prevent="submit" @input="dirty = true; acknowledged = false" @change="dirty = true">
    <div class="dialog-form-body">
    <p v-if="loading" role="status">{{ isReturn ? '正在读取归还装备…' : '正在读取候选与关系…' }}</p>
    <fieldset :disabled="busy || loading">
      <template v-if="!intent.personId && !fixedReturn"><label>{{ isReturn ? '领用人' : '选择人员' }}<div class="field-control"><UiSelect id="personId" :aria-invalid="!!errors.personId" :aria-describedby="errors.personId ? 'assignment-person-error' : undefined" v-model="personId" :aria-label="isReturn ? '领用人' : '选择人员'" :placeholder="isReturn ? '请选择领用人' : '请选择同厂站人员'" @change="choosePerson"><option v-for="p in people" :key="p.id" :value="p.id">{{ p.name }} · {{ p.code }}</option></UiSelect><small v-if="errors.personId" id="assignment-person-error" class="error" aria-live="polite">{{ errors.personId }}</small></div></label><p v-if="hidePersonCard && selection && !selection.writable" class="error">人员不在资产办理授权范围内。</p></template>
      <section v-if="selection && !hidePersonCard" :id="intent.personId || fixedReturn ? 'personId' : undefined" class="binding-card"><template v-if="isReturn"><span class="muted">领用人</span><h3 class="return-person-name">{{ selection.person.name }} <small>{{ selection.person.code }}</small></h3></template><template v-else><h3>{{ selection.person.name }}</h3><p>{{ selection.person.code }} · {{ selection.person.enabled ? '启用' : '停用（仍允许正常归还）' }} · 版本{{ selection.person.version }}</p></template><p v-if="!selection.writable" class="error">人员不在资产办理授权范围内。</p><small v-if="(intent.personId || fixedReturn) && errors.personId" class="error" aria-live="polite">{{ errors.personId }}</small></section>
      <template v-if="selection && intent.mode === 'issue' && !knownDeviceIssue">
        <section v-for="type in issueTypes" :id="chosen[type] ? 'item-' + chosen[type] : 'slot-' + type" tabindex="-1" :key="type" class="issue-slot">
          <div class="issue-slot-heading"><h3>{{ DEVICE_TYPES[type] }}</h3><span class="badge" :class="{ warning: selection.slots[type] !== 'UNASSIGNED' }">{{ SLOT_NAMES[selection.slots[type]] }}</span></div>
          <template v-if="selection.slots[type] === 'UNASSIGNED' && selection.person.enabled && selection.writable">
            <p v-if="!(candidates[type]?.rows || []).length" class="muted">暂无可领{{ DEVICE_TYPES[type] }}</p>
            <div v-else class="field-control"><UiSelect v-model="chosen[type]" :aria-label="'可领' + DEVICE_TYPES[type]"><option value="">本次不领用</option><option v-for="d in candidates[type].rows" :key="d.id" :value="d.id">{{ d.code }} · {{ d.name }}</option></UiSelect><small v-if="errors['item-' + chosen[type]]" class="error" aria-live="polite">{{ errors['item-' + chosen[type]] }}</small></div>
          </template>
          <p v-else class="muted">该槽位不可新领用；未知、冲突或不可见不能当作未领用。</p>
        </section>
        <div v-if="errors.items || errors.acknowledged" id="items"><small v-if="errors.items" class="error" aria-live="polite">{{ errors.items }}</small><small v-if="errors.acknowledged" class="error" aria-live="polite">{{ errors.acknowledged }}</small></div>
      </template>
      <section v-if="selection && isReturn" id="items" class="return-equipment" aria-labelledby="return-equipment-heading">
        <div class="return-equipment-heading"><h3 id="return-equipment-heading">归还装备</h3><label v-if="selectableReturnRows.length > 1" class="inline-check"><input type="checkbox" :checked="allReturnsSelected" :indeterminate="selectedDevices.length > 0 && !allReturnsSelected" @change="toggleAllReturns" />全选</label></div>
        <p v-if="!returnRows.length" class="return-empty">暂无可归还装备</p>
        <div v-for="r in returnRows" :id="'item-' + r.deviceId" :key="r.id" tabindex="-1" class="return-equipment-row">
          <label class="return-item" :class="{ 'return-item--selected': returns[r.id]?.selected, 'return-item--disabled': !r.writable }">
            <input v-model="returns[r.id].selected" type="checkbox" :disabled="!r.writable" :aria-label="'归还 ' + r.code + ' ' + DEVICE_TYPES[r.type]" />
            <span class="return-item-device"><strong>{{ DEVICE_TYPES[r.type] }}</strong><span>{{ r.code }}</span></span>
            <span class="return-item-time"><span class="muted">领用时间</span><time :datetime="r.startedAt || undefined">{{ beijingTime(r.startedAt) }}</time></span>
          </label>
          <small v-if="!r.writable" class="error">无权归还此装备</small><small v-if="errors['item-' + r.deviceId]" class="error" aria-live="polite">{{ errors['item-' + r.deviceId] }}</small>
        </div>
        <small v-if="errors.items" class="error" aria-live="polite">{{ errors.items }}</small><small v-if="errors.acknowledged" class="error" aria-live="polite">{{ errors.acknowledged }}</small>
      </section>
      <section v-if="knownDeviceIssue && fixedDevice" id="items" class="issue-equipment" aria-labelledby="issue-equipment-heading">
        <h3 id="issue-equipment-heading">领用装备</h3>
        <div class="issue-device" :class="{ 'issue-device--ready': fixedIssuable }" :id="selection ? (fixedIssuable ? 'item-' + fixedDevice.id : 'slot-' + fixedDevice.type) : undefined" :tabindex="selection ? -1 : undefined">
          <span class="return-item-device"><strong>{{ DEVICE_TYPES[fixedDevice.type] }}</strong><span>{{ fixedDevice.code }}<template v-if="fixedDevice.name"> · {{ fixedDevice.name }}</template></span></span>
          <span v-if="selection" class="badge" :class="{ warning: !fixedIssuable }">{{ SLOT_NAMES[selection.slots[fixedDevice.type]] || '领用情况不明' }}</span>
        </div>
        <p v-if="fixedIssueReason" class="muted">{{ fixedIssueReason }}</p>
        <small v-if="errors.acknowledged" class="error" aria-live="polite">{{ errors.acknowledged }}</small>
        <small v-if="errors.items" class="error" aria-live="polite">{{ errors.items }}</small>
        <small v-if="errors['item-' + fixedDevice.id]" class="error" aria-live="polite">{{ errors['item-' + fixedDevice.id] }}</small>
      </section>
    </fieldset><div v-if="formError" data-form-error tabindex="-1" role="alert" class="error"><p>{{ formError }}</p><button type="button" class="button" :disabled="busy" @click="reload">重新读取（清除本次选择）</button></div></div><div class="dialog-form-footer"><span>{{ intent.mode === 'issue' ? '每人可同时领用：手表1台、安全带1条、安全帽1顶' : `已选 ${selectedDevices.length} 件装备` }}</span><div class="actions"><button type="button" class="button" :disabled="busy" @click="close">取消</button><button class="button primary" :disabled="busy || loading || !selection?.writable || !selectedDevices.length">{{ busy ? (isReturn ? '正在归还…' : '正在办理…') : (isReturn ? '保存' : '确认办理') }}</button></div></div>
  </form>
</ModalPanel><p v-if="notice" class="notice assignment-notice" role="status">{{ notice }}<button class="button" @click="notice = ''">关闭提示</button></p></template>
<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
import { DEVICE_TYPES } from '../deviceData'
import { SLOT_NAMES, assignmentWarnings } from '../assignmentData'
import { beijingTime } from '../tablePresentation'
import ModalPanel from './ModalPanel.vue'
import { useConfirmation } from '../confirmation'
import { useFormFeedback } from '../formFeedback'
const confirmDiscard = useConfirmation()
const store = useAdminStore(), provider = getAdminProvider(), intent = ref(null), loading = ref(false), busy = ref(false), dirty = ref(false), error = ref(null), notice = ref(''), selection = ref(null), personId = ref(''), people = ref([]), candidates = ref({}), chosen = ref({}), returns = ref({}), acknowledged = ref(false), fixedReturn = ref(false), fixedDevice = ref(null)
let controller, generation = 0, operationId, previousGuard
const isReturn = computed(() => intent.value?.mode === 'return')
const knownDeviceIssue = computed(() => intent.value?.mode === 'issue' && !!intent.value.deviceId)
const hidePersonCard = computed(() => knownDeviceIssue.value && !intent.value?.personId)
const fixedIssuable = computed(() => {
  const device = fixedDevice.value, current = selection.value
  return !!(knownDeviceIssue.value && device && current?.person.enabled && current.writable && current.slots[device.type] === 'UNASSIGNED')
})
const fixedIssueReason = computed(() => {
  const current = selection.value
  if (!knownDeviceIssue.value || !fixedDevice.value || !current || fixedIssuable.value) return ''
  if (!current.person.enabled) return '停用人员不能新领用。'
  if (!current.writable) return ''
  return '该槽位不可新领用；未知、冲突或不可见不能当作未领用。'
})
const issueTypes = computed(() => fixedDevice.value ? [fixedDevice.value.type] : Object.keys(DEVICE_TYPES))
const returnRows = computed(() => (selection.value?.current || []).filter(r => r.relation === 'ASSIGNED' && (!intent.value?.deviceId || r.deviceId === intent.value.deviceId)))
const selectedDevices = computed(() => intent.value?.mode === 'issue' ? Object.values(candidates.value).flatMap(c => c.rows).filter(d => Object.values(chosen.value).includes(d.id)) : returnRows.value.filter(r => r.writable && returns.value[r.id]?.selected).map(r => ({ id: r.deviceId, code: r.code, type: r.type, warnings: r.warnings })))
const selectableReturnRows = computed(() => returnRows.value.filter(r => r.writable))
const allReturnsSelected = computed(() => selectableReturnRows.value.length > 0 && selectableReturnRows.value.every(r => returns.value[r.id]?.selected))
function toggleAllReturns(event) { for (const r of selectableReturnRows.value) returns.value[r.id].selected = event.target.checked; dirty.value = true }
const form = computed(() => ({ personId: personId.value, acknowledged: isReturn.value || acknowledged.value, items: selectedDevices.value.map(d => d.id), ...Object.fromEntries(selectedDevices.value.map(d => ['item-' + d.id, d.id])) }))
const { formRef, errors, formError } = useFormFeedback(form, () => error.value, '')
function report(e) { error.value = e }
async function read(kind, input) { const id = generation, signal = controller.signal; const res = await provider.query(kind, { siteId: store.siteId, ...input }, { signal }); if (id !== generation || signal.aborted) throw new DOMException('查询已取消', 'AbortError'); if (res.data.availability === 'NOT_CONNECTED') throw Object.assign(new Error(res.data.reason), { errorCode: 'NOT_CONNECTED', requestId: res.requestId }); return res.data }
async function task(work) { if (busy.value) return; const id = ++generation; controller?.abort(); controller = new AbortController(); loading.value = true; error.value = null; try { await work() } catch (e) { if (id === generation && e.name !== 'AbortError') { report(e); if (e.code === 401) provider.invalidate() } } finally { if (id === generation) loading.value = false } }
function clearSelection() { selection.value = null; chosen.value = {}; candidates.value = {}; returns.value = {}; acknowledged.value = false }
async function peopleQuery() {
  const rows = new Map()
  for (let pageNum = 1; ; pageNum++) {
    const res = await read('assignmentCandidates', { resource: 'people', purpose: intent.value.mode, deviceId: intent.value.deviceId, pageNum, pageSize: 100 })
    for (const person of res.rows) rows.set(person.id, person)
    if (!res.rows.length || res.pageNum * res.pageSize >= res.total) break
  }
  people.value = [...rows.values()]
}
async function loadAllDevices(type) {
  const rows = []
  let total = 0
  for (let pageNum = 1; pageNum <= 20; pageNum++) {
    const res = await read('assignmentCandidates', { resource: 'devices', personId: personId.value, type, pageNum, pageSize: 100, keyword: '' })
    rows.push(...(res.rows || []))
    total = res.total || rows.length
    if (!res.rows?.length || pageNum * (res.pageSize || 100) >= total) break
  }
  candidates.value[type] = { rows, total, pageNum: 1 }
  chosen.value[type] = rows.some(d => d.id === chosen.value[type]) ? chosen.value[type] : ''
}
async function selectionQuery() {
  if (!personId.value) return
  selection.value = await read('assignmentCandidates', { resource: 'selection', personId: personId.value })
  if (intent.value.mode === 'issue') {
    for (const type of issueTypes.value) {
      if (fixedDevice.value) { const current = selection.value; candidates.value[type] = { rows: [fixedDevice.value], total: 1, pageNum: 1 }; chosen.value[type] = current.slots[type] === 'UNASSIGNED' && current.person.enabled && current.writable ? fixedDevice.value.id : '' }
      else await loadAllDevices(type)
    }
  } else for (const r of returnRows.value) returns.value[r.id] = { selected: r.writable && (Boolean(intent.value.deviceId) || selectableReturnRows.value.length === 1) }
}
function choosePerson() { dirty.value = true; clearSelection(); task(selectionQuery) }
async function initialize() {
  clearSelection(); people.value = []; personId.value = intent.value.personId || ''; fixedReturn.value = false; fixedDevice.value = null; operationId = crypto.randomUUID()
  if (intent.value.deviceId) {
    const d = await read('device', { id: intent.value.deviceId }); fixedDevice.value = { ...d, warnings: assignmentWarnings(d) }
    if (intent.value.mode === 'return') { const rows = (await read('assignments', { deviceId: d.id })).rows; if (!rows[0]?.personId || rows[0].relation !== 'ASSIGNED') throw new Error('无法确认当前领用人，请刷新后重试'); personId.value = rows[0].personId; fixedReturn.value = true }
  }
  if (personId.value) await selectionQuery(); else await peopleQuery()
}
function cleanup() { generation++; controller?.abort(); intent.value = null; store.assignmentIntent = null; dirty.value = false; busy.value = false; loading.value = false; if (store.leaveGuard === guard) store.leaveGuard = previousGuard }
async function close() { if (busy.value || dirty.value && !await confirmDiscard({ message: '本次领用或归还尚未提交，放弃后将清除当前选择。' })) return false; cleanup(); return true }
const guard = () => close()
async function reload() { if (busy.value || dirty.value && !await confirmDiscard({ title: '重新读取办理数据？', message: '重新读取将清除本次选择。', confirmText: '重新读取' })) return; dirty.value = false; task(initialize) }
async function submit() {
  if (busy.value || loading.value || !selection.value?.writable || !selectedDevices.value.length) return
  const id = generation
  const items = intent.value.mode === 'issue' ? selectedDevices.value.map(d => ({ deviceId: d.id, deviceVersion: d.version })) : returnRows.value.filter(r => r.writable && returns.value[r.id]?.selected).map(r => ({ deviceId: r.deviceId, deviceVersion: r.deviceVersion, assignmentId: r.id, assignmentVersion: r.version, condition: 'GOOD' }))
  busy.value = true; error.value = null
  try { const result = await provider.execute('assignments.' + intent.value.mode, { siteId: store.siteId, personId: personId.value, personVersion: selection.value.person.version, operationId, acknowledged: true, items }, { signal: controller.signal }); if (id !== generation) return; notice.value = isReturn.value ? `归还成功，共 ${result.data.history.length} 件装备。` : `办理成功：${result.data.batchId}，共${result.data.history.length}件。`; cleanup() } catch (e) { if (id === generation && e.name !== 'AbortError') { report(e); if (e.code === 401) provider.invalidate() } } finally { if (id === generation) busy.value = false }
}
watch(() => store.assignmentIntent, value => { if (!value) return; previousGuard = store.leaveGuard; intent.value = { ...value }; store.leaveGuard = guard; dirty.value = false; notice.value = ''; task(initialize) })
const unsubscribe = provider.subscribe(e => { if (['identity', 'expired', 'reset', 'context', 'authorization'].includes(e.kind)) { cleanup(); notice.value = '' } })
onBeforeUnmount(() => { cleanup(); unsubscribe() })
</script>

<style scoped>
.return-person-name { display: flex; align-items: baseline; gap: 12px; margin: 6px 0 0; }
.return-person-name small { font-size: 14px; font-weight: 400; }
.return-equipment { margin-top: 20px; }
.return-equipment-heading { display: flex; align-items: center; justify-content: space-between; gap: 16px; margin-bottom: 12px; }
.return-equipment-heading h3 { margin: 0; }
.assignment-form .return-equipment-heading .inline-check { min-height: 36px; padding: 0 4px; }
.return-equipment-row + .return-equipment-row { margin-top: 10px; }
.assignment-form .return-item { display: grid; grid-template-columns: 18px minmax(0, 1fr) auto; align-items: center; gap: 14px; padding: 16px; border: 1px solid var(--line); border-radius: 4px; cursor: pointer; }
.assignment-form .return-item--selected { border-color: var(--blue); background: var(--soft-blue); }
.assignment-form .return-item:hover:not(.return-item--disabled) { border-color: var(--blue); }
.assignment-form .return-item--disabled { cursor: default; opacity: .65; }
.return-item input { width: 16px; min-height: 16px; margin: 0; }
.return-item-device, .return-item-time { display: flex; flex-direction: column; gap: 4px; min-width: 0; overflow-wrap: anywhere; }
.return-item-time { text-align: right; font-size: 13px; }
.return-empty { padding: 24px 0; text-align: center; }
.issue-equipment { margin-top: 32px; }
.issue-equipment h3 { margin: 0 0 12px; }
.issue-device { display: grid; grid-template-columns: minmax(0, 1fr) auto; align-items: center; gap: 14px; padding: 16px; border: 1px solid var(--line); border-radius: 4px; }
.issue-device--ready { border-color: var(--blue); background: var(--soft-blue); }
.issue-equipment :is(.muted, .error) { display: block; margin-top: 8px; }
.issue-slot { margin-top: 22px; }
.issue-slot-heading { display: flex; align-items: center; gap: 10px; margin-bottom: 10px; }
.issue-slot-heading h3 { margin: 0; }
.issue-slot .error { display: block; margin-top: 8px; }
@media (max-width: 600px) {
  .assignment-form .return-item { grid-template-columns: 18px minmax(0, 1fr); }
  .return-item-time { grid-column: 2; text-align: left; }
}
</style>
