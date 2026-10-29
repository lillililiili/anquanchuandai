export function createBusinessConfigApi({ fetchImpl = fetch, token = () => sessionStorage.getItem('wearable-admin-token') || '' } = {}) {
  const request = async (path, { method = 'GET', body, signal } = {}) => {
    const currentToken = token();
    const response = await fetchImpl('/api/admin/v1/' + path, { method, signal,
      headers: { 'Content-Type': 'application/json; charset=utf-8', 'X-Wearable-Token': currentToken },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    let result; try { result = await response.json(); } catch { throw Error('服务响应无效，请刷新后重试'); }
    if (signal?.aborted || currentToken !== token()) throw new DOMException('登录状态已变化', 'AbortError');
    if (!response.ok) throw Object.assign(Error(result.message || '操作失败'), { code: response.status });
    return result;
  };
  return {
    read: signal => request('business-config', { signal }),
    save: (visible, expectedVersion, signal) => request('business-config', { method: 'PATCH', body: { simulatedWatchVisible: visible, expectedVersion }, signal }),
    state: signal => request('state', { signal })
  };
}
