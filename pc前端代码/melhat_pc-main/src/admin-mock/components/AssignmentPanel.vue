<template><ModalPanel :open="!!intent" side heading-id="assignment-heading" :title="intent?.mode === 'issue' ? '本地装备领用' : '本地装备归还'" @close="close">
  <p class="notice">整次提交全部成功或全部失败。只操作本页内存，刷新恢复种子。</p>
  <p v-if="loading" role="status">正在读取候选与关系…</p>
  <div v-if="error" ref="errorBox" tabindex="-1" role="alert" class="notice error"><strong>办理未完成</strong><p>{{ error.message }} · {{ error.errorCode }} · {{ error.requestId }}</p><ul><li v-for="(message, key) in error.fields" :key="key"><a :href="'#' + key" @click.prevent="focus(key)">{{ message }}</a></li></ul><button class="button" :disabled="busy" @click="reload">重新读取（清除本次选择）</button></div>
  <form v-if="intent" class="master-form assignment-form" @submit.prevent="submit" @input="dirty = true; acknowledged = false" @change="dirty = true">
    <fieldset :disabled="busy || loading">
      <template v-if="!intent.personId && !fixedReturn"><label>人员关键词<input v-model="personKeyword" aria-label="人员关键词" maxlength="100" /></label><div class="actions"><button class="button" type="button" @click="loadPeople(1)">查询人员候选</button><button class="button" type="button" :disabled="peoplePage <= 1" @click="loadPeople(peoplePage - 1)">上一页人员</button><button class="button" type="button" :disabled="peoplePage * 20 >= peopleTotal" @click="loadPeople(peoplePage + 1)">下一页人员</button><span>共{{ peopleTotal }}人 · 第{{ peoplePage }}页</span></div><label>选择人员<select id="personId" v-model="personId" aria-label="选择人员" @change="choosePerson"><option value="">请选择同厂站人员</option><option v-for="p in people" :key="p.id" :value="p.id">{{ p.name }} · {{ p.code }}</option></select></label></template>
      <section v-if="selection" class="binding-card"><h3>{{ selection.person.name }}</h3><p>{{ selection.person.code }} · {{ selection.person.enabled ? '启用' : '停用（仍允许正常归还）' }} · 版本{{ selection.person.version }}</p><p v-if="!selection.writable" class="error">人员不在资产办理授权范围内。</p></section>
      <template v-if="selection && intent.mode === 'issue'"><section v-for="type in issueTypes" :id="chosen[type] ? 'item-' + chosen[type] : 'slot-' + type" tabindex="-1" :key="type" class="binding-card"><small v-if="error?.fields?.['item-' + chosen[type]]" class="error">{{ error.fields['item-' + chosen[type]] }}</small><h3>{{ DEVICE_TYPES[type] }} <span class="badge">{{ SLOT_NAMES[selection.slots[type]] }}</span></h3><template v-if="selection.slots[type] === 'UNASSIGNED' && selection.person.enabled && selection.writable"><label>可领{{ DEVICE_TYPES[type] }}<select v-model="chosen[type]" :aria-label="'可领' + DEVICE_TYPES[type]" :disabled="!!intent.deviceId"><option value="">本次不领用</option><option v-for="d in candidates[type]?.rows || []" :key="d.id" :value="d.id">{{ d.code }} · {{ d.name }}</option></select></label><template v-if="!intent.deviceId"><label>设备关键词<input v-model="keywords[type]" :aria-label="DEVICE_TYPES[type] + '候选关键词'" maxlength="100" /></label><div class="actions"><button type="button" class="button" @click="loadDevices(type, 1)">查询{{ DEVICE_TYPES[type] }}</button><button type="button" class="button" :disabled="(candidates[type]?.pageNum || 1) <= 1" @click="loadDevices(type, candidates[type].pageNum - 1)">上一页{{ DEVICE_TYPES[type] }}</button><button type="button" class="button" :disabled="!candidates[type] || candidates[type].pageNum * 20 >= candidates[type].total" @click="loadDevices(type, candidates[type].pageNum + 1)">下一页{{ DEVICE_TYPES[type] }}</button></div><small>共{{ candidates[type]?.total || 0 }}件候选；分页或查询会清除此类型选择。</small></template></template><p v-else class="muted">该槽位不可新领用；未知、冲突或不可见不能当作未领用。</p></section></template>
      <template v-if="selection && intent.mode === 'return'"><p v-if="!returnRows.length" class="query-state">没有可办理的正常有效关系。</p><section v-for="r in returnRows" :id="'item-' + r.deviceId" :key="r.id" tabindex="-1" class="binding-card"><label class="inline-check"><input v-model="returns[r.id].selected" type="checkbox" :disabled="!r.writable || !!intent.deviceId" />归还 {{ r.code }} · {{ DEVICE_TYPES[r.type] }}</label><p class="muted">领用开始：{{ r.startedAt || '未知（初始绑定快照）' }}</p><template v-if="returns[r.id].selected"><label>归还结果<select v-model="returns[r.id].condition" :aria-label="r.code + '归还结果'" @change="loadHandlers(r)"><option value="GOOD">完好</option><option value="REPAIR">需检修</option></select></label><template v-if="returns[r.id].condition === 'REPAIR'"><label>故障说明（必填）<textarea v-model="returns[r.id].reason" :aria-label="r.code + '故障说明'" rows="3" maxlength="500" /></label><label>处理人（必选）<select v-model="returns[r.id].handlerId" :aria-label="r.code + '处理人'"><option value="">请选择有效处理人</option><option v-for="h in handlers[r.id]?.rows || []" :key="h.id" :value="h.id">{{ h.name }}</option></select></label><div class="actions"><button type="button" class="button" :disabled="(handlers[r.id]?.pageNum || 1) <= 1" @click="loadHandlers(r, handlers[r.id].pageNum - 1)">上一页处理人</button><button type="button" class="button" :disabled="!handlers[r.id] || handlers[r.id].pageNum * 20 >= handlers[r.id].total" @click="loadHandlers(r, handlers[r.id].pageNum + 1)">下一页处理人</button></div><p v-if="handlers[r.id] && !handlers[r.id].total" class="error">无有效处理人，无法提交；请先由管理员配置有本设备办理权限的启用账号。</p><small v-if="error?.fields?.['item-' + r.deviceId]" class="error">{{ error.fields['item-' + r.deviceId] }}</small></template></template></section></template>
      <section v-if="selection" class="notice"><h3>本次办理清单</h3><ul><li v-for="d in selectedDevices" :key="d.id">{{ d.code }} · {{ DEVICE_TYPES[d.type] }}<small class="disabled-reason">{{ (d.warnings || []).join('；') }}</small></li></ul><p v-if="!selectedDevices.length">尚未选择装备。</p><p>离线、通信未知、过期及资料待补充不会阻止本地台账办理。</p><label class="inline-check"><input id="acknowledged" v-model="acknowledged" type="checkbox" @input.stop />仅本地台账办理，不代表设备适合真实作业</label></section>
    </fieldset><div class="form-footer"><span>{{ intent.mode === 'issue' ? '一人同类最多一件' : '未勾选的设备继续保持领用' }}</span><div class="actions"><button type="button" class="button" :disabled="busy" @click="close">取消</button><button class="button primary" :disabled="busy || loading || !selection?.writable || !selectedDevices.length || !acknowledged || handlerUnavailable">{{ busy ? '正在办理…' : '确认本地办理' }}</button></div></div>
  </form>
