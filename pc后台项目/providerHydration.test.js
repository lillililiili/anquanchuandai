import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createSeed, TOKEN_KEY, SESSION_VERSION_KEY } from './seed'

const memory = entries => {
  const values = new Map(entries)
  return { getItem: key => values.get(key) ?? null, setItem: (key, value) => values.set(key, String(value)), removeItem: key => values.delete(key) }
}
let storage, state, snapshot, transport
beforeEach(() => {
  vi.resetModules()
  storage = memory([['wearable-admin-token', 'admin-session'], [TOKEN_KEY, 'demo-system'], [SESSION_VERSION_KEY, '1']])
  const localStorage = memory()
  vi.stubGlobal('localStorage', localStorage)
  vi.stubGlobal('window', { sessionStorage: storage, localStorage })
  state = createSeed()
  state.devices[0].communication = 'OFFLINE'
  state.devices[0].battery = 12
  snapshot = {
    stations: [{ id: 'S1', name: '测试厂站' }],
    devices: [{ id: state.devices[0].portalDeviceId || state.devices[0].code || state.devices[0].id,
      source: 'DIRECT_HELMET', online: true, freshness: 'CURRENT', battery: 83, sourceTime: new Date().toISOString() }],
  }
  vi.stubGlobal('XMLHttpRequest', class {
    status = 200
    responseText = JSON.stringify({ state })
    open() {} setRequestHeader() {} send() {}
  })
  transport = vi.fn(async () => ({ ok: true, status: 200, json: async () => ({ state: snapshot }) }))
  vi.stubGlobal('fetch', transport)
})
afterEach(() => vi.unstubAllGlobals())

describe('real admin provider initialization transport', () => {
  it.each([true, false])('does not hydrate through guardian or mutate state when authenticated=%s', async authenticated => {
    if (!authenticated) storage.removeItem('wearable-admin-token')
    // Import the real service too: mocking its methods would hide inherited hydration.
    const provider = (await import('./provider')).getAdminProvider()
    const before = provider.exportState(), changed = vi.fn()
    provider.subscribe(changed)
    const hydrated = await provider.hydrate()
    expect(transport).not.toHaveBeenCalled()
    expect(hydrated).toBe(false)
    expect(provider.exportState()).toEqual(before)
    expect(changed).not.toHaveBeenCalled()
  })

  it('still loads context and current device telemetry through authenticated admin queries', async () => {
    const provider = (await import('./provider')).getAdminProvider()
    const device = { id: 'current-device', siteId: 'site-1', communication: 'ONLINE', freshness: 'CURRENT', battery: 64 }
    transport.mockImplementation(async (url, options) => {
      expect(url).toBe('/api/admin/v1/query')
      expect(options.headers['X-Wearable-Token']).toBe('admin-session')
      const { kind } = JSON.parse(options.body)
      return { status: 200, json: async () => ({ data: kind === 'context'
        ? { identity: { id: 'demo-system' }, sites: [{ id: 'site-1' }] }
        : { rows: [device], total: 1 } }) }
    })
    await provider.hydrate()
    await expect(provider.query('context')).resolves.toMatchObject({ data: { identity: { id: 'demo-system' } } })
    await expect(provider.query('devices', { siteId: 'site-1' })).resolves.toEqual({ data: { rows: [device], total: 1 } })
    expect(transport).toHaveBeenCalledTimes(2)
  })

  it('preserves explicitly constructed local-service telemetry hydration', async () => {
    const { createAdminService } = await import('./service')
    const local = createAdminService({ storage, initialState: state, delay: 0 }), changed = vi.fn()
    local.subscribe(changed)
    await expect(local.hydrate()).resolves.toBe(true)
    expect(transport).toHaveBeenCalledWith('/api/guardian/v1/snapshot')
    expect(local.exportState().devices[0]).toMatchObject({ communication: 'ONLINE', battery: 83 })
    expect(changed).toHaveBeenCalledWith(expect.objectContaining({ kind: 'revision' }))
  })
})
