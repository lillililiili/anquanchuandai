import { can, accountManageable } from './access'
import { visible } from './masterData'
import { personSlots, relationship } from './relations'

export const GROUP_QUERIES = ['groups', 'group', 'groupCandidates', 'groupTerminals', 'groupHistory']
export const GROUP_COMMANDS = ['groups.create', 'groups.update', 'groups.status', 'accounts.resetCredential']
const memberObjects = (state, group) => [group, ...group.personIds.map(id => state.people.find(p => p.id === id && p.siteId === group.siteId))]
export function groupAllowed(state, actor, group, write = false) {
  return memberObjects(state, group).every(o => o && ['access:read', 'people:read', ...(write ? ['groups:write'] : [])].every(op => can(state, actor, op, o)))
}
export function authorizeCollaboration(state, actor, type, input, fail) {
  if (type === 'accounts.resetCredential') {
    const row = state.accounts.find(a => a.id === input.id && a.siteId === input.siteId)
    if (!row || !visible(state, actor, 'accounts', row)) throw fail(404, 'OBJECT_NOT_FOUND', '账号不存在或不可见')
    if (!accountManageable(state, actor, row)) throw fail(403, 'ACCOUNT_PROTECTED', '不能重置自身、系统身份或超范围账号')
    return row
  }
  if (type === 'groups.create') {
    const target = { siteId: input.siteId, areaId: input.data?.areaId }
    if (!['access:read', 'people:read', 'groups:write'].every(op => can(state, actor, op, target))) throw fail(403, 'PERMISSION_DENIED', '无此区域协助组维护权限')
    return null
  }
  const row = state.groups.find(g => g.id === input.id && g.siteId === input.siteId)
  if (!row || !groupAllowed(state, actor, row)) throw fail(404, 'OBJECT_NOT_FOUND', '协助组不存在或完整范围不可见')
  if (!groupAllowed(state, actor, row, true)) throw fail(403, 'PERMISSION_DENIED', '无完整组范围维护权限')
  return row
}
export function queryCollaboration(state, actor, kind, input, { fail, page }) {
  if (kind === 'groupCandidates') {
    const allowed = o => ['access:read', 'people:read', 'groups:write'].every(op => can(state, actor, op, o))
    return { availability: 'AVAILABLE', people: state.people.filter(p => p.siteId === input.siteId && p.enabled && allowed(p)).map(p => ({ id: p.id, name: p.name, code: p.code, areaId: p.areaId, version: p.version })), areas: state.areas.filter(a => a.siteId === input.siteId && a.enabled && allowed({ ...a, areaId: a.id })).map(a => ({ id: a.id, name: a.name, version: a.version })) }
  }
  const rows = state.groups.filter(g => g.siteId === input.siteId && groupAllowed(state, actor, g))
  if (kind === 'groups') {
    if (input.status && !['enabled', 'disabled'].includes(input.status)) throw fail(400, 'INVALID_FILTER', '启停筛选无效')
    return { availability: 'AVAILABLE', ...page(rows.filter(g => !input.status || g.enabled === (input.status === 'enabled')).map(g => ({ ...g, memberCount: new Set(g.personIds).size, writable: groupAllowed(state, actor, g, true) })), input) }
  }
  const group = rows.find(g => g.id === input.id)
  if (!group) throw fail(404, 'OBJECT_NOT_FOUND', '协助组不存在或完整范围不可见')
  if (kind === 'group') return { ...group, availability: 'AVAILABLE', writable: groupAllowed(state, actor, group, true), members: group.personIds.map(id => { const p = state.people.find(p => p.id === id); return { id, name: p.name, code: p.code, enabled: p.enabled, areaId: p.areaId, version: p.version } }), areaName: state.areas.find(a => a.id === group.areaId)?.name || '未知', notificationEffective: group.enabled && group.sos?.enabled === true }
  if (kind === 'groupHistory') return { availability: 'AVAILABLE', ...page((state.groupHistory || []).filter(h => h.groupId === group.id && [h, ...h.members.map(p => ({ siteId: h.siteId, areaId: p.areaId }))].every(o => ['access:read', 'people:read'].every(op => can(state, actor, op, o)))).slice().reverse(), input) }
  return { availability: 'AVAILABLE', rows: group.personIds.map(id => {
    const p = state.people.find(p => p.id === id), account = state.accounts.find(a => a.personId === id), slots = personSlots(state, actor, p)
    return { personId: id, name: p.name, account: !account ? { state: 'UNLINKED' } : visible(state, actor, 'accounts', account) ? { state: 'AVAILABLE', name: account.name } : { state: 'FORBIDDEN' }, pc: 'NOT_CONNECTED', app: 'NOT_CONNECTED', slots, devices: state.devices.filter(d => state.assignments.some(a => a.active && a.personId === id && a.deviceId === d.id) && can(state, actor, 'assets:read', d)).map(d => ({ id: d.id, code: d.code, name: d.name, type: d.type, relation: relationship(state, d).state, communication: d.communication, capability: d.type === 'HELMET' ? '未验证通信能力，不代表可呼叫' : '厂家协议待确认，不推定可呼叫', sourceTime: d.sourceTime })) }
  }) }
}
export function applyCollaboration(state, actor, type, input, { fail, now }) {
  const row = authorizeCollaboration(state, actor, type, input, fail)
  const invalid = (field, message, code = 400) => { const error = fail(code, code === 409 ? 'VERSION_OR_RELATION_CONFLICT' : 'VALIDATION_ERROR', message); error.fields = { [field]: message }; throw error }
  const text = (v, field, max = 100) => { if (typeof v !== 'string' || !v.trim() || v.trim().length > max) invalid(field, `请填写${field}（1–${max}字）`); return v.trim() }
  if (row && input.expectedVersion !== row.version) throw fail(409, 'VERSION_CONFLICT', '对象已变化，请重新读取')
  if (type === 'accounts.resetCredential') {
    const reason = text(input.reason, 'reason', 500)
    if (input.confirm !== true) invalid('confirm', '请确认仅重置本地凭据')
    row.credentialVersion = (row.credentialVersion || 1) + 1; row.version++
    return { id: row.id, siteId: row.siteId, areaId: row.areaId || null, name: row.name, version: row.version, credentialVersion: row.credentialVersion, reason }
  }
  const status = type === 'groups.status', data = status ? row : input.data || {}
  if (row && type === 'groups.update') {
    const originalRefs = [state.areas.find(a => a.id === row.areaId), ...row.personIds.map(id => state.people.find(p => p.id === id))]
    if (originalRefs.some(r => !r || input.relatedVersions?.[r.id] !== r.version)) throw fail(409, 'VERSION_CONFLICT', '原区域或成员已变化，请重新读取后修改')
  }
  const keys = ['code', 'name', 'areaId', 'leaderId', 'personIds', 'sos', 'remark']
  if (!status && Object.keys(data).some(k => !keys.includes(k))) invalid('name', '包含不允许修改的字段')
  if (status && typeof input.enabled !== 'boolean') invalid('enabled', '启停参数无效')
  const record = status ? { ...row, enabled: input.enabled, version: row.version + 1 } : { id: row?.id || `group-19007199254740993-${state.nextId++}`, siteId: input.siteId, enabled: row?.enabled ?? true, version: (row?.version || 0) + 1, code: text(data.code, 'code', 50), name: text(data.name, 'name'), areaId: data.areaId, personIds: data.personIds, leaderId: data.leaderId, sos: data.sos, remark: typeof data.remark === 'string' ? data.remark.trim() : '' }
  if (record.remark.length > 500) invalid('remark', '备注最多500字')
  if (state.groups.some(g => g.id !== record.id && g.siteId === record.siteId && g.code.toLowerCase() === record.code.toLowerCase())) invalid('code', '本厂站组编号已存在', 409)
  // Disabling an old incomplete group is allowed; enabling or editing validates every reference.
  if (!status || record.enabled) {
    if (!Array.isArray(record.personIds) || !record.personIds.length || new Set(record.personIds).size !== record.personIds.length) invalid('personIds', '至少选择一名成员且不能重复')
    if (!record.personIds.includes(record.leaderId)) invalid('leaderId', '负责人必须是本组成员')
    const area = state.areas.find(a => a.id === record.areaId && a.siteId === record.siteId && a.enabled)
    if (!area) invalid('areaId', '请选择同厂站启用区域')
    if (input.relatedVersions?.[area.id] !== area.version) invalid('areaId', '区域已变化，请重新读取', 409)
    for (const id of record.personIds) {
      const p = state.people.find(p => p.id === id && p.siteId === record.siteId && p.enabled)
      if (!p || !['access:read', 'people:read', 'groups:write'].every(op => can(state, actor, op, p))) invalid('personIds', '成员未启用、跨厂站或不在完整授权范围')
      if (input.relatedVersions?.[id] !== p.version) invalid('personIds', '成员已变化，请重新读取', 409)
    }
    if (!record.sos || typeof record.sos.enabled !== 'boolean' || !Array.isArray(record.sos.recipientIds) || new Set(record.sos.recipientIds).size !== record.sos.recipientIds.length || record.sos.recipientIds.some(id => !record.personIds.includes(id)) || record.sos.enabled && !record.sos.recipientIds.length) invalid('sos', '通知开启需至少一名本组接收成员；移除成员时请显式调整接收范围')
    if (!groupAllowed(state, actor, record, true)) throw fail(403, 'PERMISSION_DENIED', '目标区域超出维护范围')
  }
  if (row) state.groups[state.groups.findIndex(g => g.id === row.id)] = record
  else state.groups.push(record)
  const names = ids => (ids || []).map(id => { const p = state.people.find(p => p.id === id); return { id, name: p?.name || '未知', areaId: p?.areaId || null } })
  state.groupHistory ||= []
  state.groupHistory.push({ id: `group-history-${state.nextId++}`, groupId: record.id, siteId: record.siteId, areaId: record.areaId, areaName: state.areas.find(a => a.id === record.areaId)?.name || '未知', code: record.code, name: record.name, remark: record.remark, version: record.version, enabled: record.enabled, action: type, occurredAt: now, operatorName: actor.name, members: names(record.personIds), leader: names(record.leaderId ? [record.leaderId] : [])[0] || null, sos: record.sos ? { enabled: record.sos.enabled, recipients: names(record.sos.recipientIds) } : null, source: '仅本地配置；未发送通知' })
  return record
}
