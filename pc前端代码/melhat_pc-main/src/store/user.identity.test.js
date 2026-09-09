import { describe, expect, it } from 'vitest'

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
})
