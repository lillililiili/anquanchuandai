import * as legacy from './legacy-events'
import { legacyAlarm } from '../utils/alarm-contract'
export const writable = false
export async function getEvents(q, signal) {
  const params = Object.fromEntries(Object.entries(q).filter(([k]) => ['siteId', 'keyword', 'from', 'to', 'eventType', 'pageNum', 'pageSize'].includes(k)))
  const r = await legacy.getEvents(params, signal)
  return { ...r, data: { ...r.data, items: r.data.items.map(legacyAlarm), filters: { ...r.data.filters, deviceType: false, handlingStatus: false } } }
}
export const getEventSummary = (q, signal) => legacy.getEventSummary({ siteId: q.siteId }, signal)
export async function getEvent(id, siteId, signal) {
  const r = await legacy.getEvent(id, siteId, signal)
  return { ...r, data: { ...r.data, event: legacyAlarm(r.data.event) } }
}
