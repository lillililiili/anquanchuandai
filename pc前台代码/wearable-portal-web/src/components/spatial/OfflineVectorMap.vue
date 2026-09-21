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
import { fromLonLat } from 'ol/proj.js'
import { containsCoordinate } from 'ol/extent.js'
import { overlayStyle, emphasisStyles, selectedFenceStyles } from '@/utils/map-styles.js'
import { overlayFitPadding, viewFitsSize, mergeExtents, prepareFitExtent, offsetCenter, MAP_MAX_FIT_ZOOM, MAP_FOCUS_ZOOM } from '@/utils/map-view.js'
import { reliablePosition, validRing } from '@/utils/spatial-contract'
import 'ol/ol.css'
const props = defineProps({ trajectory: Boolean, points: { type: Array, default: () => [] }, lines: { type: Array, default: () => [] }, fences: { type: Array, default: () => [] }, selectedFenceId: String, active: { type: Object, default: null }, detailOpen: Boolean, message: { type: String, default: '暂无可展示的可靠位置' } })
const emit = defineEmits(['select', 'select-fence'])
const target = ref(), failed = ref(false), showPoints = ref(true), showFences = ref(true), count = ref(0)
let map, observer, source, markerSource, markerLayer, pointLayer, fenceLayer, fenceSource, lastSize = [0, 0]
const style = overlayStyle(props.trajectory)
function padding() { return overlayFitPadding(props.detailOpen, map?.getSize()?.[0]) }
function singleLocation() { return !props.trajectory && !props.lines.length && !props.fences.length }
function focusPoint(coord) {
  const size = map.getSize()
  const pad = padding()
  if (!viewFitsSize(size, pad)) return false
  const view = map.getView()
  const resolution = view.getResolutionForZoom(MAP_FOCUS_ZOOM)
  view.setCenter(offsetCenter(coord, size, pad, resolution))
  view.setZoom(MAP_FOCUS_ZOOM)
  lastSize = size
  return true
}
function fit() {
  if (!map || !count.value) return
  const size = map.getSize()
  const pad = padding()
  if (!viewFitsSize(size, pad)) return
  if (singleLocation() && reliablePosition(props.active)) {
    focusPoint(fromLonLat([props.active.longitude, props.active.latitude]))
    return
  }
  const extent = prepareFitExtent(mergeExtents([source, fenceSource, markerSource]))
  if (!extent) return
  map.getView().fit(extent, { padding: pad, maxZoom: MAP_MAX_FIT_ZOOM, duration: 0 })
  lastSize = size
}
function revealActive() {
  if (!map || !showPoints.value || !reliablePosition(props.active)) return
  const coord = fromLonLat([props.active.longitude, props.active.latitude])
  if (singleLocation()) { focusPoint(coord); return }
  const pad = padding()
  const size = map.getSize()
  if (!viewFitsSize(size, pad)) return
  const topLeft = map.getCoordinateFromPixel([pad[3], pad[0]])
  const bottomRight = map.getCoordinateFromPixel([size[0] - pad[1], size[1] - pad[2]])
  if (topLeft && bottomRight) {
    const visible = [Math.min(topLeft[0], bottomRight[0]), Math.min(topLeft[1], bottomRight[1]), Math.max(topLeft[0], bottomRight[0]), Math.max(topLeft[1], bottomRight[1])]
    if (containsCoordinate(visible, coord)) return
  }
  const resolution = map.getView().getResolution()
  if (!resolution) return
  map.getView().setCenter(offsetCenter(coord, size, pad, resolution))
}
function draw() {
  if (!map) return
  source.clear(); fenceSource.clear()
  for (const p of props.points.filter(reliablePosition)) { const f = new Feature(new Point(fromLonLat([p.longitude, p.latitude]))); f.set('recordId', p.recordId); source.addFeature(f) }
  for (const line of props.lines) if (line.length > 1 && line.every(reliablePosition)) source.addFeature(new Feature(new LineString(line.map(p => fromLonLat([p.longitude, p.latitude])))))
  for (const f of props.fences.filter(validRing)) {
    const feature = new Feature(new Polygon([f.ring.map(p => fromLonLat(p))])); feature.set('fenceId', f.id)
    if (props.selectedFenceId === f.id) feature.setStyle(selectedFenceStyles())
    fenceSource.addFeature(feature)
  }
  count.value = source.getFeatures().length + fenceSource.getFeatures().length
  fit()
}
function drawActive() {
  markerSource?.clear()
  if (markerSource && reliablePosition(props.active)) markerSource.addFeature(new Feature(new Point(fromLonLat([props.active.longitude, props.active.latitude]))))
}
onMounted(() => {
  try {
    source = new VectorSource(); fenceSource = new VectorSource(); markerSource = new VectorSource()
    pointLayer = new VectorLayer({ source, style }); fenceLayer = new VectorLayer({ source: fenceSource, style })
    markerLayer = new VectorLayer({ source: markerSource, style: emphasisStyles() })
    map = new Map({ target: target.value, layers: [fenceLayer, pointLayer, markerLayer], controls: [], view: new View({ center: [0, 0], zoom: 2 }) })
    map.on('singleclick', event => { const feature = map.forEachFeatureAtPixel(event.pixel, f => f, { hitTolerance: 12 }); if (feature?.get('recordId')) emit('select', feature.get('recordId')); if (feature?.get('fenceId')) emit('select-fence', feature.get('fenceId')) })
    observer = new ResizeObserver(() => {
      if (!map) return
      map.updateSize()
      const size = map.getSize() || [0, 0]
      const wasEmpty = lastSize[0] < 40 || lastSize[1] < 40
      lastSize = size
      if (wasEmpty && size[0] >= 40 && size[1] >= 40) { fit(); revealActive() }
    }); observer.observe(target.value)
    draw(); drawActive(); nextTick(() => { map?.updateSize(); fit(); revealActive() })
  } catch { failed.value = true }
})
watch(() => [props.points, props.lines, props.fences], () => { draw(); drawActive(); nextTick(revealActive) }, { deep: true })
watch(() => props.selectedFenceId, draw)
watch(() => [props.active, props.detailOpen], () => { drawActive(); nextTick(revealActive) })
watch(showPoints, v => { pointLayer?.setVisible(v); markerLayer?.setVisible(v); if (v) nextTick(revealActive) }); watch(showFences, v => fenceLayer?.setVisible(v))
onBeforeUnmount(() => { observer?.disconnect(); map?.setTarget(undefined); map?.dispose(); map = null; source?.clear(); fenceSource?.clear(); markerSource?.clear() })
</script>
<template>
  <div class="s2-map" aria-label="位置矢量地图">
    <div ref="target" class="s2-map-target" tabindex="0" aria-label="地图画布，可使用方向键移动" />
    <div class="s2-map-caption">底图未配置 · 无底图矢量视图</div>
    <div class="s2-map-layers"><label><input v-model="showPoints" type="checkbox" :disabled="!points.length" />位置 / 轨迹</label><label :title="fences.length ? '显示围栏图层' : '暂无围栏图层数据'"><input v-model="showFences" type="checkbox" :disabled="!fences.length" />{{ fences.length ? '围栏' : '围栏待接入' }}</label><label title="作业区域来源未接入"><input type="checkbox" disabled />作业区域待接入</label></div>
    <div class="s2-map-tools"><span aria-label="地图上方为北">N ↑</span><button aria-label="放大地图" :disabled="!count" @click="map?.getView().setZoom(map.getView().getZoom() + 1)">＋</button><button aria-label="缩小地图" :disabled="!count" @click="map?.getView().setZoom(map.getView().getZoom() - 1)">－</button><button aria-label="显示全部位置" :disabled="!count" @click="fit">全域</button></div>
    <div v-if="failed || !count" class="s2-map-empty" role="status"><span class="s2-crosshair" aria-hidden="true"></span><strong>{{ failed ? '地图初始化失败' : message }}</strong><p>不使用示例坐标或未配准厂区图片替代</p></div>
    <div class="s2-map-legend">● 可靠位置 · ━ 已确认连续片段 · ▱ 围栏范围</div>
    <slot />
  </div>
</template>
