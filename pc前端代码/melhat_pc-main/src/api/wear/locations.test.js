import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { locationQualityLabel } from './locations.js'

describe('location contract', () => {
  it('unknown is not offline', () => {
    expect(locationQualityLabel('unknown')).toBe('未知')
    expect(locationQualityLabel('stale')).toBe('陈旧')
    expect(locationQualityLabel('ok')).toBe('有效')
  })

  it('pages do not invent floor or treat stale as violation', () => {
    const dir = dirname(fileURLToPath(import.meta.url))
    const loc = readFileSync(join(dir, '../../views/locations/index.vue'), 'utf8')
    const fences = readFileSync(join(dir, '../../views/geo-fences/index.vue'), 'utf8')
    expect(loc).toMatch(/floorSource/)
    expect(loc).toMatch(/未知/)
    expect(loc).not.toMatch(/楼层：\d/)
    expect(loc).toMatch(/陈旧/)
    expect(fences).toMatch(/canEditFence/)
    expect(fences).toMatch(/历史事件/)
    expect(loc).toMatch(/site-changed/)
    expect(fences).toMatch(/peopleOptions/)
  })
})
