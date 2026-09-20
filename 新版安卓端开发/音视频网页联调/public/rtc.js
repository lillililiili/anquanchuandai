let sdkPromise;
function loadAgora() {
  if (!sdkPromise) sdkPromise = new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = '/agora-sdk.js';
    script.onload = () => { window.AgoraRTC.setLogLevel(4); window.AgoraRTC.disableLogUpload(); resolve(window.AgoraRTC); };
    script.onerror = () => { sdkPromise = null; reject(new Error('声网 SDK 加载失败')); };
    document.head.append(script);
  });
  return sdkPromise;
}

export class WebRtcMedia {
  constructor({ source, caller, iceServers, signal, status, remote, failure }) {
    this.source = source; this.caller = caller; this.signal = signal;
    this.pending = []; this.closed = false;
    this.pc = new RTCPeerConnection({ iceServers });
    this.pc.onicecandidate = event => { if (event.candidate) signal({ type: 'candidate', candidate: event.candidate.toJSON() }); };
    this.pc.ontrack = event => { if (!this.closed) remote(event.streams[0] || new MediaStream([event.track])); };
    this.pc.onconnectionstatechange = () => {
      if (this.closed) return;
      status(this.pc.connectionState === 'connected');
      if (this.pc.connectionState === 'failed') failure(new Error('媒体连接失败；跨网络时请配置 TURN 服务'));
    };
    source.stream.getTracks().forEach(track => this.pc.addTrack(track, source.stream));
  }
  async start() {
    if (this.caller) {
      const offer = await this.pc.createOffer();
      if (this.closed) return;
      await this.pc.setLocalDescription(offer);
      if (!this.closed) this.signal({ type: 'offer', sdp: this.pc.localDescription.toJSON() });
    }
  }
  async receive(data) {
    if (this.closed) return;
    if (data.type === 'candidate') {
      if (this.pc.remoteDescription) await this.pc.addIceCandidate(data.candidate);
      else this.pending.push(data.candidate);
      return;
    }
    await this.pc.setRemoteDescription(data.sdp);
    if (this.closed) return;
    for (const candidate of this.pending.splice(0)) await this.pc.addIceCandidate(candidate);
    if (data.type === 'offer') {
      const answer = await this.pc.createAnswer();
      if (this.closed) return;
      await this.pc.setLocalDescription(answer);
      if (!this.closed) this.signal({ type: 'answer', sdp: this.pc.localDescription.toJSON() });
    }
  }
  async stats() {
    if (this.closed) return {};
    const stats = await this.pc.getStats();
    let sent = 0, received = 0, resolution = '—';
    stats.forEach(item => {
      if (item.type === 'outbound-rtp') sent += item.bytesSent || 0;
      if (item.type === 'inbound-rtp') {
        received += item.bytesReceived || 0;
        if (item.frameWidth) resolution = `${item.frameWidth} × ${item.frameHeight}`;
      }
    });
    return { sent, received, resolution };
  }
  close() { this.closed = true; this.pc.close(); }
}

export class AgoraMedia {
  constructor({ source, credentials, status, remote, failure, renew, departed }) {
    Object.assign(this, { source, credentials, status, remote, failure, renew, departed });
    this.closed = false; this.published = false; this.tracks = []; this.mediaStream = new MediaStream();
  }
  report() {
    const remoteAudio = this.client?.remoteUsers.some(user => user.hasAudio && user.audioTrack);
    this.status(!!(this.published && remoteAudio && this.client.connectionState === 'CONNECTED'));
  }
  async start() {
    const sdk = await loadAgora();
    if (this.closed) return;
    const client = this.client = sdk.createClient({ mode: 'rtc', codec: 'vp8' });
    client.on('user-published', async (user, mediaType) => {
      if (mediaType !== 'audio' && mediaType !== 'video') return;
      try {
        await client.subscribe(user, mediaType);
        if (this.closed) return;
        const track = mediaType === 'audio' ? user.audioTrack : user.videoTrack;
        const raw = track?.getMediaStreamTrack();
        for (const old of this.mediaStream.getTracks().filter(t => t.kind === mediaType)) this.mediaStream.removeTrack(old);
        if (raw) this.mediaStream.addTrack(raw);
        this.remote(this.mediaStream); this.report();
      } catch (error) { if (!this.closed) this.failure(error); }
    });
    client.on('user-unpublished', (user, kind) => {
      for (const old of this.mediaStream.getTracks().filter(t => t.kind === kind)) this.mediaStream.removeTrack(old);
      this.remote(this.mediaStream);
    });
    client.on('user-left', () => { if (!this.closed) { this.status(false); this.departed(); } });
    client.on('connection-state-change', () => { if (!this.closed) this.report(); });
    client.on('token-privilege-will-expire', () => this.renew());
    client.on('token-privilege-did-expire', () => this.renew());
    const c = this.credentials;
    await client.join(c.agoraAppId, c.channelName, c.agoraToken, Number(c.agoraUid));
    if (this.closed) { await client.leave(); return; }
    const audio = sdk.createCustomAudioTrack({ mediaStreamTrack: this.source.stream.getAudioTracks()[0] });
    this.tracks.push(audio);
    const video = this.source.stream.getVideoTracks()[0];
    if (video) this.tracks.push(sdk.createCustomVideoTrack({ mediaStreamTrack: video, width: 640, height: 360, frameRate: 15, bitrateMin: 150, bitrateMax: 700 }));
    await client.publish(this.tracks);
    if (this.closed) { await client.leave(); return; }
    this.published = true;
    this.report();
  }
  async renewToken(credentials) { if (!this.closed && this.client) await this.client.renewToken(credentials.agoraToken); }
  async stats() {
    if (!this.client || this.closed) return {};
    const stats = this.client.getRTCStats();
    const video = Object.values(this.client.getRemoteVideoStats())[0];
    return { sent: stats.SendBytes || 0, received: stats.RecvBytes || 0, resolution: video?.receiveResolutionWidth ? `${video.receiveResolutionWidth} × ${video.receiveResolutionHeight}` : '—' };
  }
  close() {
    this.closed = true;
    this.tracks.forEach(track => track.close());
    this.tracks = [];
    if (this.client) { this.client.removeAllListeners(); void this.client.leave().catch(() => {}); }
  }
}
