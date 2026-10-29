import { describe, expect, it } from 'vitest'
import { deviceConnectionErrors, deviceSubmission } from './deviceForm'

const form = () => ({ type: 'HELMET', source: 'DIRECT_HELMET', deviceNumber: ' device.login-1020 ', code: 'ASSET-1', sn: 'SN-OTHER-1', name: '一体式安全帽' })

describe.each([
  ['HELMET', 'DIRECT_HELMET'],
  ['BELT', 'DIRECT_BELT'],
])('direct %s registration form', (type, source) => {
  const directForm = () => ({ ...form(), type, source })
  it('sends independent platform, login and physical SN identities', () => {
    expect(deviceConnectionErrors(directForm())).toEqual({})
    expect(deviceSubmission(directForm())).toEqual({ ...directForm(), deviceNumber: 'device.login-1020' })
  })
  it('requires a valid device login ID only for direct creation', () => {
    for (const deviceNumber of ['', '含中文', 'a b', 'a'.repeat(65)]) {
      expect(deviceConnectionErrors({ ...directForm(), deviceNumber }).deviceNumber).toBeTruthy()
    }
    expect(deviceConnectionErrors({ ...directForm(), deviceNumber: '', source: 'LOCAL' })).toEqual({})
    expect(deviceConnectionErrors({ ...directForm(), deviceNumber: '' }, true)).toEqual({})
  })
  it('does not overwrite protocol identities when editing an existing device', () => {
    const data = deviceSubmission(directForm(), true)
    expect(data).not.toHaveProperty('type')
    expect(data).not.toHaveProperty('source')
    expect(data).not.toHaveProperty('deviceNumber')
    expect(data.sn).toBe('SN-OTHER-1')
  })
  it('local assets and mismatched types cannot accidentally submit direct settings', () => {
    for (const item of [{ ...directForm(), source: 'LOCAL' }, { ...directForm(), type: 'WATCH' }, { ...directForm(), type: type === 'BELT' ? 'HELMET' : 'BELT' }]) {
      const data = deviceSubmission(item)
      expect(data).not.toHaveProperty('source')
      expect(data).not.toHaveProperty('deviceNumber')
    }
  })
})
