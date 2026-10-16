<script setup>
import { nextTick, ref, watch } from "vue";
import AppEmpty from "./AppEmpty.vue";
import AppPagination from "./AppPagination.vue";
import { useTablePagination } from "@/lib/pagination";

const props = defineProps({
  columns: { type: Array, default: () => [] },
  rows: { type: Array, default: () => [] },
  resetKey: { default: null },
  tableClass: { type: String, default: "" },
  empty: Boolean,
  emptyText: { type: String, default: "暂无符合条件的记录" },
});
const viewport = ref(null);
const { page, pageSize, total, offset, visibleRows, changePage, changePageSize } = useTablePagination(() => props.rows, () => props.resetKey);
watch([page, pageSize, () => JSON.stringify(props.resetKey)], async () => {
  await nextTick();
  if (viewport.value) viewport.value.scrollTop = 0;
});
</script>

<template>
  <div class="app-table" :class="{ 'is-paginated': total > pageSize }">
    <div ref="viewport" class="table-scroll" tabindex="0" role="region" aria-label="表格数据，可滚动">
      <table :class="tableClass">
        <thead>
          <tr>
            <slot name="head">
              <th v-for="(column, index) in columns" :key="index">{{ column }}</th>
            </slot>
          </tr>
        </thead>
        <tbody>
          <tr v-if="empty || !total">
            <td :colspan="columns.length || 1"><AppEmpty :text="emptyText" /></td>
          </tr>
          <slot v-else :rows="visibleRows" :offset="offset" />
        </tbody>
      </table>
    </div>
    <AppPagination :total="total" :model-value="page" :page-size="pageSize" @update:model-value="changePage" @update:page-size="changePageSize" />
  </div>
</template>
