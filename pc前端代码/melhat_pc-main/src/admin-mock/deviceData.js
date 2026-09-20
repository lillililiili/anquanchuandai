import { can } from './access'
import { historyRows } from './assignmentData'
import { activeMaintenance, deviceMaintenanceActions } from './maintenanceData'

export const DEVICE_TYPES = { HELMET: '安全帽', BELT: '安全带', WATCH: '手表' }
export const DEVICE_FILTERS = {
  type: DEVICE_TYPES,
  lifecycle: { STOCK: '库存', IN_USE: '使用中', MAINTENANCE: '维修中', DISABLED: '停用', SCRAPPED: '报废' },
  relation: { UNASSIGNED: '未领用', ASSIGNED: '已领用', UNKNOWN: '关系未知', CONFLICT: '关系冲突' },
  communication: { NOT_CONNECTED: '未接入', ONLINE: '在线（本地）', OFFLINE: '离线（本地）', UNKNOWN: '通信未知' }
}
export const ASSEMBLY = { INSTALLED: '已装配（本地配置）', ABSENT: '未装配', UNKNOWN: '待确认' }
export const MODELS = [
  { id: 'demo-helmet-basic', type: 'HELMET', name: '预置安全帽 · 基础型', declaration: '预置型号声明，非厂家确认规格', options: [{ id: 'camera', name: '影像模块（本地选配）' }] },
  { id: 'demo-helmet-plus', type: 'HELMET', name: '预置安全帽 · 扩展型', declaration: '预置型号声明，非厂家确认规格', options: [{ id: 'camera', name: '影像模块（本地选配）' }, { id: 'position', name: '定位模块（本地选配）' }] },
  { id: 'demo-belt', type: 'BELT', name: '预置安全带 · 需求模板', declaration: '需求说明，不代表锁止、受力或定位能力已实现；厂家协议待确认', options: [] },
  { id: 'demo-watch', type: 'WATCH', name: '预置手表 · 待确认模板', declaration: '仅公共档案结构，厂家协议及生命体征能力待确认', options: [] },
  ...Object.entries(DEVICE_TYPES).map(([type, name]) => ({ id: `unknown-${type}`, type, name: `${name} · 型号待确认`, declaration: '无可靠型号声明，不能任意添加能力', options: [] }))
]
export const DEVICE_QUERIES = ['devices', 'device', 'deviceOptions', 'deviceHistory', 'deviceChanges']
export function extendDevices(state) {
  state.devices.forEach((d, i) => Object.assign(d, { manufacturer: '预置厂商（非真实厂家）', sn: `EQ-SN-${d.code}`, modelId: d.type === 'HELMET' ? (i % 2 ? 'demo-helmet-plus' : 'demo-helmet-basic') : `demo-${d.type.toLowerCase()}`, assetCode: '', purchasedOn: '', remark: '', assemblies: {}, connection: 'NOT_CONNECTED', verification: 'UNCONFIRMED', capabilitySource: '预置模板，非真机证据' }))
  state.devices.forEach(d => { d.assemblies = Object.fromEntries(MODELS.find(m => m.id === d.modelId).options.map(o => [o.id, 'UNKNOWN'])) })
  return state
}
export function keyEditReason(state, device, relationship) {
  if (device.lifecycle !== 'STOCK') return '仅库存设备可修改关键身份和选配'
  if (relationship(state, device).state !== 'UNASSIGNED' || state.assignments.some(a => a.active && a.deviceId === device.id)) return '领用关系未知、冲突或存在有效关系，请先核实'
  if (state.maintenanceOrders.some(o => o.deviceId === device.id && activeMaintenance(o))) return '存在活动维修单，请先处理'
  return ''
}
function projection(state, actor, d, relationship) {
  const r = relationship(state, d), model = MODELS.find(m => m.id === d.modelId)
  const person = r.person && can(state, actor, 'people:read', r.person) ? { id: r.person.id, name: r.person.name } : null
  return { ...d, maintenanceActions: deviceMaintenanceActions(state, actor, d), activeOrderIds: state.maintenanceOrders.filter(o => o.deviceId === d.id && activeMaintenance(o)).map(o => o.id), relation: r.state, person, personName: person?.name || null, startedAt: r.assignment?.startedAt || null, assignmentSource: r.assignment?.source || 'INITIAL_SNAPSHOT', modelName: model?.name || '型号待确认', declaration: model?.declaration || '待确认', areaName: state.areas.find(a => a.id === d.areaId)?.name || '未分配区域', identityComplete: Boolean(d.manufacturer && d.sn), keyEditReason: keyEditReason(state, d, relationship), writable: d.lifecycle !== 'SCRAPPED' && can(state, actor, 'assets:write', d) }
}
export function queryDevices(state, actor, kind, input, { fail, page, relationship }) {
  const visible = state.devices.filter(d => d.siteId === input.siteId && can(state, actor, 'assets:read', d))
  if (kind === 'deviceOptions') return { availability: 'AVAILABLE', models: MODELS, areas: state.areas.filter(a => a.siteId === input.siteId && a.enabled && can(state, actor, 'assets:read', { siteId: a.siteId, areaId: a.id })), writableAreas: state.areas.filter(a => a.siteId === input.siteId && a.enabled && can(state, actor, 'assets:write', { siteId: a.siteId, areaId: a.id })) }
  if (kind === 'devices') {
    for (const [key, values] of Object.entries(DEVICE_FILTERS)) if (input[key] && !Object.hasOwn(values, input[key])) throw fail(400, 'INVALID_FILTER', '设备筛选参数无效')
    if (input.keyword != null && (typeof input.keyword !== 'string' || input.keyword.length > 100)) throw fail(400, 'INVALID_KEYWORD', '关键词最多100字')
    const keyword = (input.keyword || '').trim().toLowerCase()
    const rows = visible.map(d => projection(state, actor, d, relationship)).filter(d => Object.keys(DEVICE_FILTERS).every(k => !input[k] || input[k] === d[k]) && (!input.areaId || input.areaId === d.areaId) && `${d.code} ${d.sn || ''}`.toLowerCase().includes(keyword))
    return { availability: 'AVAILABLE', ...page(rows, { ...input, keyword: '' }) }
  }
  const d = visible.find(d => d.id === input.id)
  if (!d) throw fail(404, 'OBJECT_NOT_FOUND', '设备不存在或不可见')
  if (kind === 'device') return projection(state, actor, d, relationship)
  if (kind === 'deviceChanges') {
    if (!can(state, actor, 'audit:read', d)) throw fail(403, 'SECTION_DENIED', '没有资料变更审计权限')
    return { availability: 'AVAILABLE', ...page(state.audit.filter(a => a.objectId === d.id && a.siteId === d.siteId && can(state, actor, 'audit:read', a)).slice().reverse(), input) }
  }
  // Historical attribution is taken only from historical records; never from current bindings.
  const rows = historyRows(state, actor, { ...input, deviceId: d.id })
  return { availability: 'AVAILABLE', ...page(rows, input) }
}
export function authorizeDevice(state, actor, type, input, fail) {
  const action = type.split('.')[1]
  if (!['create', 'update', 'configure'].includes(action)) throw fail(400, 'COMMAND_NOT_AVAILABLE', '本阶段仅开放设备建档、资料编辑和型号配置')
  const row = action === 'create' ? null : state.devices.find(d => d.id === input.id && d.siteId === input.siteId && can(state, actor, 'assets:read', d))
  if (action !== 'create' && !row) throw fail(404, 'OBJECT_NOT_FOUND', '设备不存在或不可见')
  const target = { siteId: input.siteId, areaId: input.data?.areaId === undefined ? row?.areaId : input.data.areaId }
  if (!can(state, actor, 'assets:write', row || target) || !can(state, actor, 'assets:write', target)) throw fail(403, 'PERMISSION_DENIED', '当前身份无此设备或目标区域的维护权限')
  return { entity: 'devices', action, row }
}
export function applyDevice(state, actor, type, input, { fail, relationship }) {
  const { action, row } = authorizeDevice(state, actor, type, input, fail)
  const fieldError = (field, message, code = 400) => { throw Object.assign(fail(code, code === 409 ? 'DEVICE_CONFLICT' : 'VALIDATION_ERROR', message), { fields: { [field]: message } }) }
  const data = input.data
  if (!data || Array.isArray(data) || typeof data !== 'object') throw fail(400, 'INVALID_DATA', '请提交设备资料')
  const allowed = action === 'configure' ? ['modelId', 'assemblies', 'confirmModelChange'] : ['code', 'name', 'manufacturer', 'sn', 'areaId', 'modelId', 'assetCode', 'purchasedOn', 'remark', 'assemblies', 'confirmModelChange', ...(action === 'create' ? ['type'] : [])]
  if (Object.keys(data).some(k => !allowed.includes(k))) throw fail(400, 'FIELD_NOT_ALLOWED', '不能通过基础资料修改厂站、类型、生命周期、通信、领用或验证结果')
  if (row?.lifecycle === 'SCRAPPED') throw fail(409, 'DEVICE_READ_ONLY', '报废设备全档案只读')
  const result = row ? structuredClone(row) : { id: `device-${++state.nextId}`, siteId: input.siteId, type: data.type, version: 0, lifecycle: 'STOCK', relation: 'UNASSIGNED', communication: 'NOT_CONNECTED', freshness: 'UNKNOWN', sourceTime: null, connection: 'NOT_CONNECTED', verification: 'UNCONFIRMED', capability: 'UNCONFIRMED', capabilitySource: '前端本地配置，未验证真实设备', assemblies: {} }
  if (!Object.hasOwn(DEVICE_TYPES, result.type)) fieldError('type', '请选择设备类型')
  for (const key of ['code', 'name', 'manufacturer', 'sn', 'assetCode', 'purchasedOn', 'remark']) {
    const value = data[key] === undefined ? result[key] || '' : data[key]
    if (typeof value !== 'string' || value.trim().length > (key === 'remark' ? 500 : 100)) fieldError(key, '字段格式或长度无效')
    result[key] = value.trim()
  }
  if (!result.code) fieldError('code', '请填写平台编号')
  if (!result.name) fieldError('name', '请填写设备名称')
  if (result.purchasedOn && (!/^\d{4}-\d{2}-\d{2}$/.test(result.purchasedOn) || !Number.isFinite(Date.parse(result.purchasedOn)) || new Date(result.purchasedOn).toISOString().slice(0, 10) !== result.purchasedOn)) fieldError('purchasedOn', '请填写有效购置日期')
  result.areaId = data.areaId === undefined ? result.areaId || null : data.areaId || null
  if (result.areaId) {
    const area = state.areas.find(a => a.id === result.areaId && a.siteId === input.siteId && a.enabled)
    if (!area) fieldError('areaId', '请选择本厂站启用区域')
    if (input.relatedVersions?.[area.id] !== area.version) throw fail(409, 'VERSION_CONFLICT', '区域已变化，请重新读取')
  }
  const modelId = data.modelId || result.modelId || `unknown-${result.type}`
  const model = MODELS.find(m => m.id === modelId && m.type === result.type)
  if (!model) fieldError('modelId', '型号与设备类型不匹配')
  const changedModel = row && modelId !== row.modelId
  if (changedModel && data.confirmModelChange !== true) fieldError('modelId', '请确认型号变更及选配清理影响')
  result.modelId = modelId
  const assemblies = data.assemblies === undefined ? (changedModel ? {} : result.assemblies) : data.assemblies
  if (!assemblies || Array.isArray(assemblies) || typeof assemblies !== 'object' || Object.entries(assemblies).some(([key, value]) => !model.options.some(o => o.id === key) || !Object.hasOwn(ASSEMBLY, value))) fieldError('assemblies', '只能配置所选型号支持的装配状态')
  result.assemblies = Object.fromEntries(model.options.map(o => [o.id, assemblies[o.id] || 'UNKNOWN']))
  if (row && ['code', 'manufacturer', 'sn', 'areaId', 'modelId', 'assemblies'].some(k => JSON.stringify(row[k]) !== JSON.stringify(result[k]))) {
    const reason = keyEditReason(state, row, relationship)
    if (reason) throw fail(409, 'KEY_FIELDS_LOCKED', reason)
  }
  const lower = s => s.toLowerCase()
  if (state.devices.some(d => d.id !== result.id && lower(d.code) === lower(result.code))) fieldError('code', '平台编号已存在，请核对后修改', 409)
  if (result.manufacturer && result.sn && state.devices.some(d => d.id !== result.id && d.manufacturer && d.sn && lower(d.manufacturer) === lower(result.manufacturer) && lower(d.sn) === lower(result.sn))) fieldError('sn', '厂商与SN组合已存在，请核对后修改', 409)
  result.version++
  if (row) Object.assign(row, result); else state.devices.push(result)
  return result
}
