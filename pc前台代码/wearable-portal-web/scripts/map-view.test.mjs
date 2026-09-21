import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { overlayFitPadding, viewFitsSize, mergeExtents, prepareFitExtent, offsetCenter, MAP_FIT_PADDING, MAP_FOCUS_ZOOM, MAP_MAX_FIT_ZOOM } from '../src/utils/map-view.js'

test('detail card leaves a visible gap on the right of the map', () => {
  assert.deepEqual(overlayFitPadding(false, 900), MAP_FIT_PADDING)
  const wide = overlayFitPadding(true, 900)
  assert.equal(wide[3], 380)
  assert.ok(wide[3] > wide[1])
  const narrow = overlayFitPadding(true, 400)
  assert.ok(narrow[3] < 380)
  assert.ok(viewFitsSize([900, 600], wide))
  assert.equal(viewFitsSize([200, 200], wide), false)
})

test('a single point extent is buffered so OpenLayers can fit it', () => {
  const point = [1, 2, 1, 2]
  const prepared = prepareFitExtent(point)
  assert.ok(prepared[2] > prepared[0])
  assert.ok(prepared[3] > prepared[1])
  assert.equal(prepareFitExtent(null), null)
})

test('empty vector sources are skipped when merging extents', () => {
  const empty = { getFeatures: () => [], getExtent: () => [Infinity, Infinity, -Infinity, -Infinity] }
  const filled = { getFeatures: () => [1], getExtent: () => [10, 20, 30, 40] }
  assert.deepEqual(mergeExtents([empty, filled]), [10, 20, 30, 40])
  assert.equal(mergeExtents([empty]), null)
})

test('selected marker is shifted into the unobstructed map gap', () => {
  const padding = overlayFitPadding(true, 800)
  const center = offsetCenter([0, 0], [800, 500], padding, 1)
  assert.ok(center[0] < 0)
})

test('selected person uses a closer focus zoom than overview fit', () => {
  assert.equal(MAP_FOCUS_ZOOM, 18)
  assert.ok(MAP_FOCUS_ZOOM > MAP_MAX_FIT_ZOOM)
})

test('live location plots only the selected person', () => {
  const source = readFileSync(new URL('../src/views/location/LiveLocation.vue', import.meta.url), 'utf8')
  assert.match(source, /selected\.value/)
  assert.match(source, /detail-open="!!selected"/)
  assert.doesNotMatch(source, /list\.data\?\.items \|\| \[\]/)
})
