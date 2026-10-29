<template><section class="panel device-history"><div class="section-heading"><h2>按件领用归还历史</h2><button class="button" :disabled="query.loading.value" @click="refresh">刷新</button></div><QueryState :data="query.data.value" :loading="query.loading.value" :error="query.error.value" @retry="load"><HistoryTable :rows="query.data.value?.rows || []" /><AdminPagination :total="query.data.value?.total || 0" :model-value="pageNum" :page-size="pageSize" :disabled="query.loading.value" @update:model-value="pageNum=$event" @update:page-size="pageSize=$event; pageNum=1" /></QueryState></section></template>
<script setup>
import { ref, watch } from 'vue'
import { useAdminStore } from '../store'
import { useQuery } from '../useQuery'
import QueryState from './QueryState.vue'
import HistoryTable from './HistoryTable.vue'
const props = defineProps({ personId: String, deviceId: String }), store = useAdminStore(), query = useQuery(), pageNum = ref(1), pageSize = ref(10)
function refresh() { if (pageNum.value !== 1) pageNum.value = 1; else load() }
async function load() { await query.run('assignmentHistory', { siteId: store.siteId, personId: props.personId, deviceId: props.deviceId, pageNum: pageNum.value, pageSize: pageSize.value }); const last = Math.max(1, Math.ceil((query.data.value?.total || 0) / pageSize.value)); if (query.data.value?.total != null && pageNum.value > last) pageNum.value = last }
watch(() => [props.personId, props.deviceId, store.siteId], () => { pageNum.value = 1; load() }, { immediate: true })
watch(() => [pageNum.value, pageSize.value, store.revision], load)
</script>
