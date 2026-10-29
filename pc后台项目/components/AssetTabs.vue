<template><nav class="workspace-tabs" aria-label="装备资产导航"><router-link v-for="item in items" :key="item.path" :class="{ active: route.path === item.path || route.path.startsWith(item.path + '/') }" :to="{ path: item.path, query: { siteId: store.siteId } }">{{ item.name }}</router-link></nav></template>
<script setup>
import { useRoute } from 'vue-router'
import { useAdminStore } from '../store'
const route = useRoute(), store = useAdminStore()
const items = [{ path: '/devices', name: '设备台账' }]
</script>
