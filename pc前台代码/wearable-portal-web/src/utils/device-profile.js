import { requireValue } from './portal-contract.js'

export const capabilityNames = { video: '视频监看', talk: '语音协同', location: '定位', capture: '图像采集', record: '录像', proximity: '临电报告', climbing: '登高报告', gas: '气体报告', vitals: '生命体征' }
export const profileLabels = { DECLARED: '资料已声明', OPTIONAL: '资料选配', NOT_DECLARED: '文档未声明', CONFLICTING: '资料存在差异', PRESENT: '预置已配置', ABSENT: '预置未配置', UNKNOWN: '未知', MOCK_READY: '预置数据', NOT_INTEGRATED: '未接入', VERIFIED: '已验证', UNVERIFIED: '真机未验证' }
export function capabilityDecision(device, key, { mock = false, permitted = false, moduleEnabled = false } = {}) {
  const cap = device?.profile?.capabilities?.[key]
  const deny = reason => ({ allowed: false, reason })
  if (!cap) return deny('能力资料待确认')
  if (cap.installation === 'ABSENT') return deny('该本地实例未配置此能力')
  if (cap.installation !== 'PRESENT') return deny('实例配置未知，厂家能力待确认')
  if (['video', 'capture', 'record'].includes(key) && device.profile.privacy !== 'OFF') return deny(device.profile.privacy === 'ON' ? '本地隐私状态已开启' : '隐私状态未知')
  if (!mock) return deny('真实接入尚未开放')
  if (!permitted) return deny('当前身份无操作权限')
  if (cap.integration !== 'MOCK_READY') return deny('能力来源未接入')
  if (!moduleEnabled) return deny('本阶段仅展示能力，操作尚未开放')
  return { allowed: true, reason: '仅允许本地操作，真机未验证' }
}
export function validateProfile(profile) {
  if (profile == null) return profile
  requireValue(typeof profile.model === 'string' && profile.sourceKind === 'MOCK_REQUIREMENT' && ['ON', 'OFF', 'UNKNOWN'].includes(profile.privacy))
  for (const key of Object.keys(capabilityNames)) {
    const c = profile.capabilities?.[key]
    requireValue(c && ['DECLARED', 'OPTIONAL', 'NOT_DECLARED', 'CONFLICTING'].includes(c.declaration) && ['PRESENT', 'ABSENT', 'UNKNOWN'].includes(c.installation) && ['MOCK_READY', 'NOT_INTEGRATED'].includes(c.integration) && c.verification === 'UNVERIFIED' && typeof c.evidence === 'string')
  }
  requireValue(Array.isArray(profile.observations))
  return profile
}
