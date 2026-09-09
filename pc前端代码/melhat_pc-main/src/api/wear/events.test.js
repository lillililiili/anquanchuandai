import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { eventStatusLabel, eventTypeLabel, fenceActionLabel } from './events.js'

describe('event workspace contract', () => {
  it('labels claim close and see separately', () => {
    expect(eventStatusLabel('open')).toBe('待认领')
    expect(eventStatusLabel('claimed')).toBe('已认领')
    expect(eventStatusLabel('closed')).toBe('已关闭')
    expect(eventTypeLabel('sos')).toBe('SOS')
    expect(fenceActionLabel('enter')).toBe('进入')
    expect(fenceActionLabel('leave')).toBe('离开')
  })

  it('events page does not fake a connected call', () => {
    const dir = dirname(fileURLToPath(import.meta.url))
    const page = readFileSync(join(dir, '../../views/events/index.vue'), 'utf8')
    expect(page).not.toMatch(/呼叫已接通/)
    expect(page).toMatch(/已看见/)
    expect(page).toMatch(/已认领/)
    expect(page).toMatch(/已关闭/)
    expect(page).toMatch(/applyRouteQuery/)
    expect(page).toMatch(/listDutyOperators/)
  })
})
