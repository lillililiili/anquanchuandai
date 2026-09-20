import { can, system } from './access'
import { relationship } from './relations'

export const MAINTENANCE_QUERIES = ['maintenanceOrders', 'maintenanceOrder', 'maintenanceRecords', 'deviceLifecycleHistory']
export const MAINTENANCE_COMMANDS = ['maintenance.create', 'maintenance.assign', 'maintenance.start', 'maintenance.inspect', 'devices.disable', 'devices.restore', 'devices.scrap', 'maintenance.scrap']
export const PHASES = { UNASSIGNED: '待指派', WAITING: '待处理', PROCESSING: '处理中', CLOSED: '已关闭' }
export const ACTIONS = { 'maintenance.create': '库存送修', 'maintenance.assign': '重新指派', 'maintenance.start': '接单开始', 'maintenance.inspect': '记录检测', 'devices.disable': '库存停用', 'devices.restore': '停用恢复', 'devices.scrap': '确认报废', 'maintenance.scrap': '无法修复并报废' }
export const RECORD_ACTIONS = { CREATED: '建立维修单', RETURN_REPAIR: '损坏归还转维修', ASSIGNED: '指派处理人', STARTED: '接单开始', FAILED: '检测未通过', PASSED: '检测通过', UNREPAIRABLE: '无法修复', SEND_REPAIR: '送修', REPAIRED: '维修通过回库存', DISABLED: '停用', RESTORED: '恢复库存', SCRAPPED: '报废' }
export const activeMaintenance = o => o.status === 'OPEN'
export const maintenancePhase = o => o.status === 'CLOSED' ? 'CLOSED' : o.phase || (o.handlerId ? 'WAITING' : 'UNASSIGNED')
export function maintenanceManager(state, actor, d) {
  if (!can(state, actor, 'assets:read', d)) return false
  if (system(actor)) return can(state, actor, 'assets:write', d)
  return state.roles.some(r => r.id === 'site' && r.builtin && r.enabled !== false) && can(state, { ...actor, roleIds: actor.roleIds.filter(id => id === 'site') }, 'assets:write', d)
}
function activeFor(state, d) { return state.maintenanceOrders.filter(o => o.deviceId === d.id && activeMaintenance(o)) }
export function maintenanceActionReason(state, actor, d, type, order) {
  if (!can(state, actor, 'assets:read', d) || !can(state, actor, 'assets:write', d)) return '需要本设备范围内资产办理权限'
  if (['maintenance.assign', 'devices.scrap', 'maintenance.scrap'].includes(type) && !maintenanceManager(state, actor, d)) return '仅授权范围内的系统／厂站管理员可办理'
  if (['maintenance.start', 'maintenance.inspect'].includes(type) && order?.handlerId !== actor.id) return '仅指定处理人可办理；管理员需先重新指派给自己'
  if (d.lifecycle === 'SCRAPPED') return '报废档案只读，不支持恢复或再次办理'
  if (relationship(state, d).state !== 'UNASSIGNED' || state.assignments.some(a => a.deviceId === d.id && a.active)) return '必须明确未领用且无有效关系；使用中先归还，未知或冲突需核实'
  const active = activeFor(state, d)
  if (type.startsWith('maintenance.') && type !== 'maintenance.create') {
    if (!order || !activeMaintenance(order)) return '工单不存在或已关闭'
    if (d.lifecycle !== 'MAINTENANCE' || active.length !== 1 || active[0].id !== order.id || order.siteId !== d.siteId) return '设备与活动工单状态不一致，需核实'
    if (type === 'maintenance.start' && maintenancePhase(order) !== 'WAITING') return '仅待处理工单可接单'
    if (type === 'maintenance.inspect' && maintenancePhase(order) !== 'PROCESSING') return '请先接单开始维修，再记录检测结果'
  } else {
    if (active.length) return '存在活动维修单，不能直接办理此操作'
    const allowed = type === 'devices.restore' ? ['DISABLED'] : type === 'devices.scrap' ? ['STOCK', 'DISABLED'] : ['STOCK']
    if (!allowed.includes(d.lifecycle)) return '当前生命周期不允许此操作'
  }
  return ''
}
export function deviceMaintenanceActions(state, actor, d) {
  return Object.fromEntries(['maintenance.create', 'devices.disable', 'devices.restore', 'devices.scrap'].map(type => [type, maintenanceActionReason(state, actor, d, type)]))
}
function getDevice(state, actor, input, fail) {
  const d = state.devices.find(d => d.id === input.deviceId && d.siteId === input.siteId)
  if (!d || !can(state, actor, 'assets:read', d)) throw fail(404, 'OBJECT_NOT_FOUND', '设备不存在或不可见')
  return d
}
function getOrder(state, actor, input, fail) {
  const o = state.maintenanceOrders.find(o => o.id === input.id && o.siteId === input.siteId)
  if (!o) throw fail(404, 'OBJECT_NOT_FOUND', '维修单不存在或不可见')
  return { order: o, device: getDevice(state, actor, { ...input, deviceId: o.deviceId }, fail) }
}
function projectOrder(state, actor, o, d) {
  const h = state.accounts.find(a => a.id === o.handlerId), manager = maintenanceManager(state, actor, d)
  return { ...o, phase: maintenancePhase(o), deviceCode: d.code, deviceName: d.name, deviceType: d.type, deviceVersion: d.version, deviceLifecycle: d.lifecycle, handlerName: o.handlerName || null, currentHandlerName: h?.name || null, handlerValid: Boolean(h?.enabled && can(state, h, 'assets:write', d)), manager, actions: Object.fromEntries(['maintenance.assign', 'maintenance.start', 'maintenance.inspect', 'maintenance.scrap'].map(t => [t, maintenanceActionReason(state, actor, d, t, o)])) }
}
export function queryMaintenance(state, actor, kind, input, { fail, page }) {
  if (input.deviceId) getDevice(state, actor, input, fail)
  if (kind === 'maintenanceOrder') { const { order, device } = getOrder(state, actor, input, fail); return projectOrder(state, actor, order, device) }
  if (kind === 'maintenanceOrders') {
    if (input.status && !['OPEN', 'CLOSED'].includes(input.status) || input.phase && !Object.hasOwn(PHASES, input.phase) || input.mine != null && typeof input.mine !== 'boolean') throw fail(400, 'INVALID_FILTER', '工单筛选无效')
    let rows = state.maintenanceOrders.filter(o => o.siteId === input.siteId && (!input.deviceId || o.deviceId === input.deviceId)).flatMap(o => {
      const d = state.devices.find(d => d.id === o.deviceId && d.siteId === input.siteId)
      return d && can(state, actor, 'assets:read', d) ? [projectOrder(state, actor, o, d)] : []
    }).filter(o => (!input.status || o.status === input.status) && (!input.phase || maintenancePhase(o) === input.phase) && (!input.mine || o.handlerId === actor.id)).reverse()
    rows = rows.map(o => ({ ...o, code: `${o.id} ${o.deviceCode}`, name: o.deviceName }))
    return { availability: 'AVAILABLE', ...page(rows, input) }
  }
  if (kind === 'maintenanceRecords') getOrder(state, actor, input, fail)
  if (input.action && !Object.hasOwn(RECORD_ACTIONS, input.action)) throw fail(400, 'INVALID_FILTER', '记录动作无效')
  const records = kind === 'maintenanceRecords' ? state.maintenanceRecords || [] : state.lifecycleHistory || []
  const rows = records.filter(r => r.siteId === input.siteId && (kind !== 'maintenanceRecords' || r.orderId === input.id) && (!input.deviceId || r.deviceId === input.deviceId) && (!input.action || r.action === input.action)).filter(r => {
    const d = state.devices.find(d => d.id === r.deviceId)
    return d && can(state, actor, 'assets:read', d) && can(state, actor, 'assets:read', r)
  }).slice().reverse().map(r => ({ ...r, code: r.deviceCode, name: r.deviceName }))
  return { availability: 'AVAILABLE', ...page(rows, input) }
}
export function authorizeMaintenance(state, actor, type, input, fail) {
  const result = type.startsWith('maintenance.') && type !== 'maintenance.create' ? getOrder(state, actor, input, fail) : { device: getDevice(state, actor, input, fail), order: null }
  const d = result.device
  if (input.deviceId && input.deviceId !== d.id) throw fail(404, 'OBJECT_NOT_FOUND', '设备与工单不匹配')
  if (!can(state, actor, 'assets:write', d)) throw fail(403, 'PERMISSION_DENIED', '没有本设备资产办理权限')
  if (['maintenance.assign', 'devices.scrap', 'maintenance.scrap'].includes(type) && !maintenanceManager(state, actor, d)) throw fail(403, 'ADMIN_REQUIRED', '仅授权范围内系统／厂站管理员可办理')
  if (['maintenance.start', 'maintenance.inspect'].includes(type) && result.order.handlerId !== actor.id) throw fail(403, 'HANDLER_REQUIRED', '仅当前指定处理人可办理')
  return result
}
function append(state, key, d, actor, now, fields) {
  state[key] ||= []
  const record = { id: `${key}-${state.nextId++}`, siteId: d.siteId, areaId: d.areaId, deviceId: d.id, deviceCode: d.code, deviceName: d.name, type: d.type, actorId: actor.id, actorName: actor.name, occurredAt: now, source: '前端内存本地', ...fields }
  state[key].push(record); return record
}
export function recordRepairCreation(state, order, d, actor, now, fromReturn = false) {
  order.phase = order.handlerId ? 'WAITING' : 'UNASSIGNED'
  append(state, 'maintenanceRecords', d, actor, now, { orderId: order.id, action: fromReturn ? 'RETURN_REPAIR' : 'CREATED', description: order.reason, handlerName: order.handlerName, batchId: order.batchId || null })
  append(state, 'lifecycleHistory', d, actor, now, { orderId: order.id, action: 'SEND_REPAIR', from: fromReturn ? 'IN_USE' : 'STOCK', to: 'MAINTENANCE', description: order.reason, handlerName: order.handlerName, batchId: order.batchId || null })
}
export function applyMaintenance(state, actor, type, input, { fail, now }) {
  const { device: d, order: o } = authorizeMaintenance(state, actor, type, input, fail)
  const field = (key, message, code = 400) => { throw Object.assign(fail(code, code === 409 ? 'MAINTENANCE_CONFLICT' : 'VALIDATION_ERROR', message), { fields: { [key]: message } }) }
  const keys = ['siteId', 'operationId', 'deviceId', 'deviceVersion', 'id', 'orderVersion', 'reason', 'handlerId', 'handlerVersion', 'repairContent', 'inspection', 'result', 'acknowledged', 'codeConfirmation', 'secondConfirmed']
  if (Object.keys(input).some(k => !keys.includes(k))) field('reason', '不允许指定状态、时间或经办人')
  if (input.deviceVersion !== d.version || o && input.orderVersion !== o.version) throw fail(409, 'VERSION_CONFLICT', '设备或工单已变化，请重新读取')
  const reason = maintenanceActionReason(state, actor, d, type, o)
  if (reason) field('reason', reason, 409)
  const text = key => { if (typeof input[key] !== 'string' || !input[key].trim() || input[key].trim().length > 1000) field(key, '请填写' + ({ reason: '原因', repairContent: '维修内容', inspection: '检查／检测说明' }[key] || key) + '（最多1000字）'); return input[key].trim() }
  const confirmed = () => { if (input.acknowledged !== true) field('acknowledged', '请确认仅为本地验收，不代表真实设备安全认证') }
  const handler = () => { const h = state.accounts.find(a => a.id === input.handlerId && a.enabled && can(state, a, 'assets:write', d)); if (!h) field('handlerId', '请选择仍有本设备资产办理权限的启用账号', 409); if (h.version !== input.handlerVersion) throw fail(409, 'VERSION_CONFLICT', '处理人账号已变化，请重新读取'); return h }
  const previousState = d.lifecycle
  let order = o, lifeAction = null, description = '', inspection = null
  if (['devices.scrap', 'maintenance.scrap'].includes(type)) {
    description = text('reason')
    if (typeof input.codeConfirmation !== 'string' || input.codeConfirmation.trim() !== d.code) field('codeConfirmation', '请完整复输当前设备编号，大小写必须一致')
    if (input.secondConfirmed !== true) field('secondConfirmed', '请完成报废二次确认')
    if (type === 'maintenance.scrap') inspection = text('inspection')
    d.lifecycle = 'SCRAPPED'; lifeAction = 'SCRAPPED'
    if (o) { o.status = 'CLOSED'; o.phase = 'CLOSED'; o.outcome = 'UNREPAIRABLE_SCRAPPED'; o.closedAt = now; append(state, 'maintenanceRecords', d, actor, now, { orderId: o.id, action: 'UNREPAIRABLE', description, inspection, handlerName: o.handlerName || null }) }
  } else if (type === 'maintenance.create') {
    description = text('reason'); const h = handler()
    order = { id: `repair-${state.nextId++}`, siteId: d.siteId, areaId: d.areaId, deviceId: d.id, status: 'OPEN', phase: 'WAITING', reason: description, handlerId: h.id, handlerName: h.name, version: 1, createdAt: now, source: 'MOCK_STOCK', batchId: null }
    d.lifecycle = 'MAINTENANCE'; state.maintenanceOrders.push(order); recordRepairCreation(state, order, d, actor, now)
  } else if (type === 'maintenance.assign') {
    description = text('reason'); const h = handler(), oldHandlerName = o.handlerName || null
    o.handlerId = h.id; o.handlerName = h.name; o.phase = 'WAITING'
    append(state, 'maintenanceRecords', d, actor, now, { orderId: o.id, action: 'ASSIGNED', description, oldHandlerName, handlerName: h.name })
  } else if (type === 'maintenance.start') {
    o.phase = 'PROCESSING'; append(state, 'maintenanceRecords', d, actor, now, { orderId: o.id, action: 'STARTED', handlerName: actor.name })
  } else if (type === 'maintenance.inspect') {
    const repairContent = text('repairContent'); inspection = text('inspection')
    if (!['PASS', 'FAIL'].includes(input.result)) field('result', '请选择检测通过或未通过')
    if (input.result === 'PASS') { confirmed(); o.status = 'CLOSED'; o.phase = 'CLOSED'; o.outcome = 'REPAIRED'; o.closedAt = now; d.lifecycle = 'STOCK'; lifeAction = 'REPAIRED' }
    append(state, 'maintenanceRecords', d, actor, now, { orderId: o.id, action: input.result === 'PASS' ? 'PASSED' : 'FAILED', repairContent, inspection, handlerName: actor.name })
  } else if (type === 'devices.disable') { description = text('reason'); d.lifecycle = 'DISABLED'; lifeAction = 'DISABLED' }
  else if (type === 'devices.restore') { description = text('reason'); inspection = text('inspection'); confirmed(); d.lifecycle = 'STOCK'; lifeAction = 'RESTORED' }
  if (lifeAction) append(state, 'lifecycleHistory', d, actor, now, { orderId: order?.id || null, action: lifeAction, from: previousState, to: d.lifecycle, description, inspection, handlerName: order?.handlerName || null })
  if (o) o.version++
  d.version++
  return { deviceId: d.id, orderId: order?.id || null, lifecycle: d.lifecycle, phase: order ? maintenancePhase(order) : null, deviceVersion: d.version, orderVersion: order?.version || null }
}
