<template><section><h1 class="sr-only">设备台账</h1><AssetTabs />
  <section class="panel master-list">
    <form class="list-filters" @submit.prevent="navigate({ ...filters, pageNum: '1', selectedId: undefined })"><label>编号 / SN关键词<input v-model="filters.keyword" aria-label="编号 / SN关键词" maxlength="100" /></label><label v-for="(values, key) in visibleFilters" :key="key">{{ filterNames[key] }}<UiSelect v-model="filters[key]" :aria-label="filterNames[key]"><option value="">全部</option><option v-for="(name, value) in values" :key="value" :value="value">{{ name }}</option></UiSelect></label><div class="filter-actions"><button class="button primary">查询</button><button type="button" class="button" @click="clear">重置</button></div></form><header class="device-list-heading"><h2>授权设备</h2><DeviceEditPanel :disabled="!provider.canAny('assets:write', store.siteId)" /></header>
    <div v-if="watchWritable" class="watch-visibility"><label><input type="checkbox" v-model="watchVisible" :disabled="!watchConfig || watchBusy" @change="saveWatchVisibility($event.target.checked)" /> 三端显示模拟手表</label><span v-if="watchBusy" role="status">正在保存…</span><span v-else-if="watchNotice" role="status">{{ watchNotice }}</span><span v-if="watchError" class="error" role="alert">{{ watchError }}</span><button v-if="watchError" class="button" :disabled="watchBusy" @click="loadWatchConfig">重新读取</button></div><div v-table-region class="admin-results"><QueryState :data="list.data.value" :loading="list.loading.value" :error="list.error.value" @retry="load"><template v-if="list.data.value?.rows"><div class="device-table-wrap"><table v-table class="admin-table device-table"><caption class="sr-only">设备台账。厂家设备的通信状态来自厂家查询；未返回的电量显示为空。</caption><thead><tr><th data-width="160" class="pinned-key">设备编号</th><th data-width="180">设备名称</th><th data-width="200">SN</th><th data-width="120">设备类型</th><th data-width="200">型号</th><th data-width="120" class="status-cell">领用状态</th><th data-width="140" class="status-cell">通信状态</th><th data-width="90">电量</th><th data-width="220" class="table-actions pinned-actions">操作</th></tr></thead><tbody><tr v-for="d in list.data.value.rows" :key="d.id" :class="{ 'selected-row': route.query.selectedId === d.id }"><td class="pinned-key"><router-link class="record-name" :to="detail(d)">{{ d.code }}</router-link></td><td>{{ d.name }}<small class="device-source muted">{{ d.source === 'DEMO_WATCH' ? '智能手表 · 模拟数据' : d.source === 'DIRECT_BELT' ? '安全带直连' : d.source === 'DIRECT_HELMET' ? '一体帽直连' : d.source === 'PLATFORM' ? '厂家同步' : d.manufacturer === '预置厂商（非真实厂家）' ? '示例数据' : '手工建档' }}</small></td><td>{{ d.sn || '待补充' }}</td><td>{{ DEVICE_TYPES[d.type] }}</td><td>{{ d.modelName || '待补充' }}</td><td class="status-cell"><span class="badge">{{ DEVICE_FILTERS.relation[d.relation] }}</span></td><td class="status-cell"><span class="badge">{{ DEVICE_FILTERS.communication[d.communication] }}</span></td><td>{{ d.battery == null || d.battery === '' ? '—' : d.battery + '%' }}</td><td class="table-actions pinned-actions"><div class="row-actions"><router-link class="button" :to="detail(d)">查看档案</router-link><RowMore><AssignmentEntry :device-id="d.id" :disabled="d.relation !== 'UNASSIGNED' || d.lifecycle !== 'STOCK' || !d.writable" reason="需库存、明确未领用及本设备办理权限" /><AssignmentEntry mode="return" :device-id="d.id" :disabled="d.relation !== 'ASSIGNED' || !d.person || !d.writable" reason="需正常有效关系及人员、设备办理权限" /></RowMore></div></td></tr></tbody></table></div><p v-if="!list.data.value.rows.length" class="query-state">当前筛选下暂无设备，可由有权限的管理员新建设备档案。</p><AdminPagination :total="list.data.value.total" :model-value="pageNum" :page-size="pageSize" :disabled="list.loading.value" @update:model-value="navigate({ pageNum: String($event), selectedId: undefined })" @update:page-size="navigate({ pageSize: String($event), pageNum: '1', selectedId: undefined })" /></template></QueryState></div>
  </section></section></template>
