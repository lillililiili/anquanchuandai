async (page) => {
  return await page.evaluate(async () => {
    const { inspectFile, decodeFile } = await import('/src/mock/local-file.js')
    const checks = [], active = new Set(), create = URL.createObjectURL.bind(URL), revoke = URL.revokeObjectURL.bind(URL)
    URL.createObjectURL = blob => { const url = create(blob); active.add(url); return url }
    URL.revokeObjectURL = url => { active.delete(url); revoke(url) }
    const verify = (ok, label) => { if (!ok) throw new Error(label); checks.push(label) }
    try {
      const canvas = document.createElement('canvas'); canvas.width = 64; canvas.height = 64
      const ctx = canvas.getContext('2d'); ctx.fillStyle = '#123456'; ctx.fillRect(0, 0, 64, 64)
      for (const [mime, ext] of [['image/png', 'png'], ['image/jpeg', 'jpg'], ['image/webp', 'webp']]) {
        const blob = await new Promise(resolve => canvas.toBlob(resolve, mime)), file = new File([blob], 'fixture.' + ext, { type: mime })
        const spec = await inspectFile(file); await decodeFile(file, spec.type)
        verify(active.size === 0, ext + '真实解码后释放URL')
      }
      const bytes = new ArrayBuffer(1644), view = new DataView(bytes), write = (offset, s) => [...s].forEach((c, i) => view.setUint8(offset + i, c.charCodeAt(0)))
      write(0, 'RIFF'); view.setUint32(4, 1636, true); write(8, 'WAVE'); write(12, 'fmt '); view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true); view.setUint32(24, 8000, true); view.setUint32(28, 16000, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true); write(36, 'data'); view.setUint32(40, 1600, true)
      const wav = new File([bytes], 'fixture.wav', { type: 'audio/wav' }); await inspectFile(wav); await decodeFile(wav, 'AUDIO'); verify(active.size === 0, 'WAV实际解码及释放')
      const stream = canvas.captureStream(10), chunks = [], recorder = new MediaRecorder(stream, { mimeType: 'video/webm;codecs=vp8' })
      const recorded = new Promise(resolve => { recorder.ondataavailable = e => chunks.push(e.data); recorder.onstop = resolve })
      recorder.start(); await new Promise(resolve => setTimeout(resolve, 300)); ctx.fillRect(1, 1, 10, 10); await new Promise(resolve => setTimeout(resolve, 300)); recorder.stop(); await recorded; stream.getTracks().forEach(t => t.stop())
      const video = new File(chunks, 'fixture.webm', { type: 'video/webm' }); await inspectFile(video); await decodeFile(video, 'VIDEO'); verify(active.size === 0, '合成WebM/VP8实际解码及释放，无摄像头访问')
      const corrupt = new File([Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10])], 'corrupt.png', { type: 'image/png' }); await inspectFile(corrupt)
      let rejected = false; try { await decodeFile(corrupt, 'PHOTO') } catch { rejected = true }
      verify(rejected && active.size === 0, '有正确文件头但内容损坏时拒绝并释放')
      const controller = new AbortController(); controller.abort(); rejected = false
      try { await decodeFile(wav, 'AUDIO', controller.signal) } catch (e) { rejected = e.code === 'ERR_CANCELED' }
      verify(rejected && active.size === 0, '取消解码释放URL')
      return checks
    } catch (e) { throw new Error(e.message + '；此前通过：' + checks.join('、')) }
    finally { for (const url of active) revoke(url); URL.createObjectURL = create; URL.revokeObjectURL = revoke }
  })
}
