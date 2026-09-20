<script setup>
import { ref, watch, onBeforeUnmount } from 'vue'
import { useRouter } from 'vue-router'
import { useContextStore } from '@/store/context'
import { useUserStore } from '@/store/user'
import { queryDispatch, commandDispatch } from './dispatch-runtime'
const emit = defineEmits(['triggered'])
const context = useContextStore(), user = useUserStore(), router = useRouter()
const items = ref([]), deviceId = ref(''), version = ref(null), busy = ref(false), error = ref('')
let controller, generation = 0
function clear() { generation++; controller?.abort(); items.value = []; deviceId.value = ''; version.value = null; busy.value = false; error.value = '' }
watch(() => [context.selectedSiteId, user.token], clear)
onBeforeUnmount(clear)
async function prepare() {
  clear(); controller = new AbortController(); const current = generation
  busy.value = true
  try { const r = await queryDispatch({ siteId: context.selectedSiteId, pageSize: 100 }, controller.signal); if (current !== generation) return; items.value = r.items; version.value = r.version }
  catch (e) { if (current === generation && e.code !== 'ERR_CANCELED') error.value = e.message }
  finally { if (current === generation) busy.value = false }
}
async function trigger() {
  if (busy.value || !deviceId.value || version.value == null) return
  busy.value = true; error.value = ''; const siteId = context.selectedSiteId, current = generation
  controller = new AbortController()
  try {
    const r = await commandDispatch('sos', { siteId, deviceId: deviceId.value, expectedVersion: version.value, operationId: crypto.randomUUID() }, controller.signal)
    if (current !== generation) return
    emit('triggered'); clear(); await router.push({ path: '/dispatch/sos/' + r.eventId, query: { siteId } })
  } catch (e) { if (current === generation && e.code !== 'ERR_CANCELED') error.value = e.message + '；可重新读取对象后再试' }
  finally { if (current === generation) busy.value = false }
}
</script>
<template><section class="mock-form"><h3>合成 SOS 求助</h3><p>仅产生本地事件，不呼叫、不发送设备指令。安全带电话与手表未知能力不会因此变成可用。</p><button type="button" :disabled="busy || !user.roles.includes('owner') || !context.selectedSiteId" @click="prepare">读取本地求助对象</button><label v-if="version != null">求助来源设备<select v-model="deviceId" :disabled="busy"><option value="">请选择设备</option><option v-for="d in items" :key="d.deviceId" :value="d.deviceId">{{ d.name }} · {{ d.type }}</option></select></label><button v-if="version != null" type="button" :disabled="busy || !deviceId || !user.roles.includes('owner')" @click="trigger">触发本地 SOS</button><p v-if="error" role="alert">{{ error }}</p><p v-if="!user.roles.includes('owner')">仅负责人可触发。</p></section></template>
