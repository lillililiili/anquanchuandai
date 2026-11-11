import { describe, expect, it } from 'vitest'
import { createSSRApp } from 'vue'
import { renderToString } from 'vue/server-renderer'
import DeviceFeatureStatus from './components/DeviceFeatureStatus.vue'
import { deviceFeatureRows } from './deviceFeaturePresentation'
import { featureState, featureUnavailableReason, featureLabel } from '../shared/device-features.mjs'

const pending = { supported: true, verified: false, available: false, integrationStatus: 'CONNECTED', verificationStatus: 'PENDING', reason: '待联调' }
const accepted = { ...pending, verified: true, available: true, verificationStatus: 'VERIFIED', reason: '' }
const rowFor = state => deviceFeatureRows({ featureStates: { video: state } })[0]

describe('device feature presentation', () => {
  it('shows saved maintenance statuses without altering actual telemetry or command availability', () => {
    const device = { type: 'BELT', source: 'DIRECT_BELT', featureStates: { temperature: { supported: false, optional: true, available: false, reason: '选配未确认' } },
      featureConfiguration: { temperature: { status: { support: 'SUPPORTED', connection: 'CONNECTED', availability: 'AVAILABLE' } } } }
    const before = structuredClone(device)
    expect(deviceFeatureRows(device)[0]).toMatchObject({ support: { label: '支持' }, integration: { label: '已连接' }, availability: { label: '当前可用' }, reason: '', managed: true })
    expect(featureState(device, 'temperature').available).toBe(false)
    expect(device).toEqual(before)
    device.featureConfiguration.temperature.status = { support: 'DEFAULT', connection: 'DEFAULT', availability: 'DEFAULT' }
    expect(deviceFeatureRows(device)[0]).toMatchObject({ support: { label: '选配未确认' } })
    expect(deviceFeatureRows(device)[0].managed).toBeUndefined()
  })

  it('does not combine an automatic available state with a manually disconnected feature', () => {
    const device = { featureStates: { battery: accepted }, featureConfiguration: { battery: { status: { support: 'DEFAULT', connection: 'NOT_CONNECTED', availability: 'DEFAULT' } } } }
    expect(deviceFeatureRows(device)[0]).toMatchObject({ integration: { label: '未连接' }, availability: { label: '不可用' }, managed: true })
  })
  it('scopes helmet rows to helmet functions while retaining their pending, unsupported and offline states', () => {
    const featureStates = {
      battery: accepted, wear: pending, hooks: accepted, height: { supported: false },
      location: { ...accepted, available: false, reason: '设备离线' }, alarm: accepted, sos: accepted,
      video: { supported: false }, videoCall: pending, photo: pending, recording: pending, voice: pending, broadcast: pending,
      vitals: { supported: false }, doubleRelease: { supported: false, optional: true }, lowHook: { supported: false },
      proximity: { supported: false }, temperature: { supported: false }, rtk: { supported: false }, indoorLocation: { supported: false },
    }
    const before = structuredClone(featureStates)
    for (const identity of [{ type: 'HELMET' }, { type: 'H' }, { source: 'DIRECT_HELMET' }]) {
      const rows = deviceFeatureRows({ ...identity, featureStates })
      expect(rows.map(row => row.key)).toEqual(['battery', 'wear', 'location', 'alarm', 'sos', 'video', 'videoCall', 'photo', 'recording', 'voice', 'broadcast'])
      expect(rows.find(row => row.key === 'wear').availability.label).toBe('不可用')
      expect(rows.find(row => row.key === 'video').support.label).toBe('不支持')
      expect(rows.find(row => row.key === 'location').reason).toBe('设备离线')
    }
    expect(featureStates).toEqual(before)
  })

  it('keeps belt-specific and watch-specific rows on their own equipment, and preserves unknown extensions', () => {
    const featureStates = { battery: accepted, hooks: pending, height: pending, doubleRelease: { supported: false, optional: true }, video: accepted, vitals: accepted, extraSensor: pending }
    for (const type of ['BELT', 'B']) {
      const rows = deviceFeatureRows({ type, featureStates })
      expect(rows.map(row => row.key)).toEqual(['battery', 'hooks', 'height', 'doubleRelease', 'extraSensor'])
      expect(rows.find(row => row.key === 'doubleRelease').support.label).toBe('选配未确认')
    }
    for (const type of ['WATCH', 'W']) expect(deviceFeatureRows({ type, featureStates }).map(row => row.key)).toEqual(['battery', 'vitals', 'extraSensor'])
    expect(deviceFeatureRows({ type: 'UNKNOWN', featureStates })).toHaveLength(7)
  })

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
  it('keeps physical support, integration and temporary availability separate', () => {
    const offline = rowFor({ ...accepted, available: false, reason: '设备离线' })
    expect(offline).toMatchObject({ label: '实时视频', support: { label: '支持' }, integration: { label: '已连接' }, availability: { label: '不可用' }, reason: '设备离线' })
    expect(rowFor(pending)).toMatchObject({ integration: { label: '已连接' }, availability: { label: '不可用' } })
    expect(rowFor({ ...pending, integrationStatus: 'NOT_CONNECTED', reason: '待接入' })).toMatchObject({ integration: { label: '连接不可用' }, reason: '视频服务不可用，请检查设备网络和媒体服务' })
  })

  it('does not describe generic connected or pending fields as integration for unsupported options', () => {
    const states = { supported: false, verified: false, available: false, integrationStatus: 'CONNECTED', verificationStatus: 'PENDING' }
    expect(rowFor(states)).toMatchObject({ support: { label: '不支持' }, integration: { label: '不适用' } })
    expect(rowFor({ ...states, optional: true })).toMatchObject({ support: { label: '选配未确认' }, integration: { label: '待确认' }, availability: { label: '不可用' } })
  })

  it('does not infer availability from a model, action list, incomplete record or inconsistent available flag', () => {
    expect(deviceFeatureRows({ type: 'HELMET', capabilities: { actions: ['video'] } })).toEqual([])
    expect(rowFor({ supported: true, available: true })).toMatchObject({ integration: { label: '未提供' }, availability: { label: '不可用' } })
    expect(rowFor({ ...pending, available: true }).availability.label).toBe('不可用')
  })

  it('labels simulated availability and names optional features in Chinese', () => {
    const rows = deviceFeatureRows({ source: 'DEMO_WATCH', featureStates: { vitals: accepted } })
    expect(rows[0]).toMatchObject({ label: '生命体征', integration: { label: '模拟数据' }, availability: { label: '仅模拟展示' } })
    const beltRows = deviceFeatureRows({ type: 'BELT', featureStates: { proximity: { supported: false, optional: true } } })
    expect(beltRows[0]).toMatchObject({ label: '近电检测', support: { label: '选配未确认' } })
  })

  it('omits belt and watch features from both the helmet table and narrow-screen cards', async () => {
    const html = await renderToString(createSSRApp(DeviceFeatureStatus, { device: { type: 'HELMET', featureStates: {
      battery: accepted, hooks: { supported: false }, height: { supported: false }, vitals: { supported: false },
      doubleRelease: { supported: false }, video: pending,
    } } }))
    expect(html).toContain('feature-table')
    expect(html).toContain('feature-cards')
    expect(html).toContain('实时视频')
    expect(html).not.toContain('验收')
    expect(html).not.toMatch(/双钩状态|相对高度|生命体征|防双解/)
  })

  it('renders a read-only table and labelled narrow-screen cards without any command or acceptance control', async () => {
    const html = await renderToString(createSSRApp(DeviceFeatureStatus, { device: { featureStates: { voice: { ...pending, integrationStatus: 'NOT_CONNECTED', reason: '待接入' }, video: { supported: false } } } }))
    expect(html).toContain('设备功能状态')
    expect(html).toContain('语音对讲')
    expect(html).toContain('连接不可用')
    expect(html).not.toMatch(/待联调|未接入|待接入/)
    expect(html).toContain('scope="row"')
    expect(html).not.toContain('验收')
    expect(html.match(/<th\b[^>]*scope="col"/g)).toHaveLength(4)
    expect(html).toMatch(/<dt\b[^>]*>当前可用性<\/dt>/)
    expect(html).not.toMatch(/<(?:button|input|select)\b/)
    const empty = await renderToString(createSSRApp(DeviceFeatureStatus, { device: {} }))
    expect(empty).toContain('尚未提供本设备的功能状态信息')
    expect(empty).not.toContain('验收')
  })
})
