// A command carries user intent only. Device observations and server outcomes
// are never accepted from a browser snapshot.
export function createBusinessCommands({ request, current, replace, makeId = () => crypto.randomUUID() }) {
  const pending = new Map();
  return (type, payload) => {
    const key = JSON.stringify([type, payload]);
    const operationId = pending.get(key) || makeId();
    pending.set(key, operationId);
    let result;
    try { result = request('/api/guardian/v1/business/commands', { operationId, type, payload, expectedSeq: current().seq || 0 }); }
    catch (error) { if (error.code >= 400 && error.code < 500) pending.delete(key); throw error; }
    if (!result?.state || !replace(result.state)) throw Error('操作结果未确认，请刷新后核对');
    pending.delete(key);
    return result.result;
  };
}
