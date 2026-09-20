import test from 'node:test'
import assert from 'node:assert/strict'
import { personLocation } from '../src/utils/person-location.js'
const person = { personId: 'p1', siteId: 's1', name: '人员1', equipment: { state: 'AVAILABLE', data: { helmet: { assignmentState: 'ASSIGNED', devices: [{ deviceId: 'd1' }] } } } }
const location = { personId: 'p1', siteId: 's1', deviceId: 'd1', attribution: 'CONFIRMED', position: { sourceTime: '2026-09-20T00:00:00Z', longitude: 116, latitude: 39 } }
test('person location requires matching site, person, assignment and confirmed snapshot attribution', () => {
  assert.deepEqual(personLocation(person, [location]).position, location.position)
  for (const change of [{ siteId: 'other' }, { personId: 'p2' }, { deviceId: 'other' }, { attribution: 'UNKNOWN' }]) {
    assert.equal(personLocation(person, [{ ...location, ...change }]).position, null)
  }
  for (const assignmentState of ['UNASSIGNED', 'UNKNOWN', 'CONFLICT']) {
    assert.equal(personLocation({ ...person, equipment: { state: 'AVAILABLE', data: { helmet: { assignmentState, devices: [{ deviceId: 'd1' }] } } } }, [location]).position, null)
  }
})
test('people remain visible without location, and newest confirmed snapshot is selected', () => {
  assert.equal(personLocation(person).id, 'p1')
  assert.equal(personLocation(person, [], 'FORBIDDEN').locationState, 'FORBIDDEN')
  const newer = { ...location, position: { ...location.position, sourceTime: '2026-09-20T01:00:00Z' } }
  assert.deepEqual(personLocation(person, [newer, location]).position, newer.position)
})
