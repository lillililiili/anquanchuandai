import request from './request.js'
export const enabled = true
const base = '/api/portal/v1/equipment'
export const list = (params, signal) => request.get(base, { params, signal })
export const detail = (id, siteId, signal) => request.get(base + '/' + encodeURIComponent(id), { params: { siteId }, signal })
export const options = (params, signal) => request.get(base + '/options', { params, signal })
export const issue = (input, signal) => request.post(base + '/issue', input, { signal })
export const returnAssignment = (input, signal) => request.post(base + '/return', input, { signal })
