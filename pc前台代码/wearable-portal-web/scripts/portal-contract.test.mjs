import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { validateContext, validatePage, validateDetail, formatTime, idString, validateEquipment } from '../src/utils/portal-contract.js'
import { adaptHatPage, adaptUserTable, communicationFromLegacy } from '../src/utils/portal-adapters.js'
import { safePersonnelReturn, personnelQuery } from '../src/utils/portal-route.js'
const fixture = JSON.parse(readFileSync(new URL('../../../docs/智能穿戴设备平台/S0-业务开发准备与契约基线/fixtures/s1-cases.json', import.meta.url), 'utf8'))
const data = id => structuredClone(fixture.cases.find(c => c.id === id).response.data)
for (const c of fixture.cases.filter(c => c.httpStatus === 200)) test('S0 contract ' + c.id, () => {
  const validators = { context: validateContext, people: validatePage, detail: validateDetail, history: d => validatePage(d, true) }
  assert.ok(validators[c.endpoint](c.response.data))
})
test('long IDs stay strings and unsafe numbers fail', () => {
  assert.equal(idString('9007199254740993'), '9007199254740993')
  assert.throws(() => idString(9007199254740993))
  assert.equal(adaptHatPage(fixture.legacyExamples.rPage).items[0].id, '9007199254740993')
})
test('different pagination envelopes never silently become empty', () => {
  assert.deepEqual(adaptUserTable(fixture.legacyExamples.tableDataInfo), { items: [], total: 0 })
  assert.throws(() => adaptHatPage(fixture.legacyExamples.tableDataInfo))
  assert.throws(() => adaptUserTable(fixture.legacyExamples.rPage))
})
test('unintegrated roster total cannot be zero', () => {
  const d = data('people-roster-missing'); d.total = 0
  assert.throws(() => validatePage(d))
})
test('assignment cardinality and unknown are distinct', () => {
  const d = data('people-equipment-states').items[0].equipment
  d.data.belt.assignmentState = 'ASSIGNED'
  assert.throws(() => validateEquipment(d))
})
test('snapshot cannot create history timestamps', () => {
  const d = data('history-snapshot'); d.items[0].startedAt = '2026-01-01T00:00:00Z'
  assert.throws(() => validatePage(d, true))
})
test('platform state and legacy cache use different mappings', () => {
  assert.equal(communicationFromLegacy('1').state, 'UNKNOWN')
  assert.equal(communicationFromLegacy('1', 'PLATFORM_QUERY').state, 'ONLINE')
  assert.equal(communicationFromLegacy('0', 'PLATFORM_QUERY').state, 'OFFLINE')
  assert.equal(communicationFromLegacy('-1', 'PLATFORM_QUERY').state, 'UNKNOWN')
  assert.equal(communicationFromLegacy('1', 'PLATFORM_QUERY').freshness, 'UNKNOWN')
})
test('missing/invalid source dates never render epoch', () => {
  for (const v of [null, undefined, '', 'nonsense', '2026-01-01 12:00:00']) assert.equal(formatTime(v), '—')
  assert.equal(formatTime('2026-01-01T12:00:00Z'), '2026-01-01 12:00:00 UTC')
})
test('safe return only permits personnel filters', () => {
  for (const v of ['https://evil.test', '//evil.test', '/personnel/x', '/personnel?x=1#bad', '/personnel\\evil', null]) assert.equal(safePersonnelReturn(v), '/personnel')
  assert.equal(safePersonnelReturn('/personnel?siteId=a&pageNum=2&evil=1'), '/personnel?siteId=a&pageNum=2')
  assert.deepEqual(personnelQuery({ pageSize: '101', pageNum: '-1', workState: 'fake', selectedPersonId: '../x' }), {})
})

