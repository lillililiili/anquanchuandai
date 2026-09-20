import { createRouter, createWebHashHistory } from 'vue-router'
import { ElMessage } from 'element-plus'
import 'element-plus/es/components/message/style/css'
import pinia from '@/store'
import { useUserStore } from '@/store/user'
import { portalPages, portalMenus } from './menus'
import { personIdPattern, personnelQuery, safePersonnelReturn } from '@/utils/portal-route'
import { safeWorkspaceReturn } from '@/utils/spatial-contract'
import { safeVideoReturn } from '@/utils/video-route'
import { safeEventReturn } from '@/utils/event-route'
import { safeWorkReturn } from '@/utils/work-route'
import { safeDispatchReturn } from '@/utils/dispatch-route'
import { beforeDispatchLeave } from '@dispatch-runtime'
import { safeEquipmentReturn } from '@/utils/equipment-route'
import { safeStatisticsReturn } from '@/utils/statistics'

const router = createRouter({
  history: createWebHashHistory(import.meta.env.BASE_URL),
  routes: [
    { path: '/login', name: 'login', component: () => import('@/views/login/LoginView.vue'), meta: { public: true, title: '工作账号登录' } },
    { path: '/', component: () => import('@/layouts/PortalLayout.vue'), redirect: '/overview', children:
      [...portalPages.map((item) => ({ path: item.path, component: item.component, meta: { title: portalMenus.find(m => m.path === item.path)?.title || item.title } })),
        { path: '/dispatch/sos/:eventId', name: 'sos-detail', component: () => import('@/views/dispatch/DispatchView.vue'), meta: { title: 'SOS紧急详情' } },
        { path: '/supervision/:workId', name: 'work-detail', component: () => import('@/views/supervision/SupervisionView.vue'), meta: { title: '作业监护详情' } },
        { path: '/equipment/:deviceId', name: 'equipment-detail', component: () => import('@/views/equipment/EquipmentDetailView.vue'), meta: { title: '装备详情' } },
        { path: '/personnel/:personId', name: 'person-detail', component: () => import('@/views/personnel/PersonDetailView.vue'), meta: { title: '人员详情' } },
        { path: '/video/:deviceId', name: 'video-detail', component: () => import('@/views/video/VideoDetailView.vue'), meta: { title: '单路监看' } },
        { path: '/alarms/:eventId/verification', name: 'event-verification', component: () => import('@/views/alarms/VerificationView.vue'), meta: { title: '事件核验详情' } }]
    },
    { path: '/401', name: 'unauthorized', component: () => import('@/views/error/ErrorView.vue'), meta: { public: true, title: '访问受限', status: 401 } },
    { path: '/:pathMatch(.*)*', name: 'not-found', component: () => import('@/views/error/ErrorView.vue'), meta: { title: '页面未找到', status: 404 } }
  ],
  scrollBehavior: () => ({ top: 0 })
})

export function safeRedirect(value) {
  if (typeof value !== 'string' || !value.startsWith('/') || value.startsWith('//') || value.includes('\\') || [...value].some((char) => char.charCodeAt(0) < 32)) return '/overview'
  try {
    const target = router.resolve(value)
    if (target.path === '/statistics') return safeStatisticsReturn(value)
    if (target.path === '/dispatch' || target.name === 'sos-detail') return safeDispatchReturn(value)
    if (target.path === '/supervision' || target.name === 'work-detail') return safeWorkReturn(value, true)
    if (target.path === '/equipment' || target.name === 'equipment-detail') return safeEquipmentReturn(value, true)
    if (target.path === '/alarms' || target.name === 'event-verification') return safeEventReturn(value, true)
    if (target.path === '/video' || target.name === 'video-detail') return safeVideoReturn(value, true)
    if (target.path === '/personnel') return safePersonnelReturn(value)
    if (['/location', '/materials'].includes(target.path)) return safeWorkspaceReturn(value)
    if (target.name === 'person-detail' && personIdPattern.test(String(target.params.personId))) {
      const query = personnelQuery(target.query)
      if (target.query.returnTo) query.returnTo = safeWorkspaceReturn(target.query.returnTo)
      return router.resolve({ path: target.path, query }).fullPath
    }
    return portalPages.some((item) => item.path === target.path) ? router.resolve({ path: target.path, query: personnelQuery({ siteId: target.query.siteId }) }).fullPath : '/overview'
  } catch { return '/overview' }
}

router.beforeEach(async (to) => {
  const user = useUserStore(pinia)
  if (to.meta.public && to.name !== 'login') return true
  if (!user.token) return to.meta.public ? true : { name: 'login', query: { redirect: safeRedirect(to.fullPath) }, replace: true }
  try {
    await user.loadProfile()
  } catch (error) {
    user.clearSession()
    ElMessage.error(error.code === 401 ? '登录状态已失效，请重新登录' : error.message)
    return to.name === 'login' ? true : { name: 'login', query: { redirect: safeRedirect(to.fullPath) }, replace: true }
  }
  if (to.name === 'login') return { path: safeRedirect(to.query.redirect), replace: true }
  if (!await beforeDispatchLeave(typeof to.query.siteId === 'string' ? to.query.siteId : '')) return false
  return true
})

router.afterEach((to) => { document.title = `${to.meta.title || '前台'} · ${import.meta.env.VITE_APP_TITLE}` })

export default router
