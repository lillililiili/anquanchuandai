<template>
  <section>
    <AssetTabs v-if="['devices', 'assignments', 'maintenance'].includes(route.path.split('/')[1])" />
    <h1 class="sr-only">{{ allowed ? route.meta.title : '无权限访问' }}</h1>
    <div class="panel placeholder"><img :src="stateArt" alt="" width="180" height="150" class="state-art" /><h2>{{ denied ? '当前账号无权使用此功能' : missing ? '未找到此页面' : '功能暂未开放' }}</h2><p>{{ allowed ? route.meta.description : '可以返回设备台账，或退出后更换账号。' }}</p><p class="muted">{{ denied ? '如需使用此功能，请联系管理员开通权限。' : missing ? '请检查链接，或使用顶部菜单前往其他页面。' : '此功能尚未开放，请返回设备台账选择其他功能。' }}</p><router-link class="button primary" :to="{ path: '/devices', query: store.siteId ? { siteId: store.siteId } : {} }">返回设备台账</router-link></div>
  </section>
</template>
<script setup>
import { computed } from 'vue'
import stateArt from '../assets/visual/state-empty.webp'
import { useRoute } from 'vue-router'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
import AssetTabs from '../components/AssetTabs.vue'
const route = useRoute(), store = useAdminStore()
const allowed = computed(() => { void store.revision; return !route.meta.permission || getAdminProvider().can(route.meta.permission, store.siteId) })
const denied = computed(() => route.meta.errorState === 'forbidden' || !allowed.value)
const missing = computed(() => route.meta.errorState === 'not-found')
</script>
