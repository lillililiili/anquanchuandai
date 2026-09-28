let client = null;
let microphone = null;

export async function joinChannel(rtc) {
  if (!rtc || !rtc.appId || !rtc.channel || !rtc.token) throw Error("请求安全帽异常");
  const agora = await import("agora-rtc-sdk-ng");
  const AgoraRTC = agora.default;
  await leaveChannel();
  client = AgoraRTC.createClient({ mode: "rtc", codec: "vp8" });
  const uid = rtc.uid === undefined || rtc.uid === null || rtc.uid === "" ? null : /^\d+$/.test(String(rtc.uid)) ? Number(rtc.uid) : rtc.uid;
  await client.join(rtc.appId, rtc.channel, rtc.token, uid);
  microphone = await AgoraRTC.createMicrophoneAudioTrack();
  await client.publish([microphone]);
}

export async function leaveChannel() {
  if (microphone) {
    microphone.close();
    microphone = null;
  }
  if (client) {
    await client.leave();
    client = null;
  }
}

export async function setMuted(muted) {
  if (microphone) await microphone.setEnabled(!muted);
}
