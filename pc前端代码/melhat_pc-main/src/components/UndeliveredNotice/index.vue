<template>
  <el-alert
    :closable="false"
    show-icon
    style="margin-bottom: 12px"
    type="warning"
    :title="title"
  >
    <template #default>
      {{ description }}
    </template>
  </el-alert>
</template>

<script setup>
defineProps({
  title: {
    type: String,
    default: '未交付能力'
  },
  description: {
    type: String,
    default: '本页仍走演示或旧入口，不作为智能穿戴管理平台已完成功能。'
  }
})
</script>
