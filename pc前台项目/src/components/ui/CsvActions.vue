<script setup>
import { closeModal } from "@/stores/modal";

defineProps({
  filename: { type: String, default: "导出.csv" },
  content: { type: String, default: "" },
});
</script>

<template>
  <a class="btn primary" :download="filename" :href="'data:text/csv;charset=utf-8,' + encodeURIComponent(content)">保存 CSV</a>
  <button type="button" class="btn" @click="closeModal">关闭</button>
</template>
