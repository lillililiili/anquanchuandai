import { can } from './access'
import { relationship, personSlots, TYPES } from './relations'
import { activeMaintenance, recordRepairCreation } from './maintenanceData'
export const ASSIGNMENT_QUERIES = ['assignments', 'assignmentHistory', 'assignmentCandidates', 'repairAssignees', 'maintenanceSummary']
export const SLOT_NAMES = { UNASSIGNED: '未领用', ASSIGNED: '已领用', UNKNOWN: '领用情况不明', CONFLICT: '领用记录有矛盾', UNAVAILABLE: '范围不可见' }
const readPerson = (state, actor, p) => p && can(state, actor, 'people:read', p)
const readDevice = (state, actor, d) => d && can(state, actor, 'assets:read', d)
const writeBoth = (state, actor, p, d) => can(state, actor, 'assets:write', p) && can(state, actor, 'assets:write', d)
export const availableForIssue = (state, d) => d.lifecycle === 'STOCK' && relationship(state, d).state === 'UNASSIGNED' && !state.assignments.some(a => a.active && a.deviceId === d.id) && !state.maintenanceOrders.some(o => o.deviceId === d.id && activeMaintenance(o))
const available = availableForIssue
export function assignmentWarnings(d) {
  return [d.communication !== 'ONLINE' ? '通信离线、未知或未接入' : '', d.freshness === 'STALE' ? '设备数据过期' : '', !d.manufacturer || !d.sn || d.modelId?.startsWith('unknown-') ? '资料或型号待补充' : '', d.verification !== 'VERIFIED' ? '能力未经过真实验证' : ''].filter(Boolean)
}
function person(state, actor, siteId, id, fail) {
  const p = state.people.find(p => p.id === id && p.siteId === siteId)
  if (!readPerson(state, actor, p)) throw fail(404, 'OBJECT_NOT_FOUND', '人员不存在或不可见')
  return p
}
function device(state, actor, siteId, id, fail) {
  const d = state.devices.find(d => d.id === id && d.siteId === siteId)
  if (!readDevice(state, actor, d)) throw fail(404, 'OBJECT_NOT_FOUND', '设备不存在或不可见')
  return d
}
function compactDevice(d) { return { id: d.id, code: d.code, name: d.name, type: d.type, version: d.version, warnings: assignmentWarnings(d) } }
function currentRows(state, actor, siteId) {
  return state.devices.filter(d => d.siteId === siteId && readDevice(state, actor, d)).flatMap(d => {
    const r = relationship(state, d)
    if (r.state === 'UNASSIGNED') return []
    const p = readPerson(state, actor, r.person) ? r.person : null
    return [{ id: r.assignment?.id || `uncertain-${d.id}`, deviceId: d.id, code: d.code, name: d.name, type: d.type, deviceVersion: d.version, relation: r.state, personId: p?.id || null, personName: p?.name || null, personCode: p?.code || null, personVersion: p?.version || null, version: r.assignment?.version || null, startedAt: r.assignment?.startedAt || null, source: r.assignment?.source || 'INITIAL_SNAPSHOT', writable: Boolean(p && writeBoth(state, actor, p, d)), warnings: assignmentWarnings(d) }]
  })
}
export function historyRows(state, actor, input) {
  return state.history.filter(h => h.siteId === input.siteId && (!input.personId || h.personId === input.personId) && (!input.deviceId || h.deviceId === input.deviceId)).flatMap(h => {
    const d = state.devices.find(d => d.id === h.deviceId), p = state.people.find(p => p.id === h.personId)
    if (!readDevice(state, actor, d) || !can(state, actor, 'assets:read', { siteId: h.siteId, areaId: h.areaId ?? d.areaId })) return []
    const visiblePerson = readPerson(state, actor, p) && can(state, actor, 'people:read', { siteId: h.siteId, areaId: h.personAreaId ?? p.areaId })
    if (input.personId && !visiblePerson) return []
    return [{ ...h, personId: visiblePerson ? h.personId : null, personName: visiblePerson ? h.personName || null : null, personCode: visiblePerson ? h.personCode || null : null, personAreaId: visiblePerson ? h.personAreaId : null }]
  }).reverse()
}
export function queryAssignments(state, actor, kind, input, { fail, page }) {
  if (input.type && !TYPES.includes(input.type)) throw fail(400, 'INVALID_FILTER', '设备类型无效')
  if (input.action && !['ISSUE', 'RETURN'].includes(input.action)) throw fail(400, 'INVALID_FILTER', '历史动作无效')
  if (input.personId) person(state, actor, input.siteId, input.personId, fail)
  if (input.deviceId) device(state, actor, input.siteId, input.deviceId, fail)
  if (kind === 'maintenanceSummary') {
    const order = state.maintenanceOrders.find(o => o.id === input.id && o.siteId === input.siteId)
    if (!order) throw fail(404, 'OBJECT_NOT_FOUND', '维修单不存在或不可见')
    const d = device(state, actor, input.siteId, order.deviceId, fail)
    return { id: order.id, deviceId: d.id, deviceCode: d.code, reason: order.reason, handlerName: order.handlerName || null, status: order.status, createdAt: order.createdAt || null, batchId: order.batchId || null, version: order.version }
  }
  if (kind === 'repairAssignees') {
    const d = device(state, actor, input.siteId, input.deviceId, fail)
    if (!can(state, actor, 'assets:write', d)) throw fail(403, 'PERMISSION_DENIED', '没有办理权限')
    return { availability: 'AVAILABLE', ...page(state.accounts.filter(a => a.enabled && can(state, a, 'assets:write', d)).map(a => ({ id: a.id, name: a.name, version: a.version })), input) }
  }
  if (kind === 'assignmentCandidates') {
    if (!['people', 'devices', 'selection'].includes(input.resource)) throw fail(400, 'INVALID_RESOURCE', '请选择候选资源')
    if (input.resource === 'people') {
      const d = input.deviceId ? device(state, actor, input.siteId, input.deviceId, fail) : null
      const rows = state.people.filter(p => p.siteId === input.siteId && (input.purpose === 'return' ? currentRows(state, actor, input.siteId).some(r => r.personId === p.id && r.writable && r.relation === 'ASSIGNED') : p.enabled) && readPerson(state, actor, p) && can(state, actor, 'assets:write', p) && (!d || available(state, d) && writeBoth(state, actor, p, d) && personSlots(state, actor, p)[d.type] === 'UNASSIGNED')).map(p => ({ id: p.id, name: p.name, code: p.code, version: p.version }))
      return { availability: 'AVAILABLE', ...page(rows, input) }
    }
    const p = person(state, actor, input.siteId, input.personId, fail), slots = personSlots(state, actor, p)
    if (input.resource === 'selection') return { availability: 'AVAILABLE', person: { id: p.id, code: p.code, name: p.name, version: p.version, enabled: p.enabled }, slots, current: currentRows(state, actor, input.siteId).filter(r => r.personId === p.id), writable: can(state, actor, 'assets:write', p) }
    const rows = state.devices.filter(d => d.siteId === input.siteId && (!input.type || d.type === input.type) && p.enabled && readDevice(state, actor, d) && writeBoth(state, actor, p, d) && slots[d.type] === 'UNASSIGNED' && available(state, d)).map(compactDevice)
    return { availability: 'AVAILABLE', ...page(rows, input) }
  }
  let rows = kind === 'assignments' ? currentRows(state, actor, input.siteId) : historyRows(state, actor, input)
  rows = rows.filter(r => (!input.type || r.type === input.type) && (!input.personId || r.personId === input.personId) && (!input.deviceId || r.deviceId === input.deviceId) && (!input.action || r.action === input.action) && (!input.batchId || r.batchId === input.batchId))
  if (typeof input.keyword !== 'undefined' && (typeof input.keyword !== 'string' || input.keyword.length > 100)) throw fail(400, 'INVALID_KEYWORD', '关键词最多100字')
  const keyword = (input.keyword || '').trim().toLowerCase()
  rows = rows.filter(r => `${r.code || ''} ${r.deviceCode || ''} ${r.personName || ''} ${r.personCode || ''}`.toLowerCase().includes(keyword))
  return { availability: 'AVAILABLE', ...page(rows, { ...input, keyword: '' }) }
}
export function authorizeAssignment(state, actor, type, input, fail) {
  if (!['assignments.issue', 'assignments.return'].includes(type)) throw fail(400, 'COMMAND_NOT_AVAILABLE', '不支持此领用操作')
  if (!Array.isArray(input.items) || input.items.length < 1 || input.items.length > 3 || input.items.some(i => !i || typeof i.deviceId !== 'string')) throw fail(400, 'INVALID_ITEMS', '请选择1至3件装备')
  const p = person(state, actor, input.siteId, input.personId, fail)
  const devices = input.items.map(i => device(state, actor, input.siteId, i.deviceId, fail))
  if (!devices.every(d => writeBoth(state, actor, p, d))) throw fail(403, 'PERMISSION_DENIED', '人员及每台设备均须在资产办理授权范围内')
  return { person: p, devices }
}
export function applyAssignment(state, actor, type, input, { fail, now }) {
  const { person: p, devices } = authorizeAssignment(state, actor, type, input, fail), issue = type === 'assignments.issue'
  const invalid = (field, message, code = 409) => { throw Object.assign(fail(code, code === 409 ? 'ASSIGNMENT_CONFLICT' : 'VALIDATION_ERROR', message), { fields: { [field]: message } }) }
  if (Object.keys(input).some(k => !['siteId', 'personId', 'personVersion', 'items', 'operationId', 'acknowledged'].includes(k))) invalid('items', '不允许指定生命周期、时间或经办人', 400)
  if (input.acknowledged !== true) invalid('acknowledged', '请确认本地办理边界', 400)
  if (p.version !== input.personVersion) throw fail(409, 'VERSION_CONFLICT', '人员或关系已变化，请重新读取')
  if (issue && !p.enabled) invalid('personId', '停用人员不能新领用')
  if (new Set(devices.map(d => d.id)).size !== devices.length || new Set(devices.map(d => d.type)).size !== devices.length) invalid('items', '设备或类型重复，不能整单办理')
  const slots = personSlots(state, actor, p), prepared = []
  input.items.forEach((item, index) => {
    const d = devices[index], field = `item-${d.id}`
    const keys = issue ? ['deviceId', 'deviceVersion'] : ['deviceId', 'deviceVersion', 'assignmentId', 'assignmentVersion', 'condition', 'reason', 'handlerId', 'handlerVersion']
    if (Object.keys(item).some(k => !keys.includes(k))) invalid(field, '不支持的设备办理字段', 400)
    if (d.version !== item.deviceVersion) throw fail(409, 'VERSION_CONFLICT', '设备已变化，请重新读取')
    if (issue) {
      if (slots[d.type] !== 'UNASSIGNED' || !available(state, d)) invalid(field, '人员槽位或设备不满足明确可领条件')
      prepared.push({ d, item }); return
    }
    const r = relationship(state, d), a = state.assignments.find(a => a.id === item.assignmentId && a.deviceId === d.id && a.personId === p.id && a.active)
    if (!a || r.state !== 'ASSIGNED' || slots[d.type] !== 'ASSIGNED' || r.person.id !== p.id) invalid(field, '有效领用关系不存在、未知或冲突，不能强制归还')
    if (a.version !== item.assignmentVersion) throw fail(409, 'VERSION_CONFLICT', '关系已变化，请重新读取')
    if (!['GOOD', 'REPAIR'].includes(item.condition)) invalid(field, '请选择完好或需检修', 400)
    if (state.maintenanceOrders.some(o => o.deviceId === d.id && activeMaintenance(o))) invalid(field, '存在未完成维修单，不能重复建单')
    let handler = null
    if (item.condition === 'REPAIR') {
      if (typeof item.reason !== 'string' || !item.reason.trim() || item.reason.trim().length > 500) invalid(field, '需检修必须填写故障说明（最多500字）', 400)
      handler = state.accounts.find(a => a.id === item.handlerId && a.enabled && can(state, a, 'assets:write', d))
      if (!handler) invalid(field, '处理人不存在、已停用或无本设备办理权限')
      if (handler.version !== item.handlerVersion) throw fail(409, 'VERSION_CONFLICT', '处理人账号已变化，请重新读取')
    }
    prepared.push({ d, item, a, handler })
  })
  const batchId = `handling-${state.nextId++}`, history = [], orders = []
  for (const { d, item, a, handler } of prepared) {
    let assignment = a, order = null
    if (issue) {
      assignment = { id: `assignment-${state.nextId++}`, siteId: input.siteId, personId: p.id, deviceId: d.id, active: true, startedAt: now, endedAt: null, version: 1, source: 'MOCK_OPERATION', batchId }
      state.assignments.push(assignment); d.lifecycle = 'IN_USE'; d.relation = 'ASSIGNED'
    } else {
      assignment.active = false; assignment.endedAt = now; assignment.version++; d.relation = 'UNASSIGNED'; d.lifecycle = item.condition === 'GOOD' ? 'STOCK' : 'MAINTENANCE'
      if (handler) {
        order = { id: `repair-${state.nextId++}`, deviceId: d.id, siteId: d.siteId, areaId: d.areaId, status: 'OPEN', reason: item.reason.trim(), handlerId: handler.id, handlerName: handler.name, createdAt: now, batchId, assignmentId: assignment.id, version: 1, source: 'MOCK_RETURN' }
        state.maintenanceOrders.push(order); orders.push(order.id)
        recordRepairCreation(state, order, d, actor, now, true)
      }
    }
    d.version++
    const record = { id: `history-${state.nextId++}`, siteId: d.siteId, areaId: d.areaId, personAreaId: p.areaId, batchId, assignmentId: assignment.id, action: issue ? 'ISSUE' : 'RETURN', deviceId: d.id, deviceCode: d.code, deviceName: d.name, type: d.type, personId: p.id, personName: p.name, personCode: p.code, actorId: actor.id, actorName: actor.name, occurredAt: now, startedAt: assignment.startedAt, condition: issue ? null : item.condition, maintenanceOrderId: order?.id || null, source: '前端内存本地' }
    state.history.push(record); history.push(record)
  }
  p.version++
  return { batchId, history, maintenanceOrderIds: orders }
}
