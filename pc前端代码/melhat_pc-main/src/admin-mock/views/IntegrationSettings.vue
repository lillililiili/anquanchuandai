<template><section :aria-busy="busy || settings.loading.value"><div class="page-heading"><div><span class="eyebrow">管理中心 / 接入配置</span><h1>演示参数</h1><p class="muted">仅配置当前厂站连接器实际使用的默认场景，保存在当前页面中。</p></div><span class="badge">本地模拟</span></div><nav class="workspace-tabs" aria-label="接入配置导航"><router-link :to="{ path: '/admin/integrations', query: { siteId: store.siteId } }">六类连接器</router-link><router-link :to="{ path: '/admin/integrations/settings', query: { siteId: store.siteId } }">演示参数</router-link></nav><p v-if="notice" class="notice" role="status">{{ notice }} <router-link v-if="auditAllowed" :to="{ path: '/admin/audit', query: { siteId: store.siteId } }">查看审计记录</router-link></p><div v-if="saveError" ref="errorBox" class="notice error" role="alert" tabindex="-1"><strong>{{ saveError.message }}</strong><p>{{ saveError.errorCode }} · {{ saveError.requestId }}</p><p v-if="saveError.code === 409">设置版本已变化，请重新读取后再修改。</p><button v-if="saveError.code === 409" class="button" :disabled="busy" @click="refresh">放弃修改并重新读取</button></div><section class="panel master-list"><QueryState :data="settings.data.value" :loading="settings.loading.value" :error="settings.error.value" @retry="load"><form v-if="settings.data.value?.id" class="settings-form" @submit.prevent="save"><h2>厂站默认场景 · v{{ settings.data.value.version }}</h2><p>连接器选择“使用厂站默认演示参数”时消费此设置；已指定独立场景的连接器不受影响。</p><p v-if="!writable" class="disabled-reason">无当前厂站接入配置维护权限，仅可查看。</p><label>默认演示场景<select v-model="scenario" :disabled="!writable || busy"><option value="SUCCESS">成功</option><option value="TIMEOUT">模拟超时</option><option value="FIELD_MISMATCH">字段不匹配</option></select></label><p class="muted">成功仅表示模拟测试通过，不代表真实系统已连接或实际发送成功。</p><button class="button primary" :disabled="!writable || !dirty || busy">保存演示参数</button></form></QueryState></section></section></template>
<script setup>
import { ref, computed, watch, nextTick, onBeforeUnmount } from 'vue'
import { onBeforeRouteLeave } from 'vue-router'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
import { useQuery } from '../useQuery'
import QueryState from '../components/QueryState.vue'
const provider = getAdminProvider(), store = useAdminStore(), settings = useQuery()
const scenario = ref('SUCCESS'), baseline = ref(null), draftVersion = ref(null), busy = ref(false), saveError = ref(null), notice = ref(''), errorBox = ref(null)
const dirty = computed(() => baseline.value !== null && scenario.value !== baseline.value), writable = computed(() => { void store.revision; return provider.can('integrations:write', store.siteId) }), auditAllowed = computed(() => { void store.revision; return provider.canAny('audit:read', store.siteId) })
let controller, generation = 0, operation = null
async function load() { const token = generation; await settings.run('integrationSettings', { siteId: store.siteId }); if (token === generation && settings.data.value?.id && !dirty.value) { scenario.value = settings.data.value.defaultScenario; baseline.value = scenario.value; draftVersion.value = settings.data.value.version } }
async function refresh() { if (!allowLeave()) return; baseline.value = null; saveError.value = null; await load() }
async function save() {
  if (!writable.value || busy.value || !dirty.value || !settings.data.value?.id) return
  const payload = { siteId: store.siteId, id: settings.data.value.id, expectedVersion: draftVersion.value, defaultScenario: scenario.value }, fingerprint = JSON.stringify(payload)
  if (operation?.fingerprint !== fingerprint) operation = { fingerprint, id: crypto.randomUUID() }
  const token = generation; controller?.abort(); controller = new AbortController(); busy.value = true; saveError.value = null
  try { await provider.execute('integrationSettings.update', { ...payload, operationId: operation.id }, { signal: controller.signal }); if (token !== generation) return; baseline.value = null; operation = null; notice.value = '演示参数已保存，仅影响使用默认场景的连接器。'; await load() }
  catch (e) { if (token === generation && e.name !== 'AbortError') { saveError.value = e; if (e.code === 401) provider.invalidate(); await nextTick(); errorBox.value?.focus() } }
  finally { if (token === generation) busy.value = false }
}
function clear() { generation++; controller?.abort(); settings.cancel(); baseline.value = null; scenario.value = 'SUCCESS'; operation = null; busy.value = false; saveError.value = null; notice.value = '' }
function allowLeave() { if (busy.value) return false; if (dirty.value && !window.confirm('尚有未保存的演示参数，确定放弃吗？')) return false; baseline.value = null; return true }
store.leaveGuard = allowLeave
onBeforeRouteLeave(allowLeave)
watch(scenario, () => { operation = null }, { flush: 'sync' })
watch(() => store.siteId, clear, { flush: 'sync' })
watch(() => [store.siteId, store.revision], load, { immediate: true })
const unsubscribe = provider.subscribe(({ kind }) => { if (['authorization', 'identity', 'expired', 'reset'].includes(kind)) clear() })
const beforeUnload = event => { if (dirty.value) { event.preventDefault(); event.returnValue = '' } }
window.addEventListener('beforeunload', beforeUnload)
onBeforeUnmount(() => { clear(); unsubscribe(); if (store.leaveGuard === allowLeave) store.leaveGuard = null; window.removeEventListener('beforeunload', beforeUnload) })
</script>
<style scoped>
.settings-form label{display:grid;gap:8px;max-width:420px}.settings-form select{min-height:40px}
</style>

