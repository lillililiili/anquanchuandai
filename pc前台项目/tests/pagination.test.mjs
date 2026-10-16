import test from 'node:test';
import assert from 'node:assert/strict';
import { effectScope, nextTick, ref } from 'vue';
import { pageNumbers, useTablePagination } from '../src/lib/pagination.js';

const records = (length) => Array.from({length}, (_, index) => ({id:index + 1}));
function setup(length = 25) {
  const scope = effectScope();
  const rows = ref(records(length));
  const filter = ref({query:''});
  const pager = scope.run(() => useTablePagination(rows, filter));
  return {scope, rows, filter, ...pager};
}

test('默认十条；翻页不重复、不遗漏，末页边界正确', () => {
  const p=setup();
  try {
    const ids=[];
    for (let page=1;page<=3;page++) {
      p.changePage(page);
      ids.push(...p.visibleRows.value.map(row=>row.id));
      assert.equal(p.offset.value, (page-1)*10);
    }
    assert.deepEqual(ids, records(25).map(row=>row.id));
    assert.equal(p.visibleRows.value.length,5);
    p.changePage(100); assert.equal(p.page.value,3);
    p.changePage(0); assert.equal(p.page.value,1);
  } finally {p.scope.stop();}
});

test('筛选重置首页；轮询替换相同记录不会打断当前页', async () => {
  const p=setup();
  try {
    p.changePage(3);
    p.rows.value=records(25); await nextTick();
    assert.equal(p.page.value,3);
    p.filter.value.query='筛选条件'; await nextTick();
    assert.equal(p.page.value,1);
  } finally {p.scope.stop();}
});

test('记录减少时回退有效页；零条数据仍为第一页', async () => {
  const p=setup();
  try {
    p.changePage(3); p.rows.value=records(11); await nextTick();
    assert.equal(p.page.value,2); assert.equal(p.visibleRows.value[0].id,11);
    p.rows.value=[]; await nextTick();
    assert.equal(p.page.value,1); assert.equal(p.total.value,0); assert.deepEqual(p.visibleRows.value,[]);
  } finally {p.scope.stop();}
});

test('每页条数切换重置首页，多个表格分页互不干扰', async () => {
  const a=setup(45), b=setup(45);
  try {
    a.changePage(3); b.changePage(2);
    a.changePageSize('20'); await nextTick();
    assert.equal(a.page.value,1); assert.equal(a.visibleRows.value.length,20);
    assert.equal(b.page.value,2); assert.equal(b.visibleRows.value.length,10);
    a.changePageSize(0); assert.equal(a.pageSize.value,10);
  } finally {a.scope.stop();b.scope.stop();}
});

test('大量页数保留首尾和当前页，省略号不产生重复页', () => {
  for (const current of [1,2,5,50,99,100]) {
    const pages=pageNumbers(current,100).filter(value=>typeof value==='number');
    assert.ok(pages.includes(current)); assert.equal(pages[0],1);assert.equal(pages.at(-1),100);
    assert.equal(new Set(pages).size,pages.length);
    assert.ok(pages.length<=5);
  }
});
