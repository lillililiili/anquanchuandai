<script setup>
defineOptions({ inheritAttrs: false })
defineProps({ currentPage: { type: Number, default: 1 }, pageSize: { type: Number, default: 20 }, total: { type: Number, default: 0 }, disabled: Boolean })
const emit = defineEmits(['current-change'])
</script>
<template>
  <nav class="portal-pagination" aria-label="列表分页">
    <span class="portal-pagination-total">共 {{ total }} 条 · 每页 {{ pageSize }} 条</span>
    <el-pagination background :current-page="currentPage" :page-size="pageSize" :total="total" :disabled="disabled" :pager-count="5" layout="prev, pager, next" prev-text="上一页" next-text="下一页" @current-change="emit('current-change', $event)" />
  </nav>
</template>
<style scoped>
.portal-pagination { display:flex; align-items:center; justify-content:space-between; flex-wrap:wrap; gap:8px 12px; flex-shrink:0; min-width:0; padding:12px; margin:0; border-top:1px solid var(--border); background:var(--panel-bg); color:var(--text-secondary); container-type:inline-size; }
.portal-pagination-total { font-size:12px; font-variant-numeric:tabular-nums; white-space:nowrap; }
.portal-pagination :deep(.el-pagination) { display:flex; flex-wrap:wrap; justify-content:flex-end; gap:4px; margin:0; padding:0; --el-pagination-button-height:32px; --el-pagination-button-width:32px; }
.portal-pagination :deep(.el-pagination button), .portal-pagination :deep(.el-pager li) { margin:0 !important; border:1px solid var(--border); border-radius:4px; min-width:32px; height:32px; }
.portal-pagination :deep(.el-pager) { display:flex; gap:4px; }
.portal-pagination :deep(.el-pagination button) { padding:0 10px; }
.portal-pagination :deep(.el-pagination button:focus-visible), .portal-pagination :deep(.el-pager li:focus-visible) { outline:2px solid var(--cyan); outline-offset:2px; }
@container (max-width: 350px) { .portal-pagination :deep(.el-pagination button) { padding:0 5px; } .portal-pagination :deep(.el-pager li) { min-width:26px; } }
</style>
