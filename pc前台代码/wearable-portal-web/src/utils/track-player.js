export function createTrackPlayer(onPoint, schedule = setTimeout, cancel = clearTimeout) {
  let timer, points = [], index = 0, speed = 1, running = false
  function pause() { running = false; cancel(timer); timer = undefined }
  function stop() { pause(); index = 0; onPoint(points[0] || null, index, false) }
  function tick() {
    if (!running) return
    if (index >= points.length - 1) { pause(); onPoint(points[index] || null, index, false); return }
    index++; onPoint(points[index], index, true); timer = schedule(tick, 1000 / speed)
  }
  return {
    load(value) { pause(); points = value; stop() },
    play() { if (!points.length || running) return; if (index === points.length - 1) index = 0; running = true; onPoint(points[index], index, true); timer = schedule(tick, 1000 / speed) },
    pause() { pause(); onPoint(points[index] || null, index, false) }, stop,
    speed(value) { speed = [1, 2, 4].includes(Number(value)) ? Number(value) : 1; if (running) { cancel(timer); timer = schedule(tick, 1000 / speed) } },
    seek(value) { pause(); index = Math.max(0, Math.min(points.length - 1, Number(value) || 0)); onPoint(points[index] || null, index, false) },
    dispose() { pause(); points = [] }
  }
}
