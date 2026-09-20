export const MAX_FILE_BYTES = 50 * 1024 * 1024
export const MAX_BLOB_BYTES = 200 * 1024 * 1024
const formats = { jpg: ['image/jpeg', 'PHOTO'], jpeg: ['image/jpeg', 'PHOTO'], png: ['image/png', 'PHOTO'], webp: ['image/webp', 'PHOTO'], mp4: ['video/mp4', 'VIDEO'], webm: ['video/webm', 'VIDEO'], mp3: ['audio/mpeg', 'AUDIO'], wav: ['audio/wav', 'AUDIO'], ogg: ['audio/ogg', 'AUDIO'] }
export async function inspectFile(file, name = file?.name) {
  if (!(file instanceof Blob) || !file.size || file.size > MAX_FILE_BYTES) throw new Error('请选择非空文件，单文件不能超过50MB')
  const ext = String(name).split('.').at(-1).toLowerCase(), spec = formats[ext]
  if (!spec || file.type !== spec[0]) throw new Error('扩展名或声明类型不支持：仅接受JPEG、PNG、WebP、MP4、WebM、MP3、WAV、OGG')
  const bytes = new Uint8Array(await file.slice(0, 32).arrayBuffer()), text = (a, b) => String.fromCharCode(...bytes.slice(a, b)), starts = a => a.every((n, i) => bytes[i] === n)
  const valid = { jpg: starts([255, 216, 255]), jpeg: starts([255, 216, 255]), png: starts([137, 80, 78, 71, 13, 10, 26, 10]), webp: text(0, 4) === 'RIFF' && text(8, 12) === 'WEBP', mp4: text(4, 8) === 'ftyp', webm: starts([26, 69, 223, 163]), mp3: text(0, 3) === 'ID3' || bytes[0] === 255 && (bytes[1] & 224) === 224, wav: text(0, 4) === 'RIFF' && text(8, 12) === 'WAVE', ogg: text(0, 4) === 'OggS' }[ext]
  if (!valid) throw new Error('文件内容与扩展名或声明类型不一致')
  return { mime: spec[0], type: spec[1], size: file.size, name: String(name).slice(0, 180) }
}
export function decodeFile(file, type, signal) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file), media = type === 'PHOTO' ? new Image() : document.createElement(type === 'VIDEO' ? 'video' : 'audio')
    let timer, settled = false
    const finish = error => {
      if (settled) return
      settled = true; clearTimeout(timer); signal?.removeEventListener('abort', cancel)
      media.onload = media.onerror = media.onloadeddata = null
      if (type !== 'PHOTO') { media.pause(); media.removeAttribute('src'); media.load() }
      else media.src = ''
      URL.revokeObjectURL(url)
      error ? reject(error) : resolve()
    }
    const cancel = () => finish(Object.assign(new Error('导入已取消'), { code: 'ERR_CANCELED' }))
    media.onerror = () => finish(new Error('浏览器无法解码此文件，请转换为支持的编码后重试'))
    if (type === 'PHOTO') media.onload = () => media.naturalWidth ? finish() : finish(new Error('图片解码失败'))
    else { media.preload = 'auto'; media.onloadeddata = () => finish() }
    timer = setTimeout(() => finish(new Error('文件解码超时，未导入资料')), 15000)
    signal?.addEventListener('abort', cancel, { once: true })
    if (signal?.aborted) { cancel(); return }
    media.src = url
  })
}
