<template>
  <div class="feature-editor-entry">
    <button type="button" class="button" :disabled="blocked || loading" :aria-busy="loading" @click="openEditor">{{ loading ? '正在读取配置…' : '功能配置' }}</button>
    <small v-if="unsupported">功能配置暂不可用，请联系管理员。</small>
    <small v-else-if="blocked">需要本设备的资产维护权限。</small>
    <p v-if="notice" class="notice" role="status">{{ notice }}</p>
    <p v-if="openError" class="error" role="alert">{{ openError }}</p>
  </div>
  <ModalPanel :open="open" layout="form" title="设备功能配置" heading-id="feature-editor-heading" @close="close">
    <form v-if="open && snapshot" class="feature-config-form" @submit.prevent="save">
      <div class="feature-form-body">
      <p class="muted">{{ snapshot.name }} · {{ snapshot.code }}</p>
      <label>配置功能<select :value="draft.feature" :disabled="busy" @change="selectFeature($event)"><option v-for="row in options" :key="row.key" :value="row.key">{{ row.label }}</option></select></label>
      <fieldset :disabled="busy" @input="dirty = true" @change="dirty = true">
        <legend>功能状态</legend>
        <div class="feature-form-columns">
          <label>设备支持<select v-model="draft.support"><option value="DEFAULT">自动判断</option><option value="SUPPORTED">支持</option><option value="UNSUPPORTED">不支持</option><option value="PENDING">待确认</option></select></label>
          <label>连接状态<select v-model="draft.connection"><option value="DEFAULT">自动判断</option><option value="CONNECTED">已连接</option><option value="NOT_CONNECTED">未连接</option><option value="PENDING">待确认</option></select></label>
          <label>可用状态<select v-model="draft.availability"><option value="DEFAULT">自动判断</option><option value="AVAILABLE">当前可用</option><option value="UNAVAILABLE">不可用</option><option value="PENDING">待确认</option></select></label>
        </div>
      </fieldset>
      <p v-if="lastSaved" class="muted">上次维护：{{ lastSaved.updatedByName || '管理员' }} · {{ beijingTime(lastSaved.updatedAt) }}</p>
      <p v-if="error" class="error" role="alert">{{ error }}</p>
      </div>
      <div class="feature-form-actions"><button type="button" class="button" :disabled="busy" @click="close">取消</button><button v-if="conflict" type="button" class="button" :disabled="busy" @click="openEditor">重新读取配置</button><button class="button primary" :disabled="busy || blocked || conflict" :aria-busy="busy">{{ busy ? '正在保存…' : '保存配置' }}</button></div>
    </form>
  </ModalPanel>
</template>

