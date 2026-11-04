import { describe, it, expect } from 'vitest'
import { createWorksApi, workEditable, workStatus } from './worksApi'
import { createBusinessConfigApi } from './businessConfigApi'
import { navigationFor, safeTarget } from './navigation'

describe('local work registration API', () => {
  it('reuses the same request ID after an ambiguous failure and keeps the edit version', async () => {
    const calls = []; let fail = true, id = 0
    const api = createWorksApi({ token: () => 'session', makeId: () => `request-${++id}`, fetchImpl: async (url, options) => {
      calls.push({ url, options }); if (fail) { fail = false; throw Error('network') }
      return { ok: true, json: async () => ({ id: 'W1', version: 3 }) }
    } })
    const body = { expectedVersion: 2, name: '检修', members: ['P1'] }
    await expect(api.save('W1', body)).rejects.toThrow('network')
    await expect(api.save('W1', body)).resolves.toEqual({ id: 'W1', version: 3 })
    expect(calls[0].options.body).toBe(calls[1].options.body)
    expect(JSON.parse(calls[1].options.body)).toMatchObject({ expectedVersion: 2, requestId: 'request-1' })
    expect(calls[1].url).toBe('/api/admin/v1/works/W1')
    expect(calls[1].options.method).toBe('PATCH')
  })
  it('keeps query filters encoded, supports global impact count and preserves structured errors', async () => {
    const calls = [], api = createWorksApi({ token: () => '', fetchImpl: async (url, options) => {
      calls.push(url)
      return { ok: false, status: 409, json: async () => ({ message: '人员冲突', errorCode: 'WORK_CONFLICT', fields: { members: '已有进行中作业' } }) }
    } })
    await expect(api.list({ siteId: 'site-1', keyword: '检修 & 检查', status: '', pageNum: 1 })).rejects.toMatchObject({ code: 409, errorCode: 'WORK_CONFLICT', fields: { members: '已有进行中作业' } })
    const query = new URL(calls[0], 'http://local').searchParams
    expect(query.get('keyword')).toBe('检修 & 检查'); expect(query.has('status')).toBe(false)
  })
  it('does not show a result from a previous login', async () => {
    let token = 'one'
    const api = createWorksApi({ token: () => token, fetchImpl: async () => ({ ok: true, json: async () => { token = 'two'; return { rows: [] } } }) })
    await expect(api.list({})).rejects.toMatchObject({ name: 'AbortError' })
  })
  it('updates only the work setting, retaining the shared configuration version', async () => {
    const calls = [], api = createBusinessConfigApi({ token: () => 'session', fetchImpl: async (url, options) => {
      calls.push({ url, options }); return { ok: true, json: async () => ({ workBusinessEnabled: false, simulatedWatchVisible: true, version: 8 }) }
    } })
    expect(await api.configure({ workBusinessEnabled: false }, 7)).toMatchObject({ simulatedWatchVisible: true, version: 8 })
    expect(JSON.parse(calls[0].options.body)).toEqual({ workBusinessEnabled: false, expectedVersion: 7 })
  })
  it('only shows the management entry to the system administrator and preserves its login destination', () => {
    expect(navigationFor({ id: 'demo-system' }).some(item => item.path === '/workbusiness')).toBe(true)
    expect(navigationFor({ id: 'ordinary' }).some(item => item.path === '/workbusiness')).toBe(false)
    expect(navigationFor(null).some(item => item.path === '/workbusiness')).toBe(false)
    expect(safeTarget('/workbusiness?siteId=site-1&token=secret')).toBe('/workbusiness?siteId=site-1')
  })
  it('keeps terminal and imported historical works read only', () => {
    expect(workEditable({ source: 'LOCAL', status: '待开始' })).toBe(true)
    expect(workEditable({ source: 'LOCAL', status: '进行中' })).toBe(true)
    for (const status of ['已结束', '已取消']) expect(workEditable({ source: 'LOCAL', status })).toBe(false)
    expect(workEditable({ source: '工作票', status: '监护中' })).toBe(false)
    expect(workStatus({ status: '监护中' })).toBe('进行中')
  })
})
