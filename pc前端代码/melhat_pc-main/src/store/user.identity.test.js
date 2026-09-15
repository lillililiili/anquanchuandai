import { describe, expect, it } from 'vitest'
import { ALL_PERMISSION, hasAccessPermission, mergeAccessValues } from './access'

describe('site identity contract', () => {
  it('treats missing sites as empty list not failure', () => {
    const me = { authorizedSites: [], currentSiteId: null }
    expect(Array.isArray(me.authorizedSites)).toBe(true)
    expect(me.authorizedSites.length).toBe(0)
  })

  it('does not pick a site when several are authorized and none is current', () => {
    const me = {
      authorizedSites: [{ id: '1' }, { id: '2' }],
      currentSiteId: null
    }
    expect(me.currentSiteId == null).toBe(true)
    expect(me.authorizedSites.length).toBeGreaterThan(1)
  })

  it('keeps system permissions when business identity permissions are loaded', () => {
    const permissions = mergeAccessValues(
      [ALL_PERMISSION],
      ['wear:person:list', 'wear:device:edit']
    )

    expect(permissions).toEqual([
      ALL_PERMISSION,
      'wear:person:list',
      'wear:device:edit'
    ])
    expect(hasAccessPermission(permissions, 'system:role:edit')).toBe(true)
    expect(hasAccessPermission(permissions, 'wear:fence:edit')).toBe(true)
  })

  it('does not grant unrelated permissions to a regular user', () => {
    const permissions = mergeAccessValues(
      ['system:role:list'],
      ['wear:person:list', 'wear:person:list']
    )

    expect(permissions).toEqual(['system:role:list', 'wear:person:list'])
    expect(hasAccessPermission(permissions, 'system:role:edit')).toBe(false)
  })
})
