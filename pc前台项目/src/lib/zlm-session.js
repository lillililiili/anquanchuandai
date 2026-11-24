import { authFetch } from './auth.js';

// SDP always crosses the authenticated application proxy. Never send a user
// token to a vendor-supplied URL or retain middleware credentials in the UI.
export function splitProxyPath(value) {
  if (typeof value !== 'string' || !/^\/api\/guardian\/v1\/split\/sessions\/[A-Za-z0-9_-]+(?:\/devices\/[A-Za-z0-9._%~-]+\/(?:play|talk)|\/(?:heartbeat|end))$/.test(value)) throw Error('分体帽会话地址无效，请重新发起');
  return value;
}

export function waitForZlmIce(peer, signal, { schedule = setTimeout, cancel = clearTimeout, timeout = 8000 } = {}) {
  if (signal.aborted) return Promise.reject(Error('会话已取消'));
  if (peer.iceGatheringState === 'complete') return Promise.resolve();
  return new Promise((resolve, reject) => {
    const finish = error => { cancel(timer); peer.removeEventListener('icegatheringstatechange', changed); signal.removeEventListener('abort', aborted); error ? reject(error) : resolve(); };
    const changed = () => { if (peer.iceGatheringState === 'complete') finish(); };
    const aborted = () => finish(Error('会话已取消'));
    const timer = schedule(() => finish(Error('网络候选收集超时，请检查网络后重试')), timeout);
    peer.addEventListener('icegatheringstatechange', changed); signal.addEventListener('abort', aborted, { once: true });
  });
}

