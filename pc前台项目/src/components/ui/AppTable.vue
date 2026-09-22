<script setup>
import AppEmpty from "./AppEmpty.vue";

defineProps({
  columns: { type: Array, default: () => [] },
  tableClass: { type: String, default: "" },
  empty: Boolean,
  emptyText: { type: String, default: "暂无符合条件的记录" },
});
</script>

<template>
  <div class="table-scroll">
    <table :class="tableClass">
      <thead>
        <tr>
          <slot name="head">
            <th v-for="(column, index) in columns" :key="index">{{ column }}</th>
          </slot>
        </tr>
      </thead>
      <tbody>
        <tr v-if="empty">
          <td :colspan="columns.length || 1"><AppEmpty :text="emptyText" /></td>
        </tr>
        <slot v-else />
      </tbody>
    </table>
  </div>
</template>
