<script setup>
import { computed, defineAsyncComponent } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { s2Query } from '@/utils/spatial-contract'
import { enabled as localMode } from '@spatial-actions'
const tabs = [{ name: 'live', label: '实时定位' }, { name: 'tracks', label: '历史轨迹' }, { name: 'fences', label: '电子围栏' }]
const route = useRoute()
const router = useRouter()
const views = { live: defineAsyncComponent(() => import('./LiveLocation.vue')), tracks: defineAsyncComponent(() => import('./TrackView.vue')), fences: defineAsyncComponent(() => import('./FenceView.vue')) }
const activeTab = computed({
  get: () => tabs.some((tab) => tab.name === route.query.tab) ? route.query.tab : 'live',
  set: (tab) => router.push({ path: '/location', query: { tab, ...s2Query(tab, { siteId: route.query.siteId, deviceId: route.query.deviceId }) } })
})
</script>

<template>
  <div class="s2-page"><header class="s2-heading"><div><h1>{{ tabs.find(t => t.name === activeTab)?.label }}</h1><p>按授权范围查询 · 位置快照及历史证据</p></div><span class="s2-badge">{{ localMode && activeTab === 'fences' ? '围栏管理' : '只读查询' }}</span></header><component :is="views[activeTab]" :key="activeTab" /></div>
</template>
