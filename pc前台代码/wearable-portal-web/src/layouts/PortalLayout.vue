<script setup>
import { computed, ref, onMounted, watch, nextTick } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { ElMessage } from 'element-plus'
import { portalMenus, menuOwner } from '@/router/menus'
import WorkspaceNavigation from '@/components/WorkspaceNavigation.vue'
import { workspaceTarget } from '@/utils/workspace-navigation'
import { useUserStore } from '@/store/user'
import BrandMark from '@/components/BrandMark.vue'
import AppIcon from '@/components/AppIcon.vue'
import { useContextStore } from '@/store/context'
import { reasons } from '@/utils/portal-contract'
import DispatchBanner from '@dispatch-banner'
import { beforeDispatchLeave } from '@dispatch-runtime'

const router = useRouter()
const route = useRoute()
const surface = ref(null)
watch(() => route.path, async () => {
  await nextTick()
  if (surface.value) surface.value.scrollTop = 0
  const main = document.getElementById('main-content')
  if (main) main.scrollTop = 0
})
const context = useContextStore()
onMounted(() => context.load())
async function changeSite(event) {
  const siteId = event.target.value
  const path = ['/dispatch', '/supervision', '/alarms', '/video', '/personnel', '/equipment'].find(p => route.path === p || route.path.startsWith(p + '/')) || route.path
  const failure = await router.push({ path, query: { siteId, ...(path === '/location' ? { tab: ['live', 'tracks', 'fences'].includes(route.query.tab) ? route.query.tab : 'live' } : {}) } })
  if (!failure) context.select(siteId)
  event.target.value = context.selectedSiteId
}
const user = useUserStore()
const collapsed = ref(false)
const signingOut = ref(false)
const title = import.meta.env.VITE_APP_TITLE
const localWorkspace = import.meta.env.MODE === 'mock'
const focusMain = () => document.getElementById('main-content')?.focus()
const displayName = computed(() => user.user?.nickName || user.user?.userName || '当前用户')
const adminUrl = computed(() => {
  try {
    const url = new URL(import.meta.env.VITE_ADMIN_URL)
    return ['http:', 'https:'].includes(url.protocol) ? url.href : ''
  } catch { return '' }
})

async function signOut() {
  if (signingOut.value) return
  if (!await beforeDispatchLeave('', true)) return
  signingOut.value = true
  try { await user.signOut() } catch {
    ElMessage.warning('本机登录已退出，服务端退出未确认；请检查网络')
  } finally {
    signingOut.value = false
    await router.replace('/login')
  }
}
</script>

<template>
  <div class="portal-shell" :class="{ 'is-collapsed': collapsed }" :data-workspace="menuOwner(route.path)">
    <a class="skip-link" href="#main-content" @click.prevent="focusMain">跳至正文</a>
    <header class="topbar">
      <router-link class="platform-brand" to="/overview"><BrandMark /><span class="brand-divider"></span><span class="platform-title">{{ title }}</span></router-link>
      <div class="topbar-actions">
        <span v-if="localWorkspace" class="sidebar-note" title="当前使用本地预置数据，业务服务与设备尚未接入；操作仅在本页暂存，刷新后恢复初始状态。">服务未接入</span>
        <select v-if="context.data?.sites.length" class="station-select portal-select" aria-label="当前厂站" :value="context.selectedSiteId" @change="changeSite"><option value="" disabled>请选择厂站</option><option v-for="site in context.data.sites" :key="site.siteId" :value="site.siteId">{{ site.name }}</option></select>
        <button v-else class="station-select" :disabled="context.state !== 'ERROR'" @click="context.load(true)"><AppIcon name="OfficeBuilding" /><span>{{ context.state === 'LOADING' ? '厂站读取中…' : context.state === 'ERROR' ? '厂站读取失败，重试' : reasons[context.data?.capabilities.people.reasonCode] || '厂站数据待接入' }}</span></button>
        <span class="topbar-divider"></span>
        <el-dropdown trigger="click" @command="signOut">
          <button class="user-trigger" aria-label="用户菜单"><AppIcon name="User" /><span class="user-name">{{ displayName }}</span><AppIcon name="ArrowDown" :size="14" /></button>
          <template #dropdown><el-dropdown-menu><el-dropdown-item command="logout" :disabled="signingOut">{{ signingOut ? '正在退出…' : '退出登录' }}</el-dropdown-item></el-dropdown-menu></template>
        </el-dropdown>
      </div>
    </header>
    <aside class="sidebar">
      <div class="sidebar-controls"><span v-if="!collapsed">工作空间</span><button class="icon-button" :aria-label="collapsed ? '展开侧栏' : '收起侧栏'" :aria-expanded="!collapsed" @click="collapsed = !collapsed"><AppIcon :name="collapsed ? 'Expand' : 'Fold'" :size="20" /></button></div>
      <nav class="main-nav" aria-label="前台主导航">
        <router-link v-for="item in portalMenus" :key="item.path" :to="workspaceTarget(item, context.selectedSiteId)" active-class="route-match-unused" :title="collapsed ? item.title : undefined" :aria-label="item.title" :aria-current="menuOwner(route.path) === item.path ? 'page' : undefined" class="nav-link" :class="{ 'router-link-active': menuOwner(route.path) === item.path }"><AppIcon :name="item.icon" /><span v-if="!collapsed">{{ item.title }}</span></router-link>
      </nav>
      <div class="sidebar-footer">
        <a v-if="adminUrl" :href="adminUrl" target="_blank" rel="noopener noreferrer" class="admin-link" title="管理中心（新窗口，需独立登录）" aria-label="管理中心（新窗口，需独立登录）"><AppIcon name="Setting" /><span v-if="!collapsed">管理中心</span></a>
        <button v-else class="admin-link" disabled title="请配置 VITE_ADMIN_URL" aria-label="管理中心（地址待配置）"><AppIcon name="Setting" /><span v-if="!collapsed">管理中心</span></button>
        <span v-if="!collapsed" class="sidebar-note">{{ adminUrl ? '前后台独立登录' : '后台地址待配置' }}</span>
      </div>
    </aside>
    <main id="main-content" class="main-content" tabindex="-1"><DispatchBanner /><WorkspaceNavigation /><div ref="surface" class="route-surface" :data-route="route.path" tabindex="0" aria-label="页面内容"><router-view /></div></main>
  </div>
</template>
