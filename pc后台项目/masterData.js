import { can, hasSite, system, accountManageable, DELEGATE_ROLES, OPERATIONS } from './access'
import { emptyEvidence, personSlots } from './relations'
import { historyRows } from './assignmentData'
import { PERSON_DUTY_STATUSES, normalizePersonDutyStatus } from '../shared/person-duty.mjs'

export const ENTITIES = {
  people: { read: 'people:read', write: 'people:write', title: '人员' },
  organizations: { read: 'organization:read', write: 'organization:write', title: '组织' },
  sites: { read: 'sites:read', write: 'sites:write', title: '厂站' },
  dutyShifts: { read: 'duty:read', write: 'duty:write', title: '班次' },
  accounts: { read: 'access:read', write: 'accounts:write', title: '账号' },
  roles: { read: 'access:read', write: 'roles:write', title: '角色' }
}
const activeShift = (s, now) => s.enabled && Date.parse(s.endsAt) > Date.parse(now)
export function visible(state, actor, entity, row) {
  if (entity === 'sites') return system(actor) || hasSite(state, actor, row.id, 'sites:read')
  if (entity === 'roles') return system(actor) || (row.builtin && row.grants.some(g => g.siteIds.some(siteId => hasSite(state, actor, siteId, 'access:read'))))
  if (entity === 'accounts') return system(actor) || accountManageable(state, actor, row) || row.id === actor.id
  if (entity === 'organizations') return can(state, actor, 'organization:read', row)
  if (entity === 'dutyShifts') return can(state, actor, 'duty:read', row) || (row.personIds.length > 0 && row.personIds.every(id => {
    const person = state.people.find(p => p.id === id); return person && can(state, actor, 'duty:read', person)
  }))
  return can(state, actor, ENTITIES[entity].read, row)
}
export function impacts(state, entity, row, now, all = false) {
  const results = []
  const add = (label, rows) => rows.forEach(r => results.push({ id: r.id, name: r.name || r.code || r.id, label }))
  const enabled = r => all || r.enabled !== false
  if (entity === 'people') {
    add('有效领用关系（请到发放回收页面归还或核实）', state.assignments.filter(a => a.active && a.personId === row.id))
    add(all ? '名册成员引用' : '当前或未来名册', state.dutyShifts.filter(s => s.personIds.includes(row.id) && (all || activeShift(s, now))))
    add('协助组成员（A5维护）', state.groups.filter(g => (g.personIds.includes(row.id) || all && g.leaderId === row.id) && enabled(g)))
    if (all) {
      add('绑定账号（请先解除人员关联）', state.accounts.filter(account => account.personId === row.id || account.id === row.accountId))
      add('设备人员关联（请先解除关联）', state.devices.filter(device => device.personId === row.id))
    }
  }
  if (entity === 'accounts' && all) {
    add('未完成维修工单（请先重新指派处理人）', (state.maintenanceOrders || []).filter(order => order.status === 'OPEN' && order.handlerId === row.id))
  }
  if (entity === 'roles' && all) {
    add('绑定账号（请先调整账号角色）', state.accounts.filter(account => account.roleIds?.includes(row.id)))
  }
  if (entity === 'organizations') {
    add('下级节点', state[entity].filter(x => x.parentId === row.id))
    add('人员引用', state.people.filter(p => p.organizationId === row.id))
    // Audit holds immutable snapshots, not live foreign keys; deleting a free leaf retains its audit.
  }
  if (entity === 'sites') {
    for (const key of ['organizations', 'people', 'devices', 'groups', 'integrations', 'accounts']) add(`${key}引用`, state[key].filter(r => r.siteId === row.id && (key === 'organizations' || enabled(r))))
    add('有效名册', state.dutyShifts.filter(s => s.siteId === row.id && (all || activeShift(s, now))))
  }
  return results
}
export function queryMaster(state, actor, kind, input, { fail, page, now, relationship }) {
  const entity = input.entity || (kind === 'person' ? 'people' : null)
  if (kind === 'options') {
    const data = {}
    for (const key of ['sites', 'organizations', 'people', 'roles']) data[key] = state[key].filter(r => (key === 'organizations' || r.enabled !== false) && visible(state, actor, key, r) && (['sites', 'roles'].includes(key) || r.siteId === input.siteId))
    return data
  }
  if (!ENTITIES[entity]) throw fail(400, 'INVALID_ENTITY', '不支持的资料类型')
  if (!system(actor) && !hasSite(state, actor, input.siteId, ENTITIES[entity].read)) throw fail(403, 'PERMISSION_DENIED', '当前身份没有此工作区权限')
  let rows = state[entity].filter(r => visible(state, actor, entity, r) && (['sites', 'roles'].includes(entity) || r.siteId === input.siteId))
  if (entity === 'people') rows = rows.map(row => ({ ...row, dutyStatus: normalizePersonDutyStatus(row.dutyStatus) }))
  if (['person', 'record', 'impacts'].includes(kind)) {
    const row = rows.find(r => r.id === input.id)
    if (!row) throw fail(404, 'OBJECT_NOT_FOUND', '对象不存在或不可见')
    if (kind === 'impacts') return { rows: impacts(state, entity, row, now, input.all === true), availability: 'AVAILABLE' }
    const data = { ...row }
    if (entity === 'people') {
      data.organizationName = state.organizations.find(o => o.id === row.organizationId)?.name || '未关联'
      data.equipment = state.devices.filter(d => state.assignments.some(a => a.active && a.personId === row.id && a.deviceId === d.id) && can(state, actor, 'assets:read', d)).map(d => { const r = relationship(state, d); return { ...d, relation: r.state, startedAt: r.assignment?.startedAt || null, assignmentSource: r.assignment?.source || 'INITIAL_SNAPSHOT' } })
      data.slots = personSlots(state, actor, row)
      data.history = historyRows(state, actor, { siteId: row.siteId, personId: row.id }).slice(0, 20)
      data.accountName = state.accounts.find(a => (a.id === row.accountId || a.personId === row.id) && visible(state, actor, 'accounts', a))?.name || null
    }
    return data
  }
  if (entity !== 'organizations') {
    if (input.status && !['enabled', 'disabled'].includes(input.status)) throw fail(400, 'INVALID_FILTER', '无效状态筛选')
    if (input.status) rows = rows.filter(r => r.enabled === (input.status === 'enabled'))
  }
  if (entity === 'people' && input.dutyStatus) {
    if (!Object.hasOwn(PERSON_DUTY_STATUSES, input.dutyStatus)) throw fail(400, 'INVALID_FILTER', '无效在岗状态筛选')
    rows = rows.filter(row => row.dutyStatus === input.dutyStatus)
  }
  if (input.organizationId) {
    const organizationIds = new Set([input.organizationId])
    if (entity === 'people' && input.includeDescendants === true) {
      const organizations = state.organizations.filter(row => row.siteId === input.siteId && visible(state, actor, 'organizations', row))
      if (!organizations.some(row => row.id === input.organizationId)) organizationIds.clear()
      else {
        const children = new Map()
        for (const organization of organizations) {
          if (!children.has(organization.parentId)) children.set(organization.parentId, [])
          children.get(organization.parentId).push(organization.id)
        }
        // Set iteration visits new descendants once, including malformed cyclic trees.
        for (const id of organizationIds) for (const childId of children.get(id) || []) organizationIds.add(childId)
      }
    }
    rows = rows.filter(row => organizationIds.has(row.organizationId))
  }
  return { availability: 'AVAILABLE', ...page(rows, input) }
}

