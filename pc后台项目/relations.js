import { can } from './access'
export const TYPES = ['HELMET', 'BELT', 'WATCH']
export const emptyEvidence = () => Object.fromEntries(TYPES.map(t => [t, 'COMPLETE']))
export function relationship(state, device) {
  const links = state.assignments.filter(a => a.active && a.deviceId === device.id)
  if (device.relation === 'CONFLICT' || links.length > 1) return { state: 'CONFLICT', person: null }
  if (device.relation === 'UNKNOWN') return { state: 'UNKNOWN', person: null }
  if (device.relation === 'UNASSIGNED' && links.length === 0 && device.lifecycle !== 'IN_USE') return { state: 'UNASSIGNED', person: null }
  const person = links.length === 1 && state.people.find(p => p.id === links[0].personId && p.siteId === device.siteId)
  const sameType = person && state.assignments.filter(a => a.active && a.personId === person.id && state.devices.some(d => d.id === a.deviceId && d.type === device.type))
  if (device.relation === 'ASSIGNED' && device.lifecycle === 'IN_USE' && person && sameType.length === 1) return { state: 'ASSIGNED', person, assignment: links[0] }
  return { state: 'CONFLICT', person: null }
}
export function personSlots(state, actor, person) {
  return Object.fromEntries(TYPES.map(type => {
    const links = state.assignments.filter(a => a.active && a.personId === person.id && state.devices.some(d => d.id === a.deviceId && d.type === type))
    let status = person.equipmentEvidence?.[type] === 'COMPLETE' ? 'UNASSIGNED' : 'UNKNOWN'
    if (links.length) {
      status = links.length === 1 ? 'ASSIGNED' : 'CONFLICT'
      for (const a of links) {
        const d = state.devices.find(d => d.id === a.deviceId)
        if (relationship(state, d).state !== 'ASSIGNED') status = 'CONFLICT'
        if (!can(state, actor, 'assets:read', d)) { status = 'UNAVAILABLE'; break }
      }
    }
    // An orphan binding cannot be interpreted as an empty slot.
    if (state.assignments.some(a => a.active && a.personId === person.id && !state.devices.some(d => d.id === a.deviceId))) status = 'UNKNOWN'
    return [type, status]
  }))
}
