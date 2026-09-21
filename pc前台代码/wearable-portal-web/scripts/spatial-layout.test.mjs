import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createSeed } from '../src/mock/seed.js'
import { validRing } from '../src/utils/spatial-contract.js'

test('sample positions and closed work-area fences are distributed without overlap', () => {
  const { entities } = createSeed()
  const boxes = entities.fences.map(f => {
    assert.ok(validRing(f), f.id)
    assert.equal(f.ring.length, 5)
    const xs = f.ring.map(p => p[0]), ys = f.ring.map(p => p[1])
    return [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)]
  })
  for (let i = 0; i < boxes.length; i++) for (let j = i + 1; j < boxes.length; j++) {
    const a = boxes[i], b = boxes[j]
    assert.ok(a[2] < b[0] || b[2] < a[0] || a[3] < b[1] || b[3] < a[1], `fences ${i} and ${j} overlap`)
  }
  const points = entities.locations.filter(p => p.siteId === 'mock-site-1').map(p => p.position)
  assert.ok(Math.max(...points.map(p => p.longitude)) - Math.min(...points.map(p => p.longitude)) > .05)
  assert.ok(Math.max(...points.map(p => p.latitude)) - Math.min(...points.map(p => p.latitude)) > .035)
  assert.equal(points[2].coordinateSystem, 'UNKNOWN')
})

test('fence workspace selects the first list item when none is chosen', () => {
  const source = readFileSync(new URL('../src/views/location/FenceView.vue', import.meta.url), 'utf8')
  assert.match(source, /!selectedId\.value && data\.items\?\.length\) select\(data\.items\[0\]\.id\)/)
})
