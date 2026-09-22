<script setup>
import AppIcon from "./AppIcon.vue";

defineProps({
  text: { type: String, default: "暂无数据" },
  icon: { type: String, default: "inbox-2-line" },
});
</script>

<template>
  <div class="empty">
    <AppIcon :name="icon" />
    <span>{{ text }}</span>
  </div>
</template>
