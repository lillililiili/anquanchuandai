import request from './request'
import { validateAlarmPage, validateAlarmSummary, validateAlarmDetail } from '../utils/alarm-contract'
export const writable = true
export async function getEvents(q, signal) {
  const r = await request.get('/api/portal/v1/events', { params: q, signal })
  validateAlarmPage(r.data, q); return r
}
export async function getEventSummary(q, signal) { const r = await request.get('/api/portal/v1/events/summary', { params: q, signal }); validateAlarmSummary(r.data); return r }
export async function getEvent(id, siteId, signal) {
  const r = await request.get('/api/portal/v1/events/' + encodeURIComponent(id), { params: { siteId }, signal })
  validateAlarmDetail(r.data, siteId, id)
  return r
}
