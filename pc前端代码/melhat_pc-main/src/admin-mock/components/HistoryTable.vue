<template><div v-if="rows.length" class="table-scroll"><table><caption class="sr-only">领用及归还按件流水，名称为历史快照</caption><thead><tr><th>办理号 / 动作</th><th>人员快照</th><th>设备快照</th><th>经办人 / 时间（UTC）</th><th>归还结果 / 维修单</th></tr></thead><tbody><tr v-for="h in rows" :key="h.id"><td>{{ h.batchId || '未知' }}<small>{{ h.action === 'ISSUE' ? '领用' : '归还' }}</small></td><td>{{ h.personName || '未知或无权查看' }}<small>{{ h.personCode }}</small></td><td>{{ h.deviceCode || '未知' }}<small>{{ h.deviceName }} · {{ DEVICE_TYPES[h.type] || '类型未知' }}</small></td><td>{{ h.actorName || '未知' }}<small>{{ h.occurredAt || '时间未知' }}</small><small>领用开始：{{ h.startedAt || '未知' }}</small></td><td>{{ h.condition === 'GOOD' ? '完好' : h.condition === 'REPAIR' ? '需检修' : '—' }}<router-link v-if="h.maintenanceOrderId" class="button" :to="{ path: '/admin/assets/maintenance/' + h.maintenanceOrderId, query: { siteId: store.siteId, returnTo } }">维修单 {{ h.maintenanceOrderId }}</router-link></td></tr></tbody></table></div><p v-else class="query-state">暂无符合条件的流水，初始绑定不补造历史。</p></template>
<script setup>
import { DEVICE_TYPES } from '../deviceData'
import { useAdminStore } from '../store'
defineProps({ rows: { type: Array, default: () => [] }, returnTo: { type: String, default: '/admin/assets/assignments?tab=history' } })
const store = useAdminStore()
</script>