export function authorizeMaster(state, actor, type, input, fail) {
  const [entity, action] = type.split('.')
  if (!ENTITIES[entity] || !(['create', 'update', 'status', 'delete'].includes(action) || entity === 'people' && action === 'dutyStatus') || entity === 'organizations' && action === 'status') throw fail(400, 'UNKNOWN_COMMAND', '未开放此操作')
  const row = action === 'create' ? null : state[entity].find(r => r.id === input.id)
  if (action !== 'create' && (!row || !visible(state, actor, entity, row) || (entity !== 'sites' && entity !== 'roles' && row.siteId !== input.siteId))) throw fail(404, 'OBJECT_NOT_FOUND', '对象不存在或不可见')
  if (['sites', 'roles'].includes(entity) && !system(actor)) throw fail(403, 'PERMISSION_DENIED', '仅系统管理员可维护厂站或角色')
  if (row && ((entity === 'roles' && row.builtin) || (entity === 'accounts' && row.id === 'demo-system'))) throw fail(403, 'BUILTIN_PROTECTED', '内置系统管理员或角色受保护')
  const object = row || { siteId: input.siteId }
  const scopedDuty = entity === 'dutyShifts' && (row?.personIds || input.data?.personIds || []).length > 0 && (row?.personIds || input.data.personIds).every(id => { const p = state.people.find(x => x.id === id && x.siteId === input.siteId); return p && can(state, actor, 'duty:write', p) })
  if (!system(actor) && !scopedDuty && !can(state, actor, ENTITIES[entity].write, object)) throw fail(403, 'PERMISSION_DENIED', '当前身份无此操作或厂站权限')
  if (entity === 'accounts' && row && !accountManageable(state, actor, row)) throw fail(403, 'DELEGATION_DENIED', '不能管理自身、上级权限或超出自身范围的账号')
  return { entity, action, row }
}

