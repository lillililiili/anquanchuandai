// Presentation only: keep stored audit IDs, action codes and historical snapshots intact.
const ENTITIES = {
  devices: '设备', people: '人员', organizations: '组织', areas: '区域', sites: '厂站',
  dutyShifts: '班次', accounts: '账号', roles: '角色', groups: '群组',
  assignments: '设备', maintenance: '维修工单', integrations: '外部接口', integrationSettings: '接口设置'
}
const VERBS = { create: '新增', update: '修改', status: '变更状态：', delete: '删除' }

export const AUDIT_ACTIONS = Object.fromEntries([
  ...['people', 'organizations', 'areas', 'sites', 'dutyShifts'].flatMap(entity =>
    Object.entries(VERBS).map(([verb, label]) => [`${entity}.${verb}`, `${label}${ENTITIES[entity]}`])),
  ...['accounts', 'roles', 'groups'].flatMap(entity => ['create', 'update', 'status'].map(verb =>
    [`${entity}.${verb}`, `${VERBS[verb]}${ENTITIES[entity]}`])),
  ['accounts.delete', '删除账号'], ['roles.delete', '删除角色'],
  ['people.dutyStatus', '维护人员在岗状态'],
  ['devices.create', '新增设备'], ['devices.update', '修改设备'], ['devices.configure', '配置设备型号'],
  ['devices.platformSync', '同步厂家设备'], ['accounts.resetCredential', '重置账号密码'],
  ['assignments.issue', '发放设备'], ['assignments.return', '归还设备'],
  ['maintenance.create', '设备送修'], ['maintenance.assign', '指派维修人员'],
  ['maintenance.start', '开始维修'], ['maintenance.inspect', '记录维修检测'],
  ['maintenance.scrap', '维修后报废'], ['devices.disable', '停用设备'],
  ['devices.restore', '恢复设备使用'], ['devices.scrap', '报废设备'],
  ['integrations.update', '修改接口配置'], ['integrations.test', '测试接口连接'],
  ['integrations.preview', '预览接口同步'], ['integrations.confirm', '确认接口同步'],
  ['integrations.retry', '重试接口同步'], ['integrations.receipt', '接收接口回执'],
  ['integrations.create', '同步新增资料'], ['integrations.skip', '跳过同步资料'],
  ['integrationSettings.update', '修改接口设置']
])

export function auditActionLabel(action) {
  return AUDIT_ACTIONS[action] || '未识别操作'
}

export function auditHistoricalName(row) {
  return [row?.objectName, row?.after?.name, row?.before?.name].find(value =>
    typeof value === 'string' && value.trim())?.trim() || ''
}

export function auditObjectLabel(row, currentDevice) {
  const entity = String(row?.action || '').split('.')[0]
  const historicalName = auditHistoricalName(row)
  const device = entity === 'devices'
  const type = device ? row?.after?.type || row?.before?.type || currentDevice?.type : null
  const label = ({ HELMET: '安全帽', BELT: '安全带', WATCH: '手表' })[type] || ENTITIES[entity] || '业务对象'
  if (historicalName) return `${label}：${historicalName}`
  if (device && currentDevice?.id === row?.objectId && currentDevice?.name) return `${label}：${currentDevice.name}（当前名称）`
  if (row?.action === 'devices.platformSync') return '厂家设备台账'
  return `${label}（名称未记录）`
}

// Resolve only missing legacy device names through the existing permission-checked API.
// Never write today's name back into a historical audit record.
export async function loadAuditDeviceNames(rows, provider, siteId, signal) {
  const ids = [...new Set(rows.filter(row => row.action?.startsWith('devices.') &&
    row.action !== 'devices.platformSync' && row.objectId && !auditHistoricalName(row)).map(row => row.objectId))]
  const resolved = await Promise.all(ids.map(async id => {
    try {
      const response = await provider.query('device', { siteId, id }, { signal })
      const device = response.data
      return device?.id === id && device?.siteId === siteId ? [id, { id, name: device.name, type: device.type }] : null
    } catch { return null }
  }))
  return Object.fromEntries(resolved.filter(Boolean))
}
