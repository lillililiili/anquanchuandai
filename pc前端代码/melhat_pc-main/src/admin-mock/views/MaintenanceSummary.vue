<template><section><div class="page-heading"><div><span class="eyebrow">装备资产 / 维修工单</span><h1>维修单详情</h1></div><router-link class="button" :to="maintenanceReturn(route.query.returnTo)">{{ String(route.query.returnTo || '').startsWith('/admin/assets/assignments') ? '返回发放与回收' : '返回维修与退役' }}</router-link></div><AssetTabs />
  <div class="device-detail-tools"><MaintenanceEntry :device-id="order?.deviceId" :order-id="order?.id" label="工单办理" /></div>
  <QueryState :data="order" :loading="query.loading.value" :error="query.error.value" @retry="load"><section v-if="order?.id" class="panel"><div class="record-line"><h2>{{ order.id }}</h2><span class="badge">{{ PHASES[order.phase] }}</span></div><p class="device-code">{{ order.deviceCode }} · {{ order.deviceName }}</p><dl class="record-fields"><dt>设备生命周期</dt><dd>{{ DEVICE_FILTERS.lifecycle[order.deviceLifecycle] }}</dd><dt>故障说明</dt><dd>{{ order.reason || '未知' }}</dd><dt>当前处理人</dt><dd>{{ order.currentHandlerName || '待指派' }}<small v-if="order.status === 'OPEN' && !order.handlerValid" class="error">需要管理员重新指派有效账号</small></dd><dt>处理人名称快照</dt><dd>{{ order.handlerName || '未知' }}</dd><dt>创建时间（UTC）</dt><dd>{{ order.createdAt || '未知（不补造过去时间）' }}</dd><dt>来源归还办理号</dt><dd>{{ order.batchId || (order.source === 'MOCK_STOCK' ? '库存送修，无归还办理号' : '未知') }}</dd><dt>关闭结果</dt><dd>{{ order.outcome === 'REPAIRED' ? '维修通过' : order.outcome === 'UNREPAIRABLE_SCRAPPED' ? '无法修复并报废' : '尚无关闭结果' }}</dd><dt>关闭时间（UTC）</dt><dd>{{ order.closedAt || '未关闭／未知' }}</dd></dl><router-link class="button" :to="{ path: '/admin/assets/devices/' + order.deviceId, query: { siteId: store.siteId, returnTo: maintenanceReturn(route.query.returnTo) } }">查看设备档案</router-link><div class="maintenance-rules"><p v-for="(reason, type) in order.actions" :key="type"><strong>{{ ACTIONS[type] }}</strong>：{{ reason || '可办理（仍须表单校验）' }}</p></div><p class="notice">仅指定处理人可接单和记录检测。管理员须显式重新指派才能接管；关闭工单只读。未发出真实维修通知。</p></section></QueryState>
  <MaintenanceRecords :order-id="String(route.params.orderId)" />
</section></template>
<script setup>
import { computed, watch } from 'vue'
import { useRoute } from 'vue-router'
import { useAdminStore } from '../store'
import { useQuery } from '../useQuery'
import { maintenanceReturn } from '../navigation'
import { PHASES, ACTIONS } from '../maintenanceData'
import { DEVICE_FILTERS } from '../deviceData'
import AssetTabs from '../components/AssetTabs.vue'
import QueryState from '../components/QueryState.vue'
import MaintenanceEntry from '../components/MaintenanceEntry.vue'
import MaintenanceRecords from '../components/MaintenanceRecords.vue'
const store = useAdminStore(), route = useRoute(), query = useQuery(), order = computed(() => query.data.value)
function load() { query.run('maintenanceOrder', { siteId: store.siteId, id: route.params.orderId }) }
watch(() => [route.params.orderId, store.siteId, store.revision], load, { immediate: true })
</script>
