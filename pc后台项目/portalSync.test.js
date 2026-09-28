import { describe, expect, it } from 'vitest'
import { createSeed } from './seed'
import { projectPortal } from './portalSync'

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
  it('keeps an existing helmet binding and its battery', () => {
    const admin = createSeed()
    const remote = snapshot()
    projectPortal(admin, remote)
    const binding = remote.bindings.find(item => item.deviceId === 'RL-H001' && !item.end)
    expect(binding.personId).toBe('P1')
    expect(remote.devices.find(item => item.id === 'RL-H001').battery).toBe(68)
    expect(admin.devices.find(item => item.id === 'RL-H001').communication).toBe('ONLINE')
    expect(admin.devices.find(item => item.id === 'RL-H001').battery).toBe(68)
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
    expect(remote.devices.find(item => item.id === 'RL-H009').online).toBe(false)
    expect(remote.devices.find(item => item.id === 'RL-H001').active).toBe(true)
  })
})
