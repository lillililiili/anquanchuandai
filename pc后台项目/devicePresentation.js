const ACTIONS = { location: '定位上报', telemetry: '设备状态', sos: 'SOS求助', tts: '语音播报', broadcast: '语音播报', intercom: '语音对讲', video: '实时视频', take_photo: '拍照', start_recording: '录像', list_recordings: '录像列表', upload_recording: '录像上传', set_config: '参数设置' }
import { featureState, supportedFeatures, featureLabel } from '../shared/device-features.mjs'
import { beijingTime } from './tablePresentation'

export function deviceBatteryPresentation(device, now = Date.now()) {
  const raw = device?.battery
  if (raw == null || raw === '' || !Number.isFinite(Number(raw)) || Number(raw) < 0 || Number(raw) > 100) return { value: '—', status: '未上报', title: '暂无有效电量上报' }
  const value = `${Number(raw)}%`
  if (device.source === 'DEMO_WATCH') return { value, status: '模拟', title: '模拟电量，非设备实测' }
  const reportedAt = device.batteryReportedAt || device.sourceTime
  const age = now - Date.parse(reportedAt || '')
  const fieldState = device.batteryFreshness ?? device.freshness
  const current = fieldState === 'CURRENT' && Number.isFinite(age) && age >= 0 && age <= 300000
  const historical = fieldState === 'STALE' || Number.isFinite(age) && age > 300000
  return { value, status: current ? '当前' : historical ? '历史' : '时间未确认', title: reportedAt ? `电量上报：${beijingTime(reportedAt)}（北京时间）` : '电量上报时间未提供' }
}
export function verifiedDeviceSummary(device) {
  if (device?.type === 'WATCH' && device.source === 'DEMO_WATCH') return {
    identity: '智能手表模拟数据，仅用于功能演示，尚未接入真实手表。',
    capabilities: '模拟展示', worn: '模拟数据', battery: '模拟数据（非设备上报）',
  }
  const real = ['DIRECT_HELMET', 'DIRECT_BELT', 'PLATFORM'].includes(device?.source)
  const observed = Date.parse(device?.sourceTime || '')
  const age = Date.now() - observed
  const current = real && device.freshness === 'CURRENT' && Number.isFinite(age) && age >= 0 && age <= 300000
  const actions = Array.isArray(device?.capabilities) ? device.capabilities : device?.capabilities?.actions
  const fieldCurrent = field => current && (device.source !== 'DIRECT_HELMET' && device[`${field}Freshness`] == null || device[`${field}Freshness`] === 'CURRENT')
  return {
    identity: real && Number.isFinite(observed) ? '已收到真实设备数据；各项业务能力以服务端核验结果为准。' : device?.identityComplete ? '厂家身份已填写，尚未收到可核对的真实设备数据。' : '厂家身份资料尚不完整，请核对厂商和SN。',
    capabilities: device?.featureStates ? supportedFeatures(device).map(key => featureLabel(device, key)).join('、') || '无已声明能力' : Array.isArray(actions) && actions.length ? [...new Set(actions.map(action => ACTIONS[action]).filter(Boolean))].join('、') || '业务能力待核验' : '业务能力待核验',
    worn: device?.featureStates && !featureState(device, 'wear').verified ? featureState(device, 'wear').reason : !fieldCurrent('isWeared') ? '未知（暂无最新上报）' : device.worn === true ? '已佩戴' : device.worn === false ? '未佩戴' : '待确认',
    battery: !fieldCurrent('battery') || device.battery == null || device.battery === '' ? '未知（暂无最新上报）' : `${device.battery}%`,
  }
}