export async function createZlmSession(credentials, {
  fetchImpl = authFetch, PeerConnection = globalThis.RTCPeerConnection, Stream = globalThis.MediaStream,
  microphoneStream, signal, onMediaState = () => {}, onStream = () => {}, onDeviceState = () => {},
  schedule = setTimeout, cancel = clearTimeout, audioFactory = () => typeof Audio === 'undefined' ? null : new Audio(),
  playbackOnly = false, talkOnly = false,
} = {}) {
  const sessions = credentials?.sessions;
  if (credentials?.protocol !== 'ZLM_WEBRTC' || !Array.isArray(sessions) || !sessions.length || sessions.length > 8 ||
      sessions.some(row => !row.deviceId) || new Set(sessions.map(row => row.deviceId)).size !== sessions.length) throw Error('分体帽会话须包含 1 至 8 顶不同的安全帽');
  if (credentials.expiresAt && Date.parse(credentials.expiresAt) <= Date.now()) throw Error('会话授权已过期');
  if (talkOnly && (playbackOnly || sessions.length !== 1)) throw Error('监看对讲需要当前设备的会话');
  const directions = talkOnly ? ['talk'] : playbackOnly ? ['play'] : ['play', 'talk'];
  sessions.forEach(row => { splitProxyPath(row.playUrl); if (!playbackOnly) splitProxyPath(row.talkUrl); });
  const heartbeatUrl = splitProxyPath(credentials.heartbeatUrl);
  if (!playbackOnly && !(microphoneStream?.getAudioTracks?.() || []).some(track => track.readyState !== 'ended')) throw Error('未取得麦克风，未建立对讲');
  const entries = new Map(), streams = new Map(), players = new Map(), connected = new Set();
  const abort = new AbortController();
  let closed = false, heartbeat, muted = false, heartbeatBusy = false;
  const update = (row, kind, state) => { if (!closed) onDeviceState({ deviceId: row.deviceId, kind, state }); };
  function closeEntry(entry) {
    cancel(entry.timer); cancel(entry.disconnectedTimer); entry.abort.abort(); entry.peer.ontrack = null; entry.peer.onconnectionstatechange = null; entry.peer.close();
    connected.delete(entry.key);
    if (entry.kind === 'play') { const player = players.get(entry.row.deviceId); if (player) { player.pause(); player.srcObject = null; } players.delete(entry.row.deviceId); streams.delete(entry.row.deviceId); if (!closed) onStream(null, entry.row.deviceId); }
  }
  async function close() {
    if (closed) return;
    closed = true; cancel(heartbeat); abort.abort(); signal?.removeEventListener('abort', cancelled);
    for (const entry of entries.values()) closeEntry(entry);
    entries.clear(); connected.clear();
    for (const player of players.values()) { player.pause(); player.srcObject = null; }
    players.clear(); streams.clear();
    // The parent owns the microphone and the authorized server hangup.
  }
  const cancelled = () => { void close(); };
  signal?.addEventListener('abort', cancelled, { once: true });
  async function negotiate(row, kind) {
    if (closed || signal?.aborted) throw Error('会话已取消');
    const key = row.deviceId + ':' + kind, old = entries.get(key);
    if (old) closeEntry(old);
    const peer = new PeerConnection({ iceServers: credentials.iceServers || [] });
    const entry = { key, row, kind, peer, abort: new AbortController() };
    entries.set(key, entry); update(row, kind, 'connecting');
    const active = () => !closed && entries.get(key) === entry;
    const fail = state => { if (active()) { update(row, kind, state); closeEntry(entry); entries.delete(key); if (!entries.size) onMediaState('failed'); } };
    peer.onconnectionstatechange = () => {
      if (!active()) return;
      if (peer.connectionState === 'connected') {
        cancel(entry.timer); cancel(entry.disconnectedTimer); connected.add(key); update(row, kind, 'connected');
        onMediaState(kind === 'play' ? 'remote_audio' : 'local_joined');
        if (!playbackOnly && connected.has(row.deviceId + ':play') && connected.has(row.deviceId + ':talk')) onMediaState('peer_connected');
      } else if (['failed', 'closed'].includes(peer.connectionState)) fail('failed');
      else if (peer.connectionState === 'disconnected') { connected.delete(key); update(row, kind, 'disconnected'); entry.disconnectedTimer ||= schedule(() => fail('failed'), 10000); }
    };
    if (kind === 'play') {
      peer.addTransceiver('audio', { direction: 'recvonly' });
      if (playbackOnly || credentials.video !== false) peer.addTransceiver('video', { direction: 'recvonly' });
      const remote = new Stream(); streams.set(row.deviceId, remote);
      peer.ontrack = event => {
        if (!active()) return;
        remote.addTrack(event.track); onStream(remote, row.deviceId);
        if (!playbackOnly && event.track.kind === 'audio') {
          let player = players.get(row.deviceId);
          if (!player) { player = audioFactory(); if (player) players.set(row.deviceId, player); }
          if (player) { player.srcObject = remote; void Promise.resolve(player.play()).catch(() => { if (active()) onMediaState('playback_blocked'); }); }
        }
      };
    } else {
      const track = microphoneStream.getAudioTracks()[0];
      const transceiver = peer.addTransceiver(track, { direction: 'sendonly', streams: [microphoneStream] });
      entry.sender = transceiver.sender;
      const codecs = globalThis.RTCRtpSender?.getCapabilities?.('audio')?.codecs;
      if (codecs?.length && transceiver.setCodecPreferences) {
        try { transceiver.setCodecPreferences([...codecs.filter(c => /audio\/pcm[ua]/i.test(c.mimeType)), ...codecs.filter(c => !/audio\/pcm[ua]/i.test(c.mimeType))]); } catch { /* Optional browser capability. */ }
      }
      if (muted) await entry.sender.replaceTrack(null);
    }
    try {
      await peer.setLocalDescription(await peer.createOffer());
      await waitForZlmIce(peer, entry.abort.signal, { schedule, cancel });
      const timeout = schedule(() => entry.abort.abort(), 30000);
      let response;
      try { response = await fetchImpl(splitProxyPath(kind === 'play' ? row.playUrl : row.talkUrl), { method: 'POST', headers: { 'Content-Type': 'application/sdp' }, body: peer.localDescription.sdp, signal: entry.abort.signal }); }
      finally { cancel(timeout); }
      if (!response.ok) throw Error(response.status === 401 || response.status === 403 ? '会话授权已失效' : '分体帽媒体协商失败');
      const sdp = await response.text();
      if (!active()) throw Error('会话已取消');
      if (!sdp.startsWith('v=0')) throw Error('媒体协商应答无效');
      await peer.setRemoteDescription({ type: 'answer', sdp });
      if (!active()) throw Error('会话已取消');
      if (peer.connectionState !== 'connected') entry.timer = schedule(() => fail('timeout'), 30000);
    } catch (error) { fail('failed'); throw error; }
  }
  async function renew() {
    if (closed || heartbeatBusy) return;
    heartbeatBusy = true;
    const timeout = schedule(() => abort.abort(), 15000);
    try {
      const response = await fetchImpl(heartbeatUrl, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}', signal: abort.signal });
      if (!response.ok) throw Error('续期失败');
    } catch { if (!closed) { onMediaState('failed'); await close(); } }
    finally { cancel(timeout); heartbeatBusy = false; if (!closed) heartbeat = schedule(renew, 60000); }
  }
  try {
    const results = await Promise.allSettled(sessions.flatMap(row => directions.map(kind => negotiate(row, kind))));
    if (closed || signal?.aborted) throw Error('会话已取消');
    if (results.every(result => result.status === 'rejected')) throw Error('分体帽连接未建立，请检查设备网络后重试');
    // The active monitor already renews this lease while its microphone is open.
    if (!talkOnly) heartbeat = schedule(renew, 60000);
    return {
      close,
      async setMuted(value) { muted = !!value; await Promise.all([...entries.values()].filter(entry => entry.kind === 'talk').map(entry => entry.sender.replaceTrack(muted ? null : microphoneStream.getAudioTracks()[0]))); },
      async resumeAudio() { await Promise.all([...players.values()].map(player => player.play())); },
      async retry() { await Promise.allSettled(sessions.flatMap(row => directions.filter(kind => !entries.has(row.deviceId + ':' + kind)).map(kind => negotiate(row, kind)))); },
    };
  } catch (error) { await close(); throw error; }
}

export async function openZlmLive(live, video, options = {}) {
  const session = await createZlmSession({ ...live, sessions: [{ deviceId: live.deviceId || live.streamId || live.sessionId, playUrl: live.playUrl || live.url || live.whepUrl }] }, {
    ...options, playbackOnly: true,
    onStream: stream => { video.srcObject = stream; if (!stream) { video.pause(); return; } void video.play().catch(() => options.onState?.('playback_blocked')); },
    onMediaState: state => options.onState?.(state === 'remote_audio' ? 'playing' : state, state === 'failed' ? '分体帽视频连接已中断，请重新播放' : ''),
  });
  return { close: async () => { await session.close(); video.pause(); video.srcObject = null; } };
}
