import { describe,it,expect } from 'vitest'
import { effectScope,ref,nextTick } from 'vue'
import { pageCount,clampPage,pageNumbers,useTablePagination } from './pagination'
import { resultRegionHeight } from './tableRegion'
describe('unified admin pagination',()=>{
  it('handles empty, exact and partial pages',()=>{
    expect(pageCount(0)).toBe(1);expect(pageCount(20)).toBe(2);expect(pageCount(21)).toBe(3)
    expect(clampPage(8,21)).toBe(3);expect(clampPage(-1,0)).toBe(1)
    expect(pageNumbers(5,10)).toEqual([1,'gap-4',4,5,6,'gap-10',10])
  })
  it('uses ten rows, preserves updates, resets filters and supports legacy size 100',async()=>{
    const scope=effectScope(),rows=ref(Array.from({length:25},(_,id)=>({id}))),filter=ref('')
    const pager=scope.run(()=>useTablePagination(rows,filter))
    expect(pager.visibleRows.value).toHaveLength(10);pager.changePage(3);expect(pager.visibleRows.value.map(r=>r.id)).toEqual([20,21,22,23,24])
    rows.value=rows.value.map(r=>({...r}));await nextTick();expect(pager.page.value).toBe(3)
    rows.value=rows.value.slice(0,12);await nextTick();expect(pager.page.value).toBe(2)
    filter.value='changed';await nextTick();expect(pager.page.value).toBe(1)
    pager.changePageSize(100);expect(pager.pageSize.value).toBe(100);expect(pager.visibleRows.value).toHaveLength(12)
    scope.stop()
  })
  it('bounds results by viewport and filter position, never by row count',()=>{
    expect(resultRegionHeight(900,400,60)).toBe(440)
    expect(resultRegionHeight(768,580,60)).toBe(180)
  })
})
