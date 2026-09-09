import { describe, expect, it } from 'vitest'
import defaultSettings from '@/settings'

describe('platform title', () => {
  it('uses 智能穿戴管理平台 from env', () => {
    expect(defaultSettings.title).toBe('智能穿戴管理平台')
  })
})
