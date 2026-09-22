<template>
  <ModalPanel :open="!!intent" side heading-id="maintenance-heading" title="设备运维本地办理" @close="close">
    <p class="notice">只修改当前页面。本地验收不代表正式审批或设备安全认证；不改变通信、上报时间或真实能力。</p>
    <p v-if="loading" role="status">正在读取设备、工单与处理人…</p>
    <div v-if="error" ref="errorBox" tabindex="-1" role="alert" class="notice error"><strong>办理未完成</strong><p>{{ error.message }} · {{ error.errorCode }} · {{ error.requestId }}</p><ul><li v-for="(message, key) in error.fields" :key="key"><a href="#" @click.prevent="focus(key)">{{ message }}</a></li></ul><button class="button" :disabled="busy" @click="reload">重新读取（清除本次输入）</button></div>
    <form v-if="device" class="master-form assignment-form maintenance-form" novalidate @submit.prevent="submit" @input="changed" @change="changed">
      <fieldset v-show="!reviewing" :disabled="busy || loading || reviewing">
        <section class="binding-card"><h3>{{ device.code }} · {{ device.name }}</h3><p>{{ DEVICE_FILTERS.lifecycle[device.lifecycle] }} · {{ DEVICE_FILTERS.relation[device.relation] }} · 设备版本 {{ device.version }}<template v-if="order"> / 工单版本 {{ order.version }}</template></p><p v-if="order">工单 {{ order.id }} · {{ PHASES[order.phase] }} · 当前处理人 {{ order.currentHandlerName || '待指派' }}</p></section>
        <label>办理操作<select v-model="type" aria-label="办理操作" @change="chooseAction"><option v-for="(_, key) in actions" :key="key" :value="key">{{ ACTIONS[key] }}</option></select></label>
        <p v-if="reason" class="notice warning" role="status">不可办理：{{ reason }}</p>
        <p v-if="order && !order.handlerValid && order.status === 'OPEN'" class="notice">处理人待指派、已停用或失去资产办理权限，请由有权管理员重新指派。</p>
        <template v-if="needsHandler"><label>处理人（必选）<select id="maint-handlerId" v-model="form.handlerId" aria-label="维修处理人"><option value="">请选择有效账号</option><option v-for="h in handlers?.rows || []" :key="h.id" :value="h.id">{{ h.name }}</option></select><small v-if="error?.fields?.handlerId" class="error">{{ error.fields.handlerId }}</small></label><div class="actions"><button type="button" class="button" :disabled="!handlers || handlers.pageNum <= 1" @click="loadHandlers(handlers.pageNum - 1)">上一页处理人</button><button type="button" class="button" :disabled="!handlers || handlers.pageNum * 20 >= handlers.total" @click="loadHandlers(handlers.pageNum + 1)">下一页处理人</button><small>共 {{ handlers?.total || 0 }} 个有效账号</small></div></template>
        <label v-if="needsReason">{{ type === 'maintenance.create' ? '故障说明' : '办理原因' }}（必填）<textarea id="maint-reason" v-model="form.reason" aria-label="办理原因" rows="3" maxlength="1000" /><small v-if="error?.fields?.reason" class="error">{{ error.fields.reason }}</small></label>
        <label v-if="type === 'maintenance.inspect'">维修内容（必填）<textarea id="maint-repairContent" v-model="form.repairContent" aria-label="维修内容" rows="3" maxlength="1000" /><small v-if="error?.fields?.repairContent" class="error">{{ error.fields.repairContent }}</small></label>
        <label v-if="needsInspection">{{ type === 'maintenance.scrap' ? '无法修复说明' : '检查／检测说明' }}（必填）<textarea id="maint-inspection" v-model="form.inspection" aria-label="检查说明" rows="3" maxlength="1000" /><small v-if="error?.fields?.inspection" class="error">{{ error.fields.inspection }}</small></label>
        <label v-if="type === 'maintenance.inspect'">检测结果<select id="maint-result" v-model="form.result" aria-label="检测结果"><option value="FAIL">未通过，继续维修</option><option value="PASS">通过，本地验收回库存</option></select></label>
        <label v-if="needsAck" class="inline-check"><input id="maint-acknowledged" v-model="form.acknowledged" type="checkbox" />检查通过，仅本地验收，不代表真实设备安全认证</label>
        <label v-if="scrapping">复输设备编号（区分大小写）<input id="maint-codeConfirmation" v-model="form.codeConfirmation" aria-label="复输设备编号" autocomplete="off" /><small>{{ device.code }}</small><small v-if="error?.fields?.codeConfirmation" class="error">{{ error.fields.codeConfirmation }}</small></label>
        <p class="muted">{{ warnings.join('；') }}。这些提醒不自动产生检测结果。</p>
      </fieldset>
      <section v-if="reviewing" ref="reviewBox" tabindex="-1" class="reset-confirm" role="alert"><h3>再次确认报废 {{ device.code }}？</h3><p>{{ form.reason }}</p><p>报废后档案只读、不能领用或普通恢复。{{ order ? '此未完成维修单将同时关闭为“无法修复并报废”。' : '历史保留，资产总数不减少。' }}</p><button type="button" class="button" :disabled="busy" @click="reviewing = false">返回核对</button></section>
      <div class="form-footer"><span>操作时间由服务生成 · UTC</span><div class="actions"><button type="button" class="button" :disabled="busy" @click="close">取消</button><button class="button" :class="scrapping ? 'danger' : 'primary'" :disabled="busy || loading || !!reason || versionConflict">{{ busy ? '正在办理…' : reviewing ? '确认报废（不可恢复）' : scrapping ? '核对报废信息' : '确认本地办理' }}</button></div></div>
    </form>
  </ModalPanel>
  <p v-if="notice" class="notice assignment-notice" role="status">{{ notice }}<button class="button" @click="notice = ''">关闭提示</button></p>
