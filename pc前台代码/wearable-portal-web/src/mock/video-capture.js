export const RECORD_LIMIT_MS = 60000
export const RECORD_LIMIT_BYTES = 50 * 1024 * 1024
export function recorderType(Recorder = globalThis.MediaRecorder) {
  return ['video/webm;codecs=vp8', 'video/webm'].find(type => Recorder?.isTypeSupported(type)) || null
}
export function drawCapture(media, canvas) {
  if (media.readyState < 2 || !media.videoWidth || media.paused || media.ended) throw new Error('请先播放并等待实际画面推进')
  canvas.width = media.videoWidth; canvas.height = media.videoHeight
  const ctx = canvas.getContext('2d'); ctx.drawImage(media, 0, 0)
  ctx.fillStyle = '#001d30'; ctx.fillRect(0, 0, canvas.width, 32)
  ctx.fillStyle = '#fff'; ctx.font = '18px sans-serif'; ctx.fillText('本地视频 · 非现场画面 · 源拍摄时间未知', 12, 23)
}
export function captureImage(media) {
  const canvas = document.createElement('canvas'); drawCapture(media, canvas)
  return new Promise((resolve, reject) => canvas.toBlob(blob => blob?.size ? resolve(blob) : reject(new Error('抓拍失败，未生成资料')), 'image/png'))
}
export function recordMedia(media, onResult, onError, onSeconds, { Recorder = globalThis.MediaRecorder, clock = globalThis, now = () => Date.now() } = {}) {
  const type = recorderType(Recorder), canvas = document.createElement('canvas')
  if (!type || !canvas.captureStream) throw new Error('浏览器不支持本地录像，请使用支持MediaRecorder的浏览器')
  drawCapture(media, canvas)
  const stream = canvas.captureStream(15)
  let recorder, tick, limit, dead = false, discarded = false, bytes = 0, chunks = []
  const started = now()
  const release = () => { clock.clearInterval(tick); clock.clearTimeout(limit); stream.getTracks().forEach(t => t.stop()) }
  function stop(discard = false) {
    discarded ||= discard
    if (dead) return
    clock.clearInterval(tick); clock.clearTimeout(limit)
    if (recorder?.state !== 'inactive') recorder.stop()
    else { dead = true; release() }
  }
  try {
    recorder = new Recorder(stream, { mimeType: type, videoBitsPerSecond: 1500000 })
    recorder.ondataavailable = e => { bytes += e.data.size; if (bytes > RECORD_LIMIT_BYTES) { discarded = true; onError(new Error('录像超过50MB，已丢弃，不会保存不完整文件')); stop(true) } else if (!discarded) chunks.push(e.data) }
    recorder.onerror = () => { onError(new Error('浏览器录像失败，未保存资料')); stop(true) }
    recorder.onstop = () => { if (dead) return; dead = true; release(); const blob = new Blob(chunks, { type: 'video/webm' }); chunks = []; if (!discarded && blob.size) onResult(blob); else if (!discarded) onError(new Error('录像为空，未保存资料')) }
    recorder.start(250)
    tick = clock.setInterval(() => { try { drawCapture(media, canvas); onSeconds(Math.min(60, Math.floor((now() - started) / 1000))) } catch (e) { onError(e); stop(true) } }, 66)
    limit = clock.setTimeout(() => stop(), RECORD_LIMIT_MS)
    return { stop, dispose: () => stop(true) }
  } catch (e) { dead = true; release(); throw e }
}
