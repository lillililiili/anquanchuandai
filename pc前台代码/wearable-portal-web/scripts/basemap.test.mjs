import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import Feature from 'ol/Feature.js'
import Point from 'ol/geom/Point.js'
import LineString from 'ol/geom/LineString.js'
import { OSM_TILES, SATELLITE_TILES, OVERLAY_TILES, MAP_CENTER, MAP_ZOOM, createBasemapLayers } from '../src/utils/basemap.js'
import { overlayStyle } from '../src/utils/map-styles.js'

test('portal basemap uses the backup-branch OpenLayers tile stack', () => {
  assert.equal(OSM_TILES, 'https://{a-c}.tile.openstreetmap.org/{z}/{x}/{y}.png')
  assert.equal(SATELLITE_TILES, 'https://webst01.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}')
  assert.equal(OVERLAY_TILES, 'https://webst01.is.autonavi.com/appmaptile?style=8&x={x}&y={y}&z={z}')
  assert.deepEqual(MAP_CENTER, [117.14473200, 36.66388700])
  assert.equal(MAP_ZOOM, 15)
})

test('street tiles show by default; satellite overlay stays off until chosen', () => {
  const layers = createBasemapLayers()
  assert.equal(layers.street.getVisible(), true)
  assert.equal(layers.satellite.getVisible(), false)
  assert.equal(layers.overlay.getVisible(), false)
  const map = readFileSync(new URL('../src/components/spatial/VectorMap.vue', import.meta.url), 'utf8')
  assert.match(map, /satellite = ref\(false\)/)
})

test('location marks and track lines use a larger high-contrast overlay', () => {
  const point = overlayStyle(false)(new Feature(new Point([0, 0])))
  const track = overlayStyle(true)(new Feature(new LineString([[0, 0], [1, 1]])))
  const sample = overlayStyle(true)(new Feature(new Point([0, 0])))
  assert.ok(point.some(style => style.getImage()?.getRadius() >= 10))
  assert.ok(sample.some(style => style.getImage()?.getRadius() >= 8))
  assert.ok(track.some(style => style.getStroke()?.getWidth() >= 8))
})
