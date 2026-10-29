import { describe, expect, it, vi } from 'vitest'
import { readTestSitePage } from './testSiteView'
import { testSiteChoices } from '../shared/test-site.mjs'

describe('fixed test site views', () => {
  it('keeps authorization boundaries and applies only a display alias', () => {
    const sites = [{ id: 'site-2', name: '别的厂站' }, { id: 'site-1', name: '原厂站', version: 3 }]
    expect(testSiteChoices(sites)).toEqual([{ id: 'site-1', name: '测试厂区', version: 3 }])
    expect(testSiteChoices([sites[0]])).toEqual([])
    expect(sites[1].name).toBe('原厂站')
  })
  it('reads only site-1 and keeps its original name for any later form submission', async () => {
    const row = { id: 'site-1', name: '原厂站', code: '001', enabled: true }
    const provider = { query: vi.fn(async () => ({ data: row })) }
    const controller = new AbortController()
    const result = await readTestSitePage(provider, { keyword: '测试厂区', pageNum: 1 }, { signal: controller.signal })
    expect(provider.query).toHaveBeenCalledWith('record', { entity: 'sites', siteId: 'site-1', id: 'site-1' }, { signal: controller.signal })
    expect(result.data.rows).toEqual([row])
    expect(result.data.rows[0].name).toBe('原厂站')
    expect((await readTestSitePage(provider, { pageNum: 2 })).data).toMatchObject({ total: 1, rows: [] })
    expect((await readTestSitePage(provider, { status: 'disabled' })).data.total).toBe(0)
  })
  it('does not display a different site or replace a denied read with sample data', async () => {
    const provider = { query: vi.fn(async () => ({ data: { id: 'site-2', name: '其他厂站', enabled: true } })) }
    expect((await readTestSitePage(provider, {})).data.rows).toEqual([])
    provider.query.mockRejectedValue(Object.assign(new Error('无权查看'), { code: 403 }))
    await expect(readTestSitePage(provider, {})).rejects.toMatchObject({ code: 403 })
  })
})
