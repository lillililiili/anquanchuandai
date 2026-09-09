import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { callStatusLabel, isCallConnected } from './calls.js'

describe('call status contract', () => {
  it('offered is not connected', () => {
    expect(isCallConnected('offered')).toBe(false)
    expect(isCallConnected('requesting')).toBe(false)
    expect(isCallConnected('connected')).toBe(true)
    expect(callStatusLabel('offered')).toBe('待加入')
    expect(callStatusLabel('connected')).toBe('已接通')
  })

  it('events page does not treat offered as connected and gates intercom', () => {
    const dir = dirname(fileURLToPath(import.meta.url))
    const page = readFileSync(join(dir, '../../views/events/index.vue'), 'utf8')
    expect(page).toMatch(/isCallConnected/)
    expect(page).toMatch(/supportsCapability/)
    expect(page).not.toMatch(/呼叫已接通/)
  })
})
