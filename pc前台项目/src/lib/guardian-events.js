// Shared event writes never pass through the legacy snapshot writer.
export function createEventApi({ fetchImpl, refresh, current, uuid = () => crypto.randomUUID() }) {
  const pending = new Map();
  const running = new Map();
  async function command(id, action, values = {}) {
    const key = `${id}:${action}`;
    if (running.has(key)) return running.get(key);
    const event = current(id);
    if (!event) throw Error("事件不存在，请刷新后重试");
    const data = { ...values, expectedVersion: values.expectedVersion ?? event.version };
    const fingerprint = JSON.stringify(data);
    let request = pending.get(key);
    if (!request || request.fingerprint !== fingerprint) {
      request = { fingerprint, body: { ...data, requestId: uuid() } };
      pending.set(key, request);
    }
    const operation = (async () => {
      const response = await fetchImpl(`/api/guardian/v1/events/${encodeURIComponent(id)}/${action}`, {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(request.body),
      });
      const body = await response.json();
      if (!response.ok) {
        if (response.status < 500) pending.delete(key);
        if (response.status === 409) await refresh();
        throw Object.assign(Error(body.message || "事件操作失败"), { code: response.status });
      }
      pending.delete(key);
      await refresh();
      return body;
    })();
    running.set(key, operation);
    try { return await operation; } finally { running.delete(key); }
  }
  return { command };
}
