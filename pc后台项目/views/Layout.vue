<template>
  <div class="admin-shell" :data-section="visualSection">
    <a class="skip-link" href="#main-content">跳到正文</a>
    <header class="admin-header"><AdminNavigation :sites="store.sites" :site-id="store.siteId" :identity="store.identity" :portal="portal" :switching="switching" @site="selectSite" @logout="logout" /></header>
    <main id="main-content" class="main-content" tabindex="-1">
      <p v-if="contextError" class="notice error" role="alert">{{ contextError }} <button class="button" @click="initialize">重新加载</button></p>
      <p v-else-if="initializing" class="query-state" role="status">正在加载授权厂站…</p>
      <p v-else-if="!store.siteId" class="query-state">尚未分配授权。请退出后选择管理员，为此用户账号分配角色和范围。</p>
      <router-view v-else :key="route.path" />
    </main>
    <AssignmentPanel />

  </div>
</template>
<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import AdminNavigation from '../components/AdminNavigation.vue'
import { changeSiteAfterConfirmation } from '../adminNavigation'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
import { trustedPortal, safeTarget } from '../navigation'
import AssignmentPanel from '../components/AssignmentPanel.vue'
import { finishConfirmation } from '../confirmation'
import { TEST_SITE_MODE, TEST_SITE, testSiteChoices } from '../../shared/test-site.mjs'
const provider = getAdminProvider(), store = useAdminStore(), route = useRoute(), router = useRouter()
const visualSection = computed(() => /^\/(accounts|roles|groups)(\/|$)/.test(route.path) ? 'access' : /^\/(people|organization|sites|duty)(\/|$)/.test(route.path) ? 'people' : 'assets')
const portal = trustedPortal(import.meta.env.VITE_ADMIN_PORTAL_URL || 'http://127.0.0.1:5191/')
const switching = ref(false)
const initializing = ref(true), contextError = ref('')
let controller, runId = 0
async function initialize(reconcile = false) {
  const id = ++runId; controller?.abort(); controller = new AbortController(); contextError.value = ''; if (!reconcile) initializing.value = true
  try {
    await provider.hydrate?.()
    const res = await provider.query('context', {}, { signal: controller.signal })
    if (id !== runId) return
    store.identity = res.data.identity; store.sites = testSiteChoices(res.data.sites)
    if (!store.sites.length) { store.selectSite(''); return }
    const desired = route.query.siteId
    if (desired && !store.sites.some(s => s.id === desired) && !reconcile) {
      store.selectSite(''); contextError.value = TEST_SITE_MODE ? '当前环境只开放测试厂区，该链接属于其他厂站。请从主导航返回测试厂区。' : '无权访问链接指定的厂站，请使用顶栏选择授权厂站。'; return
    }
    const next = store.sites.some(s => s.id === desired) ? desired : store.sites.some(s => s.id === store.siteId) ? store.siteId : store.sites[0]?.id || ''
    store.selectSite(next)
    if (reconcile) { store.revision++; if (desired && desired !== next) { store.leaveGuard = null; router.replace({ path: '/devices', query: next ? { siteId: next } : {} }) } }
  } catch (e) { if (e.name !== 'AbortError') { contextError.value = e.message; if (e.code === 401) provider.invalidate() } }
  finally { if (id === runId) initializing.value = false }
}
async function selectSite(id) {
  if (TEST_SITE_MODE && id !== TEST_SITE.adminId) return
  if (switching.value || !store.sites.some(site => site.id === id)) return
  switching.value = true
  try {
    await changeSiteAfterConfirmation({ current: store.siteId, next: id, confirm: () => store.confirmLeave(), commit: async next => {
      contextError.value = ''; store.selectSite(next)
      await router.replace({ path: /^\/people\//.test(route.path) ? '/people' : /^\/devices\//.test(route.path) ? '/devices' : route.path, query: { siteId: next } })
    } })
  } finally { switching.value = false }
}
async function logout() { if (await store.confirmLeave()) provider.logout() }
const unsubscribe = provider.subscribe(event => {
  if (['context', 'authorization'].includes(event.kind)) finishConfirmation(false)
  if (['identity', 'expired', 'reset'].includes(event.kind)) {
    finishConfirmation(false)
    runId++; controller?.abort(); store.clear()
    store.notice = event.kind === 'expired' ? '登录已失效，请重新登录。' : event.kind === 'reset' ? '后台数据已重置。' : ''
    router.replace({ path: '/login', query: { redirect: safeTarget(route.fullPath) } })
  } else if (event.kind === 'authorization') initialize(true)
  else if (['scenario', 'revision'].includes(event.kind)) store.revision++
})
watch(() => route.query.siteId, id => {
  if (!initializing.value && id !== store.siteId) {
    if (id && !store.sites.some(s => s.id === id)) { store.selectSite(''); contextError.value = TEST_SITE_MODE ? '当前环境只开放测试厂区，该链接属于其他厂站。请从主导航返回测试厂区。' : '无权访问链接指定的厂站，请选择授权厂站。' }
    else { contextError.value = ''; store.selectSite(id || store.sites[0]?.id || '') }
  }
})
initialize()
onBeforeUnmount(() => { runId++; controller?.abort(); unsubscribe() })
</script>
