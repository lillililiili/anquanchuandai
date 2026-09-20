import { identities } from './seed.js'
import { slots, slotKey, equipmentDevice, personEquipment, activeAssignments } from './assignment-model.js'
import { failure } from './errors.js'
const id = v => typeof v === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(v)
function authorize(role, siteId, write = false) {
  const identity = identities.find(i => i.id === role)
  if (!identity) throw failure(401, '本地会话已失效')
  if (!id(siteId)) throw failure(400, '请选择有效厂站')
  if (!identity.sites.includes(siteId)) throw failure(403, '当前身份无权访问该厂站')
  if (write && role !== 'owner') throw failure(403, '仅负责人可办理领用归还')
}
function find(dataset, collection, key, value, siteId) {
  if (!id(value)) throw failure(400, '对象标识无效')
  const object = dataset.entities[collection].find(item => item[key] === value && item.siteId === siteId)
  if (!object) throw failure(404, '对象不存在或当前身份不可见')
  return object
}
function source(dataset) {
  if (!['equipment', 'people'].includes(dataset.config.module)) return
  if (dataset.config.mode === 'failure') throw failure(503, '本地装备来源故障；操作未提交', 'SOURCE_UNAVAILABLE')
  if (dataset.config.mode === 'not-integrated') throw failure(503, '装备来源尚未接入', 'SOURCE_NOT_INTEGRATED')
  if (dataset.config.mode === 'forbidden') throw failure(403, '本地装备分区无权限', 'SECTION_FORBIDDEN')
}
function pair(dataset, person, device) {
  const current = equipmentDevice(dataset, device)
  return { person: { personId: person.personId, siteId: person.siteId, name: person.name, personCode: person.personCode },
    device: current, assignment: current.currentAssignment,
    expectedVersion: { slot: person.slots[slotKey(device.type)].version, device: device.version, assignment: current.currentAssignment?.version ?? null } }
}
export function queryEquipment(dataset, role, path, q = {}) {
  authorize(role, q.siteId)
  const base = '/api/portal/v1/equipment', list = path === base, options = path === base + '/options'
  const allowed = list ? ['siteId', 'keyword', 'type', 'assignmentState', 'pageNum', 'pageSize'] : options ? ['siteId', 'personId', 'deviceId', 'type'] : ['siteId']
  for (const [key, value] of Object.entries(q)) if (value != null && value !== '' && !allowed.includes(key)) throw failure(400, '不支持筛选：' + key)
  if (q.type && !Object.values(slots).includes(q.type)) throw failure(400, '装备类型无效')
  if (q.assignmentState && !['ASSIGNED', 'UNASSIGNED', 'UNKNOWN', 'CONFLICT'].includes(q.assignmentState)) throw failure(400, '领用状态无效')
  const pageNum = Number(q.pageNum || 1), pageSize = Number(q.pageSize || 20)
  if (![pageNum, pageSize].every(n => Number.isSafeInteger(n) && n > 0) || pageSize > 100 || pageNum > 2147483647) throw failure(400, '分页参数无效')
  if (q.keyword != null && (typeof q.keyword !== 'string' || q.keyword.length > 100)) throw failure(400, '关键词无效')
  const device = !list && !options ? find(dataset, 'devices', 'deviceId', path.slice(base.length + 1), q.siteId) : null
  const fixedPerson = options && q.personId ? find(dataset, 'people', 'personId', q.personId, q.siteId) : null
  const fixedDevice = options && q.deviceId ? find(dataset, 'devices', 'deviceId', q.deviceId, q.siteId) : null
  if (options && (!!fixedPerson === !!fixedDevice)) throw failure(400, '必须指定人员或设备其中之一')
  const scope = { siteId: q.siteId }
  if (list && ['people', 'equipment'].includes(dataset.config.module) && dataset.config.mode === 'not-integrated') return { state: 'NOT_INTEGRATED', reasonCode: 'SOURCE_NOT_INTEGRATED', scope, items: [], total: null, pageNum, pageSize }
  source(dataset)
  if (device) return { state: 'AVAILABLE', scope, device: equipmentDevice(dataset, device) }
  if (list) {
    const rows = dataset.entities.devices.filter(d => d.siteId === q.siteId).map(d => equipmentDevice(dataset, d)).filter(d =>
      (!q.keyword || [d.name, d.deviceCode, d.deviceId].join(' ').toLowerCase().includes(q.keyword.toLowerCase())) &&
      (!q.type || d.type === q.type) && (!q.assignmentState || d.assignmentState === q.assignmentState))
    return { state: 'AVAILABLE', scope, items: rows.slice((pageNum - 1) * pageSize, pageNum * pageSize), total: rows.length, pageNum, pageSize }
  }
  if (!options) throw failure(404, '装备查询不存在')
  const type = fixedDevice?.type || q.type || 'HELMET', key = slotKey(type)
  const eligible = p => personEquipment(dataset, p).data[key].assignmentState === 'UNASSIGNED'
  const people = dataset.entities.people.filter(p => p.siteId === q.siteId)
  const devices = dataset.entities.devices.filter(d => d.siteId === q.siteId && d.type === type)
  const choices = fixedPerson ? eligible(fixedPerson) ? devices.filter(d => equipmentDevice(dataset, d).assignmentState === 'UNASSIGNED').map(d => pair(dataset, fixedPerson, d)) : [] :
    equipmentDevice(dataset, fixedDevice).assignmentState === 'UNASSIGNED' ? people.filter(eligible).map(p => pair(dataset, p, fixedDevice)) : []
  const current = activeAssignments(dataset, q.siteId).filter(a => fixedPerson ? a.personId === fixedPerson.personId && a.type === type : a.deviceId === fixedDevice.deviceId).map(a => {
    const p = people.find(p => p.personId === a.personId), d = dataset.entities.devices.find(d => d.deviceId === a.deviceId)
    return pair(dataset, p, d)
  })
  return { state: 'AVAILABLE', scope, type, person: fixedPerson ? { personId: fixedPerson.personId, name: fixedPerson.name, equipment: personEquipment(dataset, fixedPerson) } : null,
    device: fixedDevice ? equipmentDevice(dataset, fixedDevice) : null, choices, current, allowed: role === 'owner' }
}
export function assignmentCommand(dataset, role, action, input, now = new Date().toISOString()) {
  authorize(role, input?.siteId, true)
  if (!['issue', 'return'].includes(action) || !id(input.operationId)) throw failure(400, '操作标识无效')
  const fingerprint = JSON.stringify([action, input.siteId, input.personId || null, input.deviceId || null, input.assignmentId || null, input.expectedVersion?.slot, input.expectedVersion?.device, input.expectedVersion?.assignment ?? null])
  const operationKey = JSON.stringify([role, input.siteId, input.operationId]), previous = dataset.operations[operationKey]
  if (previous) {
    if (previous.fingerprint !== fingerprint) throw failure(409, '同一操作标识不能用于不同输入', 'IDEMPOTENCY_CONFLICT')
    return { ...previous.result, replayed: true }
  }
  source(dataset)
  const device = find(dataset, 'devices', 'deviceId', input.deviceId, input.siteId)
  const person = find(dataset, 'people', 'personId', input.personId, input.siteId)
  const key = slotKey(device.type), slot = person.slots[key], current = equipmentDevice(dataset, device)
  const relation = action === 'return' ? dataset.relations.assignments.find(a => a.assignmentId === input.assignmentId && a.siteId === input.siteId && a.personId === person.personId && a.deviceId === device.deviceId) : null
  if (action === 'return' && !relation) throw failure(404, '领用关系不存在或不可见')
  if (input.expectedVersion?.slot !== slot.version || input.expectedVersion?.device !== device.version || action === 'return' && input.expectedVersion?.assignment !== relation.version) throw failure(409, '数据版本已变化，请重新读取后确认', 'VERSION_CONFLICT')
  const personState = personEquipment(dataset, person).data[key].assignmentState
  if (action === 'issue' ? personState !== 'UNASSIGNED' || current.assignmentState !== 'UNASSIGNED' : personState !== 'ASSIGNED' || current.assignmentState !== 'ASSIGNED' || relation.state !== 'OPEN' || current.currentAssignment?.assignmentId !== relation.assignmentId) throw failure(409, '领用关系已变化、未知或冲突，不能操作', 'ASSIGNMENT_CONFLICT')
  const seq = ++dataset.meta.sequence
  const assignment = action === 'issue' ? { assignmentId: 'mock-assignment-' + seq, siteId: input.siteId, personId: person.personId, deviceId: device.deviceId, type: device.type, state: 'OPEN', version: 1, startedAt: now, endedAt: null, sourceKind: 'MOCK_OPERATION' } : relation
  if (action === 'issue') dataset.relations.assignments.push(assignment)
  else { assignment.state = 'CLOSED'; assignment.endedAt = now; assignment.version++ }
  slot.version++; device.version++
  const record = { recordId: 'mock-assignment-record-' + seq, assignmentId: assignment.assignmentId, siteId: input.siteId, personId: person.personId, deviceId: device.deviceId, deviceCode: device.deviceCode, type: device.type, action: action === 'issue' ? 'ISSUE' : 'RETURN', evidenceQuality: 'CONFIRMED', operator: { userId: 'mock-' + role, displayName: identities.find(i => i.id === role).name }, occurredAt: now, startedAt: assignment.startedAt, endedAt: action === 'return' ? now : null, state: assignment.state, sourceKind: 'MOCK_OPERATION' }
  dataset.relations.history.unshift(record)
  const result = { assignmentId: assignment.assignmentId, recordId: record.recordId, changedEntities: ['people', 'equipment', 'history', 'video', 'workbench'], replayed: false }
  dataset.operations[operationKey] = { fingerprint, result }
  return result
}
