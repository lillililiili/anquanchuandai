import { can, hasSite, system, accountManageable, DELEGATE_ROLES, OPERATIONS } from './access'
import { emptyEvidence, personSlots } from './relations'
import { historyRows } from './assignmentData'

export const ENTITIES = {
  people: { read: 'people:read', write: 'people:write', title: '人员' },
  organizations: { read: 'organization:read', write: 'organization:write', title: '组织' },
  areas: { read: 'organization:read', write: 'organization:write', title: '区域' },
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
  if (entity === 'areas') return can(state, actor, 'organization:read', { ...row, areaId: row.id })
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
    add('有效领用关系（请在A3归还/核实）', state.assignments.filter(a => a.active && a.personId === row.id))
    add('当前或未来名册', state.dutyShifts.filter(s => s.personIds.includes(row.id) && (all || activeShift(s, now))))
    add('协助组成员（A5维护）', state.groups.filter(g => g.personIds.includes(row.id) && enabled(g)))
  }
  if (['organizations', 'areas'].includes(entity)) {
    add('下级节点', state[entity].filter(x => x.parentId === row.id && enabled(x)))
    const key = entity === 'areas' ? 'areaId' : 'organizationId'
    add('人员引用', state.people.filter(p => p[key] === row.id && enabled(p)))
    if (entity === 'areas') {
      add('设备引用', state.devices.filter(d => d.areaId === row.id))
      add('组织关联', state.organizations.filter(o => o.areaId === row.id && enabled(o)))
      add('协助组管理区域', state.groups.filter(g => g.areaId === row.id && enabled(g)))
      add('角色范围', state.roles.filter(r => r.grants.some(g => Array.isArray(g.areaIds) && g.areaIds.includes(row.id))))
      add('账号范围', state.accounts.filter(a => Object.values(a.roleScopes || {}).some(g => Array.isArray(g.areaIds) && g.areaIds.includes(row.id))))
    }
    // Audit holds immutable snapshots, not live foreign keys; deleting a free leaf retains its audit.
  }
  if (entity === 'sites') {
    for (const key of ['organizations', 'areas', 'people', 'devices', 'groups', 'integrations', 'accounts']) add(`${key}引用`, state[key].filter(r => r.siteId === row.id && enabled(r)))
    add('有效名册', state.dutyShifts.filter(s => s.siteId === row.id && (all || activeShift(s, now))))
  }
  return results
}
export function queryMaster(state, actor, kind, input, { fail, page, now, relationship }) {
  const entity = input.entity || (kind === 'person' ? 'people' : null)
  if (kind === 'options') {
    const data = {}
    for (const key of ['sites', 'organizations', 'areas', 'people', 'roles']) data[key] = state[key].filter(r => r.enabled !== false && visible(state, actor, key, r) && (['sites', 'roles'].includes(key) || r.siteId === input.siteId))
    data.scopeAreas = state.areas.filter(r => r.enabled && visible(state, actor, 'areas', r))
    return data
  }
  if (!ENTITIES[entity]) throw fail(400, 'INVALID_ENTITY', '不支持的资料类型')
  if (!system(actor) && !hasSite(state, actor, input.siteId, ENTITIES[entity].read)) throw fail(403, 'PERMISSION_DENIED', '当前身份没有此工作区权限')
  let rows = state[entity].filter(r => visible(state, actor, entity, r) && (['sites', 'roles'].includes(entity) || r.siteId === input.siteId))
  if (['person', 'record', 'impacts'].includes(kind)) {
    const row = rows.find(r => r.id === input.id)
    if (!row) throw fail(404, 'OBJECT_NOT_FOUND', '对象不存在或不可见')
    if (kind === 'impacts') return { rows: impacts(state, entity, row, now, input.all === true), availability: 'AVAILABLE' }
    const data = { ...row }
    if (entity === 'people') {
      data.equipment = state.devices.filter(d => state.assignments.some(a => a.active && a.personId === row.id && a.deviceId === d.id) && can(state, actor, 'assets:read', d)).map(d => { const r = relationship(state, d); return { ...d, relation: r.state, startedAt: r.assignment?.startedAt || null, assignmentSource: r.assignment?.source || 'INITIAL_SNAPSHOT' } })
      data.slots = personSlots(state, actor, row)
      data.history = historyRows(state, actor, { siteId: row.siteId, personId: row.id }).slice(0, 20)
      data.accountName = state.accounts.find(a => a.personId === row.id && visible(state, actor, 'accounts', a))?.name || null
    }
    return data
  }
  if (input.status && !['enabled', 'disabled'].includes(input.status)) throw fail(400, 'INVALID_FILTER', '无效状态筛选')
  if (input.status) rows = rows.filter(r => r.enabled === (input.status === 'enabled'))
  if (input.organizationId) rows = rows.filter(r => r.organizationId === input.organizationId)
  if (input.areaId) rows = rows.filter(r => r.areaId === input.areaId)
  return { availability: 'AVAILABLE', ...page(rows, input) }
}

