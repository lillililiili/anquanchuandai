import { describe, it, expect, vi } from 'vitest'
import { fitAdminNavigation, changeSiteAfterConfirmation } from './adminNavigation'
import { menuPath, MENU } from './navigation'
describe('top navigation and guarded site changes', () => {
  it('shows the five original menus in order with a two/three split', () => {
    expect(fitAdminNavigation([140,120,120,120,120],500,500,100)).toEqual({ visibleCount:5,leftCount:2 })
    expect(MENU.map(m=>m.title)).toEqual(['管理工作台','装备资产','人员组织','权限协作','操作日志'])
  })
  it('fits every visible item and the overflow trigger without reordering the prefix', () => {
    const widths=[140,120,120,120,120]
    for(const available of [90,200,270,350,600]) {
      const {visibleCount,leftCount}=fitAdminNavigation(widths,available,available,80)
      const occupied=values=>values.reduce((a,b)=>a+b,0)+Math.max(0,values.length-1)*4
      expect(occupied(widths.slice(0,leftCount))).toBeLessThanOrEqual(available)
      expect(occupied([...widths.slice(leftCount,visibleCount),...(visibleCount<5?[80]:[])])).toBeLessThanOrEqual(available)
    }
  })
  it('keeps details and workspace tabs under their existing owner', () => {
    expect(menuPath('/admin/assets/devices/RL-H001')).toBe('/admin/assets/devices')
    expect(menuPath('/admin/assets/assignments')).toBe('/admin/assets/devices')
    for(const path of ['people/person-1-0','organization','sites','duty']) expect(menuPath('/admin/'+path)).toBe('/admin/people')
    expect(menuPath('/admin/access/roles')).toBe('/admin/access/accounts')
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
