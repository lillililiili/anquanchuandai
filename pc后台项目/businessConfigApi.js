export function createBusinessConfigApi({ fetchImpl = fetch, token = () => sessionStorage.getItem('wearable-admin-token') || '' } = {}) {
  const request = async (path, { method = 'GET', body, signal } = {}) => {
    const currentToken = token();
    const response = await fetchImpl('/api/admin/v1/' + path, { method, signal,
      headers: { 'Content-Type': 'application/json; charset=utf-8', 'X-Wearable-Token': currentToken },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    let result; try { result = await response.json(); } catch { throw Error('服务响应无效，请刷新后重试'); }
    if (signal?.aborted || currentToken !== token()) throw new DOMException('登录状态已变化', 'AbortError');
    const code = response.ok ? Number(result?.code) : response.status;
    if (!response.ok || code >= 400) throw Object.assign(Error(result?.message || result?.msg || '操作失败'), { code });
    if (path.startsWith('maintenance') && (typeof result?.paused !== 'boolean' || typeof result?.quiescent !== 'boolean')) {
      throw Error('服务响应无效，请刷新后重试');
    }
    return result;
  };
  return {
    reconcileMaintenance: (reason, signal) => request('maintenance/reconcile', { method: 'POST', body: { reason }, signal }),
    maintenance: signal => request('maintenance', { signal }),
    setMaintenance: (paused, signal) => request('maintenance', { method: 'POST', body: { mode: paused ? 'PAUSED' : 'ACTIVE' }, signal }),
    read: signal => request('business-config', { signal }),
    save: (visible, expectedVersion, signal) => request('business-config', { method: 'PATCH', body: { simulatedWatchVisible: visible, expectedVersion }, signal }),
    state: signal => request('state', { signal })
  };
}
