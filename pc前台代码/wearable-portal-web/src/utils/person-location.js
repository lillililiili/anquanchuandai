// A device snapshot can represent a person only when both sources confirm the association.
export function personLocation(person, locations = [], locationState = 'AVAILABLE') {
  const devices = person.equipment?.state === 'AVAILABLE'
    ? Object.values(person.equipment.data).filter(slot => slot.assignmentState === 'ASSIGNED').flatMap(slot => slot.devices)
    : []
  const location = locations.filter(item => item.siteId === person.siteId && item.personId === person.personId && item.attribution === 'CONFIRMED' && devices.some(device => device.deviceId === item.deviceId))
    .sort((a, b) => (Date.parse(b.position?.sourceTime) || 0) - (Date.parse(a.position?.sourceTime) || 0))[0]
  return { ...person, id: person.personId, personName: person.name, locationState, position: location?.position || null, deviceId: location?.deviceId, deviceCode: location?.deviceCode, communication: location?.communication }
}
