// Page registration is deliberately independent from the seven work entrances.
export const portalPages = [
  { path: '/equipment', title: '装备查询', icon: 'Box', component: () => import('@/views/equipment/EquipmentView.vue') },
  { path: '/overview', title: '安全总览', icon: 'Grid', component: () => import('@/views/overview/OverviewView.vue') },
  { path: '/personnel', title: '人员与装备', icon: 'User', component: () => import('@/views/personnel/PersonnelView.vue') },
  { path: '/supervision', title: '作业监护', icon: 'Checked', component: () => import('@/views/supervision/SupervisionView.vue') },
  { path: '/video', title: '视频监看', icon: 'VideoCamera', component: () => import('@/views/video/VideoView.vue') },
  { path: '/dispatch', title: '调度通信', icon: 'Microphone', component: () => import('@/views/dispatch/DispatchView.vue') },
  { path: '/location', title: '定位与轨迹', icon: 'Location', component: () => import('@/views/location/LocationView.vue') },
  { path: '/alarms', title: '告警与核验', icon: 'Warning', component: () => import('@/views/alarms/AlarmsView.vue') },
  { path: '/materials', title: '现场资料', icon: 'Document', component: () => import('@/views/materials/MaterialsView.vue') },
  { path: '/statistics', title: '统计追溯', icon: 'DataAnalysis', component: () => import('@/views/statistics/StatisticsView.vue') }
]

export const portalMenus = [
  { path: '/overview', title: '安全总览', icon: 'Grid' },
  { path: '/location', title: '现场监看', icon: 'VideoCamera', query: { tab: 'live' } },
  { path: '/personnel', title: '人员装备', icon: 'User' },
  { path: '/supervision', title: '作业监护', icon: 'Checked' },
  { path: '/alarms', title: '事件处置', icon: 'Warning' },
  { path: '/dispatch', title: '调度协同', icon: 'Microphone' },
  { path: '/materials', title: '查询分析', icon: 'DataAnalysis' }
]
export function menuOwner(path) {
  if (/^\/equipment(\/|$)/.test(path)) return '/personnel'
  if (/^\/(location|video)(\/|$)/.test(path)) return '/location'
  if (/^\/(materials|statistics)(\/|$)/.test(path)) return '/materials'
  return portalMenus.find(m => path === m.path || path.startsWith(m.path + '/'))?.path || ''
}
export const pageGroups = {
  '/location': [{ path: '/location', query: { tab: 'live' }, title: '位置' }, { path: '/video', title: '视频' }, { path: '/location', query: { tab: 'tracks' }, title: '轨迹' }, { path: '/location', query: { tab: 'fences' }, title: '围栏' }],
  '/personnel': [{ path: '/personnel', title: '当班人员' }, { path: '/equipment', title: '装备查询' }],
  '/materials': [{ path: '/materials', title: '现场资料' }, { path: '/statistics', title: '统计报表' }]
}
