<template><section class="panel device-history"><h2>{{ orderId ? '维修过程记录' : '设备设备使用状态记录' }}</h2><p class="muted">时间均为UTC。记录保留办理时的名称；没有记录不补造过去事实。</p><QueryState :data="list.data.value" :loading="list.loading.value" :error="list.error.value" @retry="load"><ol v-if="list.data.value?.rows?.length" class="maintenance-records"><li v-for="r in list.data.value.rows" :key="r.id"><div class="record-line"><strong>{{ RECORD_ACTIONS[r.action] || r.action }}</strong><span>{{ r.occurredAt || '时间未知' }}</span></div><p>{{ r.deviceCode }} · {{ r.deviceName }}</p><p v-if="r.repairContent">维修内容：{{ r.repairContent }}</p><p v-if="r.description">{{ r.description }}</p><p v-if="r.inspection">检查／检测：{{ r.inspection }}</p><p v-if="r.from">{{ DEVICE_FILTERS.lifecycle[r.from] }} → {{ DEVICE_FILTERS.lifecycle[r.to] }}</p><small>经办人 {{ r.actorName || '未知' }} · 处理人快照 {{ r.handlerName || '未知' }}<template v-if="r.oldHandlerName"> · 原处理人 {{ r.oldHandlerName }}</template></small></li></ol><p v-else class="query-state">暂无{{ orderId ? '维修过程' : '设备使用状态' }}记录。</p><div class="pagination"><span>共 {{ list.data.value?.total || 0 }} 条 · 第 {{ page }} 页</span><button class="button" :disabled="page <= 1" @click="page--; load()">上一页运维记录</button><button class="button" :disabled="page * 20 >= (list.data.value?.total || 0)" @click="page++; load()">下一页运维记录</button></div></QueryState></section></template>
<script setup>
import { ref, watch } from 'vue'
import { useAdminStore } from '../store'
import { useQuery } from '../useQuery'
import { RECORD_ACTIONS } from '../maintenanceData'
import { DEVICE_FILTERS } from '../deviceData'
import QueryState from './QueryState.vue'
const props = defineProps({ deviceId: String, orderId: String }), store = useAdminStore(), list = useQuery(), page = ref(1)
function load() { list.run(props.orderId ? 'maintenanceRecords' : 'deviceLifecycleHistory', { siteId: store.siteId, deviceId: props.deviceId, id: props.orderId, pageNum: page.value }) }
watch(() => [props.deviceId, props.orderId, store.siteId], () => { page.value = 1; load() }, { immediate: true }); watch(() => store.revision, load)
</script>
