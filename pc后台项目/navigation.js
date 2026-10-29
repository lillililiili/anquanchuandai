export const DEFAULT_ADMIN_PATH = '/devices'
// Old bookmarks are normalized to the same short paths used by menus and return links.
const legacyPaths = {
  '/admin/assets/devices': '/devices', '/admin/assets/assignments': '/assignments', '/admin/assets/maintenance': '/maintenance',
  '/admin/access/accounts': '/accounts', '/admin/access/roles': '/roles', '/admin/access/groups': '/groups',
  '/admin/people': '/people', '/admin/sites': '/sites', '/admin/duty': '/duty',
  '/admin/audit': '/audit', '/admin/login': '/login', '/admin/401': '/401', '/admin/overview': '/overview', '/admin/integrations': '/integrations'
}
const isLegacyOrganizationPath = path => /^\/(?:admin\/)?organization\/?$/.test(path)
export function canonicalAdminPath(path) {
  if (isLegacyOrganizationPath(path)) return '/people'
  for (const [legacy, current] of Object.entries(legacyPaths)) {
    if (path === legacy || path.startsWith(legacy + '/')) return current + path.slice(legacy.length)
  }
  return path
}
const isRetiredAdminPath = path => /^\/(overview|integrations|maintenance|groups)(?:\/|$)/.test(path)
function parseAdminTarget(value) {
  if (typeof value !== 'string' || !value.startsWith('/') || value.startsWith('//') || /[\\\s#]/.test(value)) return null
  try {
    const url = new URL(value, 'http://admin.local')
    if (url.origin !== 'http://admin.local') return null
    if (isLegacyOrganizationPath(url.pathname)) {
      const legacyQuery = cleanQuery(Object.fromEntries(url.searchParams)), query = {}
      if (legacyQuery.siteId) query.siteId = legacyQuery.siteId
      if (legacyQuery.organizationId || legacyQuery.selectedId) query.organizationId = legacyQuery.organizationId || legacyQuery.selectedId
      url.search = new URLSearchParams(query).toString()
    }
    url.pathname = canonicalAdminPath(url.pathname)
    return url
  } catch { return null }
}
export function adminHome(query = {}) {
  const siteId = cleanQuery(query).siteId
  return DEFAULT_ADMIN_PATH + (siteId ? '?siteId=' + encodeURIComponent(siteId) : '')
}

export const MENU = [
  { path: '/devices', title: '装备资产', permission: 'assets:read', description: '设备台账、领用与归还' },
  { path: '/people', title: '人员组织', permission: 'people:read', description: '人员档案、组织班组、厂站资料与当班名册' },
  { path: '/accounts', title: '权限协作', permission: 'access:read', description: '登录账号与角色范围' },
  { path: '/audit', title: '操作日志', permission: 'audit:read', description: '查看谁在何时修改了什么，以及处理结果' },
]
export const WORKSPACES = [
  { path: '/people', title: '人员与组织', entity: 'people', group: 'people' },
  { path: '/sites', title: '厂站资料', entity: 'sites', group: 'people' },
  { path: '/duty', title: '班次名册', entity: 'dutyShifts', group: 'people' },
  { path: '/accounts', title: '用户账号', entity: 'accounts', group: 'access' },
  { path: '/roles', title: '基础角色', entity: 'roles', group: 'access' }
]
export function menuPath(value) {
  const path = canonicalAdminPath(value)
  if (isRetiredAdminPath(path) || /^\/(devices|assignments)(?:\/|$)/.test(path)) return DEFAULT_ADMIN_PATH
  if (/^\/(accounts|roles)(?:\/|$)/.test(path)) return '/accounts'
  if (/^\/(people|organization|sites|duty)(?:\/|$)/.test(path)) return '/people'
  return path
}
const allowed = new Set([...MENU.map(m => m.path), ...WORKSPACES.map(m => m.path), '/assignments', '/401'])
export function cleanAssignmentQuery(query = {}) {
  const base = cleanQuery(query), result = Object.fromEntries(['siteId', 'selectedId', 'keyword', 'pageNum', 'pageSize'].filter(k => base[k] !== undefined).map(k => [k, base[k]]))
  if (['current', 'returns', 'history'].includes(query.tab)) result.tab = query.tab
  if (['HELMET', 'BELT', 'WATCH'].includes(query.type)) result.type = query.type
  for (const key of ['batchId', 'personId', 'deviceId']) if (typeof query[key] === 'string' && /^[\w-]{1,100}$/.test(query[key])) result[key] = query[key]
  return result
}
export function assignmentReturn(value) { const target = safeTarget(value); return target.split('?')[0] === '/assignments' ? target : '/assignments' }
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
export function maintenanceReturn(value) { const target = safeTarget(value); return ['/maintenance', '/assignments'].includes(target.split('?')[0]) ? target : '/maintenance' }
export function recordReturn(value, fallback) {
  fallback = canonicalAdminPath(fallback)
  const paths = [fallback, '/assignments', '/maintenance'], url = parseAdminTarget(value)
  if (!url || !paths.includes(url.pathname)) return fallback
  const target = safeTarget(value)
  return paths.includes(target.split('?')[0]) ? target : fallback
}
export function cleanDeviceQuery(query = {}) {
  const common = cleanQuery(query), result = Object.fromEntries(['siteId', 'selectedId', 'keyword', 'pageNum', 'pageSize'].filter(k => common[k] !== undefined).map(k => [k, common[k]]))
  const enums = { type: ['HELMET', 'BELT', 'WATCH'], relation: ['ASSIGNED', 'UNASSIGNED', 'UNKNOWN', 'CONFLICT'], communication: ['NOT_CONNECTED', 'ONLINE', 'OFFLINE', 'UNKNOWN'] }
  for (const [key, values] of Object.entries(enums)) if (values.includes(query[key])) result[key] = query[key]
  if(query.source === 'PLATFORM') result.source = 'PLATFORM'
  return result
}
export function cleanQuery(query = {}) {
  const result = {}
  for (const key of ['siteId', 'organizationId', 'selectedId']) if (typeof query[key] === 'string' && /^[\w-]{1,100}$/.test(query[key])) result[key] = query[key]
  if (typeof query.keyword === 'string') result.keyword = query.keyword.slice(0, 100)
  if (['enabled', 'disabled'].includes(query.status)) result.status = query.status
  if (['ON_DUTY', 'OFF_DUTY', 'UNKNOWN'].includes(query.dutyStatus)) result.dutyStatus = query.dutyStatus
  for (const key of ['pageNum', 'pageSize']) if (/^[1-9]\d*$/.test(String(query[key])) && Number(query[key]) <= (key === 'pageSize' ? 100 : 100000)) result[key] = String(query[key])
  return result
}
export function safeTarget(value) {
  const url = parseAdminTarget(value)
  if (!url) return DEFAULT_ADMIN_PATH
  const path = url.pathname, raw = Object.fromEntries(url.searchParams)
  if (isRetiredAdminPath(path)) return adminHome(raw)
  if (!allowed.has(path) && !/^\/(people|devices)\/[\w-]{1,100}$/.test(path)) return DEFAULT_ADMIN_PATH
  const cleaned = path === '/assignments' ? cleanAssignmentQuery(raw) : /^\/devices(?:\/|$)/.test(path) ? cleanDeviceQuery(raw) : cleanQuery(raw)
  if (!/^\/people(?:\/|$)/.test(path)) delete cleaned.dutyStatus
  if (/^\/devices\/[\w-]{1,100}$/.test(path) && raw.returnTo) cleaned.returnTo = recordReturn(raw.returnTo, '/devices')
  if (/^\/people\/[\w-]{1,100}$/.test(path) && raw.returnTo) cleaned.returnTo = recordReturn(raw.returnTo, '/people')
  const search = new URLSearchParams(cleaned).toString()
  return path + (search ? '?' + search : '')
}
export function peopleReturn(value) { const target = safeTarget(value); return target.split('?')[0] === '/people' ? target : '/people' }
export function deviceReturn(value) {
  const url = parseAdminTarget(value)
  if (!url || url.pathname !== DEFAULT_ADMIN_PATH) return DEFAULT_ADMIN_PATH
  const query = new URLSearchParams(cleanDeviceQuery(Object.fromEntries(url.searchParams))).toString()
  return DEFAULT_ADMIN_PATH + (query ? '?' + query : '')
}
export function trustedPortal(value) {
  try {
    const url = new URL(value)
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) return null
    return url.href
  } catch { return null }
}
