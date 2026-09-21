import { can } from './access'
import { emptyEvidence } from './relations'

export const INTEGRATION_QUERIES = ['integrations', 'integration', 'integrationJobs', 'integrationJob', 'integrationSettings']
export const INTEGRATION_COMMANDS = ['integrations.update', 'integrations.test', 'integrations.preview', 'integrations.confirm', 'integrations.retry', 'integrations.receipt', 'integrationSettings.update']
export const INTEGRATION_KINDS = { DEVICE: '设备样本同步', PERSON: '人员样本同步', WORK_TICKET: '工作票样本映射', SAFETY: '安监样本映射', SUMMARY_RETURN: '摘要模拟回传', VERIFICATION_RETURN: '核验模拟回传' }
export const ENDPOINTS = { SAMPLE_A: 'mock://sample-a', SAMPLE_B: 'mock://sample-b' }
const SCENARIOS = ['SUCCESS', 'TIMEOUT', 'FIELD_MISMATCH']
const SOURCE = '本后台合成样本'
const labels = { SUCCESS: '模拟测试通过', TIMEOUT: '模拟超时', FIELD_MISMATCH: '模拟字段不匹配' }

export function extendIntegrations(state) {
  state.integrations = state.sites.flatMap(s => Object.entries(INTEGRATION_KINDS).map(([kind, name]) => ({ id: `integration-${s.id}-${kind}`, siteId: s.id, kind, name, version: 1, status: 'NOT_CONNECTED', credential: 'MOCK-ONLY', endpointKey: 'SAMPLE_A', scenario: null, mappedSiteId: null, areaId: null, attempts: [] })))
  state.integrationJobs = []
  state.integrationSettings = state.sites.map(s => ({ id: `integration-settings-${s.id}`, siteId: s.id, version: 1, defaultScenario: 'SUCCESS' }))
  return state
}
function requireScope(state, actor, siteId, operation, fail) {
  if (!state.sites.some(s => s.id === siteId && s.enabled !== false) || !can(state, actor, operation, { siteId })) throw fail(403, 'PERMISSION_DENIED', '需要本厂站全范围接入权限')
}
function get(state, key, input, fail) {
  const row = (state[key] || []).find(r => r.siteId === input.siteId && r.id === input.id)
  if (!row) throw fail(404, 'OBJECT_NOT_FOUND', '接入对象不存在或不可见')
  return row
}
function publicJob(job) { return Object.fromEntries(Object.entries(job).filter(([key]) => !['targetSnapshot', 'settingsVersion', 'actorSnapshot'].includes(key))) }
function actorSnapshot(state, actor) { return JSON.stringify({ id: actor.id, version: actor.version, roleIds: actor.roleIds, roleScopes: actor.roleScopes, roles: state.roles.filter(r => actor.roleIds.includes(r.id)) }) }
function settingsFor(state, siteId) { return state.integrationSettings.find(s => s.siteId === siteId) }
function canReadJob(state, actor, job) {
  const connector = state.integrations.find(c => c.id === job.connectorId && c.siteId === job.siteId)
  return connector && ['DEVICE', 'PERSON'].includes(connector.kind) && can(state, actor, connector.kind === 'DEVICE' ? 'assets:read' : 'people:read', { siteId: job.siteId })
}
export function queryIntegrations(state, actor, kind, input, { fail, page }) {
  requireScope(state, actor, input.siteId, 'integrations:read', fail)
  if (kind === 'integrationSettings') return settingsFor(state, input.siteId)
  if (kind === 'integration') return { ...get(state, 'integrations', input, fail), areas: state.areas.filter(a => a.siteId === input.siteId && a.enabled !== false), endpoints: ENDPOINTS }
  if (kind === 'integrationJob') {
    const job = get(state, 'integrationJobs', input, fail)
    if (!canReadJob(state, actor, job)) throw fail(404, 'OBJECT_NOT_FOUND', '接入任务不存在或不可见')
    return publicJob(job)
  }
  if (input.connectorId) get(state, 'integrations', { ...input, id: input.connectorId }, fail)
  if (input.status && !['PREVIEW', 'CONFLICT', 'FAILED', 'COMPLETED'].includes(input.status)) throw fail(400, 'INVALID_FILTER', '任务状态筛选无效')
  if (input.keyword != null && (typeof input.keyword !== 'string' || input.keyword.length > 100)) throw fail(400, 'INVALID_KEYWORD', '关键词最多100字')
  const rows = kind === 'integrations' ? state.integrations.filter(c => c.siteId === input.siteId) : state.integrationJobs.filter(j => j.siteId === input.siteId && canReadJob(state, actor, j) && (!input.connectorId || j.connectorId === input.connectorId) && (!input.status || j.status === input.status)).slice().reverse().map(publicJob)
  const keyword = (input.keyword || '').trim().toLowerCase()
  return { availability: 'AVAILABLE', ...page(rows.filter(r => `${r.id} ${r.name || ''} ${r.source || ''} ${r.connectorId || ''}`.toLowerCase().includes(keyword)), { ...input, keyword: '' }) }
}
export function authorizeIntegration(state, actor, type, input, fail) {
  requireScope(state, actor, input.siteId, 'integrations:read', fail)
  requireScope(state, actor, input.siteId, 'integrations:write', fail)
  const key = type === 'integrationSettings.update' ? 'integrationSettings' : ['integrations.confirm', 'integrations.retry'].includes(type) ? 'integrationJobs' : 'integrations'
  const row = get(state, key, input, fail)
  const connector = key === 'integrationJobs' ? get(state, 'integrations', { ...input, id: row.connectorId }, fail) : row
  if (['integrations.preview', 'integrations.confirm', 'integrations.retry'].includes(type)) {
    if (!['DEVICE', 'PERSON'].includes(connector.kind)) throw fail(400, 'COMMAND_NOT_AVAILABLE', '本连接器仅提供映射与模拟回执')
    requireScope(state, actor, input.siteId, connector.kind === 'DEVICE' ? 'assets:write' : 'people:write', fail)
    requireScope(state, actor, input.siteId, connector.kind === 'DEVICE' ? 'assets:read' : 'people:read', fail)
    if (key === 'integrationJobs' && row.createdBy !== actor.id) throw fail(403, 'TASK_ACTOR_REQUIRED', '仅预览任务创建人可继续此任务')
  }
  return key === 'integrationJobs' ? publicJob(row) : row
}
function samples(c) {
  if (c.kind === 'DEVICE') {
    const station = c.siteId === 'site-2' ? 2 : c.siteId === 'site-1' ? 1 : 'empty'
    return [{ sourceId: 'device-001', name: '来源安全帽样本', manufacturer: '预置厂商（非真实厂家）', sn: `EQ-SN-EQ-${station}-001`, type: 'HELMET' }, { sourceId: 'device-002', name: '来源安全带样本', manufacturer: '合成样本厂商', sn: `SAMPLE-${c.siteId}-BELT-002`, type: 'BELT' }]
  }
  return ['person-001', 'person-002'].map(sourceId => ({ sourceId, name: '同名演示人员', sourceSystem: 'MOCK_PERSON', sourcePersonId: `${c.siteId}-${sourceId}` }))
}
function sourceFields(c, sample) {
  return { sourceName: sample.name, sourceSystem: sample.sourceSystem || 'MOCK_DEVICE', sourcePersonId: sample.sourcePersonId || null, sourceId: sample.sourceId, sourceConnectorId: c.id, source: SOURCE }
}
const identityPart = value => typeof value === 'string' ? value.trim().toLowerCase() : ''
function identity(c, row, sample) { return c.kind === 'DEVICE' ? identityPart(row.manufacturer) === identityPart(sample.manufacturer) && identityPart(row.sn) === identityPart(sample.sn) : row.sourceSystem === sample.sourceSystem && row.sourcePersonId === sample.sourcePersonId }
function targets(state, c) { return c.kind === 'DEVICE' ? state.devices : state.people }
// Snapshot all identities to detect a concurrent duplicate, and complete local records to protect local changes.
// Kept private: never project another site's IDs or identity values through a job response.
function targetSnapshot(state, c) {
  return JSON.stringify({ targets: targets(state, c).map(r => r.siteId === c.siteId ? r : c.kind === 'DEVICE' ? { manufacturer: r.manufacturer, sn: r.sn } : { sourceSystem: r.sourceSystem, sourcePersonId: r.sourcePersonId }), assignments: c.kind === 'DEVICE' ? state.assignments.filter(a => a.siteId === c.siteId) : [], area: state.areas.find(a => a.id === c.areaId), site: state.sites.find(s => s.id === c.siteId) })
}
function mappingValid(state, c) { return c.mappedSiteId === c.siteId && (!c.areaId || state.areas.some(a => a.id === c.areaId && a.siteId === c.siteId && a.enabled !== false)) }
function scenarioFor(state, c) { return c.scenario || settingsFor(state, c.siteId).defaultScenario }
function buildPreview(state, actor, c, job, now) {
  const scenario = scenarioFor(state, c), mapped = mappingValid(state, c)
  const rows = samples(c).map(sample => {
    const matches = targets(state, c).filter(r => identity(c, r, sample))
    const collision = matches.length > 1 || matches.some(r => r.siteId !== c.siteId)
    const target = !collision && matches[0]
    const reason = !mapped ? '请配置本厂站映射及有效区域' : collision ? '来源身份冲突，需核实后重新预览' : scenario === 'FIELD_MISMATCH' ? '合成样本字段不匹配' : ''
    const unchanged = target && Object.entries(sourceFields(c, sample)).every(([key, value]) => target[key] === value)
    return { sourceId: sample.sourceId, name: sample.name, action: reason ? 'CONFLICT' : target ? unchanged ? 'SKIP' : 'UPDATE' : 'CREATE', targetId: target?.id || null, reason }
  })
  const counts = { created: 0, updated: 0, skipped: 0, conflicts: 0 }
  rows.forEach(r => counts[{ CREATE: 'created', UPDATE: 'updated', SKIP: 'skipped', CONFLICT: 'conflicts' }[r.action]]++)
  Object.assign(job, { configVersion: c.version, settingsVersion: settingsFor(state, c.siteId).version, actorSnapshot: actorSnapshot(state, actor), targetRevision: state.revision, targetSnapshot: targetSnapshot(state, c), rows, counts, status: scenario === 'TIMEOUT' ? 'FAILED' : counts.conflicts ? 'CONFLICT' : 'PREVIEW', source: SOURCE })
  job.attempts.push({ at: now, result: job.status, scenario, configVersion: c.version })
  return publicJob(job)
}
export function applyIntegration(state, actor, type, input, { fail, now }) {
  const authorized = authorizeIntegration(state, actor, type, input, fail)
  const row = ['integrations.confirm', 'integrations.retry'].includes(type) ? get(state, 'integrationJobs', input, fail) : authorized
  const config = ['endpointKey', 'mappedSiteId', 'areaId', 'scenario']
  const allowed = ['siteId', 'id', 'operationId', 'expectedVersion', ...(type === 'integrations.update' ? config : type === 'integrationSettings.update' ? ['defaultScenario'] : [])]
  if (Object.keys(input).some(k => !allowed.includes(k))) throw fail(400, 'FIELD_NOT_ALLOWED', '仅接受受控样本配置，不接受真实地址、密钥或任意字段')
  if (input.expectedVersion !== row.version) throw fail(409, 'VERSION_CONFLICT', '配置或任务已变化，请重新读取')
  const invalid = (field, message) => { throw Object.assign(fail(400, 'VALIDATION_ERROR', message), { fields: { [field]: message } }) }
  if (type === 'integrationSettings.update') {
    if (!SCENARIOS.includes(input.defaultScenario)) invalid('defaultScenario', '请选择演示结果')
    row.defaultScenario = input.defaultScenario; row.version++; return row
  }
  if (type === 'integrations.update') {
    const next = { ...row, ...Object.fromEntries(config.filter(k => Object.hasOwn(input, k)).map(k => [k, input[k]])) }
    if (!Object.hasOwn(ENDPOINTS, next.endpointKey)) invalid('endpointKey', '请选择演示地址')
    if (next.scenario !== null && !SCENARIOS.includes(next.scenario)) invalid('scenario', '请选择确定性场景或使用厂站默认值')
    if (next.mappedSiteId !== null && next.mappedSiteId !== row.siteId) invalid('mappedSiteId', '只能映射至当前授权厂站')
    if (next.areaId !== null && !state.areas.some(a => a.id === next.areaId && a.siteId === row.siteId && a.enabled !== false)) invalid('areaId', '请选择本厂站启用区域')
    Object.assign(row, next); row.version++; return row
  }
  if (['integrations.test', 'integrations.receipt'].includes(type)) {
    if (type === 'integrations.receipt' && ['DEVICE', 'PERSON'].includes(row.kind)) throw fail(400, 'COMMAND_NOT_AVAILABLE', '设备与人员使用预览确认同步')
    const receipt = type === 'integrations.receipt', result = scenarioFor(state, row)
    const attempt = { at: now, result, label: receipt && result === 'SUCCESS' ? '模拟回执成功（不代表发送或结案）' : labels[result], configVersion: row.version, source: SOURCE, operation: receipt ? 'RECEIPT' : 'TEST' }
    row.attempts.push(attempt); row[receipt ? 'lastReceipt' : 'lastTest'] = attempt; row.version++; return row
  }
  if (type === 'integrations.preview') {
    const job = { id: `integration-job-${state.nextId++}`, connectorId: row.id, siteId: row.siteId, version: 1, createdBy: actor.id, createdAt: now, attempts: [] }
    state.integrationJobs.push(job); return buildPreview(state, actor, row, job, now)
  }
  const c = get(state, 'integrations', { ...input, id: row.connectorId }, fail)
  if (type === 'integrations.retry') {
    if (!['FAILED', 'CONFLICT'].includes(row.status)) throw fail(409, 'TASK_STATE_CONFLICT', '只有失败或冲突任务可重试')
    row.version++; return buildPreview(state, actor, c, row, now)
  }
  if (row.status !== 'PREVIEW') throw fail(409, 'TASK_STATE_CONFLICT', '请先获得无冲突的预览，已完成任务无需重复确认')
  if (c.version !== row.configVersion || settingsFor(state, c.siteId).version !== row.settingsVersion || row.targetSnapshot !== targetSnapshot(state, c) || row.actorSnapshot !== actorSnapshot(state, actor)) throw fail(409, 'VERSION_CONFLICT', '配置、目标资料或账号授权已变化，请重新预览')
  for (const item of row.rows) {
    const sample = samples(c).find(s => s.sourceId === item.sourceId), fields = sourceFields(c, sample)
    if (item.action === 'UPDATE') { const target = targets(state, c).find(r => r.id === item.targetId); Object.assign(target, fields); target.version++ }
    if (item.action === 'CREATE') {
      const id = `${c.kind === 'DEVICE' ? 'device' : 'person'}-integration-${state.nextId++}`
      const base = { id, siteId: c.siteId, areaId: c.areaId, code: `MOCK-${id}`, name: sample.name, version: 1, remark: '', ...fields }
      const entity = c.kind === 'DEVICE' ? { ...base, manufacturer: sample.manufacturer, sn: sample.sn, type: sample.type, modelId: `unknown-${sample.type}`, lifecycle: 'STOCK', relation: 'UNASSIGNED', communication: 'NOT_CONNECTED', freshness: 'UNKNOWN', sourceTime: null, connection: 'NOT_CONNECTED', verification: 'UNCONFIRMED', capability: 'UNCONFIRMED', capabilitySource: SOURCE, assemblies: {}, assetCode: '', purchasedOn: '' } : { ...base, organizationId: null, accountId: null, enabled: true, equipmentEvidence: emptyEvidence() }
      targets(state, c).push(entity); item.targetId = id
    }
  }
  row.status = 'COMPLETED'; row.version++; row.completedAt = now; row.attempts.push({ at: now, result: 'COMPLETED', configVersion: c.version }); return publicJob(row)
}
