import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { eventStatusLabel, eventTypeLabel, fenceActionLabel } from './events.js'

describe('event workspace contract', () => {
  it('labels claim close and see separately', () => {
    expect(eventStatusLabel('open')).toBe('待现场核验')
    expect(eventStatusLabel('claimed')).toBe('待现场核验')
    expect(eventStatusLabel('closed')).toBe('历史已处理')
    expect(eventTypeLabel('sos')).toBe('SOS')
    expect(fenceActionLabel('enter')).toBe('进入')
    expect(fenceActionLabel('leave')).toBe('离开')
  })

  it('formal events page preserves audit timeline and adds platform verification review', () => {
    const dir = dirname(fileURLToPath(import.meta.url))
    const page = readFileSync(join(dir, '../../views/audit/events/index.vue'), 'utf8')
    expect(page).toMatch(/动作时间线/)
    expect(page).toMatch(/listEventActions/)
    expect(page).toMatch(/导出筛选结果/)
    expect(page).toMatch(/VerificationReview/)
    expect(page).not.toMatch(/claimEvent|handleEvent|transferEvent|closeEvent|simulateEvent/)
  })
})
