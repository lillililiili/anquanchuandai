export const MENU = [
  { path: '/admin/overview', title: '管理工作台', permission: 'overview:read', description: '设备概况、待核实的领用记录和最近操作' },
  { path: '/admin/assets/devices', title: '装备资产', permission: 'assets:read', description: '设备台账 → 发放回收 → 维修与退役' },
  { path: '/admin/people', title: '人员组织', permission: 'people:read', description: '人员档案、组织班组、厂站区域与当班名册' },
  { path: '/admin/access/accounts', title: '权限协作', permission: 'access:read', description: '登录账号、角色范围、协助组与通知范围' },
  { path: '/admin/integrations', title: '接入配置', permission: 'integrations:read', description: '连接设置、数据对应关系和测试记录（演示）' },
  { path: '/admin/audit', title: '审计记录', permission: 'audit:read', description: '查看谁在何时修改了什么，以及处理结果' }
]
export const METRICS = [
  { key: 'assets', label: '资产总数', note: '当前厂站内您有权查看的设备' },
  { key: 'available', label: '可领设备', note: '库存中尚未领用的设备，含离线设备' },
  { key: 'assigned', label: '已领用设备', note: '每台设备计一次，不含领用记录有矛盾的设备' },
  { key: 'maintenance', label: '未完成维修单', note: '尚未完成的维修单数量' },
  { key: 'unknown', label: '领用情况不明', note: '领用信息不完整，请核实领用人' },
  { key: 'conflict', label: '领用记录有矛盾', note: '领用人或设备状态不一致，请人工核实' }
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
export const menuPath = path => path.startsWith('/admin/integrations/') ? '/admin/integrations' : path.startsWith('/admin/assets/') ? '/admin/assets/devices' : path.startsWith('/admin/access/') ? '/admin/access/accounts' : /^\/admin\/(people|organization|sites|duty)(\/|$)/.test(path) ? '/admin/people' : path
const allowed = new Set([...MENU.map(m => m.path), ...WORKSPACES.map(m => m.path), '/admin/legacy', '/admin/assets/assignments', '/admin/assets/maintenance', '/admin/integrations/settings'])
export function cleanIntegrationQuery(query = {}) {
  const base = cleanQuery(query)
  const result = Object.fromEntries(['siteId', 'keyword', 'pageNum', 'pageSize'].filter(k => base[k] !== undefined).map(k => [k, base[k]]))
  if (['connectors', 'jobs'].includes(query.tab)) result.tab = query.tab
  if (['PREVIEW', 'CONFLICT', 'FAILED', 'COMPLETED'].includes(query.status)) result.status = query.status
  if (typeof query.connectorId === 'string' && /^[\w-]{1,100}$/.test(query.connectorId)) result.connectorId = query.connectorId
  return result
}
export function integrationReturn(value) {
  const target = safeTarget(value)
  return target.split('?')[0] === '/admin/integrations' ? target : '/admin/integrations'
}
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
    if (url.origin !== 'http://admin.local' || (!allowed.has(url.pathname) && !/^\/admin\/integrations\/(?:jobs\/)?[\w-]{1,100}$/.test(url.pathname) && !/^\/admin\/access\/groups\/[\w-]{1,100}$/.test(url.pathname) && !/^\/admin\/people\/[\w-]{1,100}$/.test(url.pathname) && !/^\/admin\/assets\/(devices|maintenance)\/[\w-]{1,100}$/.test(url.pathname))) return '/admin/overview'
    const raw = Object.fromEntries(url.searchParams)
    const cleaned = url.pathname.startsWith('/admin/integrations') ? cleanIntegrationQuery(raw) : url.pathname === '/admin/assets/assignments' ? cleanAssignmentQuery(raw) : url.pathname.startsWith('/admin/assets/maintenance') ? cleanMaintenanceQuery(raw) : url.pathname.startsWith('/admin/assets/') ? cleanDeviceQuery(raw) : cleanQuery(raw)
    if (url.pathname.startsWith('/admin/integrations/') && raw.returnTo) cleaned.returnTo = integrationReturn(raw.returnTo)
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
