import { createRouter, createWebHashHistory } from 'vue-router'
import { getAdminProvider } from '@admin-provider'
import { WORKSPACES, safeTarget, cleanQuery, canonicalAdminPath, DEFAULT_ADMIN_PATH } from './navigation'
import { useAdminStore } from './store'
import MasterWorkspace from './views/MasterWorkspace.vue'
import PersonDetail from './views/PersonDetail.vue'
import Login from './views/Login.vue'
import Layout from './views/Layout.vue'
import Placeholder from './views/Placeholder.vue'

// Explicit query prevents Vue Router from inheriting unsafe parameters on a bare redirect.
const inventoryRedirect = to => ({ path: DEFAULT_ADMIN_PATH, query: cleanQuery({ siteId: to.query.siteId }) })
const legacyRedirect = to => {
  if (canonicalAdminPath(to.path) === '/login') return { path: '/login', query: to.query.redirect ? { redirect: safeTarget(to.query.redirect) } : {} }
  const target = new URL(safeTarget(to.fullPath), 'http://admin.local')
  return { path: target.pathname, query: Object.fromEntries(target.searchParams) }
}

export const router = createRouter({ history: createWebHashHistory(), routes: [
  { path: '/login', component: Login },
  { path: '/admin', redirect: inventoryRedirect },
  { path: '/admin/:pathMatch(.*)*', redirect: legacyRedirect },
  { path: '/', component: Layout, meta: { adminTheme: 'business' }, children: [
    { path: '', redirect: inventoryRedirect },
    { path: '/overview/:pathMatch(.*)*', redirect: inventoryRedirect },
    { path: '/audit', component: () => import('./views/Audit.vue') },
    { path: '/devices', component: () => import('./views/Devices.vue') },
    { path: '/devices/:deviceId', component: () => import('./views/DeviceDetail.vue'), meta: { adminFamily: 'detail' } },
    { path: '/maintenance/:pathMatch(.*)*', redirect: inventoryRedirect },
    { path: '/assignments', component: () => import('./views/Assignments.vue') },
    { path: '/organization', redirect: legacyRedirect },
    ...WORKSPACES.map(w => ({ path: w.path, component: MasterWorkspace, meta: w })),
    { path: '/people/:personId', component: PersonDetail, meta: { title: '人员详情', adminFamily: 'detail' } },
    { path: '/integrations/:pathMatch(.*)*', redirect: inventoryRedirect },
    { path: '/groups/:pathMatch(.*)*', redirect: inventoryRedirect },
    { path: '/401', component: Placeholder, meta: { title: '无权限访问', description: '当前身份没有此工作区权限，请返回设备台账或重新登录。', stage: '401', errorState: 'forbidden' } },
    { path: '/:pathMatch(.*)*', component: Placeholder, meta: { title: '页面不存在', description: '链接不存在或页面尚未开放，请返回设备台账。', stage: '404', errorState: 'not-found' } }
  ] }
] })
router.beforeEach(async (to, from) => {
  const identity = getAdminProvider().identity()
  if (identity && to.fullPath !== from.fullPath && !await useAdminStore().confirmLeave()) return false
  if (to.path !== '/login' && !identity) return { path: '/login', query: { redirect: safeTarget(to.fullPath) } }
  if (to.path === '/login' && identity) return safeTarget(to.query.redirect)
})
