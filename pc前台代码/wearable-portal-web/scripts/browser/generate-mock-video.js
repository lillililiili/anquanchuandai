async (page) => {
  const download = page.waitForEvent('download')
  await page.evaluate(async () => {
    const canvas = document.createElement('canvas'); canvas.width = 640; canvas.height = 360
    const ctx = canvas.getContext('2d'), stream = canvas.captureStream(15), chunks = []
    const recorder = new MediaRecorder(stream, { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 450000 })
    const stopped = new Promise(resolve => { recorder.ondataavailable = e => chunks.push(e.data); recorder.onstop = resolve })
    let frame = 0
    const paint = () => {
      ctx.fillStyle = '#001d30'; ctx.fillRect(0, 0, 640, 360)
      ctx.strokeStyle = '#16445a'; for (let x = 0; x < 640; x += 40) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, 360); ctx.stroke() }
      for (let y = 0; y < 360; y += 40) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(640, y); ctx.stroke() }
      ctx.fillStyle = '#69e3ff'; ctx.fillRect(30 + frame * 5 % 540, 170, 42, 42)
      ctx.fillStyle = '#ffffff'; ctx.font = 'bold 32px sans-serif'; ctx.fillText('本地视频 · 非现场画面', 100, 80)
      ctx.font = '20px monospace'; ctx.fillText('SYNTHETIC / FRAME ' + String(frame++).padStart(3, '0'), 135, 280)
      ctx.font = '16px sans-serif'; ctx.fillText('设备源时间未知 · 无声音 · 不连接真实设备', 120, 325)
    }
    paint(); recorder.start(); const timer = setInterval(paint, 66)
    await new Promise(resolve => setTimeout(resolve, 6000)); recorder.stop(); await stopped
    clearInterval(timer); stream.getTracks().forEach(t => t.stop())
    const url = URL.createObjectURL(new Blob(chunks, { type: 'video/webm' })), a = document.createElement('a')
    a.href = url; a.download = 'synthetic-monitor.webm'; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000)
  })
  await (await download).saveAs('src/mock/assets/synthetic-monitor.webm')
  return 'Generated local six-second silent synthetic clip; no camera or external media.'
}
