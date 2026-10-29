import { describe, expect, it } from 'vitest'
import { isSimulatedVital, projectSingleSimulatedWatch } from '../shared/simulated-watch.mjs'

describe('one existing simulated watch in the test site', () => {
  it('recognizes actual reports despite leftover demo flags', () => {
    for (const source of ['PLATFORM', 'device', 'DIRECT_WATCH', '设备上报']) expect(isSimulatedVital({ source, demo: true })).toBe(false)
    expect(isSimulatedVital({ source: 'DEMO_WATCH', demo: true })).toBe(true)
  })
  it('keeps only RL-W001 while preserving original state and real/unknown watch rows', () => {
    const state = {
      devices: [
        { id: 'RL-W001', type: 'WATCH', siteId: 'site-1', source: 'DEMO_WATCH' },
        { id: 'RL-W002', type: 'WATCH', siteId: 'site-1', source: 'DEMO_WATCH' },
        { id: 'RL-W003', type: 'WATCH', siteId: 'site-1', source: 'PLATFORM' },
        { id: 'manual-watch', type: 'WATCH', siteId: 'site-1', source: 'LOCAL' },
      ],
      assignments: [{ deviceId: 'RL-W001' }, { deviceId: 'RL-W002' }, { deviceId: 'RL-W003' }],
    }
    const saved = JSON.stringify(state)
    const projected = projectSingleSimulatedWatch(state)
    expect(projected.devices.map(device => device.id)).toEqual(['RL-W001', 'RL-W003', 'manual-watch'])
    expect(projected.assignments.map(item => item.deviceId)).toEqual(['RL-W001', 'RL-W003'])
    expect(JSON.stringify(state)).toBe(saved)
  })
  it('does not invent a replacement or keep a sample transferred to another site', () => {
    const state = { devices: [{ id: 'RL-W001', type: 'WATCH', siteId: 'site-2', source: 'DEMO_WATCH' }] }
    expect(projectSingleSimulatedWatch(state).devices).toEqual([])
    state.devices[0].source = 'PLATFORM'
    expect(projectSingleSimulatedWatch(state).devices).toEqual(state.devices)
  })
})
