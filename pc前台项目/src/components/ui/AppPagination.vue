<script setup>
import AppButton from "./AppButton.vue";
import { toast } from "@/stores/notify";

defineProps({
  total: { type: Number, default: 0 },
});

function stay() {
  toast("当前筛选共 1 页，已显示全部记录");
}
</script>

<template>
  <div class="pagination">
    <span>共 {{ total }} 条</span>
    <div class="row">
      <AppButton tone="small" icon="arrow-left-s-line" aria-label="上一页" @click="stay" />
      <AppButton tone="primary small" @click="stay">1</AppButton>
      <AppButton tone="small" icon="arrow-right-s-line" aria-label="下一页" @click="stay" />
    </div>
  </div>
</template>
