<template>
  <details class="panel cluster-maintenance" @toggle="toggle">
    <summary>系统维护</summary>
    <template v-if="opened">
      <p role="status"><strong>{{ presentation.title }}</strong> · {{ presentation.message }}</p>
      <p v-if="state">活动操作 {{ state.activeWrites || 0 }} · 待确认 {{ state.unknown || 0 }} · 待处理设备上报 {{ state.pendingReports || 0 }}</p>
      <p v-if="error" class="notice error" role="alert">{{ error }}</p>
      <div class="actions"><button class="button" :disabled="busy" @click="refresh">刷新状态</button>
        <button class="button" :disabled="busy || !state" @click="change">{{ state?.paused ? '恢复业务' : '暂停业务写入' }}</button></div>
      <div v-if="state?.paused" class="actions"><label>核对依据 <input v-model="reason" maxlength="500" placeholder="填写失联操作核对依据（至少10字）" /></label><button class="button" :disabled="busy || reason.trim().length < 10" @click="reconcile">核对外部结果及失联操作</button></div>
      <small>核对只读取外部证据，不重发操作。证据不足时保持待确认。</small>
      <small>此操作影响所有节点。单节点排空由内部运维接口管理。</small>
    </template>
  </details>
</template>
<script setup>
import { ref, computed, onBeforeUnmount } from 'vue'
import { createBusinessConfigApi } from '../businessConfigApi'
import { maintenancePresentation } from '../clusterMaintenance'
const api = createBusinessConfigApi(), state = ref(null), busy = ref(false), error = ref(''), opened = ref(false), reason = ref('')
const presentation = computed(() => maintenancePresentation(state.value))
let poll, controller
async function refresh() {
  if (busy.value || !opened.value) return
  busy.value = true; error.value = ''; controller = new AbortController()
  try { state.value = await api.maintenance(controller.signal) } catch (e) { if (e.name !== 'AbortError') { error.value = e.message; state.value = null } }
  finally { busy.value = false }
}
async function change() {
  if (!state.value || busy.value) return
  busy.value = true; error.value = ''; controller = new AbortController()
  try { state.value = await api.setMaintenance(!state.value.paused, controller.signal) }
  catch (e) { if (e.name !== 'AbortError') { error.value = e.message; state.value = null } }
  finally { busy.value = false }
}
async function reconcile() {
  if (busy.value || !state.value?.paused || reason.value.trim().length < 10) return
  busy.value = true; error.value = ''; controller = new AbortController()
  try { state.value = await api.reconcileMaintenance(reason.value.trim(), controller.signal); reason.value = '' }
  catch (e) { if (e.name !== 'AbortError') error.value = e.message }
  finally { busy.value = false }
}
function toggle(event) { opened.value = event.target.open; clearInterval(poll); if (opened.value) { refresh(); poll = setInterval(refresh, 2000) } else controller?.abort() }
onBeforeUnmount(() => { clearInterval(poll); controller?.abort() })
</script>
<style scoped>.cluster-maintenance { margin-bottom: 16px; padding: 12px 16px; }.cluster-maintenance summary { cursor: pointer; font-weight: 600; }.cluster-maintenance small { display: block; margin-top: 8px; color: #64748b; }</style>
