import { beforeEach, describe, it, expect, vi } from 'vitest'
import { createSSRApp } from 'vue'
import { renderToString } from 'vue/server-renderer'
import { routeLocationKey } from 'vue-router'
import { fitAdminNavigation, changeSiteAfterConfirmation } from './adminNavigation'
import { menuPath, MENU } from './navigation'
import { router } from './router'
import App from './App.vue'

const session = vi.hoisted(() => ({ identity: { id: 'test-system' } }))

vi.mock('vue-router', async importOriginal => {
  const actual = await importOriginal()
  return { ...actual, createWebHashHistory: actual.createMemoryHistory }
})
vi.mock('@admin-provider', () => ({ getAdminProvider: () => ({ identity: () => session.identity }) }))
vi.mock('./store', () => ({ useAdminStore: () => ({ confirmLeave: async () => true }) }))
vi.mock('./components/ConfirmDialog.vue', () => ({ default: { render: () => null } }))
beforeEach(() => { session.identity = { id: 'test-system' } })
describe('top navigation and guarded site changes', () => {
  it('places assets and people left of the title, access and audit right', () => {
    const { visibleCount, leftCount } = fitAdminNavigation([120,120,120,120],500,500,100)
    expect({ visibleCount, leftCount }).toEqual({ visibleCount:4,leftCount:2 })
    expect(MENU.map(m=>m.title)).toEqual(['装备资产','人员组织','权限协作','操作日志'])
    expect(MENU.slice(0, leftCount).map(item => item.title)).toEqual(['装备资产', '人员组织'])
    expect(MENU.slice(leftCount, visibleCount).map(item => item.title)).toEqual(['权限协作', '操作日志'])
  })
  it('does not move the left pair across the title on asymmetric widths', () => {
    expect(fitAdminNavigation([120,120,120,120],130,500,80)).toEqual({ visibleCount:1,leftCount:1 })
  })
  it('fits every visible item and the overflow trigger without reordering the prefix', () => {
    const widths=[120,120,120,120]
    for(const available of [90,200,270,350,600]) {
      const {visibleCount,leftCount}=fitAdminNavigation(widths,available,available,80)
      const occupied=values=>values.reduce((a,b)=>a+b,0)+Math.max(0,values.length-1)*4
      expect(occupied(widths.slice(0,leftCount))).toBeLessThanOrEqual(available)
      expect(occupied([...widths.slice(leftCount,visibleCount),...(visibleCount<4?[80]:[])])).toBeLessThanOrEqual(available)
    }
  })
  it('keeps details and workspace tabs under their existing owner', () => {
    expect(menuPath('/devices/RL-H001')).toBe('/devices')
    expect(menuPath('/assignments')).toBe('/devices')
    for(const path of ['people/person-1-0','organization','sites','duty']) expect(menuPath('/'+path)).toBe('/people')
    expect(menuPath('/roles')).toBe('/accounts')
    expect(menuPath('/audit')).toBe('/audit')
  })
  it.each(['/', '/admin', '/overview', '/overview/old', '/integrations', '/integrations/settings', '/maintenance/repair-1', '/groups/group-1', '/admin/overview', '/admin/overview/old', '/admin/integrations', '/admin/integrations/settings', '/admin/assets/maintenance/repair-1', '/admin/access/groups/group-1'])('redirects actual route %s with only the valid site', async path => {
    await router.push(path + '?siteId=site-1&token=secret&keyword=retired')
    expect(router.currentRoute.value.fullPath).toBe('/devices?siteId=site-1')
  })
  it('uses inventory for an authenticated login fallback and discards invalid legacy sites', async () => {
    await router.push('/admin/login?token=secret')
    expect(router.currentRoute.value.fullPath).toBe('/devices')
    await router.push('/admin/integrations?siteId=..%2Fsite')
    expect(router.currentRoute.value.fullPath).toBe('/devices')
  })
  it.each([
    ['/admin/assets/devices', '/devices'],
    ['/admin/assets/devices/RL-H001', '/devices/RL-H001'],
    ['/admin/assets/assignments', '/assignments'],
    ['/admin/people', '/people'],
    ['/admin/people/person-1-0', '/people/person-1-0'],
    ['/admin/sites', '/sites'],
    ['/admin/duty', '/duty'],
    ['/admin/access/accounts', '/accounts'],
    ['/admin/access/roles', '/roles'],
    ['/admin/audit', '/audit'],
  ])('canonicalizes legacy route %s to %s', async (legacy, path) => {
    await router.push(legacy + '?siteId=site-1&pageNum=2&token=secret')
    expect(router.currentRoute.value.path).toBe(path)
    expect(router.currentRoute.value.query).toEqual({ siteId: 'site-1', pageNum: '2' })
  })
  it.each([
    ['/admin/assets/devices', '/devices'],
    ['/admin/people', '/people'],
    ['/admin/access/accounts', '/accounts'],
    ['/admin/unknown', '/devices'],
  ])('does not inherit rejected query fields when redirecting %s', async (legacy, path) => {
    await router.push(legacy + '?siteId=..%2Fsite&token=secret')
    expect(router.currentRoute.value.fullPath).toBe(path)
    expect(router.currentRoute.value.query).toEqual({})
  })
  it.each(['/devices', '/assignments', '/people', '/sites', '/duty', '/accounts', '/roles', '/audit'])('opens the short route %s under the administration layout', async path => {
    await router.push(path + '?siteId=site-2')
    expect(router.currentRoute.value.path).toBe(path)
    expect(router.currentRoute.value.matched).toHaveLength(2)
    expect(router.currentRoute.value.matched.at(-1).meta.errorState).toBeUndefined()
  })
  it('uses the short login URL and preserves a sanitized detail destination for anonymous users', async () => {
    session.identity = null
    await router.push('/admin/assets/devices/RL-H001?siteId=site-1&token=secret')
    expect(router.currentRoute.value.path).toBe('/login')
    expect(router.currentRoute.value.query).toEqual({ redirect: '/devices/RL-H001?siteId=site-1' })
  })
  it('resumes an authenticated login at the short URL from a legacy saved destination', async () => {
    await router.push({ path: '/login', query: { redirect: '/admin/assets/assignments?siteId=site-1&tab=history&token=secret' } })
    expect(router.currentRoute.value.path).toBe('/assignments')
    expect(router.currentRoute.value.query).toEqual({ siteId: 'site-1', tab: 'history' })
  })
  it.each(['/organization', '/admin/organization'])('redirects %s to the merged personnel list with its organization selected', async path => {
    await router.push(path + '?siteId=site-1&selectedId=org-1&keyword=old&pageNum=9&token=secret')
    expect(router.currentRoute.value.fullPath).toBe('/people?siteId=site-1&organizationId=org-1')
    expect(router.currentRoute.value.meta.entity).toBe('people')
    expect(router.currentRoute.value.query).not.toHaveProperty('selectedId')
    await router.push(path + '?siteId=..%2Fbad&selectedId=..%2Fbad&token=secret')
    expect(router.currentRoute.value.fullPath).toBe('/people')
  })
  it.each(['/organization', '/admin/organization'])('keeps the organization selection from %s through login', async path => {
    session.identity = null
    await router.push(path + '?siteId=site-1&selectedId=org-1&token=secret')
    expect(router.currentRoute.value.path).toBe('/login')
    expect(router.currentRoute.value.query).toEqual({ redirect: '/people?siteId=site-1&organizationId=org-1' })
    session.identity = { id: 'test-system' }
    await router.push({ path: '/login', query: { redirect: path + '?siteId=site-1&selectedId=org-2&token=secret' } })
    expect(router.currentRoute.value.fullPath).toBe('/people?siteId=site-1&organizationId=org-2')
  })
  it('never commits a cancelled or still-pending site switch', async () => {
    let answer; const commit=vi.fn(); const confirm=()=>new Promise(resolve=>{answer=resolve})
    const pending=changeSiteAfterConfirmation({current:'site-1',next:'site-2',confirm,commit})
    expect(commit).not.toHaveBeenCalled(); answer(false); expect(await pending).toBe(false); expect(commit).not.toHaveBeenCalled()
  })
  it('commits an accepted switch once and ignores an unchanged site', async () => {
    const commit=vi.fn(),confirm=vi.fn(async()=>true)
    expect(await changeSiteAfterConfirmation({current:'site-1',next:'site-2',confirm,commit})).toBe(true)
    expect(commit).toHaveBeenCalledExactlyOnceWith('site-2')
    await changeSiteAfterConfirmation({current:'site-1',next:'site-1',confirm,commit}); expect(confirm).toHaveBeenCalledTimes(1)
  })
})

