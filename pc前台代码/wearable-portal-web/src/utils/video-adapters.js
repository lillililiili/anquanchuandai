// Dynamically imported only after a reviewed provider supplies an authorized source.
export async function createMediaAdapter(media, source, onError) {
  if (source.type === 'flv') { const { default: mpegts } = await import('mpegts.js'); return flvAdapter(mpegts, media, source, onError) }
  if (source.type === 'native') return nativeAdapter(media, source)
  throw new Error('MEDIA_TYPE_UNSUPPORTED')
}
export function flvAdapter(mpegts, media, source, onError) {
  if (!mpegts.isSupported()) throw new Error('FLV_UNSUPPORTED')
  const p = mpegts.createPlayer({ type: 'flv', isLive: true, url: source.url }, { enableWorker: false, autoCleanupSourceBuffer: true })
  let destroyed = false
  p.on(mpegts.Events.ERROR, onError)
  return { load() { p.attachMediaElement(media); p.load() }, play() { return p.play() }, destroy() { if (destroyed) return; destroyed = true; for (const action of [() => p.off(mpegts.Events.ERROR, onError), () => p.pause(), () => p.unload(), () => p.detachMediaElement(), () => p.destroy()]) { try { action() } catch { /* Always attempt the remaining release steps. */ } } } }
}
export function nativeAdapter(media, source) {
  return { load() { media.src = source.url; media.load() }, play() { return media.play() }, destroy() { media.pause(); media.removeAttribute('src'); media.load() } }
}
