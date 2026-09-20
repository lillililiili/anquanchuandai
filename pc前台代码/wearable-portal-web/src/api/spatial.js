import request from '@/utils/request'
import { validateS2Page, validateS2Item, validateTrack } from '@/utils/spatial-contract'
const root = '/api/portal/v1'
async function get(path, params, signal, validate) {
  const r = await request.get(root + path, { params, signal })
  try { return { data: validate(r.data), asOf: r.asOf, requestId: r.requestId } }
  catch (e) { e.requestId = r.requestId; throw e }
}
export const getDevices = (q, s) => get('/devices', q, s, d => validateS2Page(d, 'devices', q))
export const getLocations = (q, s) => get('/locations/latest', q, s, d => validateS2Page(d, 'locations', q))
export const getTracks = (q, s) => get('/tracks', q, s, d => validateTrack(d, q))
export const getFences = (q, s) => get('/fences', q, s, d => validateS2Page(d, 'fences', q))
export const getFence = (id, siteId, s) => get('/fences/' + encodeURIComponent(id), { siteId }, s, d => validateS2Item(d, 'fences', siteId, id))
export const getMaterials = (q, s) => get('/materials', q, s, d => validateS2Page(d, 'materials', q))
export const getMaterial = (id, siteId, s) => get('/materials/' + encodeURIComponent(id), { siteId }, s, d => validateS2Item(d, 'materials', siteId, id))
