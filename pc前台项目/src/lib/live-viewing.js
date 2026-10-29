// A viewing lease is shared by components in this tab, never by different tabs.
// Only explicit open() starts a device stream. History reads never start one.
export function createLiveViewing({ api, makeId = () => crypto.randomUUID(), schedule = setTimeout, cancel = clearTimeout, pollMs = 5000, releaseMs = 750 }) {
  const entries = new Map();
  function notify(entry) { for (const fn of entry.listeners) fn({ ...entry.state }); }
  function update(entry, values) { entry.state = { ...entry.state, ...values }; notify(entry); }
  async function release(entry) {
    if (entry.users.size || entry.closed) return;
    entry.closed = true; cancel(entry.timer); entry.controller?.abort(); entries.delete(entry.key);
    if (entry.requested) {
      try { await api.command(entry.context.deviceId, 'stop_video', {}, entry.stopKey, undefined, entry.context); }
      catch { /* Server leases expire even if this tab disconnects. */ }
    }
    update(entry, { phase: 'idle', live: null });
  }
  async function poll(entry) {
    if (entry.closed || !entry.users.size) return;
    let retry = true;
    try {
      const result = await api.live(entry.context.deviceId, entry.context, entry.controller.signal);
      if (entry.closed) return;
      const source = result.live;
      const live = source?.hlsUrl ? { ...source, protocol: 'HLS', url: source.hlsUrl } : source;
      update(entry, { phase: live?.url ? 'ready' : 'waiting', live: live?.url ? live : null, error: '', message: result.message || '正在等待设备视频回传' });
    } catch (error) {
      if (!entry.closed && error.name !== 'AbortError') update(entry, { phase: 'error', live: null, error: error.message || '直播状态暂不可用，请重试' });
      if (error.status >= 400 && error.status < 500) { retry = false; entry.started = false; entry.startKey = makeId(); }
    } finally {
      if (retry && !entry.closed && entry.users.size) entry.timer = schedule(() => poll(entry), pollMs);
    }
  }
  async function start(entry) {
    if (entry.starting || entry.closed) return;
    entry.starting = true; entry.controller = new AbortController();
    update(entry, { phase: 'starting', error: '' });
    entry.requested = true;
    try {
      const result = await api.command(entry.context.deviceId, 'start_video', {}, entry.startKey, entry.controller.signal, entry.context);
      if (entry.closed) return;
      if (['failed','rejected','timeout'].includes(result.status)) throw Error(result.message || '设备未能开启直播');
      entry.started = true;
      await poll(entry);
    } catch (error) {
      if (!entry.closed && error.name !== 'AbortError') update(entry, { phase: 'error', live: null, error: error.message || '开启直播结果未确认，可重试同一请求' });
    } finally {
      entry.starting = false;
      // A release racing an accepted start must still release its server lease.
      if (entry.closed) await api.command(entry.context.deviceId, 'stop_video', {}, entry.stopKey, undefined, entry.context).catch(() => {});
    }
  }
  return {
    watch(context, listener) {
      const key = [context.personId, context.deviceId, context.assignmentId, context.assignmentVersion].join('/');
      function obtain() {
        let value = entries.get(key);
        if (!value) {
          value = { key, context: { ...context, viewerSessionId: makeId() }, startKey: makeId(), stopKey: makeId(), users: new Set(), listeners: new Set(), state: { phase: 'idle', live: null, error: '' } };
          entries.set(key, value);
        }
        value.listeners.add(listener); listener({ ...value.state }); return value;
      }
      let entry = obtain();
      const owner = Symbol('viewer'); let disposed = false;
      return {
        async open() {
          if (disposed) return;
          if (entry.closed) { entry.listeners.delete(listener); entry = obtain(); }
          cancel(entry.releaseTimer); entry.users.add(owner);
          if (entry.state.phase === 'ready' || entry.starting) { listener({ ...entry.state }); return; }
          cancel(entry.timer);
          if (entry.started) await poll(entry); else await start(entry);
        },
        close() {
          entry.users.delete(owner);
          if (!entry.users.size) entry.releaseTimer = schedule(() => release(entry), releaseMs);
        },
        dispose() {
          disposed = true; entry.listeners.delete(listener); entry.users.delete(owner);
          if (!entry.users.size) entry.releaseTimer = schedule(() => release(entry), releaseMs);
        },
      };
    },
    async dispose() { for (const entry of [...entries.values()]) { entry.users.clear(); await release(entry); } },
  };
}
