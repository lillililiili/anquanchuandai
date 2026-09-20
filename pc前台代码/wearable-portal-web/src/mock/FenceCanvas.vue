<script setup>
import { ref, onMounted, onBeforeUnmount, watch } from 'vue'
import Map from 'ol/Map.js'
import View from 'ol/View.js'
import Feature from 'ol/Feature.js'
import Polygon from 'ol/geom/Polygon.js'
import LineString from 'ol/geom/LineString.js'
import VectorLayer from 'ol/layer/Vector.js'
import VectorSource from 'ol/source/Vector.js'
import Modify from 'ol/interaction/Modify.js'
import { fromLonLat, toLonLat } from 'ol/proj.js'
import { Style, Fill, Stroke, Circle } from 'ol/style.js'
import 'ol/ol.css'
const props = defineProps({ nodes: { type: Array, required: true }, mode: String })
const emit = defineEmits(['change'])
const target = ref(); let map, source, modifier, observer, syncing = false
const safeNodes = () => props.nodes.filter(p => p.every(Number.isFinite) && Math.abs(p[0]) <= 180 && Math.abs(p[1]) <= 85)
function render() {
  if (!source || syncing) return
  source.clear(); const nodes = safeNodes().map(p => fromLonLat(p))
  if (nodes.length >= 3) source.addFeature(new Feature(new Polygon([[...nodes, nodes[0]]])))
  else if (nodes.length) source.addFeature(new Feature(new LineString(nodes)))
}
function fit() { if (source?.getFeatures().length) map.getView().fit(source.getExtent(), { padding: [50, 50, 50, 50], maxZoom: 18 }) }
onMounted(() => {
  source = new VectorSource()
  map = new Map({ target: target.value, layers: [new VectorLayer({ source, style: new Style({ fill: new Fill({ color: 'rgba(0,190,230,.15)' }), stroke: new Stroke({ color: '#54d7fa', width: 2 }), image: new Circle({ radius: 5, fill: new Fill({ color: '#ffd369' }) }) }) })], view: new View({ center: [0, 0], zoom: 2 }) })
  modifier = new Modify({ source }); map.addInteraction(modifier); modifier.setActive(props.mode === 'edit')
  modifier.on('modifyend', () => {
    const geometry = source.getFeatures()[0]?.getGeometry()
    if (!geometry) return
    const nodes = geometry.getType() === 'Polygon' ? geometry.getCoordinates()[0].slice(0, -1) : geometry.getCoordinates()
    syncing = true; emit('change', nodes.map(p => toLonLat(p).map(v => Number(v.toFixed(7))))); syncing = false
  })
  map.on('singleclick', event => { if (props.mode === 'draw') emit('change', [...props.nodes, toLonLat(event.coordinate).map(v => Number(v.toFixed(7)))]) })
  render(); fit(); observer = new ResizeObserver(() => map.updateSize()); observer.observe(target.value)
})
watch(() => props.nodes, render, { deep: true }); watch(() => props.mode, mode => modifier?.setActive(mode === 'edit'))
onBeforeUnmount(() => { observer?.disconnect(); map?.setTarget(undefined); map?.dispose(); source?.clear() })
</script>
<template><div class="fence-canvas"><div ref="target" class="fence-canvas-target" tabindex="0" aria-label="本地围栏编辑地图" /><button type="button" @click="fit">定位到草图</button><p>无外部底图 · WGS84 · {{ mode === 'draw' ? '单击添加节点' : '拖动节点编辑；也可修改下方坐标表' }}</p></div></template>
<style scoped>.fence-canvas { position: relative; border: 1px solid var(--border); }.fence-canvas-target { height: 320px; background: var(--panel-bg); }.fence-canvas > button { position: absolute; right: 10px; top: 10px; }.fence-canvas p { margin: 0; padding: 8px; color: var(--text-secondary); }</style>
