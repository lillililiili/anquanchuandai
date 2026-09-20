export const enabled = false
const missing = siteId => ({ state: 'NOT_INTEGRATED', reasonCode: 'SOURCE_NOT_INTEGRATED', scope: { siteId } })
export const list = async q => ({ data: { ...missing(q.siteId), items: [], total: null, pageNum: Number(q.pageNum || 1), pageSize: Number(q.pageSize || 20) } })
export const detail = async (id, siteId) => ({ data: { ...missing(siteId), device: null } })
export const options = async q => ({ data: { ...missing(q.siteId), choices: [], current: [], allowed: false } })
export const issue = async () => { throw Object.assign(new Error('当前运行模式未开放领用归还'), { code: 403, errorCode: 'FEATURE_DISABLED' }) }
export const returnAssignment = issue