describe('theme preservation on short administration routes', () => {
  it('inherits the business theme on list routes independently of the parent path', () => {
    for (const path of ['/devices', '/assignments', '/people', '/sites', '/duty', '/accounts', '/roles', '/audit']) {
      const resolved = router.resolve(path)
      expect(resolved.meta.adminTheme, path).toBe('business')
      expect(resolved.meta.adminFamily, path).not.toBe('detail')
    }
  })

  it.each(['/devices/RL-H001', '/people/person-1-0'])('retains the detail theme family for %s', path => {
    expect(router.resolve(path).meta).toMatchObject({ adminTheme: 'business', adminFamily: 'detail' })
  })

  it('keeps the login page outside the business theme', () => {
    const resolved = router.resolve('/login')
    expect(resolved.meta.adminTheme).toBeUndefined()
    expect(resolved.meta.adminFamily).toBeUndefined()
  })

  it.each([
    ['/devices', { adminTheme: 'business', adminFamily: 'list' }],
    ['/devices/RL-H001', { adminTheme: 'business', adminFamily: 'detail' }],
    ['/people/person-1-0', { adminTheme: 'business', adminFamily: 'detail' }],
    ['/login', {}],
  ])('applies the real App theme attributes when rendering %s', async (path, expected) => {
    const documentElement = { dataset: { adminTheme: 'stale', adminFamily: 'stale' } }
    vi.stubGlobal('document', { documentElement })
    try {
      const app = createSSRApp(App)
      app.provide(routeLocationKey, router.resolve(path))
      app.component('router-view', { render: () => null })
      await renderToString(app)
      expect(documentElement.dataset).toEqual(expected)
    } finally {
      vi.unstubAllGlobals()
    }
  })
})
