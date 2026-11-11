import { afterEach, describe, expect, it, vi } from 'vitest'
import { verifiedDeviceSummary, deviceBatteryPresentation, deviceRemark } from './devicePresentation'
import { syncServerTime, resetServerClock } from '../shared/server-clock.mjs'

afterEach(() => { resetServerClock(); vi.restoreAllMocks() })
describe('real device presentation',()=>{
  it('uses the server clock for fresh observations while retaining stale and future rejection', () => {
    const local = Date.parse('2026-11-05T09:38:39Z')
    vi.spyOn(Date, 'now').mockReturnValue(local)
    const device = { source: 'DIRECT_HELMET', freshness: 'CURRENT', online: true, sourceTime: '2026-11-05T09:38:41.766Z',
      battery: 83, batteryReportedAt: '2026-11-05T09:38:41.766Z', batteryFreshness: 'CURRENT', worn: false, isWearedFreshness: 'CURRENT' }
    expect(deviceBatteryPresentation(device).status).toBe('时间未确认')
    syncServerTime('Thu, 05 Nov 2026 09:38:42 GMT')
    expect(deviceBatteryPresentation(device).status).toBe('当前')
    expect(verifiedDeviceSummary(device).worn).toBe('未佩戴')
    expect(deviceBatteryPresentation({ ...device, batteryReportedAt: '2026-11-05T09:30:00Z' }).status).toBe('历史')
    expect(deviceBatteryPresentation({ ...device, batteryReportedAt: '2026-11-05T09:39:42Z' }).status).toBe('时间未确认')
  })
  it('does not claim video support from device type or identity alone',()=>{
    expect(verifiedDeviceSummary({type:'HELMET',identityComplete:true}).capabilities).toBe('业务能力待核验')
    const d={source:'DIRECT_HELMET',freshness:'CURRENT',sourceTime:new Date().toISOString(),capabilities:{actions:['tts','location']},worn:false,isWearedFreshness:'CURRENT',battery:80,batteryFreshness:'CURRENT'}
    expect(verifiedDeviceSummary(d)).toMatchObject({capabilities:'语音播报、定位上报',worn:'未佩戴'})
    expect(verifiedDeviceSummary({...d,freshness:'STALE'}).worn).toMatch(/未知/)
    expect(verifiedDeviceSummary({...d,batteryFreshness:'STALE',isWearedFreshness:'UNKNOWN'})).toMatchObject({battery:'未知（暂无最新上报）',worn:'未知（暂无最新上报）'})
  })
})

describe('device list battery freshness', () => {
  const now = Date.parse('2026-11-02T08:00:00Z')
  const current = { source: 'DIRECT_HELMET', battery: 83, batteryFreshness: 'CURRENT', batteryReportedAt: '2026-11-02T07:59:59Z', sourceTime: '2026-11-02T08:00:00Z' }
  it('keeps stale values explicitly historical even when communication has a recent heartbeat', () => {
    expect(deviceBatteryPresentation(current, now)).toMatchObject({ value: '83%', status: '当前' })
    expect(deviceBatteryPresentation({ ...current, batteryReportedAt: '2026-10-29T11:00:00Z' }, now)).toMatchObject({ value: '83%', status: '历史', title: '电量上报：2026-10-29 19:00:00（北京时间）' })
    expect(deviceBatteryPresentation({ ...current, batteryFreshness: 'STALE' }, now).status).toBe('历史')
  })
  it('distinguishes missing, unconfirmed, zero and simulated observations', () => {
    expect(deviceBatteryPresentation({ ...current, battery: null }, now)).toMatchObject({ value: '—', status: '未上报' })
    expect(deviceBatteryPresentation({ ...current, battery: 0 }, now)).toMatchObject({ value: '0%', status: '当前' })
    expect(deviceBatteryPresentation({ source: 'DIRECT_BELT', battery: 45 }, now)).toMatchObject({ value: '45%', status: '时间未确认' })
    expect(deviceBatteryPresentation({ ...current, batteryReportedAt: '2026-11-02T08:05:00Z' }, now).status).toBe('时间未确认')
    expect(deviceBatteryPresentation({ ...current, source: 'DEMO_WATCH' }, now).status).toBe('模拟')
    for (const battery of ['invalid', -1, 101]) expect(deviceBatteryPresentation({ ...current, battery }, now).status).toBe('未上报')
  })
})

describe('device remarks', () => {
  it('hides known provisioning boilerplate without rewriting stored or customer notes', () => {
    expect(deviceRemark('真实型号：HNRW-AQD1；site-1 仅为本地联调台账归属，不认定实际厂站；未绑定人员。')).toBe('型号：HNRW-AQD1')
    expect(deviceRemark('真实型号：HNRW-AQD1；site-1 仅为本地联调台账归属，不认定实际厂站；未绑定人员。客户备注：定期检查')).toBe('型号：HNRW-AQD1；客户备注：定期检查')
    expect(deviceRemark('联调后交付；未绑定人员。')).toBe('联调后交付；未绑定人员。')
    expect(deviceRemark(null)).toBe('')
  })
})
