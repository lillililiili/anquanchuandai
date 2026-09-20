<script setup>
import PortalPanel from './PortalPanel.vue'
import ConstructionEmpty from './ConstructionEmpty.vue'
defineProps({ title: { type: String, required: true }, description: { type: String, default: '' } })
</script>

<template>
  <div class="module-page">
    <header class="page-heading"><div><p class="eyebrow">智能穿戴 · 安全监护</p><h1>{{ title }}</h1></div><span class="scaffold-label">基础框架</span></header>
    <PortalPanel :title="title"><ConstructionEmpty :description="description || undefined" /></PortalPanel>
  </div>
</template>