</template>
<script setup>
import { ref, computed, watch, nextTick, onBeforeUnmount } from 'vue'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
import { ACTIONS, PHASES } from '../maintenanceData'
import { DEVICE_FILTERS } from '../deviceData'
import { assignmentWarnings } from '../assignmentData'
import ModalPanel from './ModalPanel.vue'
const store = useAdminStore(), provider = getAdminProvider(), intent = ref(null), device = ref(null), order = ref(null), type = ref(''), form = ref({}), handlers = ref(null), loading = ref(false), busy = ref(false), dirty = ref(false), error = ref(null), errorBox = ref(null), reviewing = ref(false), reviewBox = ref(null), notice = ref('')
let controller, generation = 0, operationId, previousGuard
const actions = computed(() => order.value?.actions || device.value?.maintenanceActions || {}), reason = computed(() => actions.value[type.value] ?? '请重新读取对象'), warnings = computed(() => device.value ? assignmentWarnings(device.value) : [])
const scrapping = computed(() => ['devices.scrap', 'maintenance.scrap'].includes(type.value)), needsHandler = computed(() => ['maintenance.create', 'maintenance.assign'].includes(type.value)), needsReason = computed(() => !['maintenance.start', 'maintenance.inspect'].includes(type.value)), needsInspection = computed(() => ['maintenance.inspect', 'devices.restore', 'maintenance.scrap'].includes(type.value)), needsAck = computed(() => type.value === 'devices.restore' || type.value === 'maintenance.inspect' && form.value.result === 'PASS'), versionConflict = computed(() => error.value?.errorCode === 'VERSION_CONFLICT')
function freshForm() { return { handlerId: '', reason: '', repairContent: '', inspection: '', result: 'FAIL', acknowledged: false, codeConfirmation: '' } }
function focus(key) { document.getElementById('maint-' + key)?.focus() }
async function report(e) { error.value = e; await nextTick(); errorBox.value?.focus() }
function changed() { dirty.value = true }
async function read(kind, input) { const id = generation, signal = controller.signal, res = await provider.query(kind, { siteId: store.siteId, ...input }, { signal }); if (id !== generation || signal.aborted) throw new DOMException('已取消', 'AbortError'); if (res.data.availability === 'NOT_CONNECTED') throw Object.assign(new Error(res.data.reason), { errorCode: 'NOT_CONNECTED', requestId: res.requestId }); return res.data }
async function task(fn) { if (busy.value) return; const id = ++generation; controller?.abort(); controller = new AbortController(); loading.value = true; error.value = null; try { await fn() } catch (e) { if (id === generation && e.name !== 'AbortError') { report(e); if (e.code === 401) provider.invalidate() } } finally { if (id === generation) loading.value = false } }
async function handlerQuery(page = 1) { handlers.value = await read('repairAssignees', { deviceId: device.value.id, pageNum: page }); form.value.handlerId = '' }
function loadHandlers(page) { changed(); task(() => handlerQuery(page)) }
function chooseAction() { form.value = freshForm(); reviewing.value = false; operationId = crypto.randomUUID(); error.value = null; if (needsHandler.value && !reason.value) task(() => handlerQuery()) }
async function initialize() { device.value = null; order.value = null; form.value = freshForm(); handlers.value = null; reviewing.value = false; operationId = crypto.randomUUID(); device.value = await read('device', { id: intent.value.deviceId }); if (intent.value.orderId) order.value = await read('maintenanceOrder', { id: intent.value.orderId }); type.value = intent.value.type && Object.hasOwn(actions.value, intent.value.type) ? intent.value.type : Object.keys(actions.value).find(k => !actions.value[k]) || Object.keys(actions.value)[0]; if (needsHandler.value && !reason.value) await handlerQuery() }
function cleanup() { generation++; controller?.abort(); intent.value = null; store.maintenanceIntent = null; dirty.value = false; busy.value = false; loading.value = false; device.value = null; form.value = freshForm(); if (store.leaveGuard === guard) store.leaveGuard = previousGuard }
function close() { if (busy.value || dirty.value && !window.confirm('尚有未提交的运维输入，确定放弃吗？')) return false; cleanup(); return true }
const guard = () => close()
function reload() { if (dirty.value && !window.confirm('重新读取将清除本次输入，确定继续吗？')) return; dirty.value = false; task(initialize) }
async function submit() {
  if (busy.value || loading.value || reason.value || versionConflict.value) return
  if (scrapping.value && !reviewing.value) { const fields = {}; if (!form.value.reason.trim()) fields.reason = '请填写报废原因'; if (form.value.codeConfirmation.trim() !== device.value.code) fields.codeConfirmation = '编号必须与当前设备完全一致（区分大小写）'; if (type.value === 'maintenance.scrap' && !form.value.inspection.trim()) fields.inspection = '请填写无法修复说明'; if (Object.keys(fields).length) return report(Object.assign(new Error('请核对报废必填信息'), { fields, errorCode: 'VALIDATION_ERROR' })); error.value = null; reviewing.value = true; await nextTick(); reviewBox.value?.focus(); return }
  const id = generation, h = handlers.value?.rows.find(h => h.id === form.value.handlerId)
  const input = { siteId: store.siteId, operationId, deviceId: device.value.id, deviceVersion: device.value.version, ...(order.value ? { id: order.value.id, orderVersion: order.value.version } : {}), ...(needsHandler.value ? { handlerId: form.value.handlerId, handlerVersion: h?.version } : {}), ...(needsReason.value ? { reason: form.value.reason } : {}), ...(needsInspection.value ? { inspection: form.value.inspection } : {}), ...(type.value === 'maintenance.inspect' ? { repairContent: form.value.repairContent, result: form.value.result } : {}), ...(needsAck.value ? { acknowledged: form.value.acknowledged } : {}), ...(scrapping.value ? { codeConfirmation: form.value.codeConfirmation, secondConfirmed: reviewing.value } : {}) }
  busy.value = true; error.value = null
  try { await provider.execute(type.value, input, { signal: controller.signal }); if (id !== generation) return; notice.value = `${ACTIONS[type.value]}已在本页本地完成。`; cleanup() } catch (e) { if (id === generation && e.name !== 'AbortError') { reviewing.value = false; report(e); if (e.code === 401) provider.invalidate() } } finally { if (id === generation) busy.value = false }
}
watch(() => store.maintenanceIntent, value => { if (!value) return; previousGuard = store.leaveGuard; intent.value = { ...value }; store.leaveGuard = guard; dirty.value = false; notice.value = ''; task(initialize) })
const unsubscribe = provider.subscribe(e => { if (['identity', 'expired', 'reset', 'context', 'authorization'].includes(e.kind)) { cleanup(); notice.value = '' } })
onBeforeUnmount(() => { cleanup(); unsubscribe() })
</script>
