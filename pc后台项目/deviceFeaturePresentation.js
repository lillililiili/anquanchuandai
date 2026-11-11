import { FEATURE_LABELS, featureState, featureUnavailableReason } from '../shared/device-features.mjs'

const LABELS = Object.freeze({ ...FEATURE_LABELS, videoCall: '视频通话', doubleRelease: '防双解', lowHook: '高低挂检测', proximity: '近电检测', temperature: '温度报警', silent: '静默提醒', rtk: '高精度定位', indoorLocation: '室内辅助定位' })
const ORDER = ['battery', 'wear', 'hooks', 'height', 'location', 'alarm', 'sos', 'video', 'videoCall', 'photo', 'recording', 'voice', 'broadcast', 'vitals', 'doubleRelease', 'lowHook', 'proximity', 'temperature', 'silent', 'rtk', 'indoorLocation']
const COMMON_FEATURES = ['battery', 'wear', 'location', 'alarm', 'sos']
const DEVICE_FEATURES = {
  HELMET: new Set([...COMMON_FEATURES, 'video', 'videoCall', 'photo', 'recording', 'voice', 'broadcast']),
  BELT: new Set([...COMMON_FEATURES, 'hooks', 'height', 'doubleRelease', 'lowHook', 'proximity', 'temperature', 'silent', 'rtk', 'indoorLocation']),
  WATCH: new Set(['battery', 'vitals']),
}
const DEVICE_TYPES = { H: 'HELMET', HELMET: 'HELMET', B: 'BELT', BELT: 'BELT', W: 'WATCH', WATCH: 'WATCH' }
const SOURCE_TYPES = { DIRECT_HELMET: 'HELMET', DIRECT_BELT: 'BELT', DEMO_WATCH: 'WATCH' }
const status = (label, tone = 'neutral') => ({ label, tone })

// Use persisted maintenance choices for this list; automatic choices continue
// to use observed readiness. Shared command and telemetry checks stay separate.
export function deviceFeatureRows(device) {
  const states = device?.featureStates
  if (!states || typeof states !== 'object' || Array.isArray(states)) return []
  const simulated = device.simulated === true || device.source === 'DEMO_WATCH'
  // The API returns a shared feature catalogue, including other equipment's
  // unsupported entries. Scope known rows to this device without changing its
  // support/acceptance evidence; keep unfamiliar server extensions visible.
  const applicable = DEVICE_FEATURES[DEVICE_TYPES[device.type] || SOURCE_TYPES[device.source]]
  return [...ORDER.filter(key => Object.hasOwn(states, key)), ...Object.keys(states).filter(key => !ORDER.includes(key))]
    .filter(key => !applicable || !ORDER.includes(key) || applicable.has(key))
    .filter(key => states[key] && typeof states[key] === 'object' && !Array.isArray(states[key]))
    .map(key => {
      const state = states[key]
      const supported = state.supported === true
      const unsupported = state.supported === false
      const optional = unsupported && state.optional === true && state.supportStatus !== 'UNSUPPORTED'
      const integrated = supported && state.integrationStatus === 'CONNECTED'
      const available = integrated && featureState(device, key).available
      const support = supported ? status('支持') : optional ? status('选配未确认', 'pending') : unsupported ? status('不支持') : status('未提供')
      const integration = !supported ? status(optional ? '待确认' : unsupported ? '不适用' : '未提供') : simulated ? status('模拟数据') : integrated ? status('已连接') : state.integrationStatus === 'NOT_CONNECTED' ? status('连接不可用', 'pending') : status('未提供')
      const pending = state.supportStatus === 'UNKNOWN' || state.reason === '设备数据待确认' || state.reason === '平台尚无对应数据接入'
      const availability = simulated && supported ? status('仅模拟展示') : available ? status('当前可用', 'ready') : status(pending ? '待确认' : '不可用', supported || optional ? 'pending' : 'neutral')
      const reason = available ? '' : featureUnavailableReason(state.reason || (optional ? '选配尚未确认' : unsupported ? '设备不支持' : ''), key)
      const row = { key, label: LABELS[key] || '其他功能', code: LABELS[key] ? '' : key, support, integration, availability, reason }
      const configured = device.featureConfiguration?.[key]?.status
      if (!configured) return row
      const supportChoice = { SUPPORTED: status('支持'), UNSUPPORTED: status('不支持'), PENDING: status('待确认', 'pending') }[configured.support]
      const connectionChoice = { CONNECTED: status('已连接'), NOT_CONNECTED: status('未连接', 'pending'), PENDING: status('待确认', 'pending') }[configured.connection]
      const availabilityChoice = { AVAILABLE: status('当前可用', 'ready'), UNAVAILABLE: status('不可用', 'pending'), PENDING: status('待确认', 'pending') }[configured.availability]
      if (!supportChoice && !connectionChoice && !availabilityChoice) return row
      if (supportChoice) row.support = supportChoice
      if (connectionChoice) row.integration = connectionChoice
      if (availabilityChoice) { row.availability = availabilityChoice; row.reason = '' }
      if (row.availability.tone === 'ready' && (row.support.label !== '支持' || row.integration.label !== '已连接')) {
        row.availability = status('不可用', 'pending'); row.reason = ''
      }
      row.managed = true
      return row
    })
}
