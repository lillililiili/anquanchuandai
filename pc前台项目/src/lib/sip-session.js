import { sipLogDiagnostic, sipRegistrationState } from './sip-diagnostics.js';
import { helmetSipTransportOptions } from './helmet-sip-transport.js';

// SIP.js owns signalling/WebRTC. Server call status remains authoritative for
// which physical helmet answered; a remote track alone is not that evidence.
export async function createSipSession(rtc, { onMediaState = () => {}, onStream = () => {}, active = () => true, signal } = {}, {
  loadSip = () => import('sip.js'),
  makeStream = () => new MediaStream(),
  makeAudio = () => new Audio(),
} = {}) {
  if (!rtc?.server || !/^wss:\/\//i.test(rtc.server) || !rtc.uri || !rtc.target || !rtc.authorizationUsername || !rtc.authorizationPassword) throw Error('安全帽 SIP 通话凭据不完整或未使用安全连接');
  if (rtc.expiresAt && Date.parse(rtc.expiresAt) <= Date.now()) throw Error('通话凭据已过期，请重新发起');
  const SIP = await loadSip();
  if (signal?.aborted || !active()) throw Error('通话已取消');
  const uri = SIP.UserAgent.makeURI(rtc.uri), target = SIP.UserAgent.makeURI(rtc.target);
  if (!uri || !target) throw Error('SIP 地址格式无效');
  const audio = makeAudio();
  audio.autoplay = true;
  const stream = makeStream();
  let inviter, registerer, closed = false, cancelRegistration, closePromise;
  let diagnosticCount = 0;
  const diagnostic = value => { if (import.meta.env?.DEV && value && diagnosticCount++ < 80) console.info('[helmet-sip]', JSON.stringify(value)); };
  const changed = state => { if (!closed && active()) onMediaState(state); };
  const userAgent = new SIP.UserAgent({
    uri, authorizationUsername: rtc.authorizationUsername, authorizationPassword: rtc.authorizationPassword,
    ...helmetSipTransportOptions(SIP, rtc.server),
    transportOptions: { server: rtc.server, traceSip: !!import.meta.env?.DEV },
    logBuiltinEnabled: false,
    logConfiguration: false,
    ...(import.meta.env?.DEV ? { logConnector: (_level, _category, _label, content) => diagnostic(sipLogDiagnostic(content)) } : {}),
    sessionDescriptionHandlerFactoryOptions: { peerConnectionConfiguration: { iceServers: rtc.iceServers || [] } },
    delegate: { onConnect: () => diagnostic({ event: 'transport_connected' }), onDisconnect: () => { diagnostic({ event: 'transport_disconnected' }); changed('failed'); }, onInvite: invitation => { void invitation.reject(); } },
  });
  function close() {
    if (closePromise) return closePromise;
    closed = true;
    closePromise = cleanup();
    return closePromise;
  }
  async function cleanup() {
    signal?.removeEventListener('abort', aborted);
    cancelRegistration?.();
    audio.pause(); audio.srcObject = null;
    for (const track of stream.getTracks()) track.stop();
    for (const sender of inviter?.sessionDescriptionHandler?.peerConnection?.getSenders?.() || []) sender.track?.stop();
    onStream(null);
    try {
      if (inviter?.state === SIP.SessionState.Established) await inviter.bye();
      else if (inviter && [SIP.SessionState.Initial, SIP.SessionState.Establishing].includes(inviter.state)) await inviter.cancel();
    } finally {
      try { await registerer?.unregister(); } finally { await userAgent.stop(); }
    }
  }
  const aborted = () => { void close().catch(() => {}); };
  signal?.addEventListener('abort', aborted, { once:true });
  const result = { close, resumeAudio: () => audio.play(), setMuted: async muted => {
    const tracks = inviter?.sessionDescriptionHandler?.peerConnection?.getSenders?.().map(sender => sender.track).filter(track => track?.kind === 'audio') || [];
    if (!tracks.length) throw Error('本端尚未加入通话');
    tracks.forEach(track => { track.enabled = !muted; });
  } };
  try {
    if (signal?.aborted) throw Error('通话已取消');
    await userAgent.start();
    diagnostic({ event: 'transport_start_resolved' });
    if (closed || signal?.aborted || !active()) throw Error('通话已取消');
    registerer = new SIP.Registerer(userAgent);
    await new Promise((resolve, reject) => {
      const cleanup = () => { clearTimeout(timer); registerer.stateChange.removeListener(listener); cancelRegistration = null; };
      const listener = state => {
        diagnostic({ event: 'registration_state', state: sipRegistrationState(state) });
        if (state === SIP.RegistererState.Registered) { cleanup(); resolve(); }
        else if (state === SIP.RegistererState.Terminated) { cleanup(); reject(Error('SIP 注册失败')); }
      };
      const timer = setTimeout(() => { diagnostic({ event: 'registration_timeout' }); cleanup(); reject(Error('SIP 注册超时')); }, 20000);
      cancelRegistration = () => { cleanup(); reject(Error('通话已取消')); };
      registerer.stateChange.addListener(listener);
      diagnostic({ event: 'registration_requested' });
      registerer.register({ requestDelegate: { onReject: () => { cleanup(); reject(Error('SIP 注册被拒绝')); } } }).catch(error => { cleanup(); reject(error); });
    });
    if (closed || signal?.aborted || !active()) throw Error('通话已取消');
    inviter = new SIP.Inviter(userAgent, target, { sessionDescriptionHandlerOptions: { constraints: { audio: true, video: rtc.video === true } } });
    inviter.stateChange.addListener(state => {
      if (closed || !active()) return;
      if (state === SIP.SessionState.Established) {
        const pc = inviter.sessionDescriptionHandler?.peerConnection;
        const update = () => {
          if (closed || !active()) return;
          for (const receiver of pc?.getReceivers?.() || []) if (receiver.track && !stream.getTracks().some(track => track.id === receiver.track.id)) stream.addTrack(receiver.track);
          audio.srcObject = stream;
          onStream(stream);
          void audio.play().catch(() => changed('playback_blocked'));
          changed(stream.getVideoTracks().length ? 'remote_video' : stream.getAudioTracks().length ? 'remote_audio' : 'local_joined');
        };
        if (pc) {
          pc.addEventListener('track', update);
          pc.addEventListener('connectionstatechange', () => { if (['failed','disconnected'].includes(pc.connectionState)) changed('failed'); });
        }
        update();
      } else if (state === SIP.SessionState.Terminated) {
        changed('ended');
        void close().catch(() => {});
      }
    });
    await inviter.invite();
    if (closed || signal?.aborted || !active()) throw Error('通话已取消');
    if (inviter.state !== SIP.SessionState.Established) changed('local_joined');
    return result;
  } catch (error) {
    try { await close(); } catch { /* Preserve the signalling/media error. */ }
    throw error;
  }
}
