import { identities, permissionsFor } from './seed.js'
import { equipmentDevice, personEquipment } from './assignment-model.js'
import { failure } from './errors.js'
import { vitalMetrics } from '../utils/vitals-contract.js'
import { capabilityDecision } from '../utils/device-profile.js'

export function seedVitals(dataset) {
  dataset.entities.vitalObservations = []
  for (const a of dataset.relations.assignments.filter(a => a.type === 'WATCH')) {
    const device = dataset.entities.devices.find(d => d.deviceId === a.deviceId)
    const index = Number(a.deviceId.split('-')[2])
    const time = index % 6 === 0 ? null : new Date(Date.parse(dataset.meta.baseTime) - (index % 5 === 0 ? 86400000 : 300000)).toISOString()
    if (index === 7) continue
    for (const [metric, value] of Object.entries({ heartRate: 72, oxygen: index === 8 ? null : 98, temperature: 36.5, bloodPressure: [118, 76] })) {
      dataset.entities.vitalObservations.push({ observationId: `mock-vital-${a.deviceId}-${metric}`, siteId: a.siteId, deviceId: a.deviceId, deviceCode: device.deviceCode, personId: a.personId, personName: dataset.entities.people.find(p => p.personId === a.personId).name, evidenceId: 'mock-observation-proof-' + a.assignmentId, assignmentId: a.assignmentId, metric, value, unit: vitalMetrics[metric].unit, sourceTime: time, receivedAt: dataset.meta.baseTime, freshness: time ? index % 5 === 0 ? 'STALE' : 'FRESH' : 'UNKNOWN', sourceKind: 'MOCK_REQUIREMENT' })
    }
  }
  return dataset
}
export function queryVitals(dataset, role, q) {
  const identity = identities.find(i => i.id === role)
  if (!identity) throw failure(401, '本地会话已失效')
  const validId = v => typeof v === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(v)
  if (!validId(q.siteId) || !!q.personId === !!q.deviceId || Object.keys(q).some(k => !['siteId', 'personId', 'deviceId'].includes(k)) || !validId(q.personId || q.deviceId)) throw failure(400, '体征查询参数无效')
  if (!identity.sites.includes(q.siteId) || !permissionsFor(role).includes('portal:person:read')) throw failure(403, '无权访问该厂站或人员')
  const person = q.personId ? dataset.entities.people.find(p => p.personId === q.personId && p.siteId === q.siteId) : null
  let device = q.deviceId ? dataset.entities.devices.find(d => d.deviceId === q.deviceId && d.siteId === q.siteId) : null
  if (q.personId && !person || q.deviceId && !device) throw failure(404, '对象不存在或不可见')
  const result = (state, items = [], reason = '') => ({ state, scope: { siteId: q.siteId, personId: q.personId || null, deviceId: q.deviceId || null }, items, reason })
  const mode = dataset.config.module === 'vitals' ? dataset.config.mode : 'normal'
  if (mode === 'failure') throw failure(503, '体征预置数据故障', 'SOURCE_UNAVAILABLE')
  if (mode === 'forbidden') return result('FORBIDDEN', [], '当前本地场景无权查看体征')
  if (mode === 'not-integrated') return result('NOT_INTEGRATED')
  if (person) {
    const slot = personEquipment(dataset, person).data.watch
    if (slot.assignmentState === 'UNASSIGNED') return result('NO_WATCH')
    if (slot.assignmentState !== 'ASSIGNED') return result('UNKNOWN')
    device = slot.devices[0]
  }
  if (device.type !== 'WATCH') return result('NOT_INTEGRATED')
  const decision = capabilityDecision(device, 'vitals', { mock: true, permitted: true, moduleEnabled: true })
  if (!decision.allowed) return result('UNKNOWN', [], decision.reason)
  const relation = equipmentDevice(dataset, device).currentAssignment
  const items = dataset.entities.vitalObservations.filter(o => o.siteId === q.siteId && o.deviceId === device.deviceId && (!person || o.personId === person.personId && o.assignmentId === relation?.assignmentId))
  return result(items.length ? 'AVAILABLE' : 'EMPTY', items, person ? '观测仅属于有明确佩戴证据的人员；领用不会生成读数' : '历史预置观测；观测归属不随当前领用关系变化')
}
