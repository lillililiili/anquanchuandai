import test from 'node:test'
import assert from 'node:assert/strict'
import { parseLocal, localString, monthDays, withinRange } from '../../shared/ui-spec/date-model.js'

test('日期控件保留本地字符串，不转换到 UTC，不丢失秒',()=>{
  for(const value of ['2026-10-12','2026-10-12T00:01','2026-10-12T23:59:59','2026-03-08T02:30']){
    const parsed=parseLocal(value);assert.ok(parsed)
    assert.equal(localString(parsed,value.includes('T'),value.length===19),value)
  }
  assert.equal(localString(parseLocal('0001-01-01')),'0001-01-01')
})
test('拒绝无效日期和时间，接受闰年日期',()=>{
  for(const value of ['2025-02-29','2026-04-31','2026-00-12','2026-13-12','2026-10-12T24:00','2026-10-12T12:60','2026-10-12T12:00:60','2026-10-12Z',''])assert.equal(parseLocal(value),null,value)
  assert.ok(parseLocal('2024-02-29'))
})
test('日期网格遵循原稿周日首列，跨年与六周月份完整',()=>{
  const december=monthDays(2025,12)
  assert.equal(december.length,35);assert.equal(localString(december[0]),'2025-11-30');assert.equal(localString(december.at(-1)),'2026-01-03')
  const august=monthDays(2026,8)
  assert.equal(august.length,42);assert.equal(august.filter(d=>d.month===8).length,31)
  assert.equal(monthDays(2024,2).filter(d=>d.month===2).length,29)
})
test('日期范围边界包含端点，时间精度不同仍按相同本地时间比较',()=>{
  assert.equal(withinRange('2026-10-12','2026-10-12','2026-10-12'),true)
  assert.equal(withinRange('2026-10-11','2026-10-12',''),false)
  assert.equal(withinRange('2026-10-12T18:18:00','','2026-10-12T18:18'),true)
  assert.equal(withinRange('2026-10-12T18:18:01','','2026-10-12T18:18'),false)
})
