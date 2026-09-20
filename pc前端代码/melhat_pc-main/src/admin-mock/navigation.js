export const MENU = [
  { path: '/admin/overview', title: '管理工作台', permission: 'overview:read', stage: 'A0', description: '概况、待关注关系和最近管理变更' },
  { path: '/admin/assets/devices', title: '装备资产', permission: 'assets:read', stage: 'A2—A4', description: '设备台账 → 发放回收 → 维修与退役' },
  { path: '/admin/people', title: '人员组织', permission: 'people:read', stage: 'A1', description: '人员档案、组织班组、厂站区域与当班名册' },
  { path: '/admin/access/accounts', title: '权限协作', permission: 'access:read', stage: 'A1 / A5', description: '登录账号、角色范围、协助组与通知范围' },
  { path: '/admin/integrations', title: '接入配置', permission: 'integrations:read', stage: 'A6', description: '本地配置、映射预览和尝试记录，不访问外部系统' },
  { path: '/admin/audit', title: '审计记录', permission: 'audit:read', stage: 'A6', description: '操作者、业务对象、脱敏差异与处理结果' }
]
export const METRICS = [
  { key: 'assets', label: '资产总数', note: '当前厂站 · 授权设备' },
  { key: 'available', label: '可领设备', note: '库存且明确未领用 · 离线不剔除' },
  { key: 'assigned', label: '有效领用设备', note: '一台设备只计一次 · 排除冲突' },
  { key: 'maintenance', label: '活动维修单', note: '未关闭工单 · 非设备在线数' },
  { key: 'unknown', label: '关系未知', note: '需要核实，不解释为未领用' },
  { key: 'conflict', label: '关系冲突', note: '多条绑定或状态矛盾，不自动修复' }
]
export const WORKSPACES = [
  { path: '/admin/people', title: '人员档案', entity: 'people', group: 'people' },
  { path: '/admin/organization', title: '组织与区域', entity: 'organizations', group: 'people' },
  { path: '/admin/sites', title: '厂站资料', entity: 'sites', group: 'people' },
  { path: '/admin/duty', title: '班次名册', entity: 'dutyShifts', group: 'people' },
  { path: '/admin/access/accounts', title: '本地账号', entity: 'accounts', group: 'access' },
  { path: '/admin/access/roles', title: '基础角色', entity: 'roles', group: 'access' },
  { path: '/admin/access/groups', title: '常设协助组', entity: 'groups', group: 'access' }
]
export const menuPath = path => path.startsWith('/admin/assets/') ? '/admin/assets/devices' : path.startsWith('/admin/access/') ? '/admin/access/accounts' : /^\/admin\/(people|organization|sites|duty)(\/|$)/.test(path) ? '/admin/people' : path
const allowed = new Set([...MENU.map(m => m.path), ...WORKSPACES.map(m => m.path), '/admin/legacy', '/admin/assets/assignments', '/admin/assets/maintenance'])
export function cleanAssignmentQuery(query = {}) {
  const base = cleanQuery(query), result = Object.fromEntries(['siteId', 'selectedId', 'keyword', 'pageNum', 'pageSize'].filter(k => base[k] !== undefined).map(k => [k, base[k]]))
  if (['current', 'returns', 'history'].includes(query.tab)) result.tab = query.tab
  if (['HELMET', 'BELT', 'WATCH'].includes(query.type)) result.type = query.type
  for (const key of ['batchId', 'personId', 'deviceId']) if (typeof query[key] === 'string' && /^[\w-]{1,100}$/.test(query[key])) result[key] = query[key]
  return result
}
export function assignmentReturn(value) { const target = safeTarget(value); return target.split('?')[0] === '/admin/assets/assignments' ? target : '/admin/assets/assignments' }
export function cleanMaintenanceQuery(query = {}) {
  const result = cleanDeviceQuery(query)
  if (['devices', 'orders', 'history'].includes(query.tab)) result.tab = query.tab
  if (['OPEN', 'CLOSED'].includes(query.status)) result.status = query.status
  if (['UNASSIGNED', 'WAITING', 'PROCESSING', 'CLOSED'].includes(query.phase)) result.phase = query.phase
  if (query.mine === 'true') result.mine = 'true'
  if (['SEND_REPAIR', 'REPAIRED', 'DISABLED', 'RESTORED', 'SCRAPPED'].includes(query.action)) result.action = query.action
  if (typeof query.deviceId === 'string' && /^[\w-]{1,100}$/.test(query.deviceId)) result.deviceId = query.deviceId
  return result
}
export function maintenanceReturn(value) { const target = safeTarget(value); return ['/admin/assets/maintenance', '/admin/assets/assignments'].includes(target.split('?')[0]) ? target : '/admin/assets/maintenance' }
export function recordReturn(value, fallback) {
  if (typeof value !== 'string' || ![fallback, '/admin/assets/assignments', '/admin/assets/maintenance'].includes(value.split('?')[0])) return fallback
  const target = safeTarget(value)
  return [fallback, '/admin/assets/assignments', '/admin/assets/maintenance'].includes(target.split('?')[0]) ? target : fallback
}
export function cleanDeviceQuery(query = {}) {
  const common = cleanQuery(query), result = Object.fromEntries(['siteId', 'areaId', 'selectedId', 'keyword', 'pageNum', 'pageSize'].filter(k => common[k] !== undefined).map(k => [k, common[k]]))
  const enums = { type: ['HELMET', 'BELT', 'WATCH'], lifecycle: ['STOCK', 'IN_USE', 'MAINTENANCE', 'DISABLED', 'SCRAPPED'], relation: ['ASSIGNED', 'UNASSIGNED', 'UNKNOWN', 'CONFLICT'], communication: ['NOT_CONNECTED', 'ONLINE', 'OFFLINE', 'UNKNOWN'] }
  for (const [key, values] of Object.entries(enums)) if (values.includes(query[key])) result[key] = query[key]
  return result
}
export function cleanQuery(query = {}) {
  const result = {}
  for (const key of ['siteId', 'organizationId', 'areaId', 'selectedId']) if (typeof query[key] === 'string' && /^[\w-]{1,100}$/.test(query[key])) result[key] = query[key]
  if (typeof query.keyword === 'string') result.keyword = query.keyword.slice(0, 100)
  if (['enabled', 'disabled'].includes(query.status)) result.status = query.status
  if (['organizations', 'areas'].includes(query.tree)) result.tree = query.tree
  for (const key of ['pageNum', 'pageSize']) if (/^[1-9]\d*$/.test(String(query[key])) && Number(query[key]) <= (key === 'pageSize' ? 100 : 100000)) result[key] = String(query[key])
  return result
}
export function safeTarget(value) {
  if (typeof value !== 'string' || !value.startsWith('/admin/') || /[\\\s#]/.test(value)) return '/admin/overview'
  try {
    const url = new URL(value, 'http://admin.local')
    if (url.origin !== 'http://admin.local' || (!allowed.has(url.pathname) && !/^\/admin\/access\/groups\/[\w-]{1,100}$/.test(url.pathname) && !/^\/admin\/people\/[\w-]{1,100}$/.test(url.pathname) && !/^\/admin\/assets\/(devices|maintenance)\/[\w-]{1,100}$/.test(url.pathname))) return '/admin/overview'
    const raw = Object.fromEntries(url.searchParams)
    const cleaned = url.pathname === '/admin/assets/assignments' ? cleanAssignmentQuery(raw) : url.pathname.startsWith('/admin/assets/maintenance') ? cleanMaintenanceQuery(raw) : url.pathname.startsWith('/admin/assets/') ? cleanDeviceQuery(raw) : cleanQuery(raw)
    if (/^\/admin\/assets\/maintenance\/[\w-]{1,100}$/.test(url.pathname) && raw.returnTo) cleaned.returnTo = maintenanceReturn(raw.returnTo)
    if (/^\/admin\/assets\/devices\/[\w-]{1,100}$/.test(url.pathname) && raw.returnTo) cleaned.returnTo = recordReturn(raw.returnTo, '/admin/assets/devices')
    if (/^\/admin\/people\/[\w-]{1,100}$/.test(url.pathname) && raw.returnTo) cleaned.returnTo = recordReturn(raw.returnTo, '/admin/people')
    if (/^\/admin\/access\/groups\/[\w-]{1,100}$/.test(url.pathname) && raw.returnTo) cleaned.returnTo = recordReturn(raw.returnTo, '/admin/access/groups')
    const search = new URLSearchParams(cleaned).toString()
    return url.pathname + (search ? '?' + search : '')
  } catch { return '/admin/overview' }
}
export function peopleReturn(value) { const target = safeTarget(value); return target.split('?')[0] === '/admin/people' ? target : '/admin/people' }
export function deviceReturn(value) {
  if (typeof value !== 'string' || /[\\\s#]/.test(value) || !value.startsWith('/admin/assets/devices')) return '/admin/assets/devices'
  try { const url = new URL(value, 'http://admin.local'); if (url.origin !== 'http://admin.local' || url.pathname !== '/admin/assets/devices') return '/admin/assets/devices'; const q = new URLSearchParams(cleanDeviceQuery(Object.fromEntries(url.searchParams))).toString(); return url.pathname + (q ? '?' + q : '') } catch { return '/admin/assets/devices' }
}
export function trustedPortal(value) {
  try {
    const url = new URL(value)
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) return null
    return url.href
  } catch { return null }
}
