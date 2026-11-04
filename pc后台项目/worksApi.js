// Keep request IDs after ambiguous transport errors so a retry cannot duplicate a work.
export function createWorksApi({ fetchImpl = fetch, token = () => sessionStorage.getItem('wearable-admin-token') || '', makeId = () => crypto.randomUUID() } = {}) {
  const pending = new Map()
  async function request(path, { method = 'GET', body, signal } = {}) {
    const currentToken = token(), key = body ? JSON.stringify([method, path, body]) : null
    if (key && !pending.has(key)) pending.set(key, makeId())
    const response = await fetchImpl('/api/admin/v1/works' + path, { method, signal,
      headers: { 'Content-Type': 'application/json; charset=utf-8', 'X-Wearable-Token': currentToken },
      ...(body ? { body: JSON.stringify({ ...body, requestId: pending.get(key) }) } : {}) })
    let result
    try { result = await response.json() } catch { throw Error('服务响应无效，请刷新后核对保存结果') }
    if (signal?.aborted || currentToken !== token()) throw new DOMException('登录状态已变化', 'AbortError')
    if (!response.ok) {
      if (key && response.status >= 400 && response.status < 500) pending.delete(key)
      throw Object.assign(Error(result.message || '操作失败'), { code: response.status, errorCode: result.errorCode, fields: result.fields, impacts: result.impacts })
    }
    if (key) pending.delete(key)
    return result
  }
  const query = values => '?' + new URLSearchParams(Object.entries(values).filter(([, value]) => value !== '' && value != null)).toString()
  return {
    list: (filters, signal) => request(query(filters), { signal }),
    options: (siteId, signal) => request('/options' + query({ siteId }), { signal }),
    detail: (id, signal) => request('/' + encodeURIComponent(id), { signal }),
    save: (id, body, signal) => request(id ? '/' + encodeURIComponent(id) : '', { method: id ? 'PATCH' : 'POST', body, signal }),
    act: (id, action, expectedVersion, signal) => request('/' + encodeURIComponent(id) + '/actions', { method: 'POST', body: { action, expectedVersion }, signal }),
  }
}

export const WORK_STATUSES = ['待开始', '进行中', '已结束', '已取消']
export const workStatus = work => work?.status === '监护中' ? '进行中' : work?.status || '待开始'
export const workEditable = work => ['待开始', '进行中'].includes(workStatus(work)) && work?.source === 'LOCAL'
