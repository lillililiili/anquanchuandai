<template>
  <section class="area-range">
    <div class="area-range-head">
      <strong>地图范围</strong>
      <button class="button" type="button" :disabled="!pointCount" @click="undo">撤销</button>
      <button class="button" type="button" :disabled="!pointCount" @click="clearPoints">清空</button>
    </div>
    <p class="muted">单击地图添加节点，拖动节点调整。至少 3 个点才会出现在前台地图，清空后可以只保存名称。</p>
    <div ref="mapEl" class="area-range-map"></div>
  </section>
</template>
<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import OlMap from 'ol/Map'
import View from 'ol/View'
import TileLayer from 'ol/layer/Tile'
import XYZ from 'ol/source/XYZ'
import VectorLayer from 'ol/layer/Vector'
import VectorSource from 'ol/source/Vector'
import Feature from 'ol/Feature'
import Point from 'ol/geom/Point'
import Polygon from 'ol/geom/Polygon'
import DragPan from 'ol/interaction/DragPan'
import { defaults as defaultInteractions } from 'ol/interaction/defaults'
import { boundingExtent } from 'ol/extent'
import { fromLonLat, toLonLat } from 'ol/proj'
import { Circle as CircleStyle, Fill, Stroke, Style } from 'ol/style'
import 'ol/ol.css'
import { LABEL_TILES, PLANT_CENTER, PLANT_ZOOM, SATELLITE_TILES, lonLatToPercent, percentToLonLat } from '../area-geo'

const props = defineProps({ modelValue: { type: Array, default: () => [] } })
const emit = defineEmits(['update:modelValue'])
const mapEl = ref(null)
const history = []
let map
let drag = null
let dragged = false
let interacted = false
let observer
const source = new VectorSource()

const points = () => (Array.isArray(props.modelValue) ? props.modelValue : [])
const pointCount = computed(() => points().length)

function project(point) {
  return fromLonLat(percentToLonLat(point))
}

function draw() {
  source.clear()
  const current = points()
  if (current.length >= 3) {
    const ring = current.map(project)
    ring.push(ring[0])
    source.addFeature(new Feature({ geometry: new Polygon([ring]) }))
  }
  current.forEach((point) => source.addFeature(new Feature({ geometry: new Point(project(point)) })))
}

function commit(next) {
  history.push(points().map((point) => [...point]))
  emit('update:modelValue', next)
}

function undo() {
  const previous = history.pop()
  if (previous) emit('update:modelValue', previous)
}

function clearPoints() {
  if (!points().length) return
  commit([])
}

function nearest(coordinate) {
  const here = lonLatToPercent(toLonLat(coordinate))
  const index = points().findIndex((point) => Math.hypot(point[0] - here[0], point[1] - here[1]) < 3)
  return index
}

onMounted(() => {
  map = new OlMap({
    target: mapEl.value,
    layers: [
      new TileLayer({ source: new XYZ({ url: SATELLITE_TILES }) }),
      new TileLayer({ source: new XYZ({ url: LABEL_TILES }) }),
      new VectorLayer({
        source,
        style: (feature) => new Style(feature.getGeometry() instanceof Point
          ? { image: new CircleStyle({ radius: 6, fill: new Fill({ color: '#168bff' }), stroke: new Stroke({ color: '#e7faff', width: 2 }) }) }
          : { stroke: new Stroke({ color: '#00e9dd', width: 2.5, lineDash: [6, 4] }), fill: new Fill({ color: '#00dac033' }) }),
      }),
    ],
    view: new View({ center: fromLonLat(PLANT_CENTER), zoom: PLANT_ZOOM }),
    interactions: defaultInteractions({ dragPan: false }).extend([
      new DragPan({ condition: (event) => nearest(event.coordinate) < 0 }),
    ]),
    controls: [],
  })
  map.on('pointerdown', (event) => {
    const index = nearest(event.coordinate)
    if (index >= 0) {
      history.push(points().map((point) => [...point]))
      drag = index
      event.preventDefault()
    }
  })
  map.on('pointermove', (event) => {
    if (drag == null) return
    dragged = true
    const next = points().map((point) => [...point])
    next[drag] = lonLatToPercent(toLonLat(event.coordinate)).map((value) => Math.round(value * 10) / 10)
    emit('update:modelValue', next)
  })
  map.on('pointerup', () => { drag = null })
  map.on('singleclick', (event) => {
    if (dragged) { dragged = false; return }
    if (nearest(event.coordinate) >= 0) return
    const point = lonLatToPercent(toLonLat(event.coordinate)).map((value) => Math.round(value * 10) / 10)
    commit([...points(), point])
  })
  draw()
  const fit = () => {
    const current = points()
    if (!map || interacted || !current.length) return
    map.updateSize()
    map.getView().fit(boundingExtent(current.map(project)), { padding: [28, 28, 28, 28], maxZoom: 17 })
  }
  map.on('pointerdown', () => { interacted = true })
  observer = new ResizeObserver(fit)
  observer.observe(mapEl.value)
  fit()
})

watch(() => props.modelValue, draw, { deep: true })
onUnmounted(() => { observer?.disconnect(); map?.setTarget(null); map = null })
</script>
<style scoped>
.area-range { margin-top: 12px; }
.area-range-head { display: flex; gap: 8px; align-items: center; }
.area-range-map { height: 320px; margin-top: 8px; border: 1px solid #d7e0ea; border-radius: 6px; overflow: hidden; }
</style>
