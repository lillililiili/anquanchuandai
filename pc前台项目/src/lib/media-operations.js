// Keep uncertain requests and their original assignment until the server confirms
// their outcome. A second click must never create a second recorder.
export function createMediaOperations({ api, state, makeId = () => crypto.randomUUID(), now = Date.now }) {
  const photos = new Map();
  let starting, stopping, refreshing;
  const rejected = result => ['failed', 'rejected', 'timeout'].includes(result.status);
  const definitive = error => error.status >= 400 && error.status < 500 && error.status !== 408;
  const keyOf = context => JSON.stringify(context);
  async function photo(context) {
    const key = keyOf(context);
    let request = photos.get(key);
    if (!request) { request = { key: makeId() }; photos.set(key, request); }
    if (request.pending) return request.pending;
    request.pending = api.command(context.deviceId, 'take_photo', {}, request.key, undefined, context)
      .then(result => {
        if (!['unknown', 'requesting'].includes(result.status)) photos.delete(key);
        if (rejected(result)) throw Error(result.message || '拍照失败');
        return result;
      }).catch(error => { if (definitive(error)) photos.delete(key); throw error; })
      .finally(() => { request.pending = null; });
    return request.pending;
  }
  function start(context) {
    if (starting) return starting;
    if (state.recording) return Promise.reject(Error('请先结束正在进行的录像请求'));
    const recording = { real: true, deviceId: context.deviceId, person: context.personId, start: now(), context: { ...context }, startKey: makeId(), status: 'requesting' };
    state.recording = recording;
    starting = api.command(context.deviceId, 'start_recording', {}, recording.startKey, undefined, recording.context)
      .then(result => {
        Object.assign(state.recording || recording, { commandId: result.id, status: result.status, message: result.message });
        if (rejected(result)) { state.recording = null; throw Error(result.message || '录像请求失败'); }
        return result;
      }).catch(error => {
        if (state.recording) { state.recording.status = 'unknown'; state.recording.message = '录像请求结果待确认，可查询回执或结束请求'; }
        if (definitive(error)) state.recording = null;
        throw error;
      }).finally(() => { starting = null; });
    return starting;
  }
  async function refresh() {
    if (refreshing) return refreshing;
    const recording = state.recording;
    if (!recording?.real) return;
    refreshing = api.read(recording.deviceId).then(data => {
      if (state.recording?.startKey !== recording.startKey) return;
      const source = (data.commands || []).find(row => (recording.commandId && row.id === recording.commandId) || row.requestId === recording.startKey);
      const stop = (data.commands || []).find(row => (recording.stopCommandId && row.id === recording.stopCommandId) || (recording.stopKey && row.requestId === recording.stopKey));
      if (source) Object.assign(state.recording, { commandId: source.id, status: source.status, message: source.message });
      if (stop) Object.assign(state.recording, { stopCommandId: stop.id, status: stop.status, message: stop.message });
      if (stop?.status === 'completed' || ['completed', 'cancelled', 'failed', 'rejected', 'timeout'].includes(source?.status)) {
        const terminal = stop?.status === 'completed' ? stop : source;
        const result = { ...state.recording, status: terminal.status, message: terminal.message }; state.recording = null; return result;
      }
    }).finally(() => { refreshing = null; });
    return refreshing;
  }
  function stop() {
    if (stopping) return stopping;
    if (!state.recording?.real) return Promise.resolve();
    stopping = (async () => {
      if (starting) await starting.catch(() => {});
      if (!state.recording?.real) return;
      if (!state.recording.commandId) await refresh();
      const recording = state.recording;
      if (!recording) return;
      if (!recording.commandId) throw Error('开始录像的结果尚未确认，请查询回执后重试结束');
      recording.stopKey ||= makeId();
      const result = await api.command(recording.deviceId, 'stop_recording', {}, recording.stopKey, undefined, { ...recording.context, sourceCommandId: recording.commandId });
      Object.assign(recording, { stopCommandId: result.id, status: result.status, message: result.message, stopRequested: true });
      if (['unknown', 'requesting', 'failed', 'rejected', 'timeout'].includes(result.status)) throw Error(result.message || '停止录像尚未确认，请重试');
      if (result.status === 'completed') state.recording = null;
      return result;
    })().finally(() => { stopping = null; });
    return stopping;
  }
  return { photo, start, stop, refresh };
}
