import { describe, expect, it } from 'vitest'
import { verifiedDeviceSummary, deviceBatteryPresentation } from './devicePresentation'
describe('real device presentation',()=>{
  it('does not claim video support from device type or identity alone',()=>{
    expect(verifiedDeviceSummary({type:'HELMET',identityComplete:true}).capabilities).toBe('业务能力待核验')
    const d={source:'DIRECT_HELMET',freshness:'CURRENT',sourceTime:new Date().toISOString(),capabilities:{actions:['tts','location']},worn:false,isWearedFreshness:'CURRENT',battery:80,batteryFreshness:'CURRENT'}
    expect(verifiedDeviceSummary(d)).toMatchObject({capabilities:'语音播报、定位上报',worn:'未佩戴'})
    expect(verifiedDeviceSummary(d).identity).toMatch(/已收到真实设备数据/)
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
