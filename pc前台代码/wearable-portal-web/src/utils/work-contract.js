import { requireValue } from './portal-contract.js'
import { personIdPattern } from './portal-route.js'
import { monitorLabels, sourceLabels, validUtc } from './work-route.js'
export function validateWorkResult(d, q) {
  requireValue(d && ['AVAILABLE', 'FORBIDDEN', 'NOT_INTEGRATED'].includes(d.state))
  if (d.state !== 'AVAILABLE') { requireValue(!!d.reasonCode); return d }
  const item = w => { requireValue(w && w.siteId === q.siteId && typeof w.workId === 'string' && personIdPattern.test(w.workId) && typeof w.name === 'string' && Object.hasOwn(monitorLabels, w.monitorState) && Object.hasOwn(sourceLabels, w.sourceStatus)); requireValue(Number.isSafeInteger(w.participantCount) && w.participantCount >= 0 && (w.openEventCount === null || Number.isSafeInteger(w.openEventCount) && w.openEventCount >= 0)); requireValue(validUtc(w.startsAt) && validUtc(w.endsAt) && Date.parse(w.startsAt) < Date.parse(w.endsAt)) }
  if (q.workId) {
    item(d.work); requireValue(d.work.workId === q.workId && d.monitoring.workId === q.workId && d.monitoring.siteId === q.siteId && d.monitoring.version > 0)
    for (const key of ['people', 'events', 'videos', 'materials', 'locations']) { const s = d[key]; requireValue(s && ['AVAILABLE', 'NOT_INTEGRATED', 'FORBIDDEN', 'ERROR'].includes(s.state)); requireValue(s.state === 'AVAILABLE' ? Array.isArray(s.data) && s.data.every(i => i.siteId === q.siteId) : s.data === null) }
  } else {
    requireValue(Array.isArray(d.items) && d.scope.siteId === q.siteId && d.pageNum === Number(q.pageNum || 1) && d.pageSize === Number(q.pageSize || 20) && Number.isSafeInteger(d.total) && d.total >= d.items.length && d.items.length <= d.pageSize)
    requireValue(new Set(d.items.map(w => w.workId)).size === d.items.length)
    d.items.forEach(item)
    requireValue(Object.keys(monitorLabels).every(k => Number.isSafeInteger(d.counts[k]) && d.counts[k] >= 0) && Object.values(d.counts).reduce((a, b) => a + b, 0) === d.total)
  }
  return d
}
