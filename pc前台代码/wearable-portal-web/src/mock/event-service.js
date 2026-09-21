import { identities } from './seed.js'
import { failure } from './errors.js'
export function eventScope(d, role, input, write = false) {
  const identity = identities.find(i => i.id === role)
  if (!identity) throw failure(401, '本地会话失效')
  if (!identity.sites.includes(input.siteId) || write && role === 'reader') throw failure(403, '无告警处理权限或厂站不可见')
  const event = d.entities.events.find(e => e.siteId === input.siteId && e.eventId === input.eventId)
  if (!event) throw failure(404, '告警不存在或不可见')
  if (d.config.module === 'events' && d.config.mode !== 'normal') throw failure(d.config.mode === 'forbidden' ? 403 : 503, '告警来源不可用，请恢复场景后重试')
  return event
}
export function eventCommand(d, role, action, input) {
  const event = eventScope(d, role, input, true), actor = identities.find(i => i.id === role)
  if (action !== 'handle') throw failure(400, '仅支持处理告警')
  if (!/^[\w-]{1,128}$/.test(input.operationId || '')) throw failure(400, '操作标识无效')
  const note = typeof input.description === 'string' ? input.description.trim() : ''
  if (!note || [...note].length > 1000) throw failure(400, '处理说明须为1—1000字')
  const fingerprint = JSON.stringify({ action, ...input }), actorId = 'mock-' + role
  const prev = (d.relations.eventOperations || []).find(o => o.id === input.operationId)
  if (prev) {
    if (prev.actorId !== actorId || prev.fingerprint !== fingerprint) throw failure(409, '操作标识已用于其他输入')
    return { ...structuredClone(prev.result), replayed: true }
  }
  if (input.expectedVersion !== event.version || event.handlingStatus !== 'UNHANDLED') throw failure(409, '告警已变化或已处理，请重新读取后操作')
  const now = new Date().toISOString()
  event.handlingStatus = 'HANDLED'; event.handlingNote = note
  event.handledAt = now; event.handledBy = { id: actorId, name: actor.name }; event.version++
  d.relations.timeline.unshift({ id: 'mock-handle-' + input.operationId, siteId: event.siteId, eventId: event.eventId, actorId, action: 'handle', title: '处理告警', description: note, sourceTime: now, kind: 'MOCK_LOCAL_ACTION', sequence: Math.max(0, ...d.relations.timeline.filter(t => t.eventId === event.eventId).map(t => t.sequence)) + 1 })
  const result = { version: event.version, changedEntities: ['events', 'workbench', 'works', 'dispatch', 'statistics'] }
  d.relations.eventOperations ||= []
  d.relations.eventOperations.push({ id: input.operationId, actorId, fingerprint, result: structuredClone(result) })
  return result
}
