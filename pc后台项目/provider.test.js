import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest'

vi.mock('./service', () => ({ createAdminService: vi.fn(() => ({
  setRemoteSave: vi.fn(), setRemoteLogin: vi.fn(), replaceState: vi.fn(),
  logout: vi.fn(), invalidate: vi.fn(), query: vi.fn(),
})) }))

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
  it('sends manual personnel duty updates to the authoritative backend', async () => {
    const sent = []
    vi.stubGlobal('XMLHttpRequest', class {
      status = 200; responseText = '{}'
      open(method, url) { this.method = method; this.url = url }
      setRequestHeader() {}
      send(body) {
        sent.push({ method: this.method, url: this.url, body: body && JSON.parse(body) })
        this.responseText = JSON.stringify(this.method === 'POST' ? { code: 200, data: { dutyStatus: 'OFF_DUTY' } } : { state: {} })
      }
    })
    const input = { siteId: 'site-1', id: 'person-1-0', expectedVersion: 1, operationId: 'manual-off-duty', dutyStatus: 'OFF_DUTY' }
    await expect(provider.execute('people.dutyStatus', input)).resolves.toMatchObject({ data: { dutyStatus: 'OFF_DUTY' } })
    expect(sent[0]).toMatchObject({ method: 'POST', url: '/api/admin/v1/execute', body: { type: 'people.dutyStatus', input } })
    expect(sent[1].url).toBe('/api/admin/v1/state')
  })
  it('does not substitute seed business records when the initial backend connection fails', async () => {
    vi.resetModules()
    vi.stubGlobal('XMLHttpRequest', class {
      status = 0; responseText = ''
      open() {} setRequestHeader() {} send() {}
    })
    const { createAdminService } = await import('./service')
    ;(await import('./provider')).getAdminProvider()
    const initial = createAdminService.mock.calls.at(-1)[0].initialState
    for (const key of ['devices', 'assignments', 'people', 'accounts']) expect(initial[key]).toEqual([])
  })
  it('reads device alarms with the admin session and exact ledger scope', async () => {
    const input = { siteId: 'site-1', id: 'device-13', pageNum: 2, pageSize: 10 }
    const pending = provider.query('deviceEvents', input)
    expect(requests).toHaveLength(1)
    expect(requests[0].url).toBe('/api/admin/v1/query')
    expect(requests[0].options.headers['X-Wearable-Token']).toBe('session-one')
    expect(JSON.parse(requests[0].options.body)).toMatchObject({ kind: 'deviceEvents', input })
    requests[0].resolve(response({ message: '无权查看本设备报警', errorCode: 'PERMISSION_DENIED' }, 403))
    await expect(pending).rejects.toMatchObject({ code: 403, errorCode: 'PERMISSION_DENIED' })
  })
  it('starts devices and audit together without waiting for either response', async () => {
    const devices = provider.query('devices', { siteId: 'site-1' })
    const audit = provider.query('audit', { siteId: 'site-1', pageSize: 5 })
    expect(requests).toHaveLength(2)
    expect(requests.map(r => JSON.parse(r.options.body).kind)).toEqual(['devices', 'audit'])
    requests[1].resolve(response({ data: { rows: [] } }))
    expect(await audit).toEqual({ data: { rows: [] } })
    requests[0].resolve(response({ data: { rows: [], total: 32 } }))
    expect((await devices).data.total).toBe(32)
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
    await expect(provider.query('devices', {}, { signal: controller.signal })).rejects.toMatchObject({ name: 'AbortError' })
    expect(fetch).not.toHaveBeenCalled()
  })
  it('preserves server permission/error details', async () => {
    const pending = provider.query('devices', { siteId: 'site-2' })
    requests[0].resolve(response({ message: '无权查看', errorCode: 'PERMISSION_DENIED', requestId: 'qa-read', fields: { siteId: '无权限' } }, 403))
    await expect(pending).rejects.toMatchObject({ code: 403, message: '无权查看', errorCode: 'PERMISSION_DENIED', requestId: 'qa-read', fields: { siteId: '无权限' } })
  })
  it('invalidates an expired current session', async () => {
    const pending = provider.query('devices', { siteId: 'site-1' })
    requests[0].resolve(response({ message: '登录失效' }, 401))
    await expect(pending).rejects.toMatchObject({ code: 401 })
    expect(storage.getItem('wearable-admin-token')).toBeNull()
    expect(provider.invalidate).toHaveBeenCalledOnce()
  })
  it.each([200, 401])('discards a late %s response from an earlier login', async status => {
    const pending = provider.query('devices', { siteId: 'site-1' })
    storage.setItem('wearable-admin-token', 'session-two')
    requests[0].resolve(response({ data: { counts: { assets: 100 } } }, status))
    await expect(pending).rejects.toMatchObject({ name: 'AbortError' })
    expect(storage.getItem('wearable-admin-token')).toBe('session-two')
    expect(provider.invalidate).not.toHaveBeenCalled()
  })
})