<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
import { useConfirmation } from '../confirmation'
import { beijingTime } from '../tablePresentation'
import { deviceFeatureRows } from '../deviceFeaturePresentation'
import { featureDraft, featurePayload } from '../deviceFeatureForm'
import ModalPanel from './ModalPanel.vue'
const props = defineProps({ device: { type: Object, required: true } })
const emit = defineEmits(['saved'])
const provider = getAdminProvider(), store = useAdminStore(), confirmDiscard = useConfirmation()
const open = ref(false), busy = ref(false), loading = ref(false), dirty = ref(false), snapshot = ref(null), draft = ref({}), error = ref(''), openError = ref(''), notice = ref(''), conflict = ref(false), authRevision = ref(0)
const unsupported = computed(() => !(props.device.featureManagement?.version >= 2))
const blocked = computed(() => { void authRevision.value; return unsupported.value || props.device.featureManagement?.editable !== true || !provider.canAny('assets:write', store.siteId) })
const options = computed(() => deviceFeatureRows(snapshot.value).filter(row => snapshot.value?.featureStates?.[row.key]?.configurable))
const lastSaved = computed(() => snapshot.value?.featureConfiguration?.[draft.value.feature])
let run = 0, controller, operationId
async function close() {
  if (busy.value || dirty.value && !await confirmDiscard({ message: '功能配置尚未保存，确定放弃本次修改？' })) return false
  open.value = false; dirty.value = false
  if (store.leaveGuard === close) store.leaveGuard = null
  return true
}
async function selectFeature(event) {
  const feature = event.target.value
  event.target.value = draft.value.feature
  if (dirty.value && !await confirmDiscard({ message: '切换功能会放弃当前尚未保存的配置。' })) return
  if (!open.value || busy.value || blocked.value) return
  draft.value = featureDraft(snapshot.value, feature); dirty.value = false; error.value = ''; operationId = crypto.randomUUID()
}
async function openEditor() {
  if (blocked.value || loading.value || busy.value) return
  if (dirty.value && !await confirmDiscard({ message: '重新读取将放弃当前未保存的配置。' })) return
  const id = ++run; controller?.abort(); controller = new AbortController(); loading.value = true; openError.value = ''; notice.value = ''
  try {
    const response = await provider.query('device', { siteId: store.siteId, id: props.device.id }, { signal: controller.signal })
    if (id !== run || blocked.value) return
    if (!(response.data?.featureManagement?.version >= 2)) throw Error('功能配置暂不可用，请稍后重试。')
    if (response.data?.featureManagement?.editable !== true) throw Error('当前设备无功能配置维护权限。')
    snapshot.value = structuredClone(response.data)
    draft.value = featureDraft(snapshot.value, draft.value.feature && snapshot.value.featureStates?.[draft.value.feature]?.configurable ? draft.value.feature : options.value[0]?.key)
    dirty.value = false; error.value = ''; conflict.value = false; operationId = crypto.randomUUID(); open.value = true; store.leaveGuard = close
  } catch (e) { if (id === run && e.name !== 'AbortError') openError.value = e.message } finally { if (id === run) loading.value = false }
}
async function save() {
  if (!open.value || busy.value || blocked.value || conflict.value) return
  let data
  try { data = featurePayload(draft.value) } catch (e) { error.value = e.message; return }
  const id = run; busy.value = true; error.value = ''
  try {
    await provider.execute('devices.features', { siteId: snapshot.value.siteId, id: snapshot.value.id, expectedVersion: snapshot.value.version, operationId, data })
    if (id !== run) return
    dirty.value = false; open.value = false; notice.value = '功能状态已保存。'
    if (store.leaveGuard === close) store.leaveGuard = null
    emit('saved')
  } catch (e) {
    if (id !== run || e.name === 'AbortError') return
    error.value = e.message; conflict.value = e.errorCode === 'VERSION_CONFLICT' || e.errorCode === 'IDEMPOTENCY_CONFLICT'
    if (e.code >= 400 && e.code < 500) operationId = crypto.randomUUID()
  } finally { if (id === run) busy.value = false }
}
function revoke() { run++; controller?.abort(); open.value = false; busy.value = false; loading.value = false; dirty.value = false; notice.value = ''; if (store.leaveGuard === close) store.leaveGuard = null }
const unsubscribe = provider.subscribe(event => { authRevision.value++; if (blocked.value || ['identity', 'expired', 'reset', 'context', 'authorization'].includes(event.kind)) revoke() })
watch([() => store.siteId, () => props.device.id], revoke)
watch(blocked, value => { if (value) revoke() })
onBeforeUnmount(() => { revoke(); unsubscribe() })
</script>

<style scoped>
.feature-editor-entry small { display: block; color: var(--muted); margin-top: 6px; }
.feature-config-form { display: flex; flex-direction: column; flex: 1 1 auto; min-height: 0; min-width: 0; margin: 0; overflow: hidden; }
.feature-form-body { display: grid; align-content: start; flex: 1 1 auto; gap: 24px; min-height: 0; padding: 12px 24px 24px; overflow: auto; overscroll-behavior: contain; }
.feature-config-form p { margin: 0; line-height: 1.7; }
.feature-config-form label { display: grid; gap: 10px; min-width: 0; font-weight: 500; }
.feature-config-form select { width: 100%; box-sizing: border-box; min-height: 44px; border: 1px solid var(--line); border-radius: 6px; background: var(--canvas); color: var(--text); padding: 10px 12px; font: inherit; }
.feature-config-form fieldset { min-width: 0; margin: 0; padding: 20px; border: 1px solid var(--line); border-radius: 8px; display: grid; gap: 20px; }
.feature-config-form legend { padding: 0 8px; }
.feature-form-columns { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 20px; }
.feature-form-actions { display: flex; flex: none; justify-content: flex-end; flex-wrap: wrap; gap: 12px; padding: 16px 24px 24px; border-top: 1px solid var(--line); }
@media (max-width: 600px) {
  .feature-form-body { gap: 20px; padding: 12px 16px 20px; }
  .feature-config-form fieldset { padding: 16px; }
  .feature-form-columns { grid-template-columns: 1fr; }
  .feature-form-actions { padding: 16px 16px 20px; }
}
</style>
