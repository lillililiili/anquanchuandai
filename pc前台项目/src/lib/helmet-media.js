export const COMMAND_LABELS = { take_photo:'拍照', start_recording:'开始录像', stop_recording:'停止录像', start_video:'开启直播', stop_video:'关闭直播', list_recordings:'查询设备录像', upload_recording:'上传选中录像', configure_sip:'同步语音配置' };
export const COMMAND_STATUSES = { queued:'等待发送', requesting:'正在请求', configured:'配置已保存，设备下次登录生效', waiting_media:'等待设备视频，尚未开始录像', recording:'正在录制实际视频', finalizing:'录像文件正在封装', accepted:'平台已受理', sent:'已发送，设备待回执', acknowledged:'设备已回执', completed:'设备已完成', failed:'执行失败', timeout:'等待回执超时', rejected:'设备拒绝', pending:'等待设备处理', unknown:'执行状态待确认' };

export function mediaUrl(value) {
  if (typeof value !== 'string' || !value) return null;
  try {
    const url = new URL(value, globalThis.location?.origin || 'http://localhost');
    return ['http:','https:'].includes(url.protocol) && !url.username && !url.password ? url.href : null;
  } catch { return null; }
}

export function createHelmetMediaApi(fetchImpl) {
  async function request(deviceId, suffix, options = {}) {
    const response = await fetchImpl(`/api/guardian/v1/devices/${encodeURIComponent(deviceId)}/${suffix}`, options);
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw Object.assign(Error(body.message || '设备请求失败，请重试'), { status: response.status, code: body.code });
    return body;
  }
  return {
    read: (deviceId, signal) => request(deviceId,'media',{signal}),
    live: (deviceId, context, signal) => request(deviceId, 'live?' + new URLSearchParams(context), { signal }),
    command: (deviceId, action, parameters, idempotencyKey, signal, context = {}) => request(deviceId,'commands',{method:'POST',signal,headers:{'Content-Type':'application/json'},body:JSON.stringify({...context,action,parameters,idempotencyKey})}),
  };
}

export function mediaPlaybackRejection(reason) {
  if (reason?.name === 'NotAllowedError') return { state: 'playback_blocked', error: '' };
  if (reason?.name === 'NotSupportedError') return { state: 'failed', error: '浏览器无法播放此直播格式，请检查视频编码或改用兼容播放' };
  if (reason?.name === 'AbortError') return { state: 'failed', error: '视频播放被中断，请重新播放' };
  return { state: 'failed', error: '视频播放失败，请检查直播流或重新播放' };
}

export function mediaPlaybackError(message) {
  return Object.assign(Error(message), { publicMediaMessage: message });
}

// Deliberately omit addresses, ports, IDs, SDP and credentials. This allowlist
// also prevents unexpected browser/vendor diagnostic strings reaching logs.
export function whepDiagnosticSummary(pc, stats) {
  const choice = (value, allowed) => allowed.includes(value) ? value : null;
  const count = value => Number.isSafeInteger(value) && value >= 0 ? value : null;
  const candidate = id => {
    const row = stats.get(id);
    return { type: choice(row?.candidateType, ['host','srflx','prflx','relay']), protocol: choice(row?.protocol, ['udp','tcp']) };
  };
  const pairs = [], transports = [];
  stats.forEach(row => {
    if (row.type === 'candidate-pair') pairs.push({
      state: choice(row.state, ['frozen','waiting','in-progress','failed','succeeded']), nominated: row.nominated === true,
      requestsSent: count(row.requestsSent), requestsReceived: count(row.requestsReceived),
      responsesSent: count(row.responsesSent), responsesReceived: count(row.responsesReceived),
      local: candidate(row.localCandidateId), remote: candidate(row.remoteCandidateId),
    });
    if (row.type === 'transport') transports.push({ dtlsState: choice(row.dtlsState, ['new','connecting','connected','closed','failed']) });
  });
  return {
    connectionState: choice(pc.connectionState, ['new','connecting','connected','disconnected','failed','closed']),
    iceConnectionState: choice(pc.iceConnectionState, ['new','checking','connected','completed','disconnected','failed','closed']),
    pairs, transports,
  };
}

