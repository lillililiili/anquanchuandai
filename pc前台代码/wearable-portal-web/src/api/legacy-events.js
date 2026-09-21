import request from '@/utils/request'
import { validateEventPage, validateEventSummary, validateEventDetail, validateEventRecords } from '@/utils/event-contract'
async function get(path, params, signal, validate) {
  const r = await request.get('/api/portal/v1/events' + path, { params, signal })
  try { return { data: validate(r.data), asOf: r.asOf, requestId: r.requestId } } catch (e) { e.requestId = r.requestId; throw e }
}
export const getEvents = (q, s) => get('', q, s, d => validateEventPage(d, q))
export const getEventSummary = (q, s) => get('/summary', q, s, validateEventSummary)
export const getEvent = (id, siteId, s) => get('/' + encodeURIComponent(id), { siteId }, s, d => validateEventDetail(d, siteId, id))
export const getEventRecords = (id, kind, q, s) => get('/' + encodeURIComponent(id) + '/' + kind, q, s, d => validateEventRecords(d, q, id, kind))
