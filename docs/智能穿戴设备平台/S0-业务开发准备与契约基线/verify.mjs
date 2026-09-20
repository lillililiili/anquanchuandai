import assert from 'node:assert/strict'
import { readFileSync, existsSync, readdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = dirname(fileURLToPath(import.meta.url))
const fixture = JSON.parse(readFileSync(resolve(root, 'fixtures/s1-cases.json'), 'utf8'))
const sectionStates = ['AVAILABLE', 'NOT_INTEGRATED', 'UNAVAILABLE', 'FORBIDDEN']
const datePattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$/
let checks = 0
function check(condition, message) {
  assert.ok(condition, message)
  checks++
}
function walk(value) {
  if (!value || typeof value !== 'object') return
  if (Array.isArray(value)) return value.forEach(walk)
  for (const [key, item] of Object.entries(value)) {
    if ((key.endsWith('Id') || ['userId', 'hatId'].includes(key)) && item !== null) {
      check(typeof item === 'string', key + ' must be a string')
    }
    if (['sourceTime', 'receivedAt', 'observedAt', 'asOf', 'occurredAt', 'startedAt', 'endedAt', 'startsAt', 'endsAt', 'dataUpdatedAt', 'createdAt', 'lastOccurredAt'].includes(key) && item !== null) {
      check(typeof item === 'string' && datePattern.test(item) && Number.isFinite(Date.parse(item)), key + ' must be UTC RFC3339')
    }
    walk(item)
  }
  if ('state' in value && 'data' in value && !('code' in value)) {
    check(sectionStates.includes(value.state), 'invalid section state')
    check(value.state === 'AVAILABLE' ? value.data !== null : value.data === null && !!value.reasonCode, 'section null/reason invariant')
  }
  if ('assignmentState' in value) {
    const count = value.devices.length
    check(['ASSIGNED', 'UNASSIGNED', 'UNKNOWN', 'CONFLICT'].includes(value.assignmentState), 'assignment enum')
    check(value.assignmentState === 'ASSIGNED' ? count === 1 : value.assignmentState === 'CONFLICT' ? count >= 2 : count === 0, 'assignment cardinality')
  }
  if ('freshness' in value) {
    check(['FRESH', 'STALE', 'UNKNOWN', 'NOT_APPLICABLE'].includes(value.freshness), 'freshness enum')
    if (['FRESH', 'STALE'].includes(value.freshness)) check(value.sourceTime !== null, 'fresh/stale requires source time')
  }
  if ('sourceKind' in value) {
    check(['ONLINE', 'OFFLINE', 'UNKNOWN', 'NOT_INTEGRATED'].includes(value.state), 'communication enum')
    if (value.sourceKind === 'LEGACY_SNAPSHOT') check(value.state === 'UNKNOWN', 'legacy snapshot cannot prove online')
    if (value.state === 'NOT_INTEGRATED') check(value.freshness === 'NOT_APPLICABLE', 'not integrated freshness')
  }
  if (value.action === 'MIGRATION_SNAPSHOT') {
    check(value.evidenceQuality === 'CURRENT_SNAPSHOT_ONLY' && value.state === 'UNKNOWN', 'snapshot evidence')
    check([value.startedAt, value.endedAt, value.occurredAt].every(x => x === null), 'snapshot cannot fabricate history dates')
  }
  if ('battery' in value) {
    check(value.battery.value === null || (Number.isFinite(value.battery.value) && value.battery.value >= 0 && value.battery.value <= 100), 'battery range')
    for (const capability of ['video', 'talk', 'location', 'capture', 'record']) {
      const cap = value.capabilities[capability]
      check(cap && ['SUPPORTED', 'UNSUPPORTED', 'UNKNOWN'].includes(cap.state), 'capability enum')
      check(['VERIFIED', 'UNVERIFIED'].includes(cap.verification), 'verification enum')
    }
  }
}
function validateCase(c) {
  check(c.httpStatus === c.response.code, 'new HTTP/business status mismatch')
  if (c.httpStatus !== 200) {
    check(c.response.data === null && !!c.response.errorCode, 'error envelope')
    return
  }
  const data = c.response.data
  if (['people', 'history'].includes(c.endpoint)) {
    check(sectionStates.includes(data.state), 'page state')
    check(Array.isArray(data.items), 'page items')
    check(Number.isInteger(data.pageNum) && data.pageNum >= 1 && Number.isInteger(data.pageSize) && data.pageSize >= 1 && data.pageSize <= 100, 'page bounds')
    check(data.state === 'AVAILABLE' ? Number.isInteger(data.total) && data.total >= data.items.length : data.total === null && data.items.length === 0 && !!data.reasonCode, 'unavailable is not zero')
  }
  if (c.endpoint === 'context') check(data.selectedSiteId === null || data.sites.some(s => s.siteId === data.selectedSiteId), 'selected site must be authorized')
  if (c.endpoint === 'detail') {
    for (const key of ['equipment', 'works', 'duty', 'actions']) check(JSON.stringify(data[key]) === JSON.stringify(data.person[key]), 'detail duplicate snapshot: ' + key)
  }
  walk(data)
}
check(fixture.synthetic === true, 'synthetic marker required')
check(new Set(fixture.cases.map(c => c.id)).size === fixture.cases.length, 'unique cases')
fixture.cases.forEach(validateCase)
walk(fixture)
for (const required of ['people-roster-missing', 'people-empty', 'people-equipment-states', 'history-snapshot', 'history-missing', 'detail-partial-failure', 'error-401', 'error-403', 'error-404', 'error-503']) {
  check(fixture.cases.some(c => c.id === required), 'missing case ' + required)
}
let links = 0
for (const file of readdirSync(root).filter(x => x.endsWith('.md'))) {
  const text = readFileSync(resolve(root, file), 'utf8')
  for (const match of text.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)) {
    const target = match[1].replace(/^<|>$/g, '').split('#')[0]
    if (!target || /^[a-z]+:\/\//i.test(target)) continue
    check(existsSync(resolve(root, target)), 'broken link in ' + file + ': ' + target)
    links++
  }
}
const mapping = readFileSync(resolve(root, '03-设计页面与字段映射.md'), 'utf8')
for (let n = 1; n <= 17; n++) check(mapping.includes('| F' + String(n).padStart(2, '0') + ' |'), 'missing PDF page ' + n)
const badPage = structuredClone(fixture.cases.find(c => c.id === 'people-roster-missing'))
badPage.response.data.total = 0
assert.throws(() => validateCase(badPage), /unavailable is not zero/)
const badSnapshot = structuredClone(fixture.cases.find(c => c.id === 'history-snapshot').response.data.items[0])
badSnapshot.startedAt = '2026-09-17T03:00:00Z'
assert.throws(() => walk(badSnapshot), /fabricate history/)
const badLegacy = structuredClone(fixture.stateSamples.legacySnapshot)
badLegacy.state = 'ONLINE'
assert.throws(() => walk(badLegacy), /cannot prove online/)
console.log('PASS: ' + fixture.cases.length + ' synthetic response cases, 17 PDF mappings, ' + links + ' links, 3 negative checks; ' + checks + ' invariant assertions.')
console.log('Documentation validation only. No app/backend/account/device actions; real integration remains unverified.')

