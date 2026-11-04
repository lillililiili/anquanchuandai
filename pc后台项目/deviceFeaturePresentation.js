import { FEATURE_LABELS, featureState, featureUnavailableReason } from '../shared/device-features.mjs'

const LABELS = Object.freeze({ ...FEATURE_LABELS, videoCall: '视频通话', doubleRelease: '防双解', lowHook: '高低挂检测', proximity: '近电检测', temperature: '温度报警', rtk: '高精度定位', indoorLocation: '室内辅助定位' })
const ORDER = ['battery', 'wear', 'hooks', 'height', 'location', 'alarm', 'sos', 'video', 'videoCall', 'photo', 'recording', 'voice', 'broadcast', 'vitals', 'doubleRelease', 'lowHook', 'proximity', 'temperature', 'rtk', 'indoorLocation']
const status = (label, tone = 'neutral') => ({ label, tone })

// Display only the server's per-device assessment. Model names and declared
// protocol commands are not evidence of integration or physical acceptance.
export function deviceFeatureRows(device) {
  const states = device?.featureStates
  if (!states || typeof states !== 'object' || Array.isArray(states)) return []
  const simulated = device.simulated === true || device.source === 'DEMO_WATCH'
  return [...ORDER.filter(key => Object.hasOwn(states, key)), ...Object.keys(states).filter(key => !ORDER.includes(key))]
    .filter(key => states[key] && typeof states[key] === 'object' && !Array.isArray(states[key]))
    .map(key => {
      const state = states[key]
      const supported = state.supported === true
      const unsupported = state.supported === false
      const optional = unsupported && state.optional === true
      const verified = supported && state.verified === true && state.verificationStatus === 'VERIFIED'
      const integrated = supported && state.integrationStatus === 'CONNECTED'
      const available = integrated && featureState(device, key).available
      const support = supported ? status('支持') : optional ? status('选配未确认', 'pending') : unsupported ? status('不支持') : status('未提供')
      const integration = !supported ? status(optional ? '待确认' : unsupported ? '不适用' : '未提供') : simulated ? status('模拟数据') : integrated ? status('已连接') : state.integrationStatus === 'NOT_CONNECTED' ? status('连接不可用', 'pending') : status('未提供')
      const verification = !supported ? status(optional ? '待确认' : unsupported ? '不适用' : '未提供') : simulated ? status('模拟数据') : verified ? status('已验收', 'ready') : state.verificationStatus === 'PENDING' || state.verified === false ? status('无验收记录', 'pending') : status('未提供')
      const availability = simulated && supported ? status('仅模拟展示') : available ? status('当前可用', 'ready') : status('不可用', supported || optional ? 'pending' : 'neutral')
      const reason = available ? '' : featureUnavailableReason(state.reason || (optional ? '选配尚未确认' : unsupported ? '设备不支持' : ''), key)
      return { key, label: LABELS[key] || '其他功能', code: LABELS[key] ? '' : key, support, integration, verification, availability, reason }
    })
}
