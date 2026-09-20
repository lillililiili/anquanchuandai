let pending
export function loadAMap() {
  if (window.AMap) return Promise.resolve(window.AMap)
  if (pending) return pending
  pending = new Promise((resolve, reject) => {
    const key = import.meta.env.VITE_AMAP_KEY
    if (!key) return reject(new Error('高德地图尚未配置'))
    window._AMapSecurityConfig = { securityJsCode: import.meta.env.VITE_AMAP_SECURITY_CODE }
    const script = document.createElement('script')
    const timer = setTimeout(() => { script.remove(); reject(new Error('高德地图连接超时')) }, 12000)
    script.src = `https://webapi.amap.com/maps?v=2.0&key=${encodeURIComponent(key)}`
    script.onload = () => { clearTimeout(timer); window.AMap ? resolve(window.AMap) : reject(new Error('高德地图未能加载')) }
    script.onerror = () => { clearTimeout(timer); script.remove(); reject(new Error('高德地图网络不可用')) }
    document.head.appendChild(script)
  }).catch(error => { pending = null; throw error })
  return pending
}
const convertedPoints = new Map()
let conversionQueue = Promise.resolve()
const coordinateKey = p => p.join(',')
export function convertGPS(A, coordinates) {
  const task = conversionQueue.catch(() => {}).then(async () => {
    const missing = [...new Map(coordinates.filter(p => !convertedPoints.has(coordinateKey(p))).map(p => [coordinateKey(p), p])).values()]
    for (let offset = 0; offset < missing.length; offset += 20) {
      const batch = missing.slice(offset, offset + 20)
      // Public JS keys can have low conversion QPS; pace batches and retry transient errors.
      await new Promise(resolve => setTimeout(resolve, 350))
      let converted
      for (let attempt = 0; attempt < 3; attempt++) {
        try { converted = await requestConversion(A, batch); break } catch (error) {
          if (attempt === 2) throw error
          await new Promise(resolve => setTimeout(resolve, 700 * (attempt + 1)))
        }
      }
      batch.forEach((p, i) => convertedPoints.set(coordinateKey(p), converted[i]))
    }
    return coordinates.map(p => convertedPoints.get(coordinateKey(p)))
  })
  conversionQueue = task
  return task
}
function requestConversion(A, coordinates) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('坐标转换超时')), 10000)
    A.convertFrom(coordinates.map(p => p.map(value => Number(value.toFixed(6)))), 'gps', (status, result) => {
      clearTimeout(timer)
      if (status === 'complete' && result.locations?.length === coordinates.length) resolve(result.locations)
      else reject(new Error(`坐标转换暂不可用（${result?.info || status}，${result?.locations?.length ?? 0}/${coordinates.length}）`))
    })
  })
}
