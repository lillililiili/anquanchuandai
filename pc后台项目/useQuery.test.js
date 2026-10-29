import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useQuery } from './useQuery'

const state = vi.hoisted(() => ({ requests: [], invalidate: vi.fn() }))
vi.mock('vue', async importOriginal => ({ ...await importOriginal(), onBeforeUnmount: vi.fn() }))
vi.mock('@admin-provider', () => ({ getAdminProvider: () => ({
  query: (kind, input, options) => new Promise((resolve, reject) => state.requests.push({ kind, input, options, resolve, reject })),
  invalidate: state.invalidate,
}) }))

beforeEach(() => { state.requests = []; state.invalidate.mockClear() })

async function initial(query, input = { siteId: 'site-1', id: 'device-13' }) {
  const pending = query.run('device', input)
  state.requests.at(-1).resolve({ data: { id: input.id, siteId: input.siteId, hangerAStatus: '0' } })
  await pending
}

describe('background reads preserve mounted detail content', () => {
  it('keeps current content and its loading boundary while refreshing the same device', async () => {
    const query = useQuery()
    await initial(query)
    const original = query.data.value
    const pending = query.run('device', { siteId: 'site-1', id: 'device-13' }, { background: true })
    expect(query.data.value).toBe(original)
    expect(query.loading.value).toBe(false)
    expect(query.refreshing.value).toBe(true)
    state.requests.at(-1).resolve({ data: { ...original, hangerAStatus: '1' } })
    await pending
    expect(query.data.value.hangerAStatus).toBe('1')
    expect(query.loading.value).toBe(false)
    expect(query.refreshing.value).toBe(false)
  })

  it.each([
    ['device', { siteId: 'site-2', id: 'device-13' }],
    ['device', { siteId: 'site-1', id: 'device-14' }],
    ['deviceEvents', { siteId: 'site-1', id: 'device-13', pageNum: 2 }],
  ])('clears old scope when query or identity changes', async (kind, input) => {
    const query = useQuery()
    await initial(query)
    const pending = query.run(kind, input, { background: true })
    expect(query.data.value).toBeNull()
    expect(query.loading.value).toBe(true)
    state.requests.at(-1).resolve({ data: { rows: [] } })
    await pending
  })

  it('discards a previous device refresh arriving after navigation', async () => {
    const query = useQuery()
    await initial(query)
    const old = query.run('device', { siteId: 'site-1', id: 'device-13' }, { background: true })
    const oldRequest = state.requests.at(-1)
    const next = query.run('device', { siteId: 'site-1', id: 'device-14' })
    expect(oldRequest.options.signal.aborted).toBe(true)
    oldRequest.resolve({ data: { id: 'device-13' } })
    await old
    expect(query.data.value).toBeNull()
    state.requests.at(-1).resolve({ data: { id: 'device-14' } })
    await next
    expect(query.data.value.id).toBe('device-14')
  })

  it.each([401, 403, 503])('removes retained data when refresh fails with %s', async code => {
    const query = useQuery()
    await initial(query)
    const pending = query.run('device', { siteId: 'site-1', id: 'device-13' }, { background: true })
    state.requests.at(-1).reject(Object.assign(new Error('read failed'), { code }))
    await pending
    expect(query.data.value).toBeNull()
    expect(query.error.value.code).toBe(code)
    expect(query.refreshing.value).toBe(false)
    expect(state.invalidate).toHaveBeenCalledTimes(code === 401 ? 1 : 0)
  })
})
