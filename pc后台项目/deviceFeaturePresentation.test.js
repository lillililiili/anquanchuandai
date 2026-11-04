import { describe, expect, it } from 'vitest'
import { createSSRApp } from 'vue'
import { renderToString } from 'vue/server-renderer'
import DeviceFeatureStatus from './components/DeviceFeatureStatus.vue'
import { deviceFeatureRows } from './deviceFeaturePresentation'
import { featureState, featureUnavailableReason, featureLabel } from '../shared/device-features.mjs'

const pending = { supported: true, verified: false, available: false, integrationStatus: 'CONNECTED', verificationStatus: 'PENDING', reason: '待联调' }
const accepted = { ...pending, verified: true, available: true, verificationStatus: 'VERIFIED', reason: '' }
const rowFor = state => deviceFeatureRows({ featureStates: { video: state } })[0]

describe('device feature acceptance presentation', () => {
  it('shows runtime-ready helmet commands consistently across the two device type projections', () => {
    for (const type of ['H', 'HELMET']) for (const key of ['video', 'photo', 'recording', 'voice', 'broadcast', 'videoCall']) {
      const device = { type, source: 'DIRECT_HELMET', communicationProtocol: 'SIP', featureStates: { [key]: { ...pending, available: true } } }
      expect(featureState(device, key)).toMatchObject({ supported: true, verified: false, available: true, reason: '' })
      expect(deviceFeatureRows(device)[0].availability.label).toBe('当前可用')
      expect(featureLabel(device, key)).not.toMatch(/待联调|未接入/)
      device.featureStates[key].available = false
      expect(featureState(device, key).available).toBe(false)
    }
  })

  it('does not infer a usable device command from a declaration, wrong device, missing connection or SIP protocol', () => {
    const device = { type: 'HELMET', source: 'DIRECT_HELMET', communicationProtocol: 'SIP', featureStates: { voice: { ...pending, available: true } } }
    for (const change of [{ source: 'DIRECT_BELT' }, { type: 'BELT' }, { communicationProtocol: 'UNKNOWN' }, { featureStates: { voice: { ...pending, available: true, integrationStatus: 'NOT_CONNECTED' } } }]) {
      expect(featureState({ ...device, ...change }, 'voice').available).toBe(false)
    }
    expect(featureState({ capabilities: ['intercom'] }, 'voice').available).toBe(false)
    expect(featureUnavailableReason('设备离线', 'voice')).toBe('设备离线')
    expect(featureUnavailableReason('安全帽语音服务尚未接入', 'voice')).toContain('检查设备注册')
  })
  it('keeps physical support, integration, acceptance and temporary availability separate', () => {
    const offline = rowFor({ ...accepted, available: false, reason: '设备离线' })
    expect(offline).toMatchObject({ label: '实时视频', support: { label: '支持' }, integration: { label: '已连接' }, verification: { label: '已验收' }, availability: { label: '不可用' }, reason: '设备离线' })
    expect(rowFor(pending)).toMatchObject({ integration: { label: '已连接' }, verification: { label: '无验收记录' }, availability: { label: '不可用' } })
    expect(rowFor({ ...pending, integrationStatus: 'NOT_CONNECTED', reason: '待接入' })).toMatchObject({ integration: { label: '连接不可用' }, verification: { label: '无验收记录' }, reason: '视频服务不可用，请检查设备网络和媒体服务' })
  })

  it('does not describe generic connected or pending fields as integration/acceptance for unsupported options', () => {
    const states = { supported: false, verified: false, available: false, integrationStatus: 'CONNECTED', verificationStatus: 'PENDING' }
    expect(rowFor(states)).toMatchObject({ support: { label: '不支持' }, integration: { label: '不适用' }, verification: { label: '不适用' } })
    expect(rowFor({ ...states, optional: true })).toMatchObject({ support: { label: '选配未确认' }, integration: { label: '待确认' }, verification: { label: '待确认' }, availability: { label: '不可用' } })
  })

  it('does not infer acceptance from a model, action list, incomplete record or inconsistent available flag', () => {
    expect(deviceFeatureRows({ type: 'HELMET', capabilities: { actions: ['video'] } })).toEqual([])
    expect(rowFor({ supported: true, available: true })).toMatchObject({ integration: { label: '未提供' }, verification: { label: '未提供' }, availability: { label: '不可用' } })
    expect(rowFor({ ...pending, available: true }).availability.label).toBe('不可用')
  })

  it('labels simulated acceptance without claiming physical validation and names optional features in Chinese', () => {
    const rows = deviceFeatureRows({ source: 'DEMO_WATCH', featureStates: { vitals: accepted, proximity: { supported: false, optional: true } } })
    expect(rows[0]).toMatchObject({ label: '生命体征', verification: { label: '模拟数据' }, availability: { label: '仅模拟展示' } })
    expect(rows[1]).toMatchObject({ label: '近电检测', support: { label: '选配未确认' } })
  })

  it('renders a read-only table and labelled narrow-screen cards without any command or acceptance control', async () => {
    const html = await renderToString(createSSRApp(DeviceFeatureStatus, { device: { featureStates: { voice: { ...pending, integrationStatus: 'NOT_CONNECTED', reason: '待接入' }, video: { supported: false } } } }))
    expect(html).toContain('设备功能与验收状态')
    expect(html).toContain('语音对讲')
    expect(html).toContain('连接不可用')
    expect(html).not.toMatch(/待联调|未接入|待接入/)
    expect(html).toContain('scope="row"')
    expect(html).toMatch(/<dt\b[^>]*>验收状态<\/dt>/)
    expect(html).not.toMatch(/<(?:button|input|select)\b/)
    const empty = await renderToString(createSSRApp(DeviceFeatureStatus, { device: {} }))
    expect(empty).toContain('尚未提供本设备的功能与验收记录')
  })
})
