import { describe, expect, it } from 'vitest'
import { featureDraft, featurePayload } from './deviceFeatureForm'
import { deviceFeatureRows } from './deviceFeaturePresentation'
const device = { source: 'DIRECT_BELT', type: 'BELT' }
describe('device feature maintenance', () => {
  it('reads back saved status without requesting alarm codes or evidence', () => {
    const status = { support: 'SUPPORTED', connection: 'CONNECTED', availability: 'AVAILABLE' }
    const draft = featureDraft({ ...device, featureConfiguration: { temperature: { status, evidence: '旧记录', alarmCodes: ['3'] } } }, 'temperature')
    expect(featurePayload(draft)).toEqual({ feature: 'temperature', ...status })
  })
  it('uses automatic status for existing devices and submits only the three maintained fields', () => {
    const draft = featureDraft(device, 'wear')
    expect(featurePayload(draft)).toEqual({ feature: 'wear', support: 'DEFAULT', connection: 'DEFAULT', availability: 'DEFAULT' })
    draft.evidence = 'old'; draft.alarmCodes = ['3']
    expect(featurePayload(draft)).not.toHaveProperty('evidence')
    expect(featurePayload(draft)).not.toHaveProperty('alarmCodes')
  })
  it('rejects invalid and contradictory statuses', () => {
    const draft = { ...featureDraft(device, 'temperature'), availability: 'AVAILABLE' }
    expect(() => featurePayload(draft)).toThrow('同时选择')
    Object.assign(draft, { support: 'SUPPORTED', connection: 'CONNECTED' })
    expect(featurePayload(draft).availability).toBe('AVAILABLE')
    draft.connection = 'wrong'; expect(() => featurePayload(draft)).toThrow('连接状态')
  })
  it('distinguishes pending configuration from explicitly unsupported hardware', () => {
    const unknown = { supported: false, optional: true, supportStatus: 'UNKNOWN' }
    expect(deviceFeatureRows({ ...device, featureStates: { proximity: unknown } })[0].availability.label).toBe('待确认')
    expect(deviceFeatureRows({ ...device, featureStates: { proximity: { ...unknown, supportStatus: 'UNSUPPORTED' } } })[0].support.label).toBe('不支持')
  })
})
