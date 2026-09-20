import { createSeed, TOKEN_KEY, SESSION_VERSION_KEY } from './seed'
import { can, hasSite, system } from './access'
import { ENTITIES, queryMaster, authorizeMaster, applyMaster } from './masterData'
import { DEVICE_QUERIES, queryDevices, authorizeDevice, applyDevice } from './deviceData'
import { relationship } from './relations'
import { ASSIGNMENT_QUERIES, queryAssignments, authorizeAssignment, applyAssignment, availableForIssue } from './assignmentData'
import { MAINTENANCE_QUERIES, MAINTENANCE_COMMANDS, queryMaintenance, authorizeMaintenance, applyMaintenance, activeMaintenance } from './maintenanceData'
import { GROUP_QUERIES, GROUP_COMMANDS, queryCollaboration, authorizeCollaboration, applyCollaboration } from './collaborationData'
import { authorizationDiff, needsAuthorizationPreview } from './authorizationPreview'
export { relationship } from './relations'
export { can } from './access'

export function redact(value) {
  if (Array.isArray(value)) return value.map(redact)
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, v]) => [key, /password|token|secret|credential|authorization|cookie|url|address/i.test(key) ? '[已脱敏]' : redact(v)]))
  return value
}

function stable(value) {
  if (Array.isArray(value)) return value.map(stable)
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, stable(value[k])]))
  return value
}

