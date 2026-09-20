import request from '@/utils/request'
import { validateVideoPage, validateVideoDetail } from '@/utils/video-contract'
async function get(path, params, signal, validate) {
  const r = await request.get('/api/portal/v1/video-sources' + path, { params, signal })
  try { return { data: validate(r.data), asOf: r.asOf, requestId: r.requestId } } catch (e) { e.requestId = r.requestId; throw e }
}
export const getVideoSources = (q, signal) => get('', q, signal, d => validateVideoPage(d, q))
export const getVideoSource = (id, siteId, signal) => get('/' + encodeURIComponent(id), { siteId }, signal, d => validateVideoDetail(d, siteId, id))