export function authorizeMaster(state, actor, type, input, fail) {
  const [entity, action] = type.split('.')
  if (!ENTITIES[entity] || !['create', 'update', 'status', 'delete'].includes(action)) throw fail(400, 'UNKNOWN_COMMAND', '未开放此操作')
  const row = action === 'create' ? null : state[entity].find(r => r.id === input.id)
  if (action !== 'create' && (!row || !visible(state, actor, entity, row) || (entity !== 'sites' && entity !== 'roles' && row.siteId !== input.siteId))) throw fail(404, 'OBJECT_NOT_FOUND', '对象不存在或不可见')
  if (['sites', 'roles'].includes(entity) && !system(actor)) throw fail(403, 'PERMISSION_DENIED', '仅系统管理员可维护厂站或角色')
  if (row && ((entity === 'roles' && row.builtin) || (entity === 'accounts' && row.id === 'demo-system'))) throw fail(403, 'BUILTIN_PROTECTED', '内置系统管理员或角色受保护')
  const object = row || { siteId: input.siteId, areaId: input.data?.areaId }
  const scopedDuty = entity === 'dutyShifts' && (row?.personIds || input.data?.personIds || []).length > 0 && (row?.personIds || input.data.personIds).every(id => { const p = state.people.find(x => x.id === id && x.siteId === input.siteId); return p && can(state, actor, 'duty:write', p) })
  if (!system(actor) && !scopedDuty && !can(state, actor, ENTITIES[entity].write, entity === 'areas' && row ? { ...row, areaId: row.id } : object)) throw fail(403, 'PERMISSION_DENIED', '当前身份无此操作或数据范围权限')
  if (entity === 'accounts' && row && !accountManageable(state, actor, row)) throw fail(403, 'DELEGATION_DENIED', '不能管理自身、上级权限或超出自身范围的账号')
  return { entity, action, row }
}

