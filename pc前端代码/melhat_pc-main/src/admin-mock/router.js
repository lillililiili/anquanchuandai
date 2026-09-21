import { createRouter, createWebHashHistory } from 'vue-router'
import { getAdminProvider } from '@admin-provider'
import { MENU, WORKSPACES, safeTarget } from './navigation'
import { useAdminStore } from './store'
import MasterWorkspace from './views/MasterWorkspace.vue'
import PersonDetail from './views/PersonDetail.vue'
import Login from './views/Login.vue'
import Layout from './views/Layout.vue'
import Overview from './views/Overview.vue'
import Placeholder from './views/Placeholder.vue'

export const router = createRouter({ history: createWebHashHistory(), routes: [
  { path: '/', redirect: '/admin/overview' },
  { path: '/admin/login', component: Login },
  { path: '/admin', component: Layout, children: [
    ...MENU.filter(m => !['/admin/assets/devices', '/admin/integrations', '/admin/audit'].includes(m.path) && !WORKSPACES.some(w => w.path === m.path)).map(m => ({ path: m.path, component: m.path === '/admin/overview' ? Overview : Placeholder, meta: m })),
    { path: '/admin/integrations', component: () => import('./views/Integrations.vue') },
    { path: '/admin/integrations/settings', component: () => import('./views/IntegrationSettings.vue') },
    { path: '/admin/integrations/jobs/:jobId', component: () => import('./views/Integrations.vue') },
    { path: '/admin/integrations/:connectorId', component: () => import('./views/Integrations.vue') },
    { path: '/admin/audit', component: () => import('./views/Audit.vue') },
    { path: '/admin/assets/devices', component: () => import('./views/Devices.vue') },
    { path: '/admin/assets/devices/:deviceId', component: () => import('./views/DeviceDetail.vue') },
    { path: '/admin/assets/assignments', component: () => import('./views/Assignments.vue') },
    { path: '/admin/assets/maintenance/:orderId', component: () => import('./views/MaintenanceSummary.vue') },
    { path: '/admin/assets/maintenance', component: () => import('./views/Maintenance.vue') },
    ...WORKSPACES.map(w => ({ path: w.path, component: w.entity === 'groups' ? () => import('./views/Groups.vue') : MasterWorkspace, meta: w })),
    { path: '/admin/access/groups/:groupId', component: () => import('./views/Groups.vue') },
    { path: '/admin/people/:personId', component: PersonDetail, meta: { title: '人员详情' } },
    { path: '/admin/legacy', component: Placeholder, meta: { title: '现场功能已迁往前台', description: '定位、视频、调度和现场核验在监护前台建设。本模式不会连接旧设备或媒体服务。', stage: '职责说明' } },
    { path: '/admin/401', component: Placeholder, meta: { title: '无权限访问', description: '当前身份没有此工作区权限，请返回工作台或重新登录。', stage: '401' } },
    { path: '/:pathMatch(.*)*', component: Placeholder, meta: { title: '页面不存在', description: '链接不存在或页面尚未开放，请返回管理工作台。', stage: '404' } }
  ] },
  ...['/live', '/group', '/big-screen', '/track', '/fence', '/intercom', '/sos', '/file', '/tts'].map(path => ({ path, redirect: '/admin/legacy' }))
] })
router.beforeEach((to, from) => {
  const identity = getAdminProvider().identity()
  if (identity && to.fullPath !== from.fullPath && !useAdminStore().confirmLeave()) return false
  if (to.path !== '/admin/login' && !identity) return { path: '/admin/login', query: { redirect: safeTarget(to.fullPath) } }
  if (to.path === '/admin/login' && identity) return safeTarget(to.query.redirect)
})