export function applyMaster(state, actor, type, input, { fail, now }) {
  const { entity, action, row } = authorizeMaster(state, actor, type, input, fail)
  const fieldError = (field, message, code = 400) => { const e = fail(code, code === 409 ? 'RELATION_CONFLICT' : 'VALIDATION_ERROR', message); e.fields = { [field]: message }; throw e }
  const text = (data, key, max = 100) => { if (typeof data[key] !== 'string' || !data[key].trim() || data[key].trim().length > max) fieldError(key, `请填写${key}（1–${max}字）`); return data[key].trim() }
  const enabledRef = (key, id, siteId, field) => {
    if (!id) return null
    const ref = state[key].find(r => r.id === id && (key === 'organizations' || r.enabled !== false) && r.siteId === siteId && visible(state, actor, key, r))
    if (!ref) fieldError(field, key === 'organizations' ? '关联组织不存在、不同厂站或不在授权范围' : '关联对象未启用、不同厂站或不在授权范围')
    if (['create', 'update'].includes(action) && input.relatedVersions?.[ref.id] !== ref.version) throw fail(409, 'VERSION_CONFLICT', '关联对象已变化，请重新读取')
    return ref
  }
  const siteId = row?.siteId || input.siteId
  if (entity !== 'sites' && !state.sites.some(s => s.id === siteId && s.enabled)) fieldError('siteId', '请选择启用的厂站')
  if (action === 'dutyStatus') {
    if (Object.keys(input).some(key => !['siteId', 'id', 'expectedVersion', 'operationId', 'dutyStatus'].includes(key))) fieldError('dutyStatus', '不支持的在岗状态字段')
    if (!['ON_DUTY', 'OFF_DUTY'].includes(input.dutyStatus)) fieldError('dutyStatus', '请选择在岗或离岗')
    Object.assign(row, { dutyStatus: input.dutyStatus, dutyStatusUpdatedAt: now, dutyStatusUpdatedBy: actor.name, dutyStatusSource: 'MANUAL', version: row.version + 1 })
    return row
  }
  if (action === 'delete') {
    if (!['people', 'organizations', 'accounts', 'roles'].includes(entity)) throw fail(400, 'DELETE_DISABLED', '该资料仅支持启停，不允许删除')
    const refs = impacts(state, entity, row, now, true)
    if (refs.length) { const e = fail(409, 'REFERENCED', '仍有引用，不能删除'); e.impacts = refs; throw e }
    if (entity === 'accounts') {
      for (const person of state.people.filter(person => person.accountId === row.id)) {
        person.accountId = null
        person.version++
      }
    }
    state[entity] = state[entity].filter(r => r.id !== row.id)
    return { ...row, deleted: true }
  }
  if (action === 'status') {
    if (typeof input.enabled !== 'boolean') fieldError('enabled', '启停状态无效')
    if (entity === 'dutyShifts') {
      if (input.enabled || Date.parse(row.startsAt) <= Date.parse(now)) throw fail(409, 'SHIFT_STARTED', '仅未来班次允许取消，不能恢复已取消班次')
    }
    if (!input.enabled) {
      const refs = impacts(state, entity, row, now)
      if (refs.length) { const e = fail(409, 'REFERENCED', '存在活动引用，请先处理影响清单'); e.impacts = refs; throw e }
    } else {
      if (row.parentId) enabledRef(entity, row.parentId, siteId, 'parentId')
      if (entity === 'people') enabledRef('organizations', row.organizationId, siteId, 'organizationId')
    }
    row.enabled = input.enabled; row.version++
    if (entity === 'roles') row.updatedAt = now
    return row
  }
  const data = input.data || {}, creating = action === 'create'
  if (!creating && data.siteId && data.siteId !== siteId && entity !== 'sites') fieldError('siteId', '不支持跨厂站调动')
  const record = { ...(row || {}), id: row?.id || `${entity}-19007199254740993-${state.nextId++}`, siteId, name: text(data, 'name'), enabled: row?.enabled ?? true, version: (row?.version || 0) + 1 }
  if (entity !== 'accounts' && entity !== 'roles' && entity !== 'dutyShifts') {
    record.code = text(data, 'code', 50)
    if (state[entity].some(r => r.id !== record.id && r.code.toLowerCase() === record.code.toLowerCase())) fieldError('code', '编号已存在，请使用其他编号', 409)
  }
  if (entity === 'organizations') {
    delete record.enabled
    record.parentId = data.parentId || null
    enabledRef(entity, record.parentId, siteId, 'parentId')
    let parent = record.parentId; const visited = new Set([record.id])
    while (parent) { if (visited.has(parent)) fieldError('parentId', '上级不能是自身或后代'); visited.add(parent); parent = state[entity].find(r => r.id === parent)?.parentId }
    delete record.areaId
  }
  if (entity === 'sites') {
    delete record.siteId
    record.timezone = text(data, 'timezone')
    try { new Intl.DateTimeFormat('en', { timeZone: record.timezone }).format() } catch { fieldError('timezone', '请输入有效的IANA时区，例如Asia/Shanghai') }
    if (creating) state.roles.find(r => r.id === 'system').grants[0].siteIds.push(record.id)
  }
  if (entity === 'people') {
    record.organizationId = data.organizationId || null
    record.dutyStatus = normalizePersonDutyStatus(row?.dutyStatus)
    delete record.areaId
    enabledRef('organizations', record.organizationId, siteId, 'organizationId')
    record.remark = typeof data.remark === 'string' ? data.remark.trim() : ''
    if (record.remark.length > 500) fieldError('remark', '备注最多500字')
    record.accountId = row?.accountId || null
    record.equipmentEvidence = row?.equipmentEvidence || (creating ? emptyEvidence() : {})
  }
  if (entity === 'dutyShifts') {
    if (row && (!row.enabled || Date.parse(row.startsAt) <= Date.parse(now))) throw fail(409, 'SHIFT_STARTED', '已开始或已取消班次不能普通编辑')
    for (const key of ['startsAt', 'endsAt']) if (typeof data[key] !== 'string' || !data[key].endsWith('Z') || !Number.isFinite(Date.parse(data[key]))) fieldError(key, '请提供有效UTC时间')
    if (Date.parse(data.startsAt) <= Date.parse(now) || Date.parse(data.endsAt) <= Date.parse(data.startsAt)) fieldError('endsAt', '班次必须在未来开始，结束晚于开始')
    if (!Array.isArray(data.personIds) || !data.personIds.length || new Set(data.personIds).size !== data.personIds.length) fieldError('personIds', '请选择至少一名成员，且不能重复')
    for (const id of data.personIds) { const p = enabledRef('people', id, siteId, 'personIds'); if (!p || !can(state, actor, 'duty:write', p)) fieldError('personIds', '成员不在可维护范围') }
    Object.assign(record, { startsAt: new Date(data.startsAt).toISOString(), endsAt: new Date(data.endsAt).toISOString(), personIds: [...data.personIds], source: 'MOCK', memberSnapshots: data.personIds.map(id => ({ id, name: state.people.find(p => p.id === id).name })) })
  }
  if (entity === 'accounts') {
    record.credentialVersion = row?.credentialVersion || 1
    record.loginName = text(data, 'loginName', 50)
    if (row && row.loginName !== record.loginName) fieldError('loginName', '登录名创建后不可修改')
    if (state.accounts.some(a => a.id !== record.id && a.loginName.toLowerCase() === record.loginName.toLowerCase())) fieldError('loginName', '登录名已存在', 409)
    record.personId = data.personId || null
    const person = enabledRef('people', record.personId, siteId, 'personId')
    if (person && state.accounts.some(a => a.id !== record.id && a.personId === person.id)) fieldError('personId', '该人员已关联另一个账号', 409)
    const refs = [row?.personId, record.personId].filter(Boolean)
    for (const id of new Set(refs)) {
      const p = state.people.find(x => x.id === id)
      if (input.relatedVersions?.[id] !== p.version) throw fail(409, 'VERSION_CONFLICT', '关联人员已变化，请重新读取')
      p.accountId = id === record.personId ? record.id : null; p.version++
    }
    const bindings = data.bindings === undefined ? [] : data.bindings
    if (!Array.isArray(bindings)) fieldError('bindings', '角色绑定数据格式无效')
    if (bindings.length > 1) fieldError('bindings', '每个用户最多只能绑定一个角色')
    if (bindings.some(binding => !binding || typeof binding !== 'object' || Array.isArray(binding) || typeof binding.roleId !== 'string' || !binding.roleId.trim())) fieldError('bindings', '角色绑定数据格式无效')
    record.roleIds = []; delete record.roleScopes
    for (const b of bindings) {
      const role = state.roles.find(r => r.id === b.roleId && r.enabled)
      if (!role || role.id === 'system' || (!system(actor) && !DELEGATE_ROLES.includes(role.id))) fieldError('bindings', '此角色不可委派')
      if (input.relatedVersions?.[role.id] !== role.version) throw fail(409, 'VERSION_CONFLICT', '角色已变化，请重新读取')
      if (!Array.isArray(role.grants) || !role.grants.length) fieldError('bindings', '角色尚未配置厂站范围')
      for (const grant of role.grants) {
        if (!Array.isArray(grant.siteIds) || !grant.siteIds.length) fieldError('bindings', '角色尚未配置厂站范围')
        for (const sid of grant.siteIds) {
          if (!state.sites.some(s => s.id === sid && s.enabled)) fieldError('bindings', '角色授权厂站未启用')
          if (!system(actor) && !grant.operations.every(op => can(state, actor, op, { siteId: sid }))) fieldError('bindings', '不得委派超出自身的操作或厂站范围')
        }
      }
      record.roleIds.push(role.id)
    }
    record.description = record.roleIds.length ? '自定义用户账号 · 按角色范围访问' : '自定义用户账号 · 尚未分配授权'
  }
  if (entity === 'roles') {
    const ops = data.operations, siteIds = data.siteIds
    if (!Array.isArray(ops) || !ops.length || ops.some(op => !OPERATIONS.includes(op))) fieldError('operations', '请选择已开放的操作，不允许通配权限')
    if (!Array.isArray(siteIds) || !siteIds.length || siteIds.some(id => !state.sites.some(s => s.id === id && s.enabled))) fieldError('siteIds', '请选择启用的厂站')
    record.grants = [{ operations: [...new Set(['overview:read', ...ops])], siteIds: [...new Set(siteIds)] }]
    if (creating) record.createdAt = now
    record.updatedAt = now
    delete record.siteId
  }
  if (creating) state[entity].push(record)
  else state[entity][state[entity].findIndex(r => r.id === record.id)] = record
  return record
}
