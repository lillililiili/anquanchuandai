import { identities, available } from './seed.js'
import { failure } from './errors.js'
const clone = v => structuredClone(v)
export function eventScope(d, role, input, write = false) {
  const identity = identities.find(i => i.id === role)
  if (!identity) throw failure(401, '本地会话失效')
  if (!identity.sites.includes(input.siteId) || write && role === 'reader') throw failure(403, '当前身份无事件处置权限或厂站不可见')
  const event = d.entities.events.find(e => e.siteId === input.siteId && e.eventId === input.eventId)
  if (!event) throw failure(404, '事件不存在或不可见')
  if (d.config.module === 'events' && d.config.mode !== 'normal') throw failure(d.config.mode === 'forbidden' ? 403 : 503, '事件来源不可用，请恢复场景后重试')
  return event
}
export function eventEditor(d, role, input) {
  const event = eventScope(d, role, input, true)
  const editing = !input.mode || input.mode === 'verification'
  if (editing && d.config.module === 'verifications' && d.config.mode !== 'normal') throw failure(d.config.mode === 'forbidden' ? 403 : 503, '核验分区不可用')
  const draft = editing ? (d.relations.eventDrafts || []).find(r => r.eventId === event.eventId && r.actorId === 'mock-' + role) : null
  if (draft?.evidence.data.length && d.config.module === 'materials' && d.config.mode !== 'normal') throw failure(d.config.mode === 'forbidden' ? 403 : 503, '草稿证据分区不可用')
  return { version: event.version || 1, draft: clone(draft || null), assignees: identities.filter(i => i.id !== 'reader' && i.sites.includes(input.siteId)).map(i => ({ id: 'mock-' + i.id, name: i.name })) }
}
export function eventCommand(d, role, action, input) {
  const event = eventScope(d, role, input, true), actorId = 'mock-' + role
  if (!/^[\w-]{1,128}$/.test(input.operationId || '')) throw failure(400, '操作标识无效')
  const fingerprint = JSON.stringify({ action, ...input })
  d.relations.eventOperations ||= []
  const prev = d.relations.eventOperations.find(o => o.id === input.operationId)
  if (prev) { if (prev.actorId !== actorId || prev.fingerprint !== fingerprint) throw failure(409, '操作标识已用于其他输入'); return { ...clone(prev.result), replayed: true } }
  if (input.expectedVersion !== (event.version || 1)) throw failure(409, '事件版本已变化，请重新读取后操作')
  if (event.phase === 'LOCAL_COMPLETED' && action !== 'receipt') throw failure(409, '已完成本地跟进，不支持重开、转交或再次提交')
  const now = new Date().toISOString(), responsible = event.ownerUserId === actorId
  let title
  if (action === 'claim') {
    if (event.phase !== 'UNCLAIMED' || event.ownerUserId) throw failure(409, '事件已认领或阶段不允许认领')
    event.ownerUserId = actorId; event.phase = 'PROCESSING'; title = '本地认领事件'
  } else if (['transfer', 'verify', 'complete'].includes(action)) {
    if (!responsible) throw failure(403, '仅当前事件负责人可执行此操作')
    if (!['PROCESSING', 'AWAITING_VERIFICATION'].includes(event.phase)) throw failure(409, '当前阶段不可执行此操作')
    if (action === 'transfer') {
      if (!identities.some(i => 'mock-' + i.id === input.assigneeId && i.id !== 'reader' && i.sites.includes(event.siteId)) || input.assigneeId === actorId) throw failure(400, '请选择另一名有厂站权限的预置处置人')
      event.ownerUserId = input.assigneeId; title = '本地转交事件'
    } else if (action === 'verify') {
      if (event.phase !== 'PROCESSING') throw failure(409, '仅处理中事件可转现场核验')
      event.phase = 'AWAITING_VERIFICATION'; title = '本地转现场核验'
    } else {
      const latest = d.relations.verifications.find(r => r.id === event.localLastSubmissionId)
      if (event.phase !== 'AWAITING_VERIFICATION' || !latest || latest.conclusion === 'UNCONFIRMED') throw failure(409, '需要本轮有效已提交核验；无法确认不能完成跟进')
      event.phase = 'LOCAL_COMPLETED'; title = '显式完成本地跟进（非原系统结案）'
    }
  } else if (['draft', 'submit'].includes(action)) {
    if (event.phase !== 'AWAITING_VERIFICATION') throw failure(409, '请先转现场核验')
    if (d.config.module === 'verifications' && d.config.mode !== 'normal') throw failure(d.config.mode === 'forbidden' ? 403 : 503, '核验分区不可用')
    const form = input.form || {}, conclusions = ['COMMUNICATION_ISSUE', 'ACTION_REQUIRED', 'UNCONFIRMED']
    if (form.conclusion && !conclusions.includes(form.conclusion) || typeof form.scene !== 'string' || form.scene.length > 4000 || typeof form.measures !== 'string' || form.measures.length > 4000) throw failure(400, '核验字段无效或超过4000字')
    if (action === 'submit' && (!conclusions.includes(form.conclusion) || !form.scene.trim() || form.conclusion === 'ACTION_REQUIRED' && !form.measures.trim())) throw failure(400, '请选择结论并填写现场情况；需现场处理时必须填写措施')
    if (!Array.isArray(form.evidence) || form.evidence.length > 20 || new Set(form.evidence.map(e => e.id)).size !== form.evidence.length) throw failure(400, '证据最多20份且不能重复')
    if (form.evidence.length && d.config.module === 'materials' && d.config.mode !== 'normal') throw failure(d.config.mode === 'forbidden' ? 403 : 503, '证据资料分区不可用')
    const evidence = form.evidence.map(ref => {
      const m = d.entities.materials.find(m => m.id === ref.id && m.siteId === event.siteId)
      if (!m) throw failure(404, '证据资料不可见')
      if (m.version !== ref.version) throw failure(409, '证据版本已变化，请重新选择')
      return { id: m.id, siteId: m.siteId, name: m.name, type: m.type, version: m.version, digest: m.digest || null, capturedAt: m.capturedAt || null, receivedAt: m.receivedAt || null, attribution: 'MANUAL_MOCK', associationSource: 'MANUAL_MOCK', evidenceId: 'mock-verification-evidence-' + m.id }
    })
    d.relations.eventDrafts ||= []
    const old = d.relations.eventDrafts.find(r => r.eventId === event.eventId && r.actorId === actorId)
    const record = { id: old?.id || 'mock-draft-' + input.operationId, eventId: event.eventId, siteId: event.siteId, actorId, state: 'DRAFT', sourceTime: now, submittedAt: null, conclusion: form.conclusion || null, scene: form.scene, measures: form.measures, evidence: available(evidence), version: (old?.version || 0) + 1 }
    d.relations.eventDrafts = d.relations.eventDrafts.filter(r => r !== old)
    if (action === 'draft') { d.relations.eventDrafts.push(record); title = '保存本地核验草稿（阶段不变）' }
    else {
      record.id = 'mock-verification-' + input.operationId; record.state = 'SUBMITTED'; record.submittedAt = now
      record.version = Math.max(0, ...d.relations.verifications.filter(r => r.eventId === event.eventId).map(r => r.version || 0)) + 1
      d.relations.verifications.unshift(clone(record)); event.localLastSubmissionId = record.id
      d.relations.materialReferences ||= []
      for (const e of evidence) {
        d.entities.materials.find(m => m.id === e.id).frozen = true
        d.relations.materialReferences.push({ ...clone(e), materialId: e.id, eventId: event.eventId, verificationId: record.id, source: 'MANUAL_MOCK', recordedAt: now })
      }
      title = '提交本地核验版本（未自动完成跟进）'
    }
  } else if (action === 'receipt') {
    if (!responsible || !['summary', 'verification'].includes(input.channel) || !['SUCCESS', 'FAILED'].includes(input.result)) throw failure(403, '仅事件负责人记录指定类型的本地回执')
    if (input.channel === 'verification' && !event.localLastSubmissionId) throw failure(409, '暂无本轮已提交核验可记录回执')
    event[input.channel + 'Delivery'] = { state: input.result, sourceTime: now, message: '本地回执，未发送外部系统；不代表结案' }
    title = `本地${input.channel === 'summary' ? '摘要' : '核验'}回执${input.result === 'SUCCESS' ? '成功' : '失败'}（未发送外部系统）`
  } else throw failure(400, '未实现的事件操作')
  event.version = (event.version || 1) + 1; event.localUpdatedAt = now
  d.relations.timeline.unshift({ id: 'mock-action-' + input.operationId, eventId: event.eventId, siteId: event.siteId, actorId, action, title, kind: 'MOCK_LOCAL_ACTION', sequence: Math.max(0, ...d.relations.timeline.filter(t => t.eventId === event.eventId).map(t => t.sequence)) + 1, sourceTime: now, description: '仅前端内存操作，不改变来源事实或原系统状态' })
  const result = { version: event.version, changedEntities: ['events', 'workbench', 'materials'] }
  d.relations.eventOperations.push({ id: input.operationId, actorId, fingerprint, result: clone(result) })
  return result
}