export function createAdminService({ storage, delay = 200, seed = createSeed, commands = {}, now = () => new Date().toISOString() } = {}) {
  let state = seed(), epoch = 0, sequence = 0, contextGeneration = 0
  let scenario = { target: 'overview', mode: 'normal', delayNext: false }
  const listeners = new Set()
  const previews = new Map()
  const clearSession = () => { storage?.removeItem(TOKEN_KEY); storage?.removeItem(SESSION_VERSION_KEY); previews.clear() }
  const previewFingerprint = input => { const payload = { ...input }; delete payload.previewId; return JSON.stringify(stable(payload)) }
  const copy = v => structuredClone(v)
  const emit = kind => { for (const listener of listeners) { try { listener({ kind, revision: state.revision }) } catch (e) { console.error('本地修订通知失败（已提交数据不回滚）', e) } } }
  const fail = (code, errorCode, message) => Object.assign(new Error(message), { code, errorCode, requestId: `admin-mock-${++sequence}` })
  const actor = () => {
    const id = storage?.getItem(TOKEN_KEY)
    const account = state.accounts.find(a => a.id === id && a.enabled)
    if (!account || storage?.getItem(SESSION_VERSION_KEY) !== String(account.credentialVersion || 1)) {
      if (id) clearSession()
      throw fail(401, 'SESSION_EXPIRED', '登录已失效，请重新登录')
    }
    return account
  }
  function checkSite(user, siteId) {
    if (!siteId || typeof siteId !== 'string') throw fail(400, 'SITE_REQUIRED', '请选择厂站')
    if (!hasSite(state, user, siteId)) throw fail(403, 'SITE_DENIED', '无权访问此厂站')
  }
  function requirePermission(user, operation, object) {
    if (!can(state, user, operation, object)) throw fail(403, 'PERMISSION_DENIED', '当前身份无此操作或数据范围权限')
  }
  async function wait(signal, extra = false) {
    if (signal?.aborted) throw new DOMException('请求已取消', 'AbortError')
    await new Promise((resolve, reject) => {
      const abort = () => { clearTimeout(timer); signal?.removeEventListener('abort', abort); reject(new DOMException('请求已取消', 'AbortError')) }
      const timer = setTimeout(() => { signal?.removeEventListener('abort', abort); resolve() }, extra ? 3000 : delay)
      signal?.addEventListener('abort', abort, { once: true })
    })
  }
  function rowsFor(user, siteId, metric) {
    if (!['assets', 'available', 'assigned', 'maintenance', 'unknown', 'conflict'].includes(metric)) throw fail(400, 'INVALID_METRIC', '不支持的明细类型')
    return state.devices.filter(d => d.siteId === siteId && can(state, user, 'assets:read', d)).flatMap(d => {
      const r = relationship(state, d)
      const row = { ...d, relation: r.state, personName: r.person && can(state, user, 'people:read', r.person) ? r.person.name : null }
      if (metric === 'assets') return [row]
      if (metric === 'maintenance') return state.maintenanceOrders.filter(o => o.deviceId === d.id && o.siteId === siteId && activeMaintenance(o)).map(o => ({ ...row, id: o.id, deviceId: d.id, reason: o.reason }))
      if (metric === 'available') return availableForIssue(state, d) ? [row] : []
      return r.state === metric.toUpperCase() ? [row] : []
    })
  }
  function page(rows, input) {
    const pageNum = input.pageNum ?? 1, pageSize = input.pageSize ?? 20
    if (!Number.isInteger(pageNum) || pageNum < 1 || !Number.isInteger(pageSize) || pageSize < 1 || pageSize > 100) throw fail(400, 'INVALID_PAGE', '分页参数无效')
    const keyword = input.keyword ?? ''
    if (typeof keyword !== 'string' || keyword.length > 100) throw fail(400, 'INVALID_KEYWORD', '关键词最多100字')
    const filtered = rows.filter(r => `${r.code ?? ''} ${r.loginName ?? ''} ${r.personName ?? ''} ${r.name ?? ''}`.toLowerCase().includes(keyword.trim().toLowerCase()))
    return { rows: filtered.slice((pageNum - 1) * pageSize, pageNum * pageSize), total: filtered.length, pageNum, pageSize }
  }
  async function query(kind, input = {}, { signal } = {}) {
    const user = actor(), startEpoch = epoch, generation = contextGeneration
    const slow = scenario.delayNext
    scenario.delayNext = false
    const captured = copy(scenario)
    await wait(signal, slow)
    if (startEpoch !== epoch || actor().id !== user.id) throw fail(401, 'SESSION_CHANGED', '身份已变化，请重新查询')
    if (generation !== contextGeneration) throw new DOMException('上下文已变化', 'AbortError')
    const current = actor()
    if (kind === 'context') return response({ sites: state.sites.filter(s => hasSite(state, current, s.id)), identity: current })
    checkSite(current, input.siteId)
    const master = ['master', 'record', 'person', 'options', 'impacts'].includes(kind)
    const permission = GROUP_QUERIES.includes(kind) || kind === 'authorizationPreview' ? 'access:read' : kind === 'audit' ? 'audit:read' : kind === 'overview' ? 'overview:read' : 'assets:read'
    if (!master && !hasSite(state, current, input.siteId, permission)) throw fail(403, 'PERMISSION_DENIED', '当前身份无此查询权限')
    if ((captured.target === kind || (master && captured.target === input.entity)) && captured.mode !== 'normal') {
      if (captured.mode === 'unavailable') return response({ availability: 'NOT_CONNECTED', reason: '当前查询来源未接入（预置场景）' })
      throw fail(captured.mode === 'forbidden' ? 403 : 503, captured.mode === 'forbidden' ? 'SECTION_DENIED' : 'SOURCE_FAILURE', captured.mode === 'forbidden' ? '当前分区无权限（预置场景）' : '预置数据请求失败，请恢复场景后重试')
    }
    if (master) return response(queryMaster(state, current, kind, input, { fail, page, now: now(), relationship }))
    if (kind === 'authorizationPreview') {
      const { type, command } = input
      if (!['accounts.update', 'roles.update', 'roles.status'].includes(type) || !command || command.siteId !== input.siteId) throw fail(400, 'INVALID_PREVIEW', '不支持此授权预览')
      const meta = authorizeMaster(state, current, type, command, fail)
      if (meta.row.version !== command.expectedVersion) throw fail(409, 'VERSION_CONFLICT', '对象已变化，请重新读取')
      const draft = copy(state)
      applyMaster(draft, current, type, copy(command), { fail, now: now() })
      const required = needsAuthorizationPreview(state, draft, type, command)
      const previewId = `preview-${++sequence}`
      if (previews.size >= 50) previews.delete(previews.keys().next().value)
      previews.set(previewId, { actorId: current.id, epoch, generation: contextGeneration, revision: state.revision, type, fingerprint: previewFingerprint(command) })
      return response({ availability: 'AVAILABLE', previewId, required, revision: state.revision, accounts: authorizationDiff(state, draft, type, command) })
    }
    if (GROUP_QUERIES.includes(kind)) return response(queryCollaboration(state, current, kind, input, { fail, page }))
    if (MAINTENANCE_QUERIES.includes(kind)) return response(queryMaintenance(state, current, kind, input, { fail, page }))
    if (ASSIGNMENT_QUERIES.includes(kind)) return response(queryAssignments(state, current, kind, input, { fail, page }))
    if (DEVICE_QUERIES.includes(kind)) return response(queryDevices(state, current, kind, input, { fail, page, relationship }))
    if (kind === 'overview') {
      if (!hasSite(state, current, input.siteId, 'assets:read')) throw fail(403, 'SECTION_DENIED', '当前身份无权查看资产指标，不能以零值代替')
      return response({ availability: 'AVAILABLE', counts: Object.fromEntries(['assets', 'available', 'assigned', 'maintenance', 'unknown', 'conflict'].map(m => [m, rowsFor(current, input.siteId, m).length])) })
    }
    if (kind === 'details') return response({ availability: 'AVAILABLE', ...page(rowsFor(current, input.siteId, input.metric ?? 'assets'), input) })
    if (kind === 'audit') return response({ availability: 'AVAILABLE', ...page(state.audit.filter(r => r.siteId === input.siteId && can(state, current, 'audit:read', r)).slice().reverse(), input) })
    throw fail(400, 'UNKNOWN_QUERY', '未实现此查询')
  }
  function response(data) { return copy({ code: 200, requestId: `admin-mock-${++sequence}`, data }) }
  async function execute(type, input, { signal } = {}) {
    const user = actor(), startEpoch = epoch, generation = contextGeneration
    await wait(signal)
    if (epoch !== startEpoch || actor().id !== user.id) throw fail(401, 'SESSION_CHANGED', '身份已变化，操作未提交')
    if (generation !== contextGeneration) throw new DOMException('上下文已变化', 'AbortError')
    if (GROUP_COMMANDS.includes(type)) {
      checkSite(actor(), input.siteId)
      const row = authorizeCollaboration(state, actor(), type, input, fail)
      if (typeof input.operationId !== 'string' || !input.operationId || input.operationId.length > 100) throw fail(400, 'OPERATION_REQUIRED', '操作标识无效')
      const key = JSON.stringify([user.id, type, input.operationId]), fingerprint = JSON.stringify(stable(input)), previous = state.idempotency[key]
      if (previous) { if (previous.fingerprint !== fingerprint) throw fail(409, 'IDEMPOTENCY_CONFLICT', '相同操作标识不能用于不同内容'); return copy(previous.result) }
      const draft = copy(state), occurredAt = now(), output = applyCollaboration(draft, actor(), type, copy(input), { fail, now: occurredAt })
      if (signal?.aborted || epoch !== startEpoch || generation !== contextGeneration) throw new DOMException('提交前已取消', 'AbortError')
      const result = response(output); draft.revision++
      draft.audit.push({ id: `audit-${++sequence}`, siteId: input.siteId, areaId: output.areaId || null, actorName: user.name, action: type, objectId: output.id, occurredAt, result: 'SUCCESS', requestId: result.requestId, operationId: input.operationId, before: row ? redact(copy(row)) : null, after: redact(copy(output)), source: '前端内存本地；未修改真实凭据、未发送通知' })
      draft.idempotency[key] = { fingerprint, result }; state = draft; emit('revision'); return copy(result)
    }
    if (MAINTENANCE_COMMANDS.includes(type)) {
      checkSite(actor(), input.siteId)
      const { device } = authorizeMaintenance(state, actor(), type, input, fail)
      if (typeof input.operationId !== 'string' || !input.operationId || input.operationId.length > 100) throw fail(400, 'OPERATION_REQUIRED', '操作标识无效')
      const key = JSON.stringify([user.id, type, input.operationId]), fingerprint = JSON.stringify(stable(input)), previous = state.idempotency[key]
      if (previous) { if (previous.fingerprint !== fingerprint) throw fail(409, 'IDEMPOTENCY_CONFLICT', '相同操作标识不能用于不同内容'); return copy(previous.result) }
      const draft = copy(state), occurredAt = now(), output = applyMaintenance(draft, actor(), type, copy(input), { fail, now: occurredAt })
      if (signal?.aborted || epoch !== startEpoch || generation !== contextGeneration) throw new DOMException('提交前已取消', 'AbortError')
      const result = response(output); draft.revision++
      draft.audit.push({ id: `audit-${++sequence}`, siteId: device.siteId, areaId: device.areaId, actorName: user.name, action: type, objectId: device.id, occurredAt, result: 'SUCCESS', requestId: result.requestId, operationId: input.operationId, after: redact(output), source: '前端内存本地；非正式审批或设备安全认证' })
      draft.idempotency[key] = { fingerprint, result }; state = draft; emit('revision'); return copy(result)
    }
    if (type.startsWith('assignments.')) {
      checkSite(actor(), input.siteId)
      authorizeAssignment(state, actor(), type, input, fail)
      if (typeof input.operationId !== 'string' || !input.operationId || input.operationId.length > 100) throw fail(400, 'OPERATION_REQUIRED', '操作标识无效')
      const key = JSON.stringify([user.id, type, input.operationId]), fingerprint = JSON.stringify(stable(input)), previous = state.idempotency[key]
      if (previous) { if (previous.fingerprint !== fingerprint) throw fail(409, 'IDEMPOTENCY_CONFLICT', '相同操作标识不能用于不同内容'); return copy(previous.result) }
      const draft = copy(state), output = applyAssignment(draft, actor(), type, copy(input), { fail, now: now() })
      if (signal?.aborted || epoch !== startEpoch || generation !== contextGeneration) throw new DOMException('提交前已取消', 'AbortError')
      const result = response(output); draft.revision++
      for (const h of output.history) draft.audit.push({ id: `audit-${++sequence}`, siteId: h.siteId, areaId: h.areaId, actorName: user.name, action: type, objectId: h.deviceId, batchId: output.batchId, occurredAt: h.occurredAt, result: 'SUCCESS', requestId: result.requestId, operationId: input.operationId, after: { historyId: h.id, batchId: h.batchId, action: h.action, condition: h.condition, maintenanceOrderId: h.maintenanceOrderId }, source: '前端内存本地；人员及设备快照通过领用历史授权查询' })
      draft.idempotency[key] = { fingerprint, result }; state = draft; emit('revision'); return copy(result)
    }
    if (ENTITIES[type.split('.')[0]] || type.startsWith('devices.')) {
      const deviceCommand = type.startsWith('devices.')
      if (!system(actor()) || type.split('.')[0] !== 'sites') checkSite(actor(), input.siteId)
      const meta = deviceCommand ? authorizeDevice(state, actor(), type, input, fail) : authorizeMaster(state, actor(), type, input, fail)
      if (!input.operationId || typeof input.operationId !== 'string' || input.operationId.length > 100) throw fail(400, 'OPERATION_REQUIRED', '操作标识无效')
      const key = JSON.stringify([user.id, type, input.operationId]), fingerprint = JSON.stringify(stable(input)), previous = state.idempotency[key]
      if (previous) { if (previous.fingerprint !== fingerprint) throw fail(409, 'IDEMPOTENCY_CONFLICT', '相同操作标识不能用于不同内容'); return copy(previous.result) }
      if (meta.row && input.expectedVersion !== meta.row.version) throw fail(409, 'VERSION_CONFLICT', '对象已变化，请重新读取')
      const draft = copy(state), before = meta.row ? redact(copy(meta.row)) : null
      const output = deviceCommand ? applyDevice(draft, actor(), type, copy(input), { fail, relationship }) : applyMaster(draft, actor(), type, copy(input), { fail, now: now() })
      if (!deviceCommand && needsAuthorizationPreview(state, draft, type, input)) {
        const preview = previews.get(input.previewId)
        if (!preview || preview.actorId !== user.id || preview.epoch !== epoch || preview.generation !== contextGeneration || preview.revision !== state.revision || preview.type !== type || preview.fingerprint !== previewFingerprint(input)) throw fail(409, 'PREVIEW_EXPIRED', '授权预览缺失或已失效，请重新预览后确认')
      }
      if (signal?.aborted || epoch !== startEpoch || generation !== contextGeneration) throw new DOMException('提交前已取消', 'AbortError')
      const result = response(output)
      draft.revision++
      draft.audit.push({ id: `audit-${++sequence}`, siteId: meta.entity === 'sites' ? output.id : input.siteId, areaId: output.areaId || null, actorName: user.name, action: type, objectId: output.id, occurredAt: now(), result: 'SUCCESS', requestId: result.requestId, operationId: input.operationId, before, after: redact(copy(output)), source: '前端内存本地' })
      draft.idempotency[key] = { fingerprint, result }; state = draft
      const authorizationChanged = ['accounts', 'roles', 'sites', 'areas'].includes(meta.entity)
      if (authorizationChanged) contextGeneration++
      if (!state.accounts.some(a => a.id === user.id && a.enabled)) { clearSession(); epoch++; emit('expired') }
      else emit(authorizationChanged ? 'authorization' : 'revision')
      return copy(result)
    }
    const command = commands[type]
    if (!command) throw fail(400, 'COMMAND_NOT_AVAILABLE', 'A0未开放业务写操作')
    checkSite(actor(), input.siteId)
    const object = command.locate(state, input)
    if (!object || object.siteId !== input.siteId || !can(state, actor(), command.readPermission, object)) throw fail(404, 'OBJECT_NOT_FOUND', '对象不存在或不可见')
    requirePermission(actor(), command.permission, object)
    if (!input.operationId || typeof input.operationId !== 'string' || input.operationId.length > 100) throw fail(400, 'OPERATION_REQUIRED', '操作标识无效')
    const key = JSON.stringify([user.id, type, input.operationId]), fingerprint = JSON.stringify(stable(input))
    const previous = state.idempotency[key]
    if (previous) {
      if (previous.fingerprint !== fingerprint) throw fail(409, 'IDEMPOTENCY_CONFLICT', '相同操作标识不能用于不同内容')
      return copy(previous.result)
    }
    if (!Number.isInteger(input.expectedVersion) || input.expectedVersion !== object.version) throw fail(409, 'VERSION_CONFLICT', '对象已变化，请重新读取')
    const draft = copy(state), before = redact(copy(object))
    const output = command.apply(draft, copy(input), { actorId: user.id, now: new Date().toISOString() })
    if (output?.then) throw fail(400, 'ASYNC_TRANSACTION', '事务处理必须同步完成')
    if (signal?.aborted || epoch !== startEpoch || generation !== contextGeneration) throw new DOMException('提交前已取消', 'AbortError')
    const result = response(output)
    draft.revision++
    draft.audit.push({ id: `audit-${++sequence}`, siteId: input.siteId, areaId: object.areaId, actorName: user.name, action: type, objectId: object.id, occurredAt: new Date().toISOString(), result: 'SUCCESS', requestId: result.requestId, operationId: input.operationId, before, after: redact(copy(command.locate(draft, input))), source: '前端内存本地' })
    draft.idempotency[key] = { fingerprint, result }
    state = draft
    emit('revision')
    return copy(result)
  }
  return {
    query, execute,
    identities: () => copy(state.accounts.filter(a => a.enabled).map(a => ({ id: a.id, name: a.name, description: a.description || '自定义本地身份' }))),
    identity: () => { try { return copy(actor()) } catch { return null } },
    can: (operation, siteId) => { try { return can(state, actor(), operation, { siteId }) } catch { return false } },
    canAny: (operation, siteId) => { try { return hasSite(state, actor(), siteId, operation) } catch { return false } },
    isSystem: () => system(state.accounts.find(a => a.id === storage?.getItem(TOKEN_KEY))),
    login(username, password) {
      // Local-only fixture credential; never a production authentication boundary.
      const account = state.accounts.find(a => (a.loginName === username || a.id === username) && a.enabled)
      if (!account || password !== 'Admin@2026') throw fail(401, 'IDENTITY_INVALID', '账号或密码错误，或账号已停用')
      const id = account.id
      storage.setItem(TOKEN_KEY, id); storage.setItem(SESSION_VERSION_KEY, String(state.accounts.find(a => a.id === id).credentialVersion || 1)); previews.clear(); epoch++; emit('identity'); return copy(actor())
    },
    logout() { clearSession(); epoch++; emit('identity') },
    invalidate() { clearSession(); epoch++; emit('expired') },
    changeContext() { contextGeneration++; emit('context') },
    scenario: () => copy(scenario),
    setScenario(next) {
      if (!['overview', 'details', 'audit', 'authorizationPreview', ...GROUP_QUERIES, ...DEVICE_QUERIES, ...ASSIGNMENT_QUERIES, ...MAINTENANCE_QUERIES, ...Object.keys(ENTITIES)].includes(next.target) || !['normal', 'unavailable', 'failure', 'forbidden'].includes(next.mode)) throw fail(400, 'INVALID_SCENARIO', '场景参数无效')
      scenario = { ...next, delayNext: next.delayNext === true }; contextGeneration++; emit('scenario')
    },
    restoreScenario() { scenario = { target: 'overview', mode: 'normal', delayNext: false }; contextGeneration++; emit('scenario') },
    reset() { state = seed(); scenario = { target: 'overview', mode: 'normal', delayNext: false }; epoch++; contextGeneration++; clearSession(); emit('reset') },
    subscribe(listener) { listeners.add(listener); return () => listeners.delete(listener) }
  }
}
