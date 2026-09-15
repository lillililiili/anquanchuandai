<template>
  <div class="sidebar-logo-container">
    <router-link class="sidebar-logo-link" to="/" aria-label="智能穿戴管理平台首页">
      <BrandLogo :caption="!collapse" :compact="collapse" />
    </router-link>
  </div>
</template>
<script setup>
defineProps({ collapse: { type: Boolean, required: true } })
</script>
<style scoped>
.sidebar-logo-container { display: flex; align-items: center; justify-content: center; height: 56px; border-bottom: 1px solid var(--sidebar-border); background: var(--sidebar-bg); }
.sidebar-logo-link { display: flex; align-items: center; justify-content: center; height: 56px; width: 100%; padding: 0 12px; }
.sidebar-logo-link :deep(.brand-logo) { gap: 8px; }
.sidebar-logo-link :deep(.brand-logo__name) { font-size: 12px; }
.sidebar-logo-link :deep(.brand-logo img) { width: 32px; height: 36px; }
</style>
