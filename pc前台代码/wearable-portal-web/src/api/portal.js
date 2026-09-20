import request from '@/utils/request'
import { validateContext, validatePage, validateDetail, requireValue } from '@/utils/portal-contract'
const base = '/api/portal/v1'
const get = async (path, params, signal, validate) => {
  const response = await request.get(base + path, { params, signal })
  return { data: validate(response.data), asOf: response.asOf, requestId: response.requestId }
}
export const getContext = signal => get('/context', undefined, signal, validateContext)
export const getPeople = (params, signal) => get('/people', params, signal, data => {
  validatePage(data)
  requireValue(data.scope?.siteId === params.siteId && data.items.every(p => p.siteId === params.siteId), '人员列表与所选厂站不一致')
  return data
})
export const getPerson = (id, siteId, signal) => get('/people/' + encodeURIComponent(id), { siteId }, signal, data => {
  validateDetail(data)
  requireValue(data.person.personId === id && data.person.siteId === siteId, '人员详情与请求对象不一致')
  return data
})
export const getHistory = (id, params, signal) => get('/people/' + encodeURIComponent(id) + '/equipment-history', params, signal, data => {
  validatePage(data, true)
  requireValue(data.scope?.siteId === params.siteId && data.items.every(item => item.personId === id), '历史人员归属不一致')
  return data
})
