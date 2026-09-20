import { workSummary, workSection } from './work-model.js'
export const slots = { helmet: 'HELMET', belt: 'BELT', watch: 'WATCH' }
export const slotKey = type => Object.keys(slots).find(key => slots[key] === type)

// One-time conversion: current seed snapshots are NOT issue history.
export function normalizeAssignments(dataset) {
  if (dataset.relations.assignments) return dataset
  dataset.relations.assignments = []
  dataset.operations = {}
  dataset.meta.sequence = 0
  for (const device of dataset.entities.devices) {
    device.version = 1
    device.assignmentEvidence = device.assignmentEvidence === 'KNOWN' ? 'KNOWN' : 'UNKNOWN'
  }
  for (const person of dataset.entities.people) {
    person.slots = {}
    for (const [key, type] of Object.entries(slots)) {
      const snapshot = person.equipment.data[key]
      person.slots[key] = { evidence: snapshot.assignmentState === 'UNKNOWN' ? 'UNKNOWN' : 'KNOWN', version: 1 }
      // Unassigned device evidence is explicit seed metadata, never inferred from an ID.
      for (const d of snapshot.devices) {
        dataset.entities.devices.find(item => item.deviceId === d.deviceId).assignmentEvidence = 'KNOWN'
        dataset.relations.assignments.push({ assignmentId: 'seed-assignment-' + d.deviceId, siteId: person.siteId, personId: person.personId, deviceId: d.deviceId, type, version: 1, state: 'OPEN', startedAt: null, endedAt: null, sourceKind: 'CURRENT_SNAPSHOT_ONLY' })
      }
    }
    delete person.equipment
  }
  for (const video of dataset.entities.videos) delete video.personId
  return dataset
}
export function activeAssignments(dataset, siteId) {
  return dataset.relations.assignments.filter(a => a.siteId === siteId && a.state === 'OPEN')
}
export function personEquipment(dataset, person) {
  const active = activeAssignments(dataset, person.siteId)
  return { state: 'AVAILABLE', data: Object.fromEntries(Object.entries(slots).map(([key, type]) => {
    const links = active.filter(a => a.personId === person.personId && a.type === type)
    const conflicting = links.length > 1 || links.some(a => active.filter(x => x.deviceId === a.deviceId).length > 1)
    const state = conflicting ? 'CONFLICT' : person.slots[key].evidence !== 'KNOWN' ? 'UNKNOWN' : links.length ? 'ASSIGNED' : 'UNASSIGNED'
    return [key, { type, assignmentState: state, version: person.slots[key].version, devices: ['ASSIGNED', 'CONFLICT'].includes(state) ? links.map(a => dataset.entities.devices.find(d => d.deviceId === a.deviceId)) : [] }]
  })) }
}
export function equipmentDevice(dataset, device) {
  const active = activeAssignments(dataset, device.siteId), links = active.filter(a => a.deviceId === device.deviceId)
  const conflict = links.length > 1 || links.some(a => active.filter(x => x.personId === a.personId && x.type === a.type).length > 1)
  const person = links.length === 1 ? dataset.entities.people.find(p => p.personId === links[0].personId && p.siteId === device.siteId) : null
  const state = conflict ? 'CONFLICT' : device.assignmentEvidence !== 'KNOWN' || person?.slots[slotKey(device.type)].evidence === 'UNKNOWN' ? 'UNKNOWN' : links.length ? 'ASSIGNED' : 'UNASSIGNED'
  return { ...device, assignmentState: state, currentAssignment: state === 'ASSIGNED' ? links[0] : null,
    currentPerson: state === 'ASSIGNED' && person ? { personId: person.personId, name: person.name, personCode: person.personCode, siteId: person.siteId } : null }
}
export function projectDataset(dataset) {
  return { ...dataset, entities: { ...dataset.entities,
    people: dataset.entities.people.map(person => ({ ...person, equipment: personEquipment(dataset, person), works: workSection(dataset, dataset.relations.monitoring ? { state: 'AVAILABLE', data: dataset.entities.works.filter(w => w.siteId === person.siteId && dataset.relations.monitoring.some(m => m.workId === w.workId && m.personIds.includes(person.personId))).map(w => workSummary(dataset, w)) } : person.works) })),
    videos: dataset.entities.videos.map(video => {
      const device = equipmentDevice(dataset, dataset.entities.devices.find(d => d.deviceId === video.deviceId))
      return { ...video, model: device.model, profile: device.profile, video: device.capabilities.video, personId: device.currentPerson?.personId || null, assignmentEvidenceId: device.currentAssignment?.assignmentId || null, assignmentTime: device.currentAssignment?.startedAt || null }
    })
  } }
}
