<template>
  <div class="admin-shell" :class="{ compact }" :data-section="visualSection">
    <a class="skip-link" href="#main-content">跳到正文</a>
    <header class="topbar">
      <div class="brand"><span aria-hidden="true" class="brand-mark">W</span><span>智能穿戴设备平台<small>管理中心</small></span></div>
      <span class="muted" title="业务服务尚未接入；使用本地演示数据，刷新将恢复初始状态">服务未接入</span>
      <div class="top-actions">
        <label class="site-picker">当前厂站<select :disabled="!store.sites.length" :value="store.siteId" @change="selectSite($event.target.value)"><option v-if="!store.sites.length" value="">无授权厂站</option><option v-for="site in store.sites" :key="site.id" :value="site.id">{{ site.name }}</option></select></label>
        <span class="identity-name"><User aria-hidden="true" />{{ store.identity?.name }}</span>
        <button class="button text-button" @click="logout">退出登录</button>
      </div>
    </header>
    <aside class="sidebar">
      <div class="nav-heading"><span v-if="!compact">管理菜单</span><button :aria-expanded="!compact" aria-label="折叠菜单" class="button text-button" @click="compact = !compact">{{ compact ? '展开' : '收起' }}</button></div>
      <nav aria-label="主导航"><router-link v-for="(item, index) in MENU" :key="item.path" :aria-current="menuPath(route.path) === item.path ? 'page' : undefined" :class="{ active: menuPath(route.path) === item.path }" :title="item.title" :to="{ path: item.path, query: store.siteId ? { siteId: store.siteId } : {} }"><component :is="icons[index]" aria-hidden="true" /><span v-if="!compact">{{ item.title }}</span></router-link></nav>
      <div class="sidebar-bottom"><img v-if="!compact" class="sidebar-art" :src="showroom" alt="" width="180" height="100" loading="lazy" /><p v-if="!compact" class="small muted">前台负责现场监护<br>后台负责资产与管理</p><a v-if="portal" class="button" :href="portal" rel="noopener noreferrer" target="_blank">打开监护前台</a><button v-else class="button" disabled>前台地址未配置</button><small v-if="!compact">独立登录 · 数据独立</small></div>
    </aside>
    <main id="main-content" class="main-content" tabindex="-1">
      <p v-if="contextError" class="notice error" role="alert">{{ contextError }} <button class="button" @click="initialize">重新加载</button></p>
      <p v-else-if="initializing" class="query-state" role="status">正在加载授权厂站…</p>
      <p v-else-if="!store.siteId" class="query-state">尚未分配授权。请退出后选择管理员，为此本地账号分配角色和范围。</p>
      <router-view v-else :key="route.path" />
      <footer class="workspace-footer">业务服务未接入 · 数据保存在当前页面 · 不代表设备已接入或真实业务验收通过</footer>
    </main>
    <AssignmentPanel />
    <MaintenancePanel />
    <ModalPanel heading-id="scene-heading" :open="panel" title="演示设置" @close="panel = false">
      <p class="notice">设置查询的演示结果，不修改初始数据，也不连接外部系统。</p>
      <form class="scenario-form" @submit.prevent="applyScenario">
        <label>目标查询<select v-model="target"><option value="authorizationPreview">授权效果预览</option><option value="groups">协助组列表</option><option value="group">协助组详情</option><option value="groupCandidates">协助组候选</option><option value="groupTerminals">当前终端摘要</option><option value="groupHistory">协助组配置历史</option><option v-for="kind in MAINTENANCE_QUERIES" :key="kind" :value="kind">{{ maintenanceQueryNames[kind] }}</option><option v-for="kind in ASSIGNMENT_QUERIES" :key="kind" :value="kind">{{ assignmentQueryNames[kind] }}</option><option value="overview">工作台指标</option><option value="details">指标明细</option><option value="audit">最近管理变更</option><option value="devices">设备台账</option><option value="device">设备详情</option><option value="deviceOptions">型号与区域选项</option><option value="deviceHistory">设备历史</option><option value="deviceChanges">设备变更</option><option v-for="(entry, key) in ENTITIES" :key="key" :value="key">{{ entry.title }}</option></select></label>
        <label>查询状态<select v-model="mode"><option value="normal">正常</option><option value="unavailable">来源未接入</option><option value="failure">请求失败</option><option value="forbidden">分区无权限</option></select></label>
        <label class="check"><input v-model="slow" type="checkbox" />下一次查询延迟3秒（检查切换厂站时是否显示正确数据）</label>
        <div class="actions"><button class="button primary" type="submit">应用场景</button><button class="button" type="button" @click="restore">恢复默认场景</button></div>
      </form>
      <hr><h3>会话与数据</h3><p class="muted">当前会话失效会返回登录页；重置还会恢复全部初始演示数据。</p>
      <div class="actions"><button class="button" @click="provider.invalidate()">使当前会话失效</button><button class="button danger" @click="confirmReset = true">恢复初始演示数据</button></div>
      <section v-if="confirmReset" class="reset-confirm" role="alert"><h3>确认恢复本后台初始数据？</h3><p>当前页面数据、场景和本地身份将清除，随后返回登录。前台、原PC及数据库不受影响。</p><div class="actions"><button class="button danger" @click="provider.reset()">确认重置并退出</button><button class="button" @click="confirmReset = false">保留数据</button></div></section>
    </ModalPanel>
  </div>
