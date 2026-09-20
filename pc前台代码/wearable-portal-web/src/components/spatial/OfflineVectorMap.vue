<script setup>
import { ref, onMounted, onBeforeUnmount, watch } from 'vue'
import Map from 'ol/Map.js'
import View from 'ol/View.js'
import Feature from 'ol/Feature.js'
import Point from 'ol/geom/Point.js'
import LineString from 'ol/geom/LineString.js'
import Polygon from 'ol/geom/Polygon.js'
import VectorLayer from 'ol/layer/Vector.js'
import VectorSource from 'ol/source/Vector.js'
import { Style, Circle, Fill, Stroke } from 'ol/style.js'
import { fromLonLat } from 'ol/proj.js'
import { reliablePosition, validRing } from '@/utils/spatial-contract'
import 'ol/ol.css'
const props = defineProps({ points: { type: Array, default: () => [] }, lines: { type: Array, default: () => [] }, fences: { type: Array, default: () => [] }, selectedFenceId: String, active: { type: Object, default: null }, message: { type: String, default: '暂无可展示的可靠位置' } })
const emit = defineEmits(['select', 'select-fence'])
const target = ref(), failed = ref(false), showPoints = ref(true), showFences = ref(true), count = ref(0)
let map, observer, source, markerSource, markerLayer, pointLayer, fenceLayer, fenceSource
const style = new Style({ image: new Circle({ radius: 7, fill: new Fill({ color: '#168ff0' }), stroke: new Stroke({ color: '#eafcff', width: 2 }) }), stroke: new Stroke({ color: '#04c8ec', width: 3 }), fill: new Fill({ color: 'rgba(4,200,236,.13)' }) })
function fit() {
  if (!map || !count.value) return
  const extents = [source, fenceSource].filter(s => s.getFeatures().length).map(s => s.getExtent())
  const extent = extents.reduce((a, b) => [Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.max(a[2], b[2]), Math.max(a[3], b[3])])
  map.getView().fit(extent, { padding: [90, 65, 65, 65], maxZoom: 17 })
}
function draw() {
  if (!map) return
  source.clear(); fenceSource.clear()
  for (const p of props.points.filter(reliablePosition)) { const f = new Feature(new Point(fromLonLat([p.longitude, p.latitude]))); f.set('recordId', p.recordId); source.addFeature(f) }
  for (const line of props.lines) if (line.length > 1 && line.every(reliablePosition)) source.addFeature(new Feature(new LineString(line.map(p => fromLonLat([p.longitude, p.latitude])))))
  for (const f of props.fences.filter(validRing)) {
    const feature = new Feature(new Polygon([f.ring.map(p => fromLonLat(p))])); feature.set('fenceId', f.id)
    if (props.selectedFenceId === f.id) feature.setStyle(new Style({ stroke: new Stroke({ color: '#ffd369', width: 4 }), fill: new Fill({ color: 'rgba(255,211,105,.22)' }) }))
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
    const markerStyle = new Style({ image: new Circle({ radius: 11, fill: new Fill({ color: '#ffd369' }), stroke: new Stroke({ color: '#ffffff', width: 3 }) }) })
    markerLayer = new VectorLayer({ source: markerSource, style: markerStyle })
    map = new Map({ target: target.value, layers: [fenceLayer, pointLayer, markerLayer], controls: [], view: new View({ center: [0, 0], zoom: 2 }) })
    map.on('singleclick', event => { const feature = map.forEachFeatureAtPixel(event.pixel, f => f); if (feature?.get('recordId')) emit('select', feature.get('recordId')); if (feature?.get('fenceId')) emit('select-fence', feature.get('fenceId')) })
    observer = new ResizeObserver(() => { map?.updateSize(); fit() }); observer.observe(target.value)
    draw(); drawActive()
  } catch { failed.value = true }
})
watch(() => [props.points, props.lines, props.fences], draw, { deep: true })
watch(() => props.selectedFenceId, draw)
watch(() => props.active, drawActive)
watch(showPoints, v => { pointLayer?.setVisible(v); markerLayer?.setVisible(v) }); watch(showFences, v => fenceLayer?.setVisible(v))
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
