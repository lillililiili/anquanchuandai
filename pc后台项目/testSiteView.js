import { TEST_SITE, testSiteName } from '../shared/test-site.mjs'

// Query the one authorized site directly so pagination cannot reveal other sites.
export async function readTestSitePage(provider, input, options) {
  const result = await provider.query('record', { entity: 'sites', siteId: TEST_SITE.adminId, id: TEST_SITE.adminId }, options)
  const row = result.data
  const keyword = String(input.keyword || '').trim().toLowerCase()
  const matches = row?.id === TEST_SITE.adminId &&
    (!input.status || row.enabled === (input.status === 'enabled')) &&
    (!keyword || [row.code, row.id, row.name, testSiteName(row)].some(value => String(value || '').toLowerCase().includes(keyword)))
  return { ...result, data: { availability: 'AVAILABLE', total: matches ? 1 : 0, rows: matches && Number(input.pageNum || 1) === 1 ? [row] : [] } }
}
