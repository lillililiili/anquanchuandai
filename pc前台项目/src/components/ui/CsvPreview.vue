<script setup>
import AppTable from "./AppTable.vue";

defineOptions({ inheritAttrs: false });

defineProps({
  headers: { type: Array, default: () => [] },
  rows: { type: Array, default: () => [] },
});
</script>

<template>
  <p class="note">按当前筛选生成 {{ rows.length }} 条记录。如浏览器未自动下载，请点击下方保存 CSV。</p>
  <AppTable :columns="headers" :empty="!rows.length">
    <tr v-for="(row, index) in rows" :key="index">
      <td v-for="(cell, cellIndex) in row" :key="cellIndex">{{ cell }}</td>
    </tr>
  </AppTable>
</template>
