import request from './request.js'
export const simulated = true
export const read = (params, signal) => request.get('/api/portal/v1/vitals', { params, signal })
