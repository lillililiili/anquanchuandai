import { available, missing } from './seed.js'
import { workSummary } from './work-model.js'
import { projectDataset } from './assignment-model.js'
import { distinctEvents } from './statistics-service.js'
export const openPhases = ['UNCLAIMED', 'PROCESSING', 'AWAITING_VERIFICATION']
export function buildWorkbench(dataset, role, siteId) {
  dataset = projectDataset(dataset)
  const scoped = name => dataset.entities[name].filter(x => x.siteId === siteId)
  const people = scoped('people'), events = distinctEvents(scoped('events'))
  const unique = (rows, key) => [...new Map(rows.map(row => [row[key], row])).values()]
  const duty = unique(people.filter(p => p.duty.state === 'AVAILABLE' && p.duty.data.state === 'ON_DUTY'), 'personId')
  const equipment = unique(people.flatMap(p => p.equipment.state === 'AVAILABLE' ? Object.values(p.equipment.data).filter(slot => slot.assignmentState === 'ASSIGNED').flatMap(slot => slot.devices) : []), 'deviceId')
  const open = unique(events.filter(e => openPhases.includes(e.phase)), 'eventId')
  const mine = open.filter(e => e.ownerUserId === 'mock-' + role)
  const wrap = (module, rows) => {
    if (dataset.config.module !== module) return available(rows)
    if (dataset.config.mode === 'not-integrated') return missing()
    if (dataset.config.mode === 'forbidden') return { state: 'FORBIDDEN', data: null }
    if (dataset.config.mode === 'failure') return { state: 'ERROR', data: null, message: '预置数据故障，请恢复场景后重试' }
    return available(rows)
  }
  return { siteId, source: 'MOCK', revision: dataset.meta.businessRevision || 0,
    collaboration: wrap('dispatch', (dataset.relations.dispatch?.sessions || []).filter(s => s.siteId === siteId && s.state === 'ACTIVE').map(s => ({ id: s.id, title: '本地协同进行中', count: s.participants.filter(p => p.state === 'CONNECTED').length, total: s.participants.length }))),
    broadcasts: wrap('dispatch', (dataset.relations.dispatch?.broadcasts || []).filter(b => b.siteId === siteId && b.recipients.some(r => r.state === 'PENDING')).map(b => ({ id: b.id, title: '本地广播待回执', count: b.recipients.filter(r => r.state === 'PENDING').length }))),
    works: wrap('works', scoped('works').map(w => workSummary(dataset, w))), duty: wrap('people', duty), equipment: wrap('people', equipment), open: wrap('events', open),
    mine: role === 'reader' ? { state: 'FORBIDDEN', data: null, message: '当前身份无处置权限' } : wrap('events', mine),
    unknown: wrap('events', events.filter(e => e.phase === 'UNKNOWN')) }
}
