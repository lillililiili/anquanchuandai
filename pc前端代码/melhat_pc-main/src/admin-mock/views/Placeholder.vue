<template>
  <section>
    <AssetTabs v-if="route.path.startsWith('/admin/assets/')" />
    <div class="page-heading"><div><span class="eyebrow">管理中心 / {{ route.meta.title }}</span><h1>{{ allowed ? route.meta.title : '无权限访问' }}</h1></div><span class="badge">{{ route.meta.stage }}</span></div>
    <div class="panel placeholder"><img :src="stateArt" alt="" width="180" height="150" class="state-art" /><h2>{{ allowed ? '工作区准备中' : '当前身份没有此工作区权限' }}</h2><p>{{ allowed ? route.meta.description : '可以返回工作台，或退出后选择其他预置身份。' }}</p><p class="muted">{{ allowed ? `本阶段只交付管理骨架。${route.meta.stage}阶段接入对应业务，不执行真实请求。` : '路由入口和数据服务分别检查权限，不因看到菜单而获得授权。' }}</p><router-link class="button primary" to="/admin/overview">返回管理工作台</router-link></div>
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
</script>