export function applyMaster(state, actor, type, input, { fail, now }) {
  const { entity, action, row } = authorizeMaster(state, actor, type, input, fail)
  const fieldError = (field, message, code = 400) => { const e = fail(code, code === 409 ? 'RELATION_CONFLICT' : 'VALIDATION_ERROR', message); e.fields = { [field]: message }; throw e }
  const text = (data, key, max = 100) => { if (typeof data[key] !== 'string' || !data[key].trim() || data[key].trim().length > max) fieldError(key, `请填写${key}（1–${max}字）`); return data[key].trim() }
  const enabledRef = (key, id, siteId, field) => {
    if (!id) return null
    const ref = state[key].find(r => r.id === id && r.enabled !== false && r.siteId === siteId && visible(state, actor, key, r))
    if (!ref) fieldError(field, '关联对象未启用、不同厂站或不在授权范围')
    if (['create', 'update'].includes(action) && input.relatedVersions?.[ref.id] !== ref.version) throw fail(409, 'VERSION_CONFLICT', '关联对象已变化，请重新读取')
    return ref
  }
  const siteId = row?.siteId || input.siteId
  if (entity !== 'sites' && !state.sites.some(s => s.id === siteId && s.enabled)) fieldError('siteId', '请选择启用的厂站')
  if (action === 'delete') {
    if (!['organizations', 'areas'].includes(entity)) throw fail(400, 'DELETE_DISABLED', '该资料仅支持启停，不允许删除')
    const refs = impacts(state, entity, row, now, true)
    if (refs.length) { const e = fail(409, 'REFERENCED', '仍有引用，不能删除'); e.impacts = refs; throw e }
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
      if (entity === 'people') { enabledRef('areas', row.areaId, siteId, 'areaId'); enabledRef('organizations', row.organizationId, siteId, 'organizationId') }
    }
    row.enabled = input.enabled; row.version++; return row
  }
  const data = input.data || {}, creating = action === 'create'
  if (!creating && data.siteId && data.siteId !== siteId && entity !== 'sites') fieldError('siteId', '不支持跨厂站调动')
  const record = { ...(row || {}), id: row?.id || `${entity}-19007199254740993-${state.nextId++}`, siteId, name: text(data, 'name'), enabled: row?.enabled ?? true, version: (row?.version || 0) + 1 }
  if (entity !== 'accounts' && entity !== 'roles' && entity !== 'dutyShifts') {
    record.code = text(data, 'code', 50)
    if (state[entity].some(r => r.id !== record.id && r.code.toLowerCase() === record.code.toLowerCase())) fieldError('code', '编号已存在，请使用其他编号', 409)
  }
  if (['organizations', 'areas'].includes(entity)) {
    record.parentId = data.parentId || null
    enabledRef(entity, record.parentId, siteId, 'parentId')
    let parent = record.parentId; const visited = new Set([record.id])
    while (parent) { if (visited.has(parent)) fieldError('parentId', '上级不能是自身或后代'); visited.add(parent); parent = state[entity].find(r => r.id === parent)?.parentId }
    if (entity === 'organizations') { record.areaId = data.areaId || null; enabledRef('areas', record.areaId, siteId, 'areaId'); if (!system(actor) && !can(state, actor, 'organization:write', record)) fieldError('areaId', '目标区域不在可维护范围') }
  }
  if (entity === 'sites') {
    delete record.siteId
    record.timezone = text(data, 'timezone')
    try { new Intl.DateTimeFormat('en', { timeZone: record.timezone }).format() } catch { fieldError('timezone', '请输入有效的IANA时区，例如Asia/Shanghai') }
    if (creating) state.roles.find(r => r.id === 'system').grants[0].siteIds.push(record.id)
  }
  if (entity === 'people') {
    record.organizationId = data.organizationId || null; record.areaId = data.areaId || null
    enabledRef('organizations', record.organizationId, siteId, 'organizationId'); enabledRef('areas', record.areaId, siteId, 'areaId')
    if (!system(actor) && !can(state, actor, 'people:write', record)) fieldError('areaId', '目标区域不在可维护范围')
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
    const bindings = data.bindings || []
    if (creating && bindings.length) fieldError('bindings', '新账号先以无授权状态创建，再编辑分配角色')
    if (!Array.isArray(bindings) || new Set(bindings.map(b => b.roleId)).size !== bindings.length) fieldError('bindings', '角色不能重复')
    record.roleIds = []; record.roleScopes = {}
    for (const b of bindings) {
      const role = state.roles.find(r => r.id === b.roleId && r.enabled)
      if (!role || role.id === 'system' || (!system(actor) && !DELEGATE_ROLES.includes(role.id))) fieldError('bindings', '此角色不可委派')
      if (input.relatedVersions?.[role.id] !== role.version) throw fail(409, 'VERSION_CONFLICT', '角色已变化，请重新读取')
      if (!Array.isArray(b.siteIds) || !b.siteIds.length || (b.areaIds !== '*' && (!Array.isArray(b.areaIds) || !b.areaIds.length))) fieldError('bindings', '请选择角色的厂站和区域范围')
      for (const sid of b.siteIds) {
        if (!state.sites.some(s => s.id === sid && s.enabled)) fieldError('bindings', '授权厂站未启用')
        const templates = role.grants.filter(g => g.siteIds.includes(sid))
        if (!templates.length) fieldError('bindings', '账号范围不能超过角色模板')
        for (const g of templates) {
          if (b.areaIds === '*' && g.areaIds !== '*') fieldError('bindings', '区域角色不能扩大为全厂')
          if (b.areaIds !== '*' && b.areaIds.some(id => !state.areas.some(a => a.id === id && a.enabled && b.siteIds.includes(a.siteId)))) fieldError('bindings', '区域不属于选定厂站')
          const areas = b.areaIds === '*' ? [null] : b.areaIds.filter(id => state.areas.some(a => a.id === id && a.siteId === sid))
          if (!areas.length) fieldError('bindings', '每个选定厂站至少需要一个授权区域')
          for (const areaId of areas) {
            if (areaId && !state.areas.some(a => a.id === areaId && a.siteId === sid && a.enabled)) fieldError('bindings', '区域不属于选定厂站')
            if (areaId && g.areaIds !== '*' && !g.areaIds.includes(areaId)) fieldError('bindings', '区域超出角色模板')
            if (!system(actor) && !g.operations.every(op => can(state, actor, op, { siteId: sid, areaId }))) fieldError('bindings', '不得委派超出自身的操作或范围')
          }
        }
      }
      record.roleIds.push(role.id); record.roleScopes[role.id] = { siteIds: [...b.siteIds], areaIds: b.areaIds === '*' ? '*' : [...b.areaIds] }
    }
    record.description = record.roleIds.length ? '自定义本地账号 · 按角色范围访问' : '自定义本地账号 · 尚未分配授权'
  }
  if (entity === 'roles') {
    const ops = data.operations, siteIds = data.siteIds, areaIds = data.areaIds
    if (!Array.isArray(ops) || !ops.length || ops.some(op => !OPERATIONS.includes(op))) fieldError('operations', '请选择已开放的操作，不允许通配权限')
    if (!Array.isArray(siteIds) || !siteIds.length || siteIds.some(id => !state.sites.some(s => s.id === id && s.enabled))) fieldError('siteIds', '请选择启用的厂站')
    if (areaIds !== '*' && (!Array.isArray(areaIds) || !areaIds.length || areaIds.some(id => !state.areas.some(a => a.id === id && a.enabled && siteIds.includes(a.siteId))))) fieldError('areaIds', '请选择这些厂站内的区域')
    record.grants = [{ operations: [...new Set(['overview:read', ...ops])], siteIds: [...new Set(siteIds)], areaIds: areaIds === '*' ? '*' : [...new Set(areaIds)] }]
    delete record.siteId
  }
  if (creating) state[entity].push(record)
  else state[entity][state[entity].findIndex(r => r.id === record.id)] = record
  return record
}
