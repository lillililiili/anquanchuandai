<template><button class="button" :class="{ primary: !device }" :disabled="disabled" :aria-busy="loading" @click="openEditor">{{ device ? '编辑设备资料' : '新建设备' }}</button><small v-if="loading" role="status">正在读取型号与区域…</small><small v-if="disabled" class="disabled-reason">{{ reason || '当前身份无资产维护权限' }}</small><p v-if="openError" role="alert" class="error">{{ openError.message }}</p><p v-if="notice" role="status" class="notice">{{ notice }}</p>
  <ModalPanel :open="open" side :title="device ? '编辑设备档案' : '新建设备档案'" heading-id="device-editor-heading" @close="close"><DeviceEditor v-if="open && options" :key="editorKey" :row="snapshot" :options="options" :busy="busy" :error="error" @save="save" @dirty="dirty = true" @close="close" /></ModalPanel>
</template>
<script setup>
import { ref, onBeforeUnmount } from 'vue'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
import ModalPanel from './ModalPanel.vue'
import DeviceEditor from './DeviceEditor.vue'
const props = defineProps({ device: Object, disabled: Boolean, reason: String })
const provider = getAdminProvider(), store = useAdminStore()
const open = ref(false), busy = ref(false), loading = ref(false), dirty = ref(false), options = ref(null), snapshot = ref(null), error = ref(null), openError = ref(null), notice = ref(''), editorKey = ref(0)
let controller, operationId, run = 0
function close() { if (busy.value || (dirty.value && !window.confirm('尚有未保存的设备资料，确定放弃吗？'))) return false; dirty.value = false; open.value = false; return true }
const guard = () => close()
async function openEditor() {
  if (loading.value || props.disabled) return
  const id = ++run; controller?.abort(); controller = new AbortController(); loading.value = true; openError.value = null; notice.value = ''
  try {
    const res = await provider.query('deviceOptions', { siteId: store.siteId }, { signal: controller.signal })
    if (id !== run) return
    if (res.data.availability !== 'AVAILABLE') throw new Error(res.data.reason)
    options.value = res.data; snapshot.value = props.device ? JSON.parse(JSON.stringify(props.device)) : null; error.value = null; operationId = crypto.randomUUID(); dirty.value = false; editorKey.value++; open.value = true; store.leaveGuard = guard
  } catch (e) { if (id === run && e.name !== 'AbortError') openError.value = e } finally { if (id === run) loading.value = false }
}
async function save(data) {
  busy.value = true; error.value = null; controller = new AbortController()
  try {
    await provider.execute(`devices.${snapshot.value ? 'update' : 'create'}`, { siteId: store.siteId, id: snapshot.value?.id, expectedVersion: snapshot.value?.version, operationId, relatedVersions: Object.fromEntries(options.value.areas.map(a => [a.id, a.version])), data }, { signal: controller.signal })
    busy.value = false; dirty.value = false; open.value = false; notice.value = '设备资料已保存到本页内存。通信与真实验证状态未改变。'
  } catch (e) { if (e.name !== 'AbortError') { error.value = e; if (e.code === 401) provider.invalidate() } } finally { busy.value = false }
}
const unsubscribe = provider.subscribe(e => { if (['identity', 'expired', 'reset', 'context', 'authorization'].includes(e.kind)) { run++; controller?.abort(); dirty.value = false; busy.value = false; loading.value = false; open.value = false; notice.value = '' } })
onBeforeUnmount(() => { run++; controller?.abort(); unsubscribe(); if (store.leaveGuard === guard) store.leaveGuard = null })
</script>