<script setup>
import { computed, reactive, ref, watch, onBeforeUnmount } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
import { useQuery } from '../useQuery'
import { createBusinessConfigApi } from '../businessConfigApi'
import { cleanDeviceQuery } from '../navigation'
import { DEVICE_TYPES, DEVICE_FILTERS } from '../deviceData'
import QueryState from '../components/QueryState.vue'
import AssetTabs from '../components/AssetTabs.vue'
import DeviceEditPanel from '../components/DeviceEditPanel.vue'
import AssignmentEntry from '../components/AssignmentEntry.vue'
const route = useRoute(), router = useRouter(), store = useAdminStore(), provider = getAdminProvider(), list = useQuery()
const watchApi = createBusinessConfigApi(), watchConfig = ref(null), watchVisible = ref(true), watchBusy = ref(false), watchNotice = ref(''), watchError = ref('')
const watchWritable = computed(() => store.identity?.id === 'demo-system')
let watchController, watchGeneration = 0
async function loadWatchConfig() {
  const generation = ++watchGeneration; watchController?.abort(); watchController = new AbortController(); watchConfig.value = null; watchError.value = ''; watchNotice.value = ''
  if (!watchWritable.value) return
  try { const config = await watchApi.read(watchController.signal); if (generation === watchGeneration) { watchConfig.value = config; watchVisible.value = config.simulatedWatchVisible !== false } }
  catch (error) { if (generation === watchGeneration && error.name !== 'AbortError') watchError.value = error.message }
}
async function saveWatchVisibility(visible) {
  if (!watchWritable.value || !watchConfig.value || watchBusy.value) return
  const generation = ++watchGeneration; watchController?.abort(); watchController = new AbortController(); watchBusy.value = true; watchError.value = ''; watchNotice.value = ''
  let saved = false
  try {
    const config = await watchApi.save(visible, watchConfig.value.version, watchController.signal)
    if (generation !== watchGeneration) return
    saved = true; watchConfig.value = config; watchVisible.value = config.simulatedWatchVisible !== false
    const current = await watchApi.state(watchController.signal)
    if (generation !== watchGeneration) return
    if (!current.state) throw Error('设备列表未返回')
    provider.replaceState(current.state); store.revision++
    watchNotice.value = '已保存，三端刷新业务数据后生效。'
    if (!visible && query.value.type === 'WATCH') navigate({ type: undefined, pageNum: '1' })
  } catch (error) {
    if (generation === watchGeneration && error.name !== 'AbortError') { watchVisible.value = watchConfig.value?.simulatedWatchVisible !== false; watchError.value = saved ? '设置已保存，设备列表刷新失败，请刷新页面。' : error.message }
  } finally { if (generation === watchGeneration) watchBusy.value = false }
}
watch(() => store.identity?.id, () => { watchBusy.value = false; loadWatchConfig() }, { immediate: true })
onBeforeUnmount(() => { watchGeneration++; watchController?.abort() })
const visibleFilters = computed(() => { void store.revision; const showWatch = provider.exportState().businessConfig?.simulatedWatchVisible !== false; return { type: Object.fromEntries(Object.entries(DEVICE_FILTERS.type).filter(([key]) => showWatch || key !== 'WATCH')), relation: DEVICE_FILTERS.relation, communication: DEVICE_FILTERS.communication }; });
const filters = reactive({}), filterNames = { type: '设备类型', relation: '领用状态', communication: '通信状态' }
const query = computed(() => cleanDeviceQuery(route.query)), pageNum = computed(() => Number(query.value.pageNum || 1)), pageSize = computed(() => Number(query.value.pageSize || 10))
function navigate(patch) { router.replace({ path: '/devices', query: cleanDeviceQuery({ ...query.value, ...patch, siteId: store.siteId }) }) }
function clear() { router.replace({ path: '/devices', query: { siteId: store.siteId } }) }
function detail(d) { return { path: `/devices/${d.id}`, query: { siteId: store.siteId, returnTo: '/devices?' + new URLSearchParams({ ...query.value, siteId: store.siteId, selectedId: d.id }) } } }
async function load() {
  await list.run('devices', { ...query.value, siteId: store.siteId, pageNum: pageNum.value, pageSize: pageSize.value })
  if (list.data.value?.total != null && pageNum.value > Math.max(1, Math.ceil(list.data.value.total / pageSize.value))) navigate({ pageNum: String(Math.max(1, Math.ceil(list.data.value.total / pageSize.value))) })
}
watch(() => [route.fullPath, store.siteId, store.revision], () => { for (const k of ['keyword', ...Object.keys(filterNames)]) filters[k] = query.value[k] || ''; load() }, { immediate: true })
</script>

<style scoped>.device-source{display:block;margin-top:4px}.watch-visibility{display:flex;align-items:center;flex-wrap:wrap;gap:12px;margin:12px 0}.watch-visibility label{display:inline-flex;align-items:center;gap:8px}.watch-visibility input{width:18px;height:18px}.watch-visibility span{font-size:14px}</style>
