import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { connectionLabel, supportsCapability } from './devices.js'

describe('device capability contract', () => {
  it('does not treat helmet type as having video', () => {
    const noVideo = { typeCode: 'helmet', capabilities: { actions: ['tts'], attributes: ['gnss'] } }
    expect(supportsCapability(noVideo, 'video')).toBe(false)
    const withVideo = { typeCode: 'helmet', capabilities: { actions: ['video'] } }
    expect(supportsCapability(withVideo, 'video')).toBe(true)
  })

  it('device page does not hardcode helmet video', () => {
    const dir = dirname(fileURLToPath(import.meta.url))
    const page = readFileSync(join(dir, '../../views/devices/index.vue'), 'utf8')
    expect(page).toMatch(/supportsCapability\([^,]+,\s*'video'\)/)
    expect(page).not.toMatch(/typeCode === 'helmet'[\s\S]{0,80}video/)
  })

  it('null online is unknown not offline', () => {
    expect(connectionLabel({ online: null, connectionQuality: 'unknown' })).toBe('未知')
    expect(connectionLabel({ online: '1', connectionQuality: 'stale' })).toBe('陈旧')
    expect(connectionLabel({ connectionQuality: 'ok' })).toBe('有效')
    const dir = dirname(fileURLToPath(import.meta.url))
    const page = readFileSync(join(dir, '../../views/devices/index.vue'), 'utf8')
    expect(page).toMatch(/connectionLabel/)
    expect(page).not.toMatch(/S6 真实接入后才显示/)
  })
})
