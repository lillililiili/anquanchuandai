<template>
  <section class="area-range">
    <div class="area-range-head">
      <strong>{{ TEST_SITE.name }} · 地图范围</strong>
      <button class="button" type="button" @click="resetSite">返回厂区</button>
      <button class="button" type="button" :disabled="!history.length" @click="undo">撤销</button>
      <button class="button" type="button" :disabled="!pointCount" @click="clearPoints">清空</button>
    </div>
    <p class="muted">单击地图添加节点，拖动节点调整。至少 3 个点才会出现在前台地图，清空后可以只保存名称。</p>
    <p v-if="!coordinateSystem && pointCount" class="muted">旧示意范围仅供参考；清空并重新绘制后保存真实地图范围。</p>
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
import { LABEL_TILES, SATELLITE_TILES, lonLatToPercent, percentToLonLat } from '../area-geo'
import { TEST_SITE, testSiteViewport } from '../../shared/test-site.mjs'
import { toMapCoordinates, fromMapCoordinates } from '../../shared/map-coordinates.mjs'

const props = defineProps({ modelValue: { type: Array, default: () => [] }, coordinateSystem: { type: String, default: 'GCJ02' } })
const emit = defineEmits(['update:modelValue', 'update:coordinateSystem'])
const mapEl = ref(null)
const history = ref([])
const siteViewport = testSiteViewport()
let map
let drag = null
let dragged = false
let interacted = false
let observer
const source = new VectorSource()

const points = () => (Array.isArray(props.modelValue) ? props.modelValue : [])
const pointCount = computed(() => points().length)

function project(point) {
  const coordinates = props.coordinateSystem
    ? toMapCoordinates({ longitude: point[0], latitude: point[1], coordinateSystem: props.coordinateSystem })
    : percentToLonLat(point)
  return coordinates ? fromLonLat(coordinates) : null
}

function unproject(coordinate) {
  const point = toLonLat(coordinate)
  return props.coordinateSystem ? fromMapCoordinates(point, props.coordinateSystem).map(value => Number(value.toFixed(7))) : lonLatToPercent(point).map(value => Math.round(value * 10) / 10)
}

function resetSite() {
  if (!map) return
  interacted = true
  map.getView().setCenter(fromLonLat(siteViewport.center))
  map.getView().setZoom(siteViewport.zoom)
}

function draw() {
  source.clear()
  const current = points().filter(point => project(point))
  if (current.length >= 3) {
    const ring = current.map(project)
    ring.push(ring[0])
    source.addFeature(new Feature({ geometry: new Polygon([ring]) }))
  }
  current.forEach((point) => source.addFeature(new Feature({ geometry: new Point(project(point)) })))
}

function commit(next) {
  remember()
  emit('update:modelValue', next)
}

function remember() {
  history.value.push({ points: points().map(point => [...point]), coordinateSystem: props.coordinateSystem })
}

function undo() {
  const previous = history.value.pop()
  if (previous) {
    emit('update:modelValue', previous.points)
    emit('update:coordinateSystem', previous.coordinateSystem)
  }
}

function clearPoints() {
  if (!points().length) return
  commit([])
  emit('update:coordinateSystem', 'GCJ02')
  resetSite()
}

function nearest(coordinate) {
  const here = map?.getPixelFromCoordinate(coordinate)
  if (!here) return -1
  const index = points().findIndex((point) => {
    const projected = project(point)
    const pixel = projected && map.getPixelFromCoordinate(projected)
    return pixel && Math.hypot(pixel[0] - here[0], pixel[1] - here[1]) < 14
  })
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
          ? { image: new CircleStyle({ radius: 6, fill: new Fill({ color: '#4faff7' }), stroke: new Stroke({ color: '#ffffff', width: 2 }) }) }
          : { stroke: new Stroke({ color: '#83f6fd', width: 2.5, lineDash: [6, 4] }), fill: new Fill({ color: '#83f6fd33' }) }),
      }),
    ],
    view: new View({ center: fromLonLat(siteViewport.center), zoom: siteViewport.zoom }),
    interactions: defaultInteractions({ dragPan: false }).extend([
      new DragPan({ condition: (event) => nearest(event.coordinate) < 0 }),
    ]),
    controls: [],
  })
  map.on('pointerdown', (event) => {
    if (!props.coordinateSystem) return
    const index = nearest(event.coordinate)
    if (index >= 0) {
      remember()
      drag = index
      event.preventDefault()
    }
  })
  map.on('pointermove', (event) => {
    if (drag == null) return
    dragged = true
    const next = points().map((point) => [...point])
    next[drag] = unproject(event.coordinate)
    emit('update:modelValue', next)
  })
  map.on('pointerup', () => { drag = null })
  map.on('singleclick', (event) => {
    if (!props.coordinateSystem) return
    if (dragged) { dragged = false; return }
    if (nearest(event.coordinate) >= 0) return
    const point = unproject(event.coordinate)
    commit([...points(), point])
  })
  draw()
  const fit = () => {
    const current = points().filter(point => project(point))
    if (!map || interacted || !current.length) return
    map.updateSize()
    map.getView().fit(boundingExtent(current.map(project)), { padding: [28, 28, 28, 28], maxZoom: 17 })
  }
  map.on('pointerdown', () => { interacted = true })
  mapEl.value.addEventListener('wheel', () => { interacted = true }, { passive: true })
  observer = new ResizeObserver(fit)
  observer.observe(mapEl.value)
  fit()
})

watch(() => [props.modelValue, props.coordinateSystem], draw, { deep: true })
onUnmounted(() => { observer?.disconnect(); map?.setTarget(null); map = null })
</script>
<style scoped>
.area-range { margin-top: 12px; }
.area-range-head { display: flex; gap: 8px; align-items: center; }
.area-range-map { height: 320px; margin-top: 8px; border: 1px solid var(--theme-border); border-radius: 6px; overflow: hidden; }
</style>
