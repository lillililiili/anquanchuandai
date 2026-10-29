import { describe, expect, it } from 'vitest'
import { createSeed } from './seed'
import { projectPortal, applyTelemetry } from './portalSync'

function snapshot() {
  return {
    version: 1,
    seq: 100,
    stations: [{ id: 'S1', name: '临江示范电厂' }, { id: 'S2', name: '北江示范电厂' }],
    people: [{ id: 'P1', name: '陈建国', team: '维护一班', station: 'S1', active: true, area: '锅炉区', position: [36, 37], locationValid: true }],
    devices: [{ id: 'RL-H001', type: 'H', station: 'S1', active: true, online: true, battery: 68, video: 'available', updated: '2026-09-15 10:39:00' }],
    bindings: [{ id: 'BIND0', deviceId: 'RL-H001', personId: 'P1', start: '2026-09-15 08:00:00', end: null, operator: '赵晓东' }],
  }
}

describe('portal projection', () => {
  it('projects manual duty without ending held equipment or disabling the person', () => {
    const admin = createSeed(), remote = snapshot()
    const person = admin.people.find(row => row.id === 'person-1-0')
    Object.assign(person, { dutyStatus: 'OFF_DUTY', dutyStatusSource: 'MANUAL', dutyStatusUpdatedBy: '管理员', dutyStatusUpdatedAt: '2026-10-27T08:00:00Z' })
    projectPortal(admin, remote)
    expect(remote.people.find(row => row.id === 'P1')).toMatchObject({ active: true, dutyStatus: 'OFF_DUTY', dutyStatusSource: 'MANUAL', dutyStatusUpdatedBy: '管理员', dutyStatusUpdatedAt: person.dutyStatusUpdatedAt })
    expect(remote.bindings.find(row => row.id === 'BIND0').end).toBeNull()
    person.dutyStatus = 'ON_DUTY'
    projectPortal(admin, remote)
    expect(remote.people.find(row => row.id === 'P1')).toMatchObject({ active: true, dutyStatus: 'ON_DUTY' })
    delete person.dutyStatus
    projectPortal(admin, remote)
    expect(remote.people.find(row => row.id === 'P1').dutyStatus).toBe('UNKNOWN')
    expect(remote.bindings.find(row => row.id === 'BIND0').end).toBeNull()
  })
  it('direct helmet stale or missing telemetry remains unknown instead of offline/current', () => {
    const admin = { devices: [{ id: 'device-1', portalDeviceId: 'direct-1' }] }
    const direct = { id: 'direct-1', source: 'DIRECT_HELMET', freshness: 'CURRENT', updated: new Date(Date.now() - 1000).toISOString(), online: true, battery: 70 }
    applyTelemetry(admin, { devices: [direct] })
    expect(admin.devices[0]).toMatchObject({ communication: 'ONLINE', freshness: 'CURRENT', battery: 70 })
    applyTelemetry(admin, { devices: [{ ...direct, freshness: 'STALE' }] })
    expect(admin.devices[0]).toMatchObject({ communication: 'UNKNOWN', freshness: 'STALE', battery: null })
    applyTelemetry(admin, { devices: [{ ...direct, updated: null, online: null }] })
    expect(admin.devices[0]).toMatchObject({ communication: 'UNKNOWN', freshness: 'UNKNOWN', battery: null })
    applyTelemetry(admin, { devices: [{ ...direct, freshness: 'STALE', online: false }] })
    expect(admin.devices[0]).toMatchObject({ communication: 'OFFLINE', freshness: 'STALE', battery: null })
  })
  it('keeps an existing helmet binding but never promotes preset telemetry to a real report', () => {
    const admin = createSeed()
    const remote = snapshot()
    remote.mapAreas = [{ id: 'legacy-area', station: 'S1', points: [[0, 0], [1, 0], [0, 1]] }]
    projectPortal(admin, remote)
    expect(remote.mapAreas).toEqual([])
    expect(remote.people.find(item => item.id === 'P1')).not.toHaveProperty('area')
    expect(remote.people.find(item => item.id === 'P1').position).toEqual([36, 37])
    const binding = remote.bindings.find(item => item.deviceId === 'RL-H001' && !item.end)
    expect(binding.personId).toBe('P1')
    expect(remote.devices.find(item => item.id === 'RL-H001').battery).toBe(68)
    expect(admin.devices.find(item => item.id === 'RL-H001').communication).toBe('NOT_CONNECTED')
    expect(admin.devices.find(item => item.id === 'RL-H001').battery).toBeNull()
  })
  it('moves a returned helmet off the open binding and issues a stock helmet', () => {
    const admin = createSeed()
    const helmet = admin.devices.find(item => item.id === 'RL-H001')
    const stock = admin.devices.find(item => item.id === 'RL-H009')
    const current = admin.assignments.find(item => item.active && item.deviceId === 'RL-H001')
    current.active = false
    helmet.lifecycle = 'STOCK'
    helmet.relation = 'UNASSIGNED'
    stock.lifecycle = 'IN_USE'
    stock.relation = 'ASSIGNED'
    admin.assignments.push({ id: 'assignment-RL-H009', deviceId: 'RL-H009', personId: 'person-1-0', siteId: 'site-1', active: true, startedAt: '2026-09-15T01:00:00.000Z', version: 1 })
    const remote = snapshot()
    projectPortal(admin, remote)
    expect(remote.bindings.find(item => item.id === 'BIND0').end).toBeTruthy()
    const open = remote.bindings.find(item => item.deviceId === 'RL-H009' && !item.end)
    expect(open.personId).toBe('P1')
    expect(remote.devices.find(item => item.id === 'RL-H009')).toMatchObject({ online: null, video: 'unavailable', updated: null })
    expect(remote.devices.find(item => item.id === 'RL-H001').active).toBe(true)
  })
  it('direct belt freshness is checked and simulated watches are not live readings', () => {
    const admin = { devices: [{ id: 'belt' }, { id: 'watch' }] }
    applyTelemetry(admin, { devices: [
      { id: 'belt', type: 'B', source: 'DIRECT_BELT', freshness: 'CURRENT', online: true, battery: 88, sourceTime: new Date(Date.now() - 600000).toISOString() },
      { id: 'watch', type: 'W', source: 'DEMO_WATCH', online: true, battery: 99 },
    ] })
    expect(admin.devices[0]).toMatchObject({ communication: 'UNKNOWN', freshness: 'STALE', battery: null })
    expect(admin.devices[1]).toMatchObject({ source: 'DEMO_WATCH', communication: 'UNKNOWN', battery: null })
  })
})
