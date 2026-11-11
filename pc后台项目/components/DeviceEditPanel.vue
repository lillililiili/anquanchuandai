<template><div class="device-edit-entry"><button class="button" :class="{ primary: !device }" :disabled="blocked" :aria-busy="loading" @click="openEditor">{{ device ? '编辑设备资料' : '新建设备' }}</button><small v-if="loading" role="status">正在加载…</small><small v-if="blocked" class="disabled-reason">{{ reason || '当前身份无资产维护权限' }}</small><p v-if="openError" role="alert" class="error">{{ openError.message }}</p><p v-if="notice" role="status" class="notice">{{ notice }}</p></div>
  <ModalPanel :open="open" layout="form" :title="device ? '编辑设备档案' : '新建设备档案'" heading-id="device-editor-heading" @close="close"><DeviceEditor v-if="open && options" :key="editorKey" :row="snapshot" :options="options" :busy="busy" :error="error" @save="save" @dirty="dirty = true" @close="close" /></ModalPanel>
</template>
<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
import ModalPanel from './ModalPanel.vue'
import DeviceEditor from './DeviceEditor.vue'
import { useConfirmation } from '../confirmation'
const confirmDiscard = useConfirmation()
const props = defineProps({ device: Object, disabled: Boolean, reason: String })
const provider = getAdminProvider(), store = useAdminStore()
const open = ref(false), busy = ref(false), loading = ref(false), dirty = ref(false), options = ref(null), snapshot = ref(null), error = ref(null), openError = ref(null), notice = ref(''), editorKey = ref(0)
const authorizationRevision = ref(0)
const blocked = computed(() => { void authorizationRevision.value; return props.disabled || !provider.canAny('assets:write', store.siteId) })
let controller, operationId, run = 0
async function close() { if (busy.value || (dirty.value && !await confirmDiscard({ message: '设备资料尚未保存，放弃后将无法恢复。' }))) return false; dirty.value = false; open.value = false; return true }
const guard = () => close()
async function openEditor() {
  if (loading.value || blocked.value) return
  const id = ++run; controller?.abort(); controller = new AbortController(); loading.value = true; openError.value = null; notice.value = ''
  try {
    const res = await provider.query('deviceOptions', { siteId: store.siteId }, { signal: controller.signal })
    if (id !== run || blocked.value) return
    if (res.data.availability !== 'AVAILABLE') throw new Error(res.data.reason)
    options.value = res.data; snapshot.value = props.device ? JSON.parse(JSON.stringify(props.device)) : null; error.value = null; operationId = crypto.randomUUID(); dirty.value = false; editorKey.value++; open.value = true; store.leaveGuard = guard
  } catch (e) { if (id === run && e.name !== 'AbortError') openError.value = e } finally { if (id === run) loading.value = false }
}
async function save(data) {
  if (!open.value || busy.value || blocked.value) return
  const id = run
  busy.value = true; error.value = null; controller = new AbortController()
  try {
    await provider.execute(`devices.${snapshot.value ? 'update' : 'create'}`, { siteId: store.siteId, id: snapshot.value?.id, expectedVersion: snapshot.value?.version, operationId, data }, { signal: controller.signal })
    if (id !== run) return
    busy.value = false; dirty.value = false; open.value = false; notice.value = '设备资料已保存。'
  } catch (e) { if (id === run && e.name !== 'AbortError') { error.value = e; if (e.code === 401) provider.invalidate() } } finally { if (id === run) busy.value = false }
}
function revokeEditor() { run++; controller?.abort(); dirty.value = false; busy.value = false; loading.value = false; open.value = false; notice.value = ''; if (store.leaveGuard === guard) store.leaveGuard = null }
const unsubscribe = provider.subscribe(e => { authorizationRevision.value++; if (blocked.value || ['identity', 'expired', 'reset', 'context', 'authorization'].includes(e.kind)) revokeEditor() })
watch(blocked, value => { if (value) revokeEditor() }, { flush: 'sync' })
onBeforeUnmount(() => { run++; controller?.abort(); unsubscribe(); if (store.leaveGuard === guard) store.leaveGuard = null })
</script>
