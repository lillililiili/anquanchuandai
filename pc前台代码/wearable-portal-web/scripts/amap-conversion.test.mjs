import test from 'node:test'
import assert from 'node:assert/strict'
import { convertGPS } from '../src/utils/amap-loader.js'

test('AMap conversion deduplicates, bounds request size, normalizes decimals and preserves ordering', async () => {
  const batches = []
  const A = { convertFrom(points, system, done) { assert.equal(system, 'gps'); batches.push(points); done('complete', { locations: points.map(p => ({ lng: p[0], lat: p[1] })) }) } }
  const coordinates = Array.from({ length: 45 }, (_, i) => [111.30000000000001 + i * .001, 32.123456789])
  const output = await convertGPS(A, [...coordinates, coordinates[0]])
  assert.deepEqual(batches.map(b => b.length), [20, 20, 5])
  assert.equal(output.length, 46)
  assert.equal(output[0], output[45])
  assert.equal(batches[0][0][1], 32.123457)
  await convertGPS(A, coordinates)
  assert.equal(batches.length, 3)
})

test('failed conversion is retryable and never caches wrong coordinate counts', async () => {
  const points = [[113.9, 34.9], [113.91, 34.91]]
  await assert.rejects(convertGPS({ convertFrom(_points, _system, done) { done('complete', { locations: [] }) } }, points), /坐标转换暂不可用/)
  const output = await convertGPS({ convertFrom(items, _system, done) { done('complete', { locations: items }) } }, points)
  assert.deepEqual(output, points)
})

test('concurrent conversions share cached coordinates without duplicate network calls', async () => {
  let calls = 0
  const A = { convertFrom(points, _system, done) { calls++; setTimeout(() => done('complete', { locations: points }), 10) } }
  const points = [[115.1, 30.1]]
  const [a, b] = await Promise.all([convertGPS(A, points), convertGPS(A, points)])
  assert.deepEqual(a, b)
  assert.equal(calls, 1)
})
