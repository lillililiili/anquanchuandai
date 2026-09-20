import request from './request.js'
export const getWorkbench = (siteId, signal) => request.get('/api/portal/v1/workbench', { params: { siteId }, signal })
