import test from 'node:test'
import assert from 'node:assert/strict'
import { createSeed } from '../src/mock/seed.js'
import { buildStatistics, distinctEvents } from '../src/mock/statistics-service.js'
import { inInterval, statisticsCsv, csvCell, safeStatisticsReturn } from '../src/utils/statistics.js'
import { assignmentCommand, queryEquipment } from '../src/mock/equipment-service.js'
import { eventCommand } from '../src/mock/event-service.js'
const siteId = 'mock-site-1', read = d => buildStatistics(d, 'owner', { siteId }), metric = (d, id) => read(d).metrics.find(m => m.id === id)
test('statistics current assignments 68/69/68; drilldown counts and long IDs use shared data', () => {
  const d = createSeed(), personId = '9007199254740993102'
  const options = () => queryEquipment(d, 'owner', '/api/portal/v1/equipment/options', { siteId, personId, type: 'HELMET' })
  assert.equal(metric(d, 'assignment-ASSIGNED').count, 68)
  const p = options().choices[0]
  assignmentCommand(d, 'owner', 'issue', { siteId, personId, deviceId: p.device.deviceId, expectedVersion: p.expectedVersion, operationId: 'stats-issue' })
  assert.equal(metric(d, 'assignment-ASSIGNED').count, 69)
  const r = options().current[0]
  assignmentCommand(d, 'owner', 'return', { siteId, personId, deviceId: r.device.deviceId, assignmentId: r.assignment.assignmentId, expectedVersion: r.expectedVersion, operationId: 'stats-return' })
  assert.equal(metric(d, 'assignment-ASSIGNED').count, 68)
  for (const m of read(d).metrics) assert.equal(m.count, m.rows.length)
  assert.equal(metric(d, 'duty').rows[1].id, personId)
  assert.equal(read(d).assignmentDenominator, 71)
})
test('historical interval is half-open; unknown source time and date grouping separate', () => {
  assert.equal(inInterval('2026-01-01T00:00:00Z','2026-01-01T00:00:00Z','2026-01-02T00:00:00Z'), true)
  assert.equal(inInterval('2026-01-02T00:00:00Z','2026-01-01T00:00:00Z','2026-01-02T00:00:00Z'), false)
  const d = createSeed(), result = buildStatistics(d, 'owner', { siteId, from:'2000-01-01T00:00:00Z', to:'2000-01-02T00:00:00Z' })
  assert.equal(result.metrics.find(m => m.id === 'occurred').count, 0)
  assert.equal(result.metrics.find(m => m.id === 'unknownTime').count, 3)
  assert.equal(result.metrics.find(m => m.id === 'duty').count, 25)
  assert.equal(metric(d, 'captureUnknown').count, 8)
  assert.equal(result.timeZone, 'Asia/Shanghai')
})
test('seed completion and submitted verification are not explicit completion', () => {
  const d = createSeed(), eventId = 'event-1-1'
  assert.equal(metric(d, 'phase-LOCAL_COMPLETED').count, 5); assert.equal(metric(d, 'completed').count, 0)
  const command = (action, extra = {}) => eventCommand(d, 'owner', action, { siteId, eventId, operationId:'stats-' + action, expectedVersion: d.entities.events.find(e => e.eventId === eventId).version || 1, ...extra })
  command('claim'); command('verify'); command('submit', { form: { conclusion:'COMMUNICATION_ISSUE', scene:'预置确认', measures:'', evidence:[] } })
  assert.equal(metric(d, 'completed').count, 0)
  command('complete'); assert.equal(metric(d, 'completed').count, 1)
  command('receipt', { channel:'summary', result:'SUCCESS' }); assert.equal(metric(d, 'completed').count, 1)
})
test('source identity dedup does not merge same identifier from different systems', () => {
  const e = { siteId, eventId:'1', sourceSystem:'A', sourceEventId:'10' }
  assert.equal(distinctEvents([e, { ...e, eventId:'2' }, { ...e, eventId:'3', sourceSystem:'B' }]).length, 2)
})
test('site permissions, missing sources, unknown denominator, empty site and invalid filter', () => {
  const d = createSeed()
  assert.throws(() => buildStatistics(d, '', {siteId}), e => e.code === 401)
  assert.throws(() => buildStatistics(d, 'reader', {siteId:'mock-site-2'}), e => e.code === 403)
  assert.throws(() => buildStatistics(d, 'owner', {siteId, unexpected:'x'}), e => e.code === 400)
  assert.throws(() => buildStatistics(d, 'owner', {siteId, from:'bad'}), e => e.code === 400)
  assert.equal(buildStatistics(d, 'owner', {siteId:'mock-site-empty'}).assignmentRate, null)
  for (const [mode,state] of [['failure','ERROR'],['forbidden','FORBIDDEN'],['not-integrated','NOT_INTEGRATED']]) {
    d.config = { module:'equipment', mode }; const r=read(d), m=r.metrics.find(m=>m.id==='assignment-ASSIGNED')
    assert.equal(m.state,state); assert.equal(m.count,null); assert.deepEqual(m.rows,[]); assert.equal(r.assignmentRate,null)
    assert.equal(r.metrics.find(m=>m.id==='duty').count,25)
  }
})
test('CSV escapes formulas, quotes, Unicode IDs and exports scope; safe restore whitelist', () => {
  for (const v of ['=1+1',' +CMD','@SUM(A1)','-1','\tABC','\n=2']) assert.ok(csvCell(v).startsWith('"\''))
  assert.equal(csvCell('a"b'), '"a""b"')
  const d=createSeed(), r=read(d), csv=statisticsCsv(r,r.metrics[0],'2026-01-01T00:00:00Z')
  assert.ok(csv.includes('服务未接入 · 本地工作空间')); assert.ok(csv.includes('9007199254740993101')); assert.ok(csv.includes('[from,to)'))
  assert.equal(safeStatisticsReturn('/statistics?tab=events&evil=x'),'/statistics?tab=events')
  assert.equal(safeStatisticsReturn('//evil.test/statistics'),'/statistics')
})
