<template><section><div class="page-heading"><div><span class="eyebrow">装备资产 / 三类设备</span><h1>设备台账</h1><p class="muted">先建立资产档案，再发放与维护。配置不是设备上报，也不是能力验证。</p></div></div><AssetTabs />
  <section class="panel master-list"><header class="device-list-heading"><h2>授权设备</h2><DeviceEditPanel :disabled="!provider.canAny('assets:write', store.siteId)" /></header>
    <form class="list-filters" @submit.prevent="navigate({ ...filters, pageNum: '1', selectedId: undefined })"><label>编号 / SN关键词<input v-model="filters.keyword" aria-label="编号 / SN关键词" maxlength="100" /></label><label v-for="(values, key) in DEVICE_FILTERS" :key="key">{{ filterNames[key] }}<select v-model="filters[key]" :aria-label="filterNames[key]"><option value="">全部</option><option v-for="(name, value) in values" :key="value" :value="value">{{ name }}</option></select></label><label>区域<select v-model="filters.areaId" aria-label="区域"><option value="">全部区域</option><option v-for="area in options.data.value?.areas || []" :key="area.id" :value="area.id">{{ area.name }}</option></select></label><button class="button primary">查询</button><button type="button" class="button" @click="clear">清除筛选</button></form>
    <p v-if="options.error.value" class="error">区域选项读取失败：{{ options.error.value.message }}</p>
    <p v-if="options.data.value?.availability === 'NOT_CONNECTED'" class="notice">区域选项未接入：{{ options.data.value.reason }}</p>
    <QueryState :data="list.data.value" :loading="list.loading.value" :error="list.error.value" @retry="load"><template v-if="list.data.value?.rows"><div class="device-table-wrap"><table class="device-table"><caption class="sr-only">设备台账，所有状态均来自本页本地数据</caption><thead><tr><th>设备编号 / 名称</th><th>类型 / 型号</th><th>区域</th><th>设备使用状态 / 领用</th><th>通信 / 资料</th><th>操作</th></tr></thead><tbody><tr v-for="d in list.data.value.rows" :key="d.id" :class="{ 'selected-row': route.query.selectedId === d.id }"><td><router-link class="record-name" :to="detail(d)">{{ d.code }}</router-link><small>{{ d.name }}</small><small>SN：{{ d.sn || '待补充' }}</small></td><td>{{ DEVICE_TYPES[d.type] }}<small>{{ d.modelName }}</small></td><td>{{ d.areaName }}</td><td>{{ DEVICE_FILTERS.lifecycle[d.lifecycle] }}<small>{{ DEVICE_FILTERS.relation[d.relation] }}</small></td><td>{{ DEVICE_FILTERS.communication[d.communication] }}<small>{{ d.identityComplete ? '厂家身份已填写（未验证）' : '厂家身份未完整核验' }}</small></td><td><router-link class="button" :to="detail(d)">查看档案</router-link><MaintenanceEntry :device-id="d.id" /><AssignmentEntry :device-id="d.id" :disabled="d.relation !== 'UNASSIGNED' || d.lifecycle !== 'STOCK' || !d.writable" reason="需库存、明确未领用及本设备办理权限" /><AssignmentEntry mode="return" :device-id="d.id" :disabled="d.relation !== 'ASSIGNED' || !d.person || !d.writable" reason="需正常有效关系及人员、设备办理权限" /></td></tr></tbody></table></div><p v-if="!list.data.value.rows.length" class="query-state">当前筛选下暂无设备，可由有权限的管理员新建设备档案。</p><div class="pagination"><span>共 {{ list.data.value.total }} 条 · 第 {{ pageNum }} 页</span><label>每页<select :value="pageSize" aria-label="每页条数" @change="navigate({ pageSize: $event.target.value, pageNum: '1', selectedId: undefined })"><option :value="20">20</option><option :value="50">50</option><option :value="100">100</option></select></label><button class="button" :disabled="pageNum <= 1" @click="navigate({ pageNum: String(pageNum - 1), selectedId: undefined })">上一页</button><button class="button" :disabled="pageNum * pageSize >= list.data.value.total" @click="navigate({ pageNum: String(pageNum + 1), selectedId: undefined })">下一页</button></div></template></QueryState>
  </section></section></template>
<script setup>
import { computed, reactive, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
import { useQuery } from '../useQuery'
import { cleanDeviceQuery } from '../navigation'
import { DEVICE_TYPES, DEVICE_FILTERS } from '../deviceData'
import QueryState from '../components/QueryState.vue'
import AssetTabs from '../components/AssetTabs.vue'
import DeviceEditPanel from '../components/DeviceEditPanel.vue'
import AssignmentEntry from '../components/AssignmentEntry.vue'
import MaintenanceEntry from '../components/MaintenanceEntry.vue'
const route = useRoute(), router = useRouter(), store = useAdminStore(), provider = getAdminProvider(), list = useQuery(), options = useQuery()
const filters = reactive({}), filterNames = { type: '设备类型', lifecycle: '设备使用状态', relation: '领用状态', communication: '通信状态' }
const query = computed(() => cleanDeviceQuery(route.query)), pageNum = computed(() => Number(query.value.pageNum || 1)), pageSize = computed(() => Number(query.value.pageSize || 20))
function navigate(patch) { router.replace({ path: '/admin/assets/devices', query: cleanDeviceQuery({ ...query.value, ...patch, siteId: store.siteId }) }) }
function clear() { router.replace({ path: '/admin/assets/devices', query: { siteId: store.siteId } }) }
function detail(d) { return { path: `/admin/assets/devices/${d.id}`, query: { siteId: store.siteId, returnTo: '/admin/assets/devices?' + new URLSearchParams({ ...query.value, siteId: store.siteId, selectedId: d.id }) } } }
async function load() {
  await list.run('devices', { ...query.value, siteId: store.siteId, pageNum: pageNum.value, pageSize: pageSize.value })
  if (list.data.value?.total != null && pageNum.value > Math.max(1, Math.ceil(list.data.value.total / pageSize.value))) navigate({ pageNum: String(Math.max(1, Math.ceil(list.data.value.total / pageSize.value))) })
}
watch(() => [route.fullPath, store.siteId, store.revision], () => { for (const k of ['keyword', 'areaId', ...Object.keys(DEVICE_FILTERS)]) filters[k] = query.value[k] || ''; load(); options.run('deviceOptions', { siteId: store.siteId }) }, { immediate: true })
</script>
