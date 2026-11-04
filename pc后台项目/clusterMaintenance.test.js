import { describe, it, expect } from 'vitest'
import { maintenancePresentation } from './clusterMaintenance'
import { createBusinessConfigApi } from './businessConfigApi'
describe('cluster maintenance', () => {
  it('never reports drained while any result is unknown', () => {
    expect(maintenancePresentation({ paused: true, quiescent: true, unknown: 1 }).title).toBe('已暂停 · 结果待核对')
    expect(maintenancePresentation({ paused: true, quiescent: false, activeWrites: 2 }).title).toBe('已暂停 · 正在排空')
    expect(maintenancePresentation({ paused: true, quiescent: true }).title).toBe('已暂停 · 已排空')
    expect(maintenancePresentation({ paused: false }).title).toBe('正常运行')
  })
  it('reads and changes only the authorized global maintenance API', async () => {
    const calls = [], api = createBusinessConfigApi({ token: () => 'fixture', fetchImpl: async (url, options) => { calls.push({ url, options }); return { ok: true, json: async () => ({ paused: true, quiescent: false }) } } })
    await api.maintenance(); const state = await api.setMaintenance(true); await api.setMaintenance(false)
    expect(calls.every(c => c.url === '/api/admin/v1/maintenance')).toBe(true)
    expect(JSON.parse(calls[1].options.body)).toEqual({ mode: 'PAUSED' }); expect(JSON.parse(calls[2].options.body)).toEqual({ mode: 'ACTIVE' })
    expect(state.quiescent).toBe(false)
  })
})
