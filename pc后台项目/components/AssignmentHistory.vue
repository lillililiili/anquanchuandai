<template><section class="panel device-history"><h2>按件领用归还历史</h2><p class="muted">历史名称为办理时快照；初始绑定不补造领用流水。</p><QueryState :data="query.data.value" :loading="query.loading.value" :error="query.error.value" @retry="load"><HistoryTable :rows="query.data.value?.rows || []" /><div class="pagination"><span>共 {{ query.data.value?.total || 0 }} 条 · 第 {{ pageNum }} 页</span><button class="button" :disabled="pageNum <= 1" @click="pageNum--">上一页历史</button><button class="button" :disabled="pageNum * 20 >= (query.data.value?.total || 0)" @click="pageNum++">下一页历史</button></div></QueryState></section></template>
<script setup>
import { ref, watch } from 'vue'
import { useAdminStore } from '../store'
import { useQuery } from '../useQuery'
import QueryState from './QueryState.vue'
import HistoryTable from './HistoryTable.vue'
const props = defineProps({ personId: String, deviceId: String }), store = useAdminStore(), query = useQuery(), pageNum = ref(1)
async function load() { await query.run('assignmentHistory', { siteId: store.siteId, personId: props.personId, deviceId: props.deviceId, pageNum: pageNum.value }); const last = Math.max(1, Math.ceil((query.data.value?.total || 0) / 20)); if (query.data.value?.total != null && pageNum.value > last) pageNum.value = last }
watch(() => [props.personId, props.deviceId, store.siteId], () => { pageNum.value = 1; load() }, { immediate: true })
watch(() => [pageNum.value, store.revision], load)
</script>
