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

  it('formal audit page and root app do not expose PC call controls', () => {
    const dir = dirname(fileURLToPath(import.meta.url))
    const page = readFileSync(join(dir, '../../views/audit/events/index.vue'), 'utf8')
    const app = readFileSync(join(dir, '../../App.vue'), 'utf8')
    expect(page).not.toMatch(/startCall|joinCall|sendTts|呼叫|播报/)
    expect(app).not.toMatch(/VideoView|AlarmNotification|assist-video/)
  })
})