</ModalPanel><p v-if="notice" class="notice assignment-notice" role="status">{{ notice }}<button class="button" @click="notice = ''">关闭提示</button></p></template>
<script setup>
import { ref, computed, watch, onBeforeUnmount, nextTick } from 'vue'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
import { DEVICE_TYPES } from '../deviceData'
import { SLOT_NAMES, assignmentWarnings } from '../assignmentData'
import ModalPanel from './ModalPanel.vue'
const store = useAdminStore(), provider = getAdminProvider(), intent = ref(null), loading = ref(false), busy = ref(false), dirty = ref(false), error = ref(null), errorBox = ref(null), notice = ref(''), selection = ref(null), personId = ref(''), people = ref([]), peoplePage = ref(1), peopleTotal = ref(0), personKeyword = ref(''), candidates = ref({}), keywords = ref({}), chosen = ref({}), returns = ref({}), handlers = ref({}), acknowledged = ref(false), fixedReturn = ref(false), fixedDevice = ref(null)
let controller, generation = 0, operationId, previousGuard
const issueTypes = computed(() => fixedDevice.value ? [fixedDevice.value.type] : Object.keys(DEVICE_TYPES))
const returnRows = computed(() => (selection.value?.current || []).filter(r => r.relation === 'ASSIGNED' && (!intent.value?.deviceId || r.deviceId === intent.value.deviceId)))
const handlerUnavailable = computed(() => returnRows.value.some(r => returns.value[r.id]?.selected && returns.value[r.id]?.condition === 'REPAIR' && handlers.value[r.id]?.total === 0))
const selectedDevices = computed(() => intent.value?.mode === 'issue' ? Object.values(candidates.value).flatMap(c => c.rows).filter(d => Object.values(chosen.value).includes(d.id)) : returnRows.value.filter(r => returns.value[r.id]?.selected).map(r => ({ id: r.deviceId, code: r.code, type: r.type, warnings: r.warnings })))
function focus(key) { document.getElementById(key)?.focus(); document.getElementById(key)?.scrollIntoView({ block: 'center' }) }
async function report(e) { error.value = e; await nextTick(); errorBox.value?.focus() }
async function read(kind, input) { const id = generation, signal = controller.signal; const res = await provider.query(kind, { siteId: store.siteId, ...input }, { signal }); if (id !== generation || signal.aborted) throw new DOMException('查询已取消', 'AbortError'); if (res.data.availability === 'NOT_CONNECTED') throw Object.assign(new Error(res.data.reason), { errorCode: 'NOT_CONNECTED', requestId: res.requestId }); return res.data }
async function task(work) { if (busy.value) return; const id = ++generation; controller?.abort(); controller = new AbortController(); loading.value = true; error.value = null; try { await work() } catch (e) { if (id === generation && e.name !== 'AbortError') { report(e); if (e.code === 401) provider.invalidate() } } finally { if (id === generation) loading.value = false } }
function clearSelection() { selection.value = null; chosen.value = {}; candidates.value = {}; returns.value = {}; handlers.value = {}; acknowledged.value = false }
async function peopleQuery(page) { peoplePage.value = page; const res = await read('assignmentCandidates', { resource: 'people', purpose: intent.value.mode, deviceId: intent.value.deviceId, pageNum: page, keyword: personKeyword.value }); people.value = res.rows; peopleTotal.value = res.total }
function loadPeople(page) { dirty.value = true; personId.value = ''; clearSelection(); task(() => peopleQuery(page)) }
async function devicesQuery(type, page) { chosen.value[type] = ''; const res = await read('assignmentCandidates', { resource: 'devices', personId: personId.value, type, pageNum: page, keyword: keywords.value[type] || '' }); candidates.value[type] = res }
function loadDevices(type, page) { dirty.value = true; acknowledged.value = false; task(() => devicesQuery(type, page)) }
async function selectionQuery() {
  if (!personId.value) return
  selection.value = await read('assignmentCandidates', { resource: 'selection', personId: personId.value })
  if (intent.value.mode === 'issue') {
    for (const type of issueTypes.value) {
      if (fixedDevice.value) { candidates.value[type] = { rows: [fixedDevice.value], total: 1, pageNum: 1 }; chosen.value[type] = fixedDevice.value.id }
      else await devicesQuery(type, 1)
    }
  } else for (const r of returnRows.value) returns.value[r.id] = { selected: Boolean(intent.value.deviceId), condition: 'GOOD', reason: '', handlerId: '' }
}
function choosePerson() { dirty.value = true; clearSelection(); task(selectionQuery) }
function loadHandlers(r, page = 1) { acknowledged.value = false; returns.value[r.id].handlerId = ''; if (returns.value[r.id].condition !== 'REPAIR') return; task(async () => { handlers.value[r.id] = await read('repairAssignees', { deviceId: r.deviceId, pageNum: page }) }) }
async function initialize() {
  clearSelection(); personId.value = intent.value.personId || ''; fixedReturn.value = false; fixedDevice.value = null; operationId = crypto.randomUUID()
  if (intent.value.deviceId) {
    const d = await read('device', { id: intent.value.deviceId }); fixedDevice.value = { ...d, warnings: assignmentWarnings(d) }
    if (intent.value.mode === 'return') { const rows = (await read('assignments', { deviceId: d.id })).rows; if (!rows[0]?.personId || rows[0].relation !== 'ASSIGNED') throw new Error('领用关系未知、冲突或人员不可见，不能归还'); personId.value = rows[0].personId; fixedReturn.value = true }
  }
  if (personId.value) await selectionQuery(); else await peopleQuery(1)
}
function cleanup() { generation++; controller?.abort(); intent.value = null; store.assignmentIntent = null; dirty.value = false; busy.value = false; loading.value = false; if (store.leaveGuard === guard) store.leaveGuard = previousGuard }
function close() { if (busy.value || dirty.value && !window.confirm('尚有未提交的办理选择，确定放弃吗？')) return false; cleanup(); return true }
const guard = () => close()
function reload() { if (dirty.value && !window.confirm('重新读取将清除本次选择，确定继续吗？')) return; dirty.value = false; task(initialize) }
async function submit() {
  if (busy.value || loading.value) return
  const id = generation
  const items = intent.value.mode === 'issue' ? selectedDevices.value.map(d => ({ deviceId: d.id, deviceVersion: d.version })) : returnRows.value.filter(r => returns.value[r.id]?.selected).map(r => { const v = returns.value[r.id], h = handlers.value[r.id]?.rows.find(h => h.id === v.handlerId); return { deviceId: r.deviceId, deviceVersion: r.deviceVersion, assignmentId: r.id, assignmentVersion: r.version, condition: v.condition, ...(v.condition === 'REPAIR' ? { reason: v.reason, handlerId: v.handlerId, handlerVersion: h?.version } : {}) } })
  busy.value = true; error.value = null
  try { const result = await provider.execute('assignments.' + intent.value.mode, { siteId: store.siteId, personId: personId.value, personVersion: selection.value.person.version, operationId, acknowledged: acknowledged.value, items }, { signal: controller.signal }); if (id !== generation) return; notice.value = `本地办理成功：${result.data.batchId}，共${result.data.history.length}件。`; cleanup() } catch (e) { if (id === generation && e.name !== 'AbortError') { report(e); if (e.code === 401) provider.invalidate() } } finally { if (id === generation) busy.value = false }
}
watch(() => store.assignmentIntent, value => { if (!value) return; previousGuard = store.leaveGuard; intent.value = { ...value }; store.leaveGuard = guard; dirty.value = false; personKeyword.value = ''; keywords.value = {}; notice.value = ''; task(initialize) })
const unsubscribe = provider.subscribe(e => { if (['identity', 'expired', 'reset', 'context', 'authorization'].includes(e.kind)) { cleanup(); notice.value = '' } })
onBeforeUnmount(() => { cleanup(); unsubscribe() })
</script>
