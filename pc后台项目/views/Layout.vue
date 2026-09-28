<template>
  <div class="admin-shell" :class="{ compact }" :data-section="visualSection">
    <a class="skip-link" href="#main-content">跳到正文</a>
    <header class="topbar">
      <div class="brand"><span class="rl-brand" role="img" aria-label="融瓴 ROLLING"><img class="rl-brand-mark" src="/assets/brand-mark.svg" alt="" width="42" height="42" /><span class="rl-brand-type" aria-hidden="true"><b class="rl-brand-name">融瓴</b><span class="rl-brand-en">ROLLING</span></span></span><span class="brand-product">智能穿戴设备平台<small>管理中心</small></span></div>
      <div class="top-actions">
        <label class="site-picker">当前厂站<select :disabled="!store.sites.length" :value="store.siteId" @change="selectSite($event.target.value)"><option v-if="!store.sites.length" value="">无授权厂站</option><option v-for="site in store.sites" :key="site.id" :value="site.id">{{ site.name }}</option></select></label>
        <span class="identity-name"><User aria-hidden="true" />{{ store.identity?.name }}</span>
        <button class="button text-button" @click="logout">退出登录</button>
      </div>
    </header>
    <aside class="sidebar">
      <div class="nav-heading"><span v-if="!compact">管理菜单</span><button :aria-expanded="!compact" aria-label="折叠菜单" class="button text-button" @click="compact = !compact">{{ compact ? '展开' : '收起' }}</button></div>
      <nav aria-label="主导航"><router-link v-for="(item, index) in MENU" :key="item.path" :aria-current="menuPath(route.path) === item.path ? 'page' : undefined" :class="{ active: menuPath(route.path) === item.path }" :title="item.title" :to="{ path: item.path, query: store.siteId ? { siteId: store.siteId } : {} }"><component :is="icons[index]" aria-hidden="true" /><span v-if="!compact">{{ item.title }}</span></router-link></nav>
      <div class="sidebar-bottom"><a v-if="portal" class="button" :href="portal" rel="noopener noreferrer" target="_blank">打开监护前台</a><button v-else class="button" disabled>前台地址未配置</button></div>
    </aside>
    <main id="main-content" class="main-content" tabindex="-1">
      <p v-if="contextError" class="notice error" role="alert">{{ contextError }} <button class="button" @click="initialize">重新加载</button></p>
      <p v-else-if="initializing" class="query-state" role="status">正在加载授权厂站…</p>
      <p v-else-if="!store.siteId" class="query-state">尚未分配授权。请退出后选择管理员，为此本地账号分配角色和范围。</p>
      <router-view v-else :key="route.path" />
      <footer class="workspace-footer">台账保存在后台服务 · 领用同步到监护前台 · 通信和电量来自快照，不能手改</footer>
    </main>
    <AssignmentPanel />
    <MaintenancePanel />
  </div>
</template>
<script setup>
import { computed, ref, watch, onBeforeUnmount, nextTick } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { House, Box, User, Key, Document } from '@element-plus/icons-vue'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
import { MENU, trustedPortal, safeTarget, menuPath } from '../navigation'
import AssignmentPanel from '../components/AssignmentPanel.vue'
import MaintenancePanel from '../components/MaintenancePanel.vue'
const provider = getAdminProvider(), store = useAdminStore(), route = useRoute(), router = useRouter()
const visualSection = computed(() => route.path.includes('/maintenance') ? 'maintenance' : route.path.includes('/access') ? 'access' : /^\/admin\/(people|organization|sites|duty)/.test(route.path) ? 'people' : 'assets')
const icons = [House, Box, User, Key, Document]
const portal = trustedPortal(import.meta.env.VITE_ADMIN_PORTAL_URL || 'http://127.0.0.1:5191/')
const compact = ref(false)
const initializing = ref(true), contextError = ref('')
let controller, runId = 0
async function initialize(reconcile = false) {
  const id = ++runId; controller?.abort(); controller = new AbortController(); contextError.value = ''; if (!reconcile) initializing.value = true
  try {
    await provider.hydrate?.()
    const res = await provider.query('context', {}, { signal: controller.signal })
    if (id !== runId) return
    store.identity = res.data.identity; store.sites = res.data.sites
    if (!store.sites.length) { store.selectSite(''); return }
    const desired = route.query.siteId
    if (desired && !store.sites.some(s => s.id === desired) && !reconcile) {
      store.selectSite(''); contextError.value = '无权访问链接指定的厂站，请使用顶栏选择授权厂站。'; return
    }
    const next = store.sites.some(s => s.id === desired) ? desired : store.sites.some(s => s.id === store.siteId) ? store.siteId : store.sites[0]?.id || ''
    store.selectSite(next)
    if (reconcile) { store.revision++; if (desired && desired !== next) { store.leaveGuard = null; router.replace({ path: '/admin/overview', query: next ? { siteId: next } : {} }) } }
  } catch (e) { if (e.name !== 'AbortError') { contextError.value = e.message; if (e.code === 401) provider.invalidate() } }
  finally { if (id === runId) initializing.value = false }
}
async function selectSite(id) {
  if (!store.confirmLeave()) { await nextTick(); document.querySelector('.site-picker select').value = store.siteId; return }
  contextError.value = ''; store.selectSite(id)
  router.replace({ path: /^\/admin\/people\//.test(route.path) ? '/admin/people' : /^\/admin\/assets\/devices\//.test(route.path) ? '/admin/assets/devices' : /^\/admin\/assets\/maintenance\//.test(route.path) ? '/admin/assets/maintenance' : route.path, query: { siteId: id } })
}
function logout() { provider.logout() }
const unsubscribe = provider.subscribe(event => {
  if (['identity', 'expired', 'reset'].includes(event.kind)) {
    runId++; controller?.abort(); store.clear()
    store.notice = event.kind === 'expired' ? '登录已失效，请重新登录。' : event.kind === 'reset' ? '后台数据已重置。' : ''
    router.replace({ path: '/admin/login', query: { redirect: safeTarget(route.fullPath) } })
  } else if (event.kind === 'authorization') initialize(true)
  else if (['scenario', 'revision'].includes(event.kind)) store.revision++
})
watch(() => route.query.siteId, id => {
  if (!initializing.value && id !== store.siteId) {
    if (id && !store.sites.some(s => s.id === id)) { store.selectSite(''); contextError.value = '无权访问链接指定的厂站，请选择授权厂站。' }
    else { contextError.value = ''; store.selectSite(id || store.sites[0]?.id || '') }
  }
})
initialize()
onBeforeUnmount(() => { runId++; controller?.abort(); unsubscribe() })
</script>
