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
      const body = await response.json().catch(() => null);
      const code = response.ok ? Number(body?.code) : response.status;
      if (!response.ok || code >= 400) {
        if (code >= 400 && code < 500) pending.delete(key);
        if (code === 409) await refresh();
        throw Object.assign(Error(body?.message || body?.msg || "事件操作失败"), { code });
      }
      if (body?.id !== id || !Number.isSafeInteger(body.version) || body.version < 1) throw Error("事件操作响应无效，请刷新后重试");
      pending.delete(key);
      // The committed event is the acknowledgment; snapshot refresh is only for display.
      await refresh();
      return body;
    })();
    running.set(key, operation);
    try { return await operation; } finally { running.delete(key); }
  }
  return { command };
}
