import { describe, expect, it } from 'vitest'
import { DEFAULT_ADMIN_PATH, MENU, WORKSPACES, safeTarget, menuPath, deviceReturn, peopleReturn, assignmentReturn, recordReturn, cleanQuery } from './navigation'

describe('short administration URLs', () => {
  it('uses one route segment for every menu and workspace destination', () => {
    expect(DEFAULT_ADMIN_PATH).toBe('/devices')
    for (const item of [...MENU, ...WORKSPACES]) expect(item.path).toMatch(/^\/[a-z]+$/)
  })

  it.each([
    ['/admin/assets/devices', '/devices'],
    ['/admin/assets/assignments', '/assignments'],
    ['/admin/people', '/people'],
    ['/admin/sites', '/sites'],
    ['/admin/duty', '/duty'],
    ['/admin/access/accounts', '/accounts'],
    ['/admin/access/roles', '/roles'],
    ['/admin/audit', '/audit'],
  ])('normalizes %s and its safe query to %s', (legacy, canonical) => {
    const query = '?siteId=site-1&pageNum=2&token=secret&redirect=https%3A%2F%2Fevil.invalid'
    expect(safeTarget(legacy + query)).toBe(canonical + '?siteId=site-1&pageNum=2')
    expect(safeTarget(canonical + query)).toBe(canonical + '?siteId=site-1&pageNum=2')
    expect(menuPath(legacy)).toBe(menuPath(canonical))
  })

  it('combines personnel and organization into one workspace destination', () => {
    expect(WORKSPACES.find(item => item.path === '/people')).toMatchObject({ title: '人员与组织', entity: 'people' })
    expect(WORKSPACES.some(item => item.path === '/organization' || item.entity === 'organizations')).toBe(false)
  })

  it.each(['/organization', '/admin/organization', '/organization/', '/admin/organization/'])('converts an old organization selection from %s without opening a person', path => {
    const source = path + '?siteId=site-1&selectedId=org-19007199254740993001&keyword=old&pageNum=3&status=disabled&token=secret'
    const expected = '/people?siteId=site-1&organizationId=org-19007199254740993001'
    expect(safeTarget(source)).toBe(expected)
    expect(peopleReturn(source)).toBe(expected)
    expect(recordReturn(source, '/people')).toBe(expected)
    expect(menuPath(path)).toBe('/people')
  })

  it('prefers a valid organization filter and discards invalid legacy identifiers', () => {
    expect(safeTarget('/organization?siteId=site-1&organizationId=current-org&selectedId=old-org')).toBe('/people?siteId=site-1&organizationId=current-org')
    expect(safeTarget('/admin/organization?organizationId=..%2Fbad&selectedId=valid-org')).toBe('/people?organizationId=valid-org')
    expect(safeTarget('/organization?siteId=..%2Fbad&selectedId=https%3A%2F%2Fevil.invalid')).toBe('/people')
    expect(safeTarget('/people?siteId=site-1&selectedId=person-1&organizationId=org-1')).toBe('/people?siteId=site-1&organizationId=org-1&selectedId=person-1')
    expect(safeTarget('/admin/organization/person-like-id')).toBe('/devices')
  })

  it('keeps long record IDs and canonicalizes nested legacy list returns', () => {
    const returnTo = '/admin/assets/devices?siteId=site-1&type=WATCH&pageNum=3&token=secret'
    const target = safeTarget('/admin/assets/devices/9007199254740993?siteId=site-1&returnTo=' + encodeURIComponent(returnTo))
    const url = new URL(target, 'http://admin.local')
    expect(url.pathname).toBe('/devices/9007199254740993')
    expect(url.searchParams.get('returnTo')).toBe('/devices?siteId=site-1&pageNum=3&type=WATCH')
    expect(target).not.toContain('admin%2F')
    expect(target).not.toContain('secret')
  })

  it('preserves supported device and assignment filters after login', () => {
    expect(safeTarget('/devices?siteId=site-1&type=BELT&lifecycle=STOCK&communication=OFFLINE&token=secret')).toBe('/devices?siteId=site-1&type=BELT&communication=OFFLINE')
    expect(safeTarget('/admin/assets/assignments?tab=history&deviceId=device-1&personId=person-2&siteId=site-1&pageSize=999')).toBe('/assignments?siteId=site-1&tab=history&personId=person-2&deviceId=device-1')
  })

  it.each(['ON_DUTY', 'OFF_DUTY', 'UNKNOWN'])('preserves the independent personnel duty filter %s through saved list returns', dutyStatus => {
    expect(cleanQuery({ dutyStatus, status: 'enabled' })).toEqual({ status: 'enabled', dutyStatus })
    const list = `/people?siteId=site-1&dutyStatus=${dutyStatus}`
    expect(peopleReturn(list)).toBe(list)
    const detail = new URL(safeTarget('/people/person-1?returnTo=' + encodeURIComponent(list)), 'http://admin.local')
    expect(detail.searchParams.get('returnTo')).toBe(list)
    expect(safeTarget(`/accounts?status=enabled&dutyStatus=${dutyStatus}`)).toBe('/accounts?status=enabled')
  })

  it('discards invalid duty filters without reinterpreting archive enablement', () => {
    for (const dutyStatus of ['enabled', 'disabled', 'ON', 'unknown', ['ON_DUTY']]) expect(cleanQuery({ dutyStatus })).toEqual({})
    expect(safeTarget('/people?dutyStatus=enabled&status=enabled')).toBe('/people?status=enabled')
  })

  it('returns to canonical lists from both old and short saved URLs', () => {
    expect(deviceReturn('/admin/assets/devices?siteId=site-1&type=WATCH&token=secret')).toBe('/devices?siteId=site-1&type=WATCH')
    expect(peopleReturn('/admin/people?siteId=site-1&pageNum=2')).toBe('/people?siteId=site-1&pageNum=2')
    expect(assignmentReturn('/admin/assets/assignments?tab=history')).toBe('/assignments?tab=history')
    expect(recordReturn('/admin/assets/assignments?siteId=site-1&tab=history', '/devices')).toBe('/assignments?siteId=site-1&tab=history')
    expect(recordReturn('/admin/people?siteId=site-1', '/people')).toBe('/people?siteId=site-1')
    expect(recordReturn('/roles', '/devices')).toBe('/devices')
  })

  it.each([
    undefined,
    'https://evil.invalid/devices',
    '//evil.invalid/devices',
    'javascript:alert(1)',
    '/devices#outside',
    '/devices\\outside',
    '/devices bad',
    '/devices-unknown',
    '/api/admin/v1/state',
    '/admin/unknown',
    '/admin/overview/../../live',
  ])('rejects unsafe or unsupported destinations %s', value => {
    expect(safeTarget(value)).toBe('/devices')
  })

  it('does not allow external return URLs or leak invalid site identifiers', () => {
    const target = safeTarget('/devices/device-1?siteId=..%2Fsite&returnTo=' + encodeURIComponent('https://evil.invalid'))
    const url = new URL(target, 'http://admin.local')
    expect(url.pathname).toBe('/devices/device-1')
    expect(url.searchParams.has('siteId')).toBe(false)
    expect(url.searchParams.get('returnTo')).toBe('/devices')
  })
})
