import { closedMediaProvider } from './media-provider.js'
export const playerLabels = { NOT_INTEGRATED: '未接入', UNSUPPORTED: '不支持', IDLE: '未播放', CONNECTING: '连接中', PLAYING: '播放中', BUFFERING: '缓冲中', PAUSED: '已暂停', INTERRUPTED: '画面中断', ERROR: '播放失败', FORBIDDEN: '无权限' }
// Provider and adapter injection is for independent tests/future reviewed media-session integration, never page metadata.
export function createVideoPlayer({ media, provider = closedMediaProvider, createAdapter, context = () => ({}), onChange = () => {}, documentRef = globalThis.document, clock = globalThis, now = () => Date.now(), stallMs = 5000 }) {
  let generation = 0, controller, adapter, release, timer, frame, listeners = [], destroyed = false, lastProgress = 0, lastTime = -1, playingEvent = false
  let snapshot = { state: 'IDLE', reason: '', sourceTime: null, lastDisplayedAt: null, muted: true }
  media.muted = true
  const update = patch => { snapshot = { ...snapshot, ...patch }; onChange({ ...snapshot }) }
  function cleanup() {
    generation++; controller?.abort(); controller = null
    for (const [event, listener] of listeners) media.removeEventListener(event, listener)
    listeners = []; if (timer != null) clock.clearInterval(timer); timer = null
    if (frame != null) media.cancelVideoFrameCallback?.(frame); frame = null
    const safely = fn => { try { fn() } catch { /* Cleanup must continue even when an adapter is already detached. */ } }
    safely(() => adapter?.destroy()); adapter = null
    safely(() => media.pause()); safely(() => media.removeAttribute?.('src')); safely(() => { media.srcObject = null }); safely(() => media.load?.()); safely(() => release?.()); release = null
    playingEvent = false; lastTime = -1
  }
  function progress(current, stamp) {
    if (current !== generation || destroyed || !playingEvent || media.paused || media.ended) return
    if (media.loop && stamp < lastTime) lastTime = -1
    if (stamp > lastTime) { lastTime = stamp; lastProgress = now(); update({ state: 'PLAYING', reason: '', lastDisplayedAt: new Date(now()).toISOString() }) }
  }
  async function start() {
    if (destroyed) return
    cleanup(); const current = generation; controller = new AbortController()
    update({ state: 'CONNECTING', reason: '', sourceTime: null, lastDisplayedAt: null }); lastProgress = now()
    try {
      const source = await provider.acquire(context(), controller.signal)
      if (current !== generation || destroyed) { source?.release?.(); return }
      if (documentRef?.hidden) { source?.release?.(); cleanup(); update({ state: 'PAUSED', reason: '页面已隐藏；恢复后请手动播放' }); return }
      if (!source || source.state !== 'AVAILABLE') { update({ state: ['FORBIDDEN', 'UNSUPPORTED'].includes(source?.state) ? source.state : 'NOT_INTEGRATED', reason: source?.reason || '真实媒体访问未开放' }); return }
      release = source.release; update({ sourceTime: source.sourceTime || null })
      const on = (event, fn) => { const listener = () => { if (current === generation && !destroyed) fn() }; media.addEventListener(event, listener); listeners.push([event, listener]) }
      on('playing', () => { playingEvent = true; lastProgress = now(); update({ state: 'CONNECTING', reason: '等待画面推进' }) })
      on('waiting', () => { playingEvent = false; update({ state: 'BUFFERING' }) })
      on('stalled', () => { playingEvent = false; update({ state: 'INTERRUPTED' }) })
      on('pause', () => { playingEvent = false; update({ state: 'PAUSED' }) })
      on('ended', () => { playingEvent = false; update({ state: 'INTERRUPTED', reason: '媒体已结束' }) })
      on('error', () => { cleanup(); update({ state: 'ERROR', reason: '媒体播放失败，请手动重试' }) })
      if (media.requestVideoFrameCallback) {
        const tick = (_, info) => { if (current !== generation || destroyed) return; progress(current, info.mediaTime); frame = media.requestVideoFrameCallback(tick) }
        frame = media.requestVideoFrameCallback(tick)
      } else on('timeupdate', () => { if (media.readyState >= 2) progress(current, media.currentTime) })
      timer = clock.setInterval(() => { if (current === generation && ['PLAYING', 'CONNECTING'].includes(snapshot.state) && now() - lastProgress >= stallMs) update({ state: 'INTERRUPTED', reason: '本机画面未推进，不代表设备离线' }) }, 1000)
      const created = await createAdapter(media, source, () => { if (current === generation) { cleanup(); update({ state: 'ERROR', reason: '媒体适配器错误' }) } })
      if (current !== generation || destroyed) { created.destroy(); return }
      adapter = created
      await adapter.load(); if (current !== generation) return
      await adapter.play() // Resolution alone is deliberately not a PLAYING transition.
    } catch (e) { if (current === generation && !destroyed) { cleanup(); update({ state: 'ERROR', reason: e?.name === 'NotAllowedError' ? '浏览器拒绝播放，请手动重试' : '媒体连接失败，请手动重试' }) } }
  }
  function pause() { if (!destroyed) { cleanup(); update({ state: 'PAUSED', reason: '已停止拉流；继续需手动播放' }) } }
  const visibility = () => { if (documentRef.hidden) pause() }
  documentRef?.addEventListener('visibilitychange', visibility)
  return {
    start, retry: start, pause,
    mute(value) { media.muted = !!value; update({ muted: media.muted }) },
    async fullscreen(element = media) { try { if (!element.requestFullscreen) throw new Error(); await element.requestFullscreen(); return true } catch { update({ reason: '浏览器不允许全屏，请使用窗口查看' }); return false } },
    destroy() { if (destroyed) return; destroyed = true; cleanup(); documentRef?.removeEventListener('visibilitychange', visibility) },
    get snapshot() { return { ...snapshot } }
  }
}
