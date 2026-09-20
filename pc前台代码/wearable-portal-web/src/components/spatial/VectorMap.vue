<script setup>
import { ref, onMounted, onBeforeUnmount, watch } from 'vue'
import OfflineVectorMap from './OfflineVectorMap.vue'
import { loadAMap, convertGPS } from '@/utils/amap-loader'
import { reliablePosition, validRing } from '@/utils/spatial-contract'
const props = defineProps({ points: { type: Array, default: () => [] }, lines: { type: Array, default: () => [] }, fences: { type: Array, default: () => [] }, selectedFenceId: String, active: { type: Object, default: null }, message: { type: String, default: '暂无可展示的可靠位置' } })
const emit = defineEmits(['select', 'select-fence'])
const target = ref(), failure = ref(''), ready = ref(false), status = ref('正在加载高德地图…'), satellite = ref(false), showPoints = ref(true), showFences = ref(true)
const demo = import.meta.env.MODE === 'mock'
let A, map, observer, satelliteLayer, roadLayer, bounds, overlays = [], pointOverlays = [], fenceOverlays = [], generation = 0, disposed = false, fitted = false
function fit() {
  if (!map || !bounds) return
  map.setBounds(bounds, true, [70, 90, 60, 60])
  if (map.getZoom() > 17) map.setZoom(17, true)
}
function fallback(error) { observer?.disconnect(); map?.destroy(); map = null; failure.value = error.message }
async function draw() {
  if (!map) return
  const current = ++generation
  const points = props.points.filter(reliablePosition), lines = props.lines.filter(line => line.length > 1 && line.every(reliablePosition)), fences = props.fences.filter(validRing)
  const active = reliablePosition(props.active) ? props.active : null
  const coordinates = [...points.map(p => [p.longitude, p.latitude]), ...lines.flatMap(line => line.map(p => [p.longitude, p.latitude])), ...fences.flatMap(f => f.ring), ...(active ? [[active.longitude, active.latitude]] : [])]
  map.remove(overlays); overlays = []; pointOverlays = []; fenceOverlays = []; bounds = null
  if (!coordinates.length) { status.value = props.message; return }
  status.value = '正在定位…'
  try {
    // The source contract is WGS84; convert before drawing on GCJ-02 basemaps.
    const converted = await convertGPS(A, coordinates)
    if (disposed || current !== generation) return
    const lngs = converted.map(p => p.getLng()), lats = converted.map(p => p.getLat())
    bounds = new A.Bounds([Math.min(...lngs) - 0.00015, Math.min(...lats) - 0.00015], [Math.max(...lngs) + 0.00015, Math.max(...lats) + 0.00015])
    let offset = 0
    for (const p of points) {
      const marker = new A.CircleMarker({ center: converted[offset++], radius: 7, fillColor: '#45daff', fillOpacity: 1, strokeColor: '#ffffff', strokeWeight: 2, cursor: 'pointer', zIndex: 120 })
      marker.on('click', () => emit('select', p.recordId)); pointOverlays.push(marker)
    }
    for (const line of lines) { pointOverlays.push(new A.Polyline({ path: converted.slice(offset, offset + line.length), strokeColor: '#55e5ff', strokeWeight: 4, showDir: true })); offset += line.length }
    for (const f of fences) {
      const polygon = new A.Polygon({ path: converted.slice(offset, offset + f.ring.length), strokeColor: f.id === props.selectedFenceId ? '#ffd08a' : '#6defcc', strokeWeight: 3, fillColor: '#38dab8', fillOpacity: 0.18, cursor: 'pointer' })
      polygon.on('click', () => emit('select-fence', f.id)); fenceOverlays.push(polygon); offset += f.ring.length
    }
    if (active) pointOverlays.push(new A.CircleMarker({ center: converted[offset], radius: 11, fillColor: '#ffd08a', fillOpacity: 1, strokeColor: '#fff', strokeWeight: 3, zIndex: 150 }))
    overlays = [...pointOverlays, ...fenceOverlays]; map.add(overlays)
    pointOverlays.forEach(o => showPoints.value ? o.show() : o.hide()); fenceOverlays.forEach(o => showFences.value ? o.show() : o.hide())
    if (!fitted) { fit(); fitted = true }
    status.value = demo ? '预置位置 · 非实时定位' : '位置快照 · 非实时连接'
  } catch (error) { if (current === generation && !disposed) fallback(error) }
}
onMounted(async () => {
  try {
    A = await loadAMap(); if (disposed) return
    map = new A.Map(target.value, { zoom: 5, center: [104.1, 35.6], mapStyle: 'amap://styles/blue', viewMode: '2D', animateEnable: false })
    map.on('complete', fit)
    satelliteLayer = new A.TileLayer.Satellite(); roadLayer = new A.TileLayer.RoadNet()
    observer = new ResizeObserver(() => map?.resize()); observer.observe(target.value)
    ready.value = true; await draw()
  } catch (error) { if (!disposed) fallback(error) }
})
watch(() => [props.points, props.lines, props.fences], () => { fitted = false; draw() }, { deep: true })
watch(() => [props.active, props.selectedFenceId], draw, { deep: true })
watch(satellite, value => { if (map) value ? map.add([satelliteLayer, roadLayer]) : map.remove([satelliteLayer, roadLayer]) })
watch(showPoints, value => pointOverlays.forEach(o => value ? o.show() : o.hide()))
watch(showFences, value => fenceOverlays.forEach(o => value ? o.show() : o.hide()))
onBeforeUnmount(() => { disposed = true; generation++; observer?.disconnect(); map?.destroy(); map = null })
</script>
<template>
  <div v-if="failure" class="amap-fallback"><p role="status">{{ failure }} · 已切换离线矢量视图</p><OfflineVectorMap v-bind="props" @select="emit('select', $event)" @select-fence="emit('select-fence', $event)"><slot /></OfflineVectorMap></div>
  <div v-else class="s2-map amap-scene" aria-label="高德位置地图">
    <div ref="target" class="s2-map-target" tabindex="0" aria-label="高德地图画布" />
    <div class="s2-map-caption">高德地图 · {{ status }}</div>
    <div class="s2-map-layers"><label v-if="points.length || lines.length || active"><input v-model="showPoints" type="checkbox" />位置 / 轨迹</label><label v-if="fences.length"><input v-model="showFences" type="checkbox" />围栏</label><label><input v-model="satellite" type="checkbox" :disabled="!ready" />卫星影像</label></div>
    <div class="s2-map-tools"><span>N ↑</span><button aria-label="放大地图" :disabled="!ready" @click="map?.zoomIn()">＋</button><button aria-label="缩小地图" :disabled="!ready" @click="map?.zoomOut()">－</button><button aria-label="显示全部位置" :disabled="!ready" @click="fit">全域</button></div>
    <div class="amap-data-legend">● 位置快照 ━ 轨迹片段 ▱ 围栏范围</div><slot />
  </div>
</template>
<style scoped>
.amap-fallback { display:flex; flex-direction:column; min-height:0; height:100%; }.amap-fallback>p { padding:6px 10px; font-size:12px; color:#ffd08a; }.amap-fallback>.s2-map { flex:1; }.amap-scene { background:#123451; }.amap-data-legend { position:absolute; bottom:32px; left:12px; color:#dcf3ff; background:#092b47df; border:1px solid #487c98; border-radius:5px; padding:5px 9px; font-size:11px; pointer-events:none; }.amap-scene .s2-map-caption { max-width:calc(100% - 100px); }
</style>
