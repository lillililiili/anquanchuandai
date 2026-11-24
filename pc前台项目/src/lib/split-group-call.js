import { createZlmSession } from './zlm-session.js';
import { communicationGuard } from './communication-guard.js';

export function createSplitGroupCall({ fetchImpl, guard = communicationGuard, createSession = createZlmSession,
  getUserMedia = () => navigator.mediaDevices.getUserMedia({ audio: true, video: false }), makeId = () => crypto.randomUUID(),
  onStream = () => {}, onChange = () => {}, schedule = setTimeout, cancel = clearTimeout } = {}) {
  let row, rtc, microphone, reservation, payload, ending, generation = 0, requestController, mediaController, joinedSignature = '', joining = false;
  let state = { phase: 'idle', error: '', devices: {}, muted: false };
  const update = value => { state = { ...state, ...value }; onChange({ ...state, devices: { ...state.devices } }); };
  async function request(path, body, requestFetch = fetchImpl) {
    const controller = new AbortController(), timer = schedule(() => controller.abort(), 30000);
    requestController = controller;
    try {
      const response = await requestFetch('/api/guardian/v1/mobile/calls' + path, { signal: controller.signal, ...(body === undefined ? {} : { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) throw Object.assign(Error(result.message || '分体帽调度请求失败'), { status: response.status });
      return result;
    } finally { cancel(timer); if (requestController === controller) requestController = null; }
  }
  async function leave() {
    mediaController?.abort(); mediaController = null;
    const active = rtc; rtc = null; await active?.close();
    for (const track of microphone?.getTracks?.() || []) track.stop();
    microphone = null;
  }
  function release() { guard.release(reservation); reservation = null; payload = null; }
  async function reportJoined(operation) {
    if (joining || operation !== generation || !row?.id) return;
    const connectedDeviceIds = (row.credentials?.sessions || []).filter(device => state.devices[device.deviceId + ':play'] === 'connected' && state.devices[device.deviceId + ':talk'] === 'connected').map(device => device.deviceId).sort();
    const signature = connectedDeviceIds.join(',');
    if (!connectedDeviceIds.length || joinedSignature === signature) return;
    joining = true; let reported = false;
    try {
      await request('/' + encodeURIComponent(row.id) + '/joined', { peerConnected: true, connectedDeviceIds });
      if (operation === generation) { joinedSignature = signature; reported = true; }
    } catch (error) { if (operation === generation) update({ error: '媒体已连接，平台入会记录尚未确认；请重试连接或结束会话' }); }
    finally { joining = false; if (reported) void reportJoined(operation); }
  }
  async function end(requestFetch = fetchImpl) {
    if (ending) return ending;
    ++generation; update({ phase: 'ending' });
    ending = (async () => {
      await leave();
      if (!row?.id && payload) {
        // Resolve the original idempotent request before ending it. Never send
        // another key when a network timeout left creation uncertain.
        try { row = await request('', payload, requestFetch); }
        catch { update({ phase: 'unknown', error: '创建结果尚未确认，本地音频已关闭；请重试结束同一请求' }); return; }
      }
      if (!row?.id) { release(); update({ phase: 'ended' }); return; }
      try {
        const result = await request('/' + encodeURIComponent(row.id) + '/end', {}, requestFetch);
        if (!['ended','failed'].includes(result.status)) { update({ phase: 'unknown', error: '本地连接已关闭，服务器结束状态待确认，请重试结束' }); return; }
        release(); update({ phase: 'ended', error: '', devices: {} }); row = null;
      } catch { update({ phase: 'unknown', error: '本地连接已关闭，结束请求未确认，请重试' }); }
    })().finally(() => { ending = null; });
    return ending;
  }
  async function start(recipients, { video = false } = {}) {
    if (reservation || !Array.isArray(recipients) || recipients.length < 2 || recipients.length > 8 || new Set(recipients.map(r => r.deviceId)).size !== recipients.length) throw Error('请选择 2 至 8 名领用不同分体帽的人员，并先结束已有通话');
    if (recipients.some(r => !r.personId || !r.deviceId || !r.assignmentId || r.assignmentVersion == null)) throw Error('人员领用关系已变化，请刷新');
    const operation = ++generation;
    reservation = guard.acquire(); row = null; payload = null; joinedSignature = ''; joining = false;
    update({ phase: 'preparing', error: '', devices: {}, muted: false });
    try {
      const active = await request('?owned=true&status=active');
      if (!Array.isArray(active) || active.some(call => !['ended','failed'].includes(call.status))) throw Error('当前账号有未结束会话，请先刷新并结束已有通话');
      if (operation !== generation) return;
      let permissionTimer, permissionExpired = false;
      const pending = Promise.resolve().then(getUserMedia).then(stream => { if (operation !== generation || permissionExpired) { stream.getTracks().forEach(track => track.stop()); throw Error('麦克风准备已取消'); } return stream; });
      let prepared;
      try { prepared = await Promise.race([pending, new Promise((_, reject) => { permissionTimer = schedule(() => { permissionExpired = true; reject(Error('麦克风授权超时，未发起呼叫')); }, 20000); })]); }
      finally { cancel(permissionTimer); }
      if (operation !== generation) { prepared?.getTracks().forEach(track => track.stop()); return; }
      microphone = prepared;
      if (!microphone.getAudioTracks().length) throw Error('未取得麦克风，未发起呼叫');
      payload = { recipients, video, idempotencyKey: makeId() };
      update({ phase: 'requesting' }); const created = await request('', payload);
      if (operation !== generation) return;
      row = created;
      if (!row.id || row.credentials?.protocol !== 'ZLM_WEBRTC') throw Error('未取得分体帽会话凭证');
      update({ phase: 'connecting', recordId: row.id });
      mediaController = new AbortController();
      const connected = await createSession(row.credentials, {
        fetchImpl, microphoneStream: microphone, signal: mediaController.signal,
        onStream: (stream, id) => { if (operation === generation) onStream(stream, id); },
        onDeviceState: value => { if (operation === generation) { update({ devices: { ...state.devices, [value.deviceId + ':' + value.kind]: value.state } }); void reportJoined(operation); } },
        onMediaState: value => {
          if (operation !== generation) return;
          if (value === 'failed') { update({ error: '媒体连接已中断，正在结束会话' }); void end(); }
          else if (value === 'playback_blocked') update({ error: '浏览器暂停了通话声音，请点击播放声音' });
          else if (value === 'peer_connected') update({ phase: 'active' });
        },
      });
      if (operation !== generation) { await connected.close(); return; }
      rtc = connected;
      await reportJoined(operation);
    } catch (error) {
      if (operation !== generation) return;
      await leave();
      if (row?.id) { update({ error: error.message }); await end(); }
      else if (payload && !(error.status >= 400 && error.status < 500 && error.status !== 408)) update({ phase: 'unknown', error: '呼叫结果未确认，本机已退出音频；请结束同一请求，勿重复发起' });
      else { release(); update({ phase: 'failed', error: error.message || '无法发起分体帽调度' }); }
    }
  }
  return { start, end, getState: () => state,
    async setMuted(value) { if (!rtc) throw Error('本端尚未连接'); await rtc.setMuted(value); update({ muted: value }); },
    async retry() { await rtc?.retry(); await reportJoined(generation); }, resumeAudio: () => rtc?.resumeAudio(),
    async revoke(requestFetch) { requestController?.abort(); await end(requestFetch); },
  };
}
