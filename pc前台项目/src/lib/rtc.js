import { createSipSession } from './sip-session.js';
import { communicationGuard } from './communication-guard.js';

export function createRtcSession(loadAgora = () => import("agora-rtc-sdk-ng"), sipFactory = createSipSession, guard = communicationGuard, {
  getUserMedia = constraints => {
    if (!globalThis.navigator?.mediaDevices?.getUserMedia) throw Error('当前浏览器无法使用麦克风，请使用安全地址并检查录音设备');
    return globalThis.navigator.mediaDevices.getUserMedia(constraints);
  }, schedule = setTimeout, cancel = clearTimeout, microphoneTimeout = 20000,
} = {}) {
  let current = null;
  let preparedMicrophone = null, preparingMicrophone = null;
  let generation = 0;
  let remoteStream = null;
  const streamListeners = new Set();
  const publishStream = stream => { remoteStream = stream; streamListeners.forEach(listener => listener(stream)); };
  const stopStream = stream => { for (const track of stream?.getTracks?.() || []) track.stop(); };

  async function prepareMicrophone({ reservation, onMediaState = () => {} } = {}) {
    guard.assertAvailable(reservation);
    if (current || preparingMicrophone || preparedMicrophone) throw Error('请先结束当前音频准备或通话');
    const controller = new AbortController();
    const pending = { controller };
    preparingMicrophone = pending;
    onMediaState('microphone_permission');
    try {
      const stream = await new Promise((resolve, reject) => {
        let settled = false;
        const done = (error, stream) => {
          if (settled) { stopStream(stream); return; }
          settled = true; cancel(timer); controller.signal.removeEventListener('abort', aborted);
          if (error) reject(error); else resolve(stream);
        };
        const aborted = () => done(Error('麦克风准备已取消，未呼叫设备'));
        const timer = schedule(() => done(Error('等待电脑麦克风授权超时，未呼叫设备；请允许麦克风后重试')), microphoneTimeout);
        controller.signal.addEventListener('abort', aborted, { once: true });
        // Prepare after read-only recovery and before any dial POST. Browser
        // permission prompts may never settle; late streams must still stop.
        try {
          Promise.resolve(getUserMedia({ audio: true, video: false })).then(stream => {
            if (!(stream?.getAudioTracks?.() || []).some(track => track.readyState !== 'ended')) {
              stopStream(stream); done(Error('未取得可用的电脑麦克风，未呼叫设备')); return;
            }
            done(null, stream);
          }, error => {
            const messages = { NotAllowedError: '电脑麦克风权限被拒绝，未呼叫设备', NotFoundError: '电脑未检测到麦克风，未呼叫设备', NotReadableError: '电脑麦克风被占用或无法读取，未呼叫设备', SecurityError: '浏览器安全设置阻止麦克风，未呼叫设备' };
            done(Error(messages[error?.name] || error?.message || '电脑麦克风准备失败，未呼叫设备'));
          });
        } catch (error) { done(error); }
      });
      if (preparingMicrophone !== pending || controller.signal.aborted) { stopStream(stream); throw Error('麦克风准备已取消，未呼叫设备'); }
      preparedMicrophone = { stream, reservation };
      onMediaState('microphone_ready');
    } finally { if (preparingMicrophone === pending) preparingMicrophone = null; }
  }

  async function close(session) {
    if (!session) return;
    if ('sip' in session) {
      try { if (session.sip) await session.sip.close(); else session.controller?.abort(); }
      finally { stopStream(session.microphoneStream); }
      return;
    }
    session.client.removeAllListeners();
    for (const track of session.remote.values()) track.stop();
    session.remote.clear();
    session.microphone?.close();
    await session.client.leave();
  }

  async function leaveChannel(reservation) {
    guard.assertAvailable(reservation);
    generation++;
    preparingMicrophone?.controller.abort();
    preparingMicrophone = null;
    stopStream(preparedMicrophone?.stream); preparedMicrophone = null;
    const previous = current;
    current = null;
    publishStream(null);
    await close(previous);
  }

  async function joinChannel(rtc, { onMediaState = () => {}, reservation } = {}) {
    guard.assertAvailable(reservation);
    if (String(rtc?.protocol).toUpperCase() === 'SIP') {
      const microphone = preparedMicrophone;
      if (microphone && microphone.reservation !== reservation) throw Error('麦克风准备不属于当前会话');
      preparedMicrophone = null;
      const operation = generation + 1;
      try {
        await leaveChannel(reservation);
        guard.assertAvailable(reservation);
        if (generation !== operation) throw Error('通话已取消');
      } catch (error) { stopStream(microphone?.stream); throw error; }
      const placeholder = { sip: null, controller: new AbortController(), callId:rtc.callId || rtc.channel, microphoneStream: microphone?.stream };
      current = placeholder;
      try {
        const sip = await sipFactory(rtc, { signal: placeholder.controller.signal, microphoneStream: microphone?.stream, onMediaState, onStream: stream => { if (current === placeholder) publishStream(stream); }, active: () => generation === operation && current === placeholder });
        if (generation !== operation || current !== placeholder) { await sip.close(); throw Error('通话已取消'); }
        placeholder.sip = sip;
      } catch (error) { if (current === placeholder) current = null; stopStream(microphone?.stream); throw error; }
      return;
    }
    if (!rtc || !rtc.appId || !rtc.channel || !rtc.token ||
        (rtc.protocol && String(rtc.protocol).toUpperCase() !== "AGORA")) {
      throw Error("通话凭证或媒体协议不可用");
    }
    await leaveChannel(reservation);
    const operation = generation;
    const { default: AgoraRTC } = await loadAgora();
    if (operation !== generation) throw Error("通话已取消");
    const session = {
      callId: rtc.callId || rtc.channel,
      client: AgoraRTC.createClient({ mode: "rtc", codec: "vp8" }),
      microphone: null,
      remote: new Map(),
    };
    current = session;
    const active = () => current === session && operation === generation;
    const changed = (state) => { if (active()) onMediaState(state); };
    const removeRemote = (user) => {
      if (!active()) return;
      session.remote.get(user.uid)?.stop();
      session.remote.delete(user.uid);
      if (!session.remote.size) changed("local_joined");
    };
    session.client.on("user-published", (user, mediaType) => {
      if (mediaType !== "audio" || !active()) return;
      // Agora emits asynchronously; failures must be handled inside the callback.
      void (async () => {
        await session.client.subscribe(user, "audio");
        if (!active() || !user.audioTrack) return;
        session.remote.set(user.uid, user.audioTrack);
        user.audioTrack.play();
        changed("remote_audio");
      })().catch(() => changed("failed"));
    });
    session.client.on("user-unpublished", (user, mediaType) => {
      if (mediaType === "audio") removeRemote(user);
    });
    session.client.on("user-left", removeRemote);
    session.client.on("connection-state-change", (state) => {
      if (state === "DISCONNECTED") changed("failed");
    });
    try {
      const uid = rtc.uid == null || rtc.uid === "" ? null :
        /^\d+$/.test(String(rtc.uid)) ? Number(rtc.uid) : rtc.uid;
      await session.client.join(rtc.appId, rtc.channel, rtc.token, uid);
      if (!active()) throw Error("通话已取消");
      const microphone = await AgoraRTC.createMicrophoneAudioTrack();
      if (!active()) { microphone.close(); throw Error("通话已取消"); }
      session.microphone = microphone;
      await session.client.publish([microphone]);
      if (!active()) throw Error("通话已取消");
    } catch (error) {
      if (active()) {
        current = null;
        generation++;
        try { await close(session); } catch { /* Preserve the original join error. */ }
      }
      throw error;
    }
  }

  async function setMuted(muted, reservation) {
    guard.assertAvailable(reservation);
    if (current?.sip) return current.sip.setMuted(muted);
    if (!current?.microphone) throw Error("本端尚未加入通话");
    await current.microphone.setEnabled(!muted);
  }

  function subscribeMedia(listener) { streamListeners.add(listener); listener(remoteStream); return () => streamListeners.delete(listener); }
  return { prepareMicrophone, joinChannel, leaveChannel, setMuted, subscribeMedia, getActiveCallId:()=>current?.callId, resumeAudio: reservation => { guard.assertAvailable(reservation); return current?.sip?.resumeAudio(); } };
}

const session = createRtcSession();
export const prepareMicrophone = options => session.prepareMicrophone(options);
export const joinChannel = (...args) => session.joinChannel(...args);
export const leaveChannel = reservation => session.leaveChannel(reservation);
export const setMuted = (muted, reservation) => session.setMuted(muted, reservation);
export const subscribeMedia = listener => session.subscribeMedia(listener);
export const resumeAudio = reservation => session.resumeAudio(reservation);
export const getActiveCallId = () => session.getActiveCallId();
