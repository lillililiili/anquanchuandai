<script setup>
import { ref, onMounted, onBeforeUnmount, watch } from 'vue'
import Map from 'ol/Map.js'
import View from 'ol/View.js'
import Feature from 'ol/Feature.js'
import Polygon from 'ol/geom/Polygon.js'
import Point from 'ol/geom/Point.js'
import LineString from 'ol/geom/LineString.js'
import VectorLayer from 'ol/layer/Vector.js'
import VectorSource from 'ol/source/Vector.js'
import { defaults as defaultInteractions } from 'ol/interaction.js'
import { createBasemapLayers, MAP_CENTER, MAP_ZOOM, MAP_MIN_ZOOM, MAP_MAX_ZOOM } from '@/utils/basemap'
import { fromLonLat, toLonLat } from 'ol/proj.js'
import { Style, Fill, Stroke, Circle } from 'ol/style.js'
import 'ol/ol.css'
const props = defineProps({ nodes: { type: Array, required: true }, mode: String })
const emit = defineEmits(['change'])
const target = ref(), mapStatus = ref('正在加载地图…'); let map, source, observer, basemapSource
const safeNodes = () => props.nodes.filter(p => p.every(Number.isFinite) && Math.abs(p[0]) <= 180 && Math.abs(p[1]) <= 85)
function render() {
  if (!source) return
  source.clear(); const nodes = safeNodes().map(p => fromLonLat(p))
  if (nodes.length >= 3) source.addFeature(new Feature(new Polygon([[...nodes, nodes[0]]])))
  else if (nodes.length > 1) source.addFeature(new Feature(new LineString(nodes)))
  for (const point of nodes) source.addFeature(new Feature(new Point(point)))
}
function fit() { if (source?.getFeatures().length) map.getView().fit(source.getExtent(), { padding: [50, 50, 50, 50], maxZoom: 18 }) }
onMounted(() => {
  source = new VectorSource()
  // Use the existing WGS84 street basemap, not GCJ-02 imagery for WGS84 draft coordinates.
  const { street } = createBasemapLayers()
  basemapSource = street.getSource()
  basemapSource.on('tileloadend', loaded); basemapSource.on('tileloaderror', failed)
  map = new Map({ target: target.value, interactions: defaultInteractions({ doubleClickZoom: false }), layers: [street, new VectorLayer({ source, style: new Style({ fill: new Fill({ color: 'rgba(0,190,230,.22)' }), stroke: new Stroke({ color: '#007db8', width: 3 }), image: new Circle({ radius: 5, fill: new Fill({ color: '#ffd369' }) }) }) })], view: new View({ center: fromLonLat(MAP_CENTER), zoom: MAP_ZOOM, minZoom: MAP_MIN_ZOOM, maxZoom: MAP_MAX_ZOOM }) })
  map.on('singleclick', event => { if (props.mode === 'draw' && props.nodes.length < 500) emit('change', [...props.nodes, toLonLat(event.coordinate).map(v => Number(v.toFixed(7)))]) })
  render(); fit(); observer = new ResizeObserver(() => map.updateSize()); observer.observe(target.value)
})
function loaded() { mapStatus.value = '街道底图 · WGS84' }
function failed() { mapStatus.value = '部分底图加载失败，请检查网络后重试' }
function retry() { mapStatus.value = '正在重新加载地图…'; basemapSource?.refresh() }
watch(() => props.nodes, render, { deep: true })
onBeforeUnmount(() => { observer?.disconnect(); basemapSource?.un('tileloadend', loaded); basemapSource?.un('tileloaderror', failed); map?.setTarget(undefined); map?.dispose(); source?.clear() })
</script>
<template><div class="fence-canvas"><div ref="target" class="fence-canvas-target" :class="{ drawing: mode === 'draw' }" tabindex="0" aria-label="新增围栏地图" /><div class="canvas-tools"><button type="button" :disabled="!nodes.length" @click="fit">定位到草图</button><button type="button" @click="retry">重新加载底图</button></div><p role="status">{{ mapStatus }} · {{ mode === 'draw' ? '单击添加顶点，拖动平移，滚轮缩放' : '绘制已完成，可保存围栏' }}</p></div></template>
<style scoped>.fence-canvas { position: relative; border: 1px solid var(--border); }.fence-canvas-target { height: clamp(280px, 42vh, 460px); background: var(--panel-bg); }.drawing { cursor:crosshair; }.canvas-tools { position: absolute; right: 10px; top: 10px; display:flex; gap:8px; }.fence-canvas p { margin: 0; padding: 8px; color: var(--text-secondary); }</style>
