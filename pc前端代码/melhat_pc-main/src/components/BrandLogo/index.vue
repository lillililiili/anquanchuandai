<template>
  <span class="brand-logo" :class="{ 'brand-logo--compact': compact }">
    <img :alt="compact ? title : ''" height="40" :src="logo" width="40" />
    <span v-if="!compact" class="brand-logo__name">{{ title }}<small v-if="caption">智能守护 · 协同调度</small></span>
  </span>
</template>

<script setup>
defineProps({ compact: Boolean, caption: Boolean })
const title = import.meta.env.VITE_APP_TITLE || '智能穿戴管理平台'
const logo = `${import.meta.env.BASE_URL}visuals/brand-logo.png`
</script>

<style scoped>
.brand-logo { display: inline-flex; align-items: center; gap: 11px; min-width: 0; color: var(--text-primary); }
.brand-logo img { display: block; width: 40px; height: 40px; flex: none; object-fit: contain; }
.brand-logo__name { font-size: 14px; font-weight: 650; line-height: 1.5; white-space: nowrap; }
.brand-logo__name small { display: block; margin-top: 3px; color: var(--text-muted); font-size: 10px; font-weight: 400; letter-spacing: 2px; }
.brand-logo--compact img { width: 34px; height: 34px; }
</style>