</template>
<script setup>
import { computed, ref, watch, onBeforeUnmount, nextTick } from 'vue'
import showroom from '../assets/visual/showroom-banner.webp'
import { useRoute, useRouter } from 'vue-router'
import { House, Box, User, Key, Connection, Document } from '@element-plus/icons-vue'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
import { MENU, trustedPortal, safeTarget, menuPath } from '../navigation'
import { ENTITIES } from '../masterData'
import ModalPanel from '../components/ModalPanel.vue'
import AssignmentPanel from '../components/AssignmentPanel.vue'
import MaintenancePanel from '../components/MaintenancePanel.vue'
import { MAINTENANCE_QUERIES } from '../maintenanceData'
const maintenanceQueryNames = { maintenanceOrders: '维修工单列表', maintenanceOrder: '维修工单详情', maintenanceRecords: '维修过程记录', deviceLifecycleHistory: '设备使用状态记录' }
import { ASSIGNMENT_QUERIES } from '../assignmentData'
const assignmentQueryNames = { assignments: '当前领用', assignmentHistory: '领用归还历史', assignmentCandidates: '办理候选', repairAssignees: '维修处理人', maintenanceSummary: '维修摘要' }
const provider = getAdminProvider(), store = useAdminStore(), route = useRoute(), router = useRouter()
const visualSection = computed(() => route.path.includes('/maintenance') ? 'maintenance' : route.path.includes('/access') ? 'access' : /^\/admin\/(people|organization|sites|duty)/.test(route.path) ? 'people' : 'assets')
const icons = [House, Box, User, Key, Connection, Document]
const portal = trustedPortal(import.meta.env.VITE_ADMIN_PORTAL_URL)
const compact = ref(false), panel = ref(false), confirmReset = ref(false), target = ref('overview'), mode = ref('normal'), slow = ref(false)
const initializing = ref(true), contextError = ref('')
let controller, runId = 0
async function initialize(reconcile = false) {
  const id = ++runId; controller?.abort(); controller = new AbortController(); contextError.value = ''; if (!reconcile) initializing.value = true
  try {
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
  router.replace({ path: /^\/admin\/integrations\/(?!settings$)/.test(route.path) ? '/admin/integrations' : /^\/admin\/people\//.test(route.path) ? '/admin/people' : /^\/admin\/assets\/devices\//.test(route.path) ? '/admin/assets/devices' : /^\/admin\/assets\/maintenance\//.test(route.path) ? '/admin/assets/maintenance' : /^\/admin\/access\/groups\//.test(route.path) ? '/admin/access/groups' : route.path, query: { siteId: id } })
}
function logout() { provider.logout() }
function applyScenario() { provider.setScenario({ target: target.value, mode: mode.value, delayNext: slow.value }); panel.value = false; slow.value = false }
function restore() { provider.restoreScenario(); mode.value = 'normal'; slow.value = false; panel.value = false }
const unsubscribe = provider.subscribe(event => {
  if (['identity', 'expired', 'reset'].includes(event.kind)) {
    runId++; controller?.abort(); panel.value = false; store.clear()
    store.notice = event.kind === 'expired' ? '登录已失效，请重新登录。' : event.kind === 'reset' ? '本后台演示数据已重置。' : ''
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
