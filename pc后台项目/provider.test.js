import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest'

vi.mock('./service', () => ({ createAdminService: () => ({
  setRemoteSave: vi.fn(), setRemoteLogin: vi.fn(), replaceState: vi.fn(),
  logout: vi.fn(), invalidate: vi.fn(), query: vi.fn(),
}) }))

let provider, storage, requests
const response = (data, status = 200) => ({ status, json: async () => data })
beforeEach(async () => {
  vi.resetModules()
  const values = new Map([['wearable-admin-token', 'session-one'], ['wearable-admin-account', 'demo-system']])
  storage = { getItem: key => values.get(key) ?? null, setItem: (key, value) => values.set(key, value), removeItem: key => values.delete(key) }
  vi.stubGlobal('window', { sessionStorage: storage })
  vi.stubGlobal('XMLHttpRequest', class {
    status = 200; responseText = '{"state":{}}'
    open() {} setRequestHeader() {} send() {}
  })
  requests = []
  vi.stubGlobal('fetch', vi.fn((url, options) => new Promise((resolve, reject) => {
    requests.push({ url, options, resolve, reject })
    options.signal?.addEventListener('abort', () => reject(new DOMException('cancelled', 'AbortError')), { once: true })
  })))
  provider = (await import('./provider')).getAdminProvider()
})
afterEach(() => vi.unstubAllGlobals())

describe('non-blocking admin reads', () => {
  it('starts overview and audit together without waiting for either response', async () => {
    const overview = provider.query('overview', { siteId: 'site-1' })
    const audit = provider.query('audit', { siteId: 'site-1', pageSize: 5 })
    expect(requests).toHaveLength(2)
    expect(requests.map(r => JSON.parse(r.options.body).kind)).toEqual(['overview', 'audit'])
    requests[1].resolve(response({ data: { rows: [] } }))
    expect(await audit).toEqual({ data: { rows: [] } })
    requests[0].resolve(response({ data: { counts: { assets: 32 } } }))
    expect((await overview).data.counts.assets).toBe(32)
  })
  it('cancels the underlying fetch when leaving a page', async () => {
    const controller = new AbortController()
    const pending = provider.query('devices', { siteId: 'site-1' }, { signal: controller.signal })
    const check = expect(pending).rejects.toMatchObject({ name: 'AbortError' })
    controller.abort()
    await check
    expect(requests[0].options.signal.aborted).toBe(true)
  })
  it('does not start already cancelled queries', async () => {
    const controller = new AbortController(); controller.abort()
    await expect(provider.query('overview', {}, { signal: controller.signal })).rejects.toMatchObject({ name: 'AbortError' })
    expect(fetch).not.toHaveBeenCalled()
  })
  it('preserves server permission/error details', async () => {
    const pending = provider.query('overview', { siteId: 'site-2' })
    requests[0].resolve(response({ message: '无权查看', errorCode: 'PERMISSION_DENIED', requestId: 'qa-read', fields: { siteId: '无权限' } }, 403))
    await expect(pending).rejects.toMatchObject({ code: 403, message: '无权查看', errorCode: 'PERMISSION_DENIED', requestId: 'qa-read', fields: { siteId: '无权限' } })
  })
  it('invalidates an expired current session', async () => {
    const pending = provider.query('overview', { siteId: 'site-1' })
    requests[0].resolve(response({ message: '登录失效' }, 401))
    await expect(pending).rejects.toMatchObject({ code: 401 })
    expect(storage.getItem('wearable-admin-token')).toBeNull()
    expect(provider.invalidate).toHaveBeenCalledOnce()
  })
  it.each([200, 401])('discards a late %s response from an earlier login', async status => {
    const pending = provider.query('overview', { siteId: 'site-1' })
    storage.setItem('wearable-admin-token', 'session-two')
    requests[0].resolve(response({ data: { counts: { assets: 100 } } }, status))
    await expect(pending).rejects.toMatchObject({ name: 'AbortError' })
    expect(storage.getItem('wearable-admin-token')).toBe('session-two')
    expect(provider.invalidate).not.toHaveBeenCalled()
  })
})
