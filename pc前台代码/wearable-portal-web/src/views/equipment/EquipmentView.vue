<script setup>
import { computed, reactive, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useContextStore } from '@/store/context'
import { useUserStore } from '@/store/user'
import { usePortalQuery } from '@/composables/usePortalQuery'
import { useBusinessRevision } from '@/composables/useBusinessRevision'
import { getEquipment } from '@/api/equipment'
import { equipmentQuery, equipmentTypes, assignmentLabels } from '@/utils/equipment-route'
import { labels } from '@/utils/portal-contract'
import WorkspaceState from '@/components/spatial/WorkspaceState.vue'
import EquipmentActions from '@/components/equipment/EquipmentActions.vue'
import '@/styles/equipment.scss'
const route = useRoute(), router = useRouter(), context = useContextStore(), user = useUserStore()
const query = computed(() => equipmentQuery(route.query)), siteId = computed(() => query.value.siteId || context.selectedSiteId)
const availableSite = computed(() => context.state === 'READY' && !!user.token && context.data?.sites.some(s => s.siteId === siteId.value))
const list = reactive(usePortalQuery()), form = reactive({ keyword: '', type: '', assignmentState: '' })
const params = computed(() => ({ ...query.value, siteId: siteId.value, pageNum: Number(query.value.pageNum || 1), pageSize: Number(query.value.pageSize || 20) }))
async function reload() {
  if (!availableSite.value) return list.clear()
  context.select(siteId.value)
  await list.run(signal => getEquipment(params.value, signal))
  if (list.data?.state === 'AVAILABLE' && params.value.pageNum > 1 && !list.data.items.length) turnPage(Math.max(1, Math.ceil(list.data.total / params.value.pageSize)))
}
function search(reset = false) { router.push({ path: '/equipment', query: equipmentQuery({ siteId: siteId.value, pageSize: params.value.pageSize, ...(reset ? {} : form) }) }) }
function turnPage(pageNum) { router.replace({ path: '/equipment', query: { ...query.value, siteId: siteId.value, pageNum: String(pageNum) } }) }
watch(() => [JSON.stringify(params.value), availableSite.value, user.token], reload, { immediate: true })
watch(query, q => { for (const key of Object.keys(form)) form[key] = q[key] || '' }, { immediate: true })
useBusinessRevision(['equipment'], reload)
</script>
<template><section class="equipment-page">
  <header class="equipment-heading"><div><h1>装备查询</h1><p>三类装备 · 领用关系与设备通信分别表达</p></div><span>当前厂站范围</span></header>
  <form class="equipment-filters" @submit.prevent="search()"><label>装备编号或名称<input v-model="form.keyword" maxlength="100" placeholder="输入编号或名称" :disabled="!availableSite"></label><label>设备类型<select v-model="form.type" :disabled="!availableSite"><option value="">全部类型</option><option v-for="(label, key) in equipmentTypes" :key="key" :value="key">{{ label }}</option></select></label><label>领用状态<select v-model="form.assignmentState" :disabled="!availableSite"><option value="">全部状态</option><option v-for="(label, key) in assignmentLabels" :key="key" :value="key">{{ label }}</option></select></label><el-button native-type="submit" type="primary" :disabled="!availableSite">查询</el-button><el-button :disabled="!availableSite" @click="search(true)">重置</el-button></form>
  <WorkspaceState :context="context" :site-id="siteId" :available-site="availableSite" :query="list" @retry="reload">
    <div class="equipment-table-wrap"><table class="equipment-table"><thead><tr><th>装备编号 / 名称</th><th>类型 / 型号</th><th>领用状态</th><th>当前领用人</th><th>通信 / 数据</th><th>操作</th></tr></thead><tbody><tr v-for="d in list.data.items" :key="d.deviceId"><td><router-link :to="{ path: '/equipment/' + d.deviceId, query: { siteId, returnTo: route.fullPath } }">{{ d.deviceCode }}</router-link><small>{{ d.name }}</small></td><td>{{ equipmentTypes[d.type] }}<small>{{ d.model || '型号待确认' }}</small></td><td>{{ assignmentLabels[d.assignmentState] }}</td><td>{{ d.currentPerson?.name || (d.assignmentState === 'UNASSIGNED' ? '无当前领用人' : '待核实') }}</td><td>{{ labels[d.communication.state] }}<small>{{ labels[d.communication.freshness] || '数据时间未知' }}</small></td><td><router-link :to="{ path: '/equipment/' + d.deviceId, query: { siteId, returnTo: route.fullPath } }">装备详情 →</router-link><EquipmentActions :site-id="siteId" :device-id="d.deviceId" :type="d.type" :state="d.assignmentState" /></td></tr></tbody></table></div>
    <p v-if="!list.data.items.length" class="equipment-empty">当前筛选范围暂无装备。</p><AppPagination :current-page="params.pageNum" :page-size="params.pageSize" :total="list.data.total" @current-change="turnPage" />
  </WorkspaceState>
  <p class="equipment-note">领用关系未知或冲突时不可操作；离线、通信未知或数据过期只作提醒。安全带、手表厂家协议待确认。</p>
</section></template>