export async function openWhep(live, video, { fetchImpl = fetch, PeerConnection = RTCPeerConnection, Stream = MediaStream, onState = () => {}, signal } = {}) {
  const url = mediaUrl(live?.url);
  if (!url) throw mediaPlaybackError('直播地址无效');
  if (live.expiresAt && Date.parse(live.expiresAt) <= Date.now()) throw mediaPlaybackError('直播授权已过期，请刷新');
  const pc = new PeerConnection({ iceServers: live.iceServers || [] });
  let resource, closed = false, phase = 'offer', diagnosed = false;
  const controller = new AbortController();
  function diagnoseFailure() {
    if (!import.meta.env?.DEV || diagnosed) return;
    diagnosed = true;
    void pc.getStats().then(stats => console.info('[helmet-whep]', JSON.stringify(whepDiagnosticSummary(pc, stats))))
      .catch(() => console.info('[helmet-whep]', '{"diagnosticUnavailable":true}'));
  }
  async function close() {
    if (closed) return;
    closed = true;
    controller.abort();
    signal?.removeEventListener('abort', aborted);
    pc.close();
    video.pause(); video.srcObject = null;
    if (resource) await fetchImpl(resource,{method:'DELETE',credentials:'omit',keepalive:true}).catch(()=>{});
  }
  const aborted = () => { void close(); };
  signal?.addEventListener('abort',aborted,{once:true});
  pc.addTransceiver('video',{direction:'recvonly'});
  pc.addTransceiver('audio',{direction:'recvonly'});
  pc.addEventListener('track', event => {
    if (closed) return;
    const stream = video.srcObject || new Stream();
    if (!stream.getTracks().some(track => track.id === event.track.id)) stream.addTrack(event.track);
    video.srcObject = stream;
    void video.play().then(()=>{if(!closed)onState('playing');}).catch(reason=>{
      if(closed)return;const result=mediaPlaybackRejection(reason);onState(result.state,result.error);
    });
  });
  pc.addEventListener('connectionstatechange',()=>{
    if (!closed && ['failed','disconnected'].includes(pc.connectionState)) onState('failed',`实时视频网络连接中断（WebRTC ${pc.connectionState}），请重试或改用兼容播放`);
    if (!closed && pc.connectionState === 'failed') diagnoseFailure();
  });
  pc.addEventListener('iceconnectionstatechange',()=>{
    if(!closed && pc.iceConnectionState==='failed')onState('failed','实时视频网络连接失败（ICE failed），请检查媒体端口或改用兼容播放');
    if(!closed && pc.iceConnectionState==='failed')diagnoseFailure();
  });
  try {
    if (signal?.aborted) throw mediaPlaybackError('播放已取消');
    await pc.setLocalDescription(await pc.createOffer());
    phase = 'ice';
    if (pc.iceGatheringState !== 'complete') await new Promise((resolve,reject)=>{
      const cleanup=()=>{clearTimeout(timer);pc.removeEventListener('icegatheringstatechange',changed);controller.signal.removeEventListener('abort',cancel);};
      const changed=()=>{if(pc.iceGatheringState==='complete'){cleanup();resolve();}};
      const cancel=()=>{cleanup();reject(mediaPlaybackError('播放已取消'));};
      const timer=setTimeout(()=>{cleanup();reject(mediaPlaybackError('视频网络协商超时（ICE gathering），请检查媒体服务或重试'));},10000);
      pc.addEventListener('icegatheringstatechange',changed);
      controller.signal.addEventListener('abort',cancel,{once:true});
      if(controller.signal.aborted) cancel();
    });
    phase = 'request';
    const response=await fetchImpl(url,{method:'POST',credentials:'omit',headers:{'Content-Type':'application/sdp'},body:pc.localDescription.sdp,signal:controller.signal});
    if (!response.ok) throw mediaPlaybackError(response.status===401 || response.status===403 ? `直播授权已过期或无权限（HTTP ${response.status}），请刷新` : `实时视频协商请求失败（HTTP ${response.status}），请稍后重试`);
    const location=response.headers.get('Location');
    if(location){const resolved=new URL(location,url);if(resolved.origin===new URL(url).origin)resource=resolved.href;}
    if(closed) { if(resource) await fetchImpl(resource,{method:'DELETE',credentials:'omit'}).catch(()=>{}); throw mediaPlaybackError('播放已取消'); }
    phase = 'answer';
    await pc.setRemoteDescription({type:'answer',sdp:await response.text()});
    return {close};
  } catch(error){
    await close();
    if(error.publicMediaMessage)throw error;
    throw mediaPlaybackError({offer:'浏览器无法创建实时视频连接',ice:'实时视频网络协商失败（ICE）',request:'实时视频协商请求未完成，请检查媒体服务、网络或跨域配置',answer:'实时视频应答无法解析，请检查服务协议和设备视频编码'}[phase]);
  }
}
