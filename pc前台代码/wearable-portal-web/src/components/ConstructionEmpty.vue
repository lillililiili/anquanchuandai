<script setup>
import AppIcon from './AppIcon.vue'
defineProps({ description: { type: String, default: '当前模块已预留，业务功能将在后续版本接入。' } })
</script>

<template>
  <div class="construction-empty" role="status">
    <span class="empty-symbol"><AppIcon name="Document" :size="42" /></span>
    <h3>功能建设中</h3>
    <p>{{ description }}</p>
    <span class="empty-note">暂无业务数据接入</span>
  </div>
</template>
