<script setup>
import MockAssignment from '@mock-assignment'
import { equipmentEnabled } from '@/api/equipment'
defineProps({ siteId: { type: String, required: true }, personId: { type: String, default: '' }, deviceId: { type: String, default: '' }, type: { type: String, default: 'HELMET' }, state: { type: String, default: '' } })
</script>
<template><MockAssignment v-if="equipmentEnabled" :site-id="siteId" :person-id="personId" :device-id="deviceId" :type="type" :state="state" /><div v-else class="equipment-disabled"><el-button disabled>领用 / 归还</el-button><small>领用服务尚未接入</small></div></template>
<style scoped>.equipment-disabled { display:flex; flex-wrap:wrap; gap:8px; align-items:center; margin:12px 0 }small { color:var(--text-secondary) }</style>
