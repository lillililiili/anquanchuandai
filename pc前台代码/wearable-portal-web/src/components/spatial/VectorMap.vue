<script setup>
import { ref, onMounted, onBeforeUnmount, watch, nextTick } from 'vue'
import Map from 'ol/Map.js'
import View from 'ol/View.js'
import Feature from 'ol/Feature.js'
import Point from 'ol/geom/Point.js'
import LineString from 'ol/geom/LineString.js'
import Polygon from 'ol/geom/Polygon.js'
import VectorLayer from 'ol/layer/Vector.js'
import VectorSource from 'ol/source/Vector.js'
import { fromLonLat, toLonLat } from 'ol/proj.js'
import { containsCoordinate } from 'ol/extent.js'
import { defaults as defaultControls } from 'ol/control.js'
import OfflineVectorMap from './OfflineVectorMap.vue'
import { createBasemapLayers, MAP_CENTER, MAP_ZOOM, MAP_MIN_ZOOM, MAP_MAX_ZOOM } from '@/utils/basemap.js'
import { overlayStyle, emphasisStyles, selectedFenceStyles } from '@/utils/map-styles.js'
import { overlayFitPadding, viewFitsSize, mergeExtents, prepareFitExtent, offsetCenter, MAP_MAX_FIT_ZOOM, MAP_FOCUS_ZOOM } from '@/utils/map-view.js'
import { reliablePosition, validRing } from '@/utils/spatial-contract'
import 'ol/ol.css'
const props = defineProps({ trajectory: Boolean, points: { type: Array, default: () => [] }, lines: { type: Array, default: () => [] }, fences: { type: Array, default: () => [] }, selectedFenceId: String, active: { type: Object, default: null }, detailOpen: Boolean, message: { type: String, default: '暂无可展示的可靠位置' } })
const emit = defineEmits(['select', 'select-fence'])
const target = ref(), failure = ref(''), ready = ref(false), status = ref('正在加载底图…'), satellite = ref(false), showPoints = ref(true), showFences = ref(true)
const demo = import.meta.env.MODE === 'mock'
let olMap, map, observer, source, fenceSource, markerSource, pointLayer, fenceLayer, markerLayer, satelliteLayer, overlayLayer, disposed = false, fitted = false, lastSize = [0, 0]
let pointOverlays = [], fenceOverlays = []
const style = overlayStyle(props.trajectory)
function mapFacade() {
  const view = () => olMap.getView()
  return {
    getZoom: () => view().getZoom(),
    getCenter: () => ({ toArray: () => toLonLat(view().getCenter()) }),
    zoomIn: () => view().setZoom(view().getZoom() + 1),
    zoomOut: () => view().setZoom(view().getZoom() - 1)
  }
}
function padding() {
  return overlayFitPadding(props.detailOpen, olMap?.getSize()?.[0])
}
function singleLocation() {
  return !props.trajectory && !props.lines.length && !props.fences.length
}
function focusPoint(coord, animate) {
  const size = olMap.getSize()
  const pad = padding()
  if (!viewFitsSize(size, pad)) return false
  const view = olMap.getView()
  const resolution = view.getResolutionForZoom(MAP_FOCUS_ZOOM)
  const center = offsetCenter(coord, size, pad, resolution)
  if (animate && !props.trajectory) view.animate({ center, zoom: MAP_FOCUS_ZOOM, duration: 280 })
  else { view.setCenter(center); view.setZoom(MAP_FOCUS_ZOOM) }
  lastSize = size
  return true
}
function fit() {
  if (!olMap) return
  const size = olMap.getSize()
  const pad = padding()
  if (!viewFitsSize(size, pad)) return
  if (singleLocation() && reliablePosition(props.active)) {
    focusPoint(fromLonLat([props.active.longitude, props.active.latitude]), false)
    return
  }
  const extent = prepareFitExtent(mergeExtents([source, fenceSource, markerSource]))
  if (!extent) return
  olMap.getView().fit(extent, { padding: pad, maxZoom: MAP_MAX_FIT_ZOOM, duration: 0 })
  lastSize = size
}
function visibleExtent(pad) {
  const size = olMap.getSize()
  if (!viewFitsSize(size, pad)) return null
  const topLeft = olMap.getCoordinateFromPixel([pad[3], pad[0]])
  const bottomRight = olMap.getCoordinateFromPixel([size[0] - pad[1], size[1] - pad[2]])
  if (!topLeft || !bottomRight) return null
  return [Math.min(topLeft[0], bottomRight[0]), Math.min(topLeft[1], bottomRight[1]), Math.max(topLeft[0], bottomRight[0]), Math.max(topLeft[1], bottomRight[1])]
}
function revealActive() {
  if (!olMap || !showPoints.value || !reliablePosition(props.active)) return
  const coord = fromLonLat([props.active.longitude, props.active.latitude])
  if (singleLocation()) { focusPoint(coord, true); return }
  const pad = padding()
  const visible = visibleExtent(pad)
  if (visible && containsCoordinate(visible, coord)) return
  const view = olMap.getView()
  const size = olMap.getSize()
  const resolution = view.getResolution()
  if (!size || !resolution) return
  view.animate({ center: offsetCenter(coord, size, pad, resolution), duration: props.trajectory ? 0 : 220 })
}
function draw() {
  if (!olMap) return
  source.clear(); fenceSource.clear(); pointOverlays = []; fenceOverlays = []
  for (const p of props.points.filter(reliablePosition)) {
    const feature = new Feature(new Point(fromLonLat([p.longitude, p.latitude]))); feature.set('recordId', p.recordId)
    source.addFeature(feature); pointOverlays.push(feature)
  }
  for (const line of props.lines) if (line.length > 1 && line.every(reliablePosition)) {
    const feature = new Feature(new LineString(line.map(p => fromLonLat([p.longitude, p.latitude]))))
    source.addFeature(feature); pointOverlays.push(feature)
  }
  for (const fence of props.fences.filter(validRing)) {
    const feature = new Feature(new Polygon([fence.ring.map(p => fromLonLat(p))])); feature.set('fenceId', fence.id)
    if (props.selectedFenceId === fence.id) feature.setStyle(selectedFenceStyles())
    fenceSource.addFeature(feature); fenceOverlays.push(feature)
  }
  pointLayer.setVisible(showPoints.value); markerLayer.setVisible(showPoints.value); fenceLayer.setVisible(showFences.value)
  if (pointOverlays.length || fenceOverlays.length) {
    if (!fitted || singleLocation()) { fit(); fitted = true }
    status.value = demo ? '预置位置 · 非实时定位' : '位置快照 · 非实时连接'
  } else status.value = props.message
}
function drawActive() {
  markerSource?.clear()
  if (markerSource && reliablePosition(props.active)) markerSource.addFeature(new Feature(new Point(fromLonLat([props.active.longitude, props.active.latitude]))))
}
function applySatellite(value) { satelliteLayer?.setVisible(value); overlayLayer?.setVisible(value) }
onMounted(() => {
  try {
    const layers = createBasemapLayers()
    satelliteLayer = layers.satellite; overlayLayer = layers.overlay; applySatellite(satellite.value)
    source = new VectorSource(); fenceSource = new VectorSource(); markerSource = new VectorSource()
    pointLayer = new VectorLayer({ source, style, zIndex: 4 })
    fenceLayer = new VectorLayer({ source: fenceSource, style, zIndex: 3 })
    markerLayer = new VectorLayer({ source: markerSource, zIndex: 5, style: emphasisStyles() })
    olMap = new Map({
      target: target.value,
      layers: [layers.street, satelliteLayer, overlayLayer, fenceLayer, pointLayer, markerLayer],
      controls: defaultControls({ zoom: false, rotate: false, attribution: false }),
      view: new View({ center: fromLonLat(MAP_CENTER), zoom: MAP_ZOOM, minZoom: MAP_MIN_ZOOM, maxZoom: MAP_MAX_ZOOM })
    })
    map = mapFacade()
    olMap.on('singleclick', event => {
      const feature = olMap.forEachFeatureAtPixel(event.pixel, f => f, { hitTolerance: 12 })
      if (feature?.get('recordId')) emit('select', feature.get('recordId'))
      if (feature?.get('fenceId')) emit('select-fence', feature.get('fenceId'))
    })
    observer = new ResizeObserver(() => {
      if (!olMap) return
      olMap.updateSize()
      const size = olMap.getSize() || [0, 0]
      const wasEmpty = lastSize[0] < 40 || lastSize[1] < 40
      lastSize = size
      if (wasEmpty && size[0] >= 40 && size[1] >= 40) { fitted = false; fit(); revealActive() }
    }); observer.observe(target.value)
    ready.value = true; draw(); drawActive(); nextTick(() => { olMap?.updateSize(); fit(); revealActive() })
  } catch (error) { if (!disposed) failure.value = error.message || '地图初始化失败' }
})
watch(() => [props.points, props.lines, props.fences], () => { fitted = false; draw(); drawActive(); nextTick(revealActive) }, { deep: true })
watch(() => [props.active, props.selectedFenceId, props.detailOpen], () => {
  if (props.fences.length) draw()
  drawActive(); nextTick(revealActive)
}, { deep: true })
watch(satellite, applySatellite)
watch(showPoints, value => { pointLayer?.setVisible(value); markerLayer?.setVisible(value); if (value) nextTick(revealActive) })
watch(showFences, value => fenceLayer?.setVisible(value))
onBeforeUnmount(() => { disposed = true; observer?.disconnect(); olMap?.setTarget(undefined); olMap?.dispose(); olMap = null; map = null; source?.clear(); fenceSource?.clear(); markerSource?.clear() })
</script>
<template>
  <div v-if="failure" class="amap-fallback"><p role="status">{{ failure }} · 已切换离线矢量视图</p><OfflineVectorMap v-bind="props" @select="emit('select', $event)" @select-fence="emit('select-fence', $event)"><slot /></OfflineVectorMap></div>
  <div v-else class="s2-map amap-scene" aria-label="位置地图">
    <div ref="target" class="s2-map-target" tabindex="0" aria-label="地图画布" />
    <div class="s2-map-caption">瓦片底图 · {{ status }}</div>
    <div class="s2-map-layers"><label v-if="points.length || lines.length || active"><input v-model="showPoints" type="checkbox" />位置 / 轨迹</label><label v-if="fences.length"><input v-model="showFences" type="checkbox" />围栏</label><label><input v-model="satellite" type="checkbox" :disabled="!ready" />卫星影像</label></div>
    <div class="s2-map-tools"><span>N ↑</span><button aria-label="放大地图" :disabled="!ready" @click="map?.zoomIn()">＋</button><button aria-label="缩小地图" :disabled="!ready" @click="map?.zoomOut()">－</button><button aria-label="显示全部位置" :disabled="!ready" @click="fit">全域</button></div>
    <div class="amap-data-legend">{{ trajectory ? '━ 青色轨迹 · ● 采样点 · ● 金色为回放位置' : '● 位置快照 ━ 轨迹片段 ▱ 围栏范围' }}</div><slot />
  </div>
</template>
<style scoped>
.amap-fallback { display:flex; flex-direction:column; min-height:0; height:100%; }.amap-fallback>p { padding:6px 10px; font-size:12px; color:#ffd08a; }.amap-fallback>.s2-map { flex:1; }.amap-scene { background:#123451; }.amap-data-legend { position:absolute; bottom:32px; left:12px; color:#dcf3ff; background:#092b47df; border:1px solid #487c98; border-radius:5px; padding:5px 9px; font-size:11px; pointer-events:none; }.amap-scene .s2-map-caption { max-width:calc(100% - 100px); }
</style>
