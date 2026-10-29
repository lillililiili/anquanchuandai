import { createSipSession } from './sip-session.js';
import { communicationGuard } from './communication-guard.js';

export function createRtcSession(loadAgora = () => import("agora-rtc-sdk-ng"), sipFactory = createSipSession, guard = communicationGuard) {
  let current = null;
  let generation = 0;
  let remoteStream = null;
  const streamListeners = new Set();
  const publishStream = stream => { remoteStream = stream; streamListeners.forEach(listener => listener(stream)); };

  async function close(session) {
    if (!session) return;
    if ('sip' in session) {
      if (session.sip) await session.sip.close();
      else session.controller?.abort();
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
    const previous = current;
    current = null;
    publishStream(null);
    await close(previous);
  }

  async function joinChannel(rtc, { onMediaState = () => {}, reservation } = {}) {
    guard.assertAvailable(reservation);
    if (String(rtc?.protocol).toUpperCase() === 'SIP') {
      await leaveChannel(reservation);
      const operation = generation;
      const placeholder = { sip: null, controller: new AbortController(), callId:rtc.callId || rtc.channel };
      current = placeholder;
      try {
        const sip = await sipFactory(rtc, { signal: placeholder.controller.signal, onMediaState, onStream: stream => { if (current === placeholder) publishStream(stream); }, active: () => generation === operation && current === placeholder });
        if (generation !== operation || current !== placeholder) { await sip.close(); throw Error('通话已取消'); }
        placeholder.sip = sip;
      } catch (error) { if (current === placeholder) current = null; throw error; }
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
  return { joinChannel, leaveChannel, setMuted, subscribeMedia, getActiveCallId:()=>current?.callId, resumeAudio: reservation => { guard.assertAvailable(reservation); return current?.sip?.resumeAudio(); } };
}

const session = createRtcSession();
export const joinChannel = (...args) => session.joinChannel(...args);
export const leaveChannel = reservation => session.leaveChannel(reservation);
export const setMuted = (muted, reservation) => session.setMuted(muted, reservation);
export const subscribeMedia = listener => session.subscribeMedia(listener);
export const resumeAudio = reservation => session.resumeAudio(reservation);
export const getActiveCallId = () => session.getActiveCallId();
