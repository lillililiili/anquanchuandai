import { mediaUrl, openWhep, mediaPlaybackError, mediaPlaybackRejection } from './helmet-media.js';

// Only the known authorization parameter is ephemeral. Other query parameters
// may identify a different source and must continue to trigger reconnection.
function sourceIdentity(live) {
  const value = mediaUrl(live?.url);
  if (!value) return null;
  const url = new URL(value);
  url.searchParams.delete('token');
  url.searchParams.sort();
  url.hash = '';
  return `${String(live.protocol || '').toUpperCase()}|${live.streamId || ''}|${url.href}`;
}

export function createLiveVideoPlayer(video, {
  open = openWhep, loadHls = () => import('hls.js'), onChange = () => {},
  now = Date.now, schedule = setTimeout, cancel = clearTimeout,
} = {}) {
  let latest, identity, session, hls, controller, renewal, generation = 0, disposed = false;
  let fallback = false, state = 'loading', error = '';
  const notify = () => onChange({ state, error, fallback });
  const selected = () => fallback && latest?.hlsUrl
    ? { ...latest, protocol: 'HLS', url: latest.hlsUrl } : latest;
  function cleanup() {
    cancel(renewal); renewal = undefined;
    controller?.abort(); controller = undefined;
    const previous = session; session = undefined;
    void Promise.resolve(previous?.close()).catch(() => {});
    hls?.destroy(); hls = undefined;
    video.pause(); video.srcObject = null; video.removeAttribute('src'); video.load();
  }
  // HLS keeps requesting playlists and segments after initial authorization.
  // Apply renewed tickets only within the exact same stream directory/origin.
  function requestUrl(value) {
    const live = selected(), current = mediaUrl(live?.url), requested = mediaUrl(value);
    if (!current || !requested) return value;
    const target = new URL(requested), source = new URL(current);
    const directory = source.pathname.slice(0, source.pathname.lastIndexOf('/') + 1);
    if (String(live.protocol).toUpperCase() === 'HLS' && target.origin === source.origin &&
        target.pathname.startsWith(directory) && source.searchParams.has('token')) {
      target.searchParams.set('token', source.searchParams.get('token'));
    }
    return target.href;
  }
  async function play() {
    if (disposed) return;
    const operation = ++generation;
    cleanup();
    controller = new AbortController(); state = 'loading'; error = ''; notify();
    const active = () => !disposed && operation === generation;
    const status = (value, detail) => {
      if (!active()) return;
      state = value;
      error = value === 'failed' ? detail || '直播连接中断，请重新播放' : '';
      notify();
    };
    const rejected = reason => { const result = mediaPlaybackRejection(reason); status(result.state, result.error); };
    try {
      const live = selected(), url = mediaUrl(live?.url);
      if (!url) throw mediaPlaybackError('暂无可用直播地址');
      if (live.expiresAt && Date.parse(live.expiresAt) <= now()) throw mediaPlaybackError('直播授权已过期，请刷新后重新播放');
      const protocol = String(live.protocol || '').toUpperCase();
      if (protocol === 'WHEP') {
        const opened = await open(live, video, { signal: controller.signal, onState: status });
        if (!active()) { await opened.close(); return; }
        session = opened;
      } else if (protocol === 'HLS') {
        const { default: Hls } = await loadHls();
        if (!active()) return;
        if (Hls.isSupported()) {
          hls = new Hls({
            xhrSetup: (xhr, value) => xhr.open('GET', requestUrl(value), true),
            fetchSetup: (context, init) => new Request(requestUrl(context.url), init),
          });
          hls.on(Hls.Events.ERROR, (_event, data) => {
            if (!data.fatal) return;
            const code = Number(data.response?.code);
            const http = Number.isInteger(code) && code >= 100 && code <= 599 ? `（HTTP ${code}）` : '';
            status('failed', data.type === 'networkError' ? `兼容直播读取失败${http}，请检查直播流和网络`
              : data.type === 'mediaError' ? '兼容直播解码失败，请检查设备视频和音频编码' : '兼容直播播放失败，请重新播放');
          });
          hls.on(Hls.Events.MANIFEST_PARSED, () => {
            if (active()) void video.play().catch(rejected);
          });
          hls.loadSource(url); hls.attachMedia(video);
        } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
          video.src = url;
          // Native HLS has no request hook. Renew near the loaded ticket's
          // expiry, using the newest polled URL, rather than on every poll.
          const expiry = Date.parse(live.expiresAt);
          if (Number.isFinite(expiry)) renewal = schedule(() => {
            if (!active()) return;
            if (mediaUrl(selected()?.url) !== url && Date.parse(selected()?.expiresAt) > now()) void play();
            else { cleanup(); status('failed'); error = '直播授权即将过期，请刷新后重新播放'; notify(); }
          }, Math.max(1000, expiry - now() - 15000));
          await video.play().catch(rejected);
        } else throw mediaPlaybackError('当前浏览器不支持此视频流');
      } else throw mediaPlaybackError('尚未配置支持的直播协议');
    } catch (reason) {
      if (active()) { state = 'failed'; error = reason.publicMediaMessage || '视频连接失败，请重新播放'; notify(); }
    }
  }
  return {
    update(live) {
      if (disposed) return;
      const previousIdentity = sourceIdentity(latest);
      latest = live ? { ...live } : live;
      if (previousIdentity !== sourceIdentity(latest)) fallback = false;
      const next = sourceIdentity(selected());
      if (next !== identity) { identity = next; return play(); }
      // Keep the latest ticket for explicit retry, including after a failed
      // connection. Polling must not repeatedly interrupt an ICE negotiation.
    },
    retry: play,
    mediaError() {
      if (disposed || !video.error) return;
      state = 'failed';
      error = ({2:'视频下载失败，请检查直播流和网络',3:'视频解码失败，请检查设备视频和音频编码',4:'浏览器不支持此直播格式，请改用兼容播放或检查视频编码'})[video.error.code] || '视频播放失败，请重新播放';
      notify();
    },
    useHls() { if (!latest?.hlsUrl || disposed) return; fallback = true; identity = sourceIdentity(selected()); return play(); },
    dispose() { if (disposed) return; disposed = true; generation++; cleanup(); },
  };
}
