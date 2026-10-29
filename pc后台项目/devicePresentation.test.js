import { describe, expect, it } from 'vitest'
import { verifiedDeviceSummary } from './devicePresentation'
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
