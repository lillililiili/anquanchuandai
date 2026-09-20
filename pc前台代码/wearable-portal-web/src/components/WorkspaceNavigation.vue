<script setup>
import { computed, watch } from 'vue'
import { useRoute } from 'vue-router'
import { menuOwner, portalMenus, pageGroups } from '@/router/menus'
import { workspaceTarget } from '@/utils/workspace-navigation'
import { useContextStore } from '@/store/context'
import { useWorkspaceStore } from '@/store/workspace'
import AppIcon from '@/components/AppIcon.vue'
const route = useRoute(), context = useContextStore(), workspace = useWorkspaceStore()
const owner = computed(() => menuOwner(route.path)), group = computed(() => pageGroups[owner.value] || [])
const siteId = computed(() => route.query.siteId || context.selectedSiteId)
const active = item => item.path === route.path && (!item.query?.tab || item.query.tab === (route.query.tab || 'live'))
watch(() => [siteId.value, context.state, context.selectedSiteId, route.path, route.query.deviceId, route.query.selectedId, route.params.deviceId], () => {
  if (owner.value !== '/location' || context.state !== 'READY' || context.selectedSiteId !== siteId.value) return
  const deviceId = route.params.deviceId || (route.path === '/video' ? route.query.selectedId : route.query.deviceId)
  if (deviceId) workspace.select(siteId.value, deviceId)
}, { immediate: true, flush: 'post' })
</script>
<template>
  <nav v-if="group.length || Object.keys(route.params).length" class="workspace-navigation" aria-label="工作区导航">
    <span class="workspace-identity"><AppIcon :name="portalMenus.find(m => m.path === owner)?.icon" :size="18" />{{ portalMenus.find(m => m.path === owner)?.title }}</span>
    <template v-for="item in group" :key="item.title">
      <router-link v-if="item.path" :to="workspaceTarget(item, siteId, workspace.selection)" :aria-current="active(item) ? 'page' : undefined">{{ item.title }}</router-link>
      <span v-else class="workspace-pending"><button disabled>{{ item.title }}</button><small>{{ item.reason }}</small></span>
    </template>
    <span v-if="Object.keys(route.params).length" aria-current="page">/ {{ route.meta.title }}</span>
    <small v-if="owner === '/location' && workspace.selection.siteId === siteId && workspace.selection.deviceId">共享设备：{{ workspace.selection.deviceId }}。围栏只按厂站查看，不推定设备与围栏关系。</small>
  </nav>
</template>
<style scoped>
.workspace-navigation { display:flex; flex-wrap:wrap; align-items:center; gap:12px; margin-bottom:20px; padding-bottom:12px; border-bottom:1px solid var(--border); color:var(--text-secondary) }
a,button { padding:10px 16px; border:1px solid var(--border); background:var(--panel-bg); color:inherit; border-radius:4px }
a[aria-current] { border-color:var(--cyan); color:var(--cyan) }
.workspace-pending { display:flex; align-items:center; gap:8px } small { color:var(--text-muted) }
</style>
