import { identities } from './seed.js'
import { capabilityDecision } from '../utils/device-profile.js'
import { failure } from './errors.js'
export function videoAccess(dataset, role, siteId, deviceId, key = 'video') {
  const identity = identities.find(i => i.id === role)
  if (!identity) throw failure(401, '本地会话失效')
  if (!identity.sites.includes(siteId)) throw failure(403, '无权访问该厂站')
  const device = dataset.entities.devices.find(d => d.siteId === siteId && d.deviceId === deviceId)
  if (!device || !dataset.entities.videos.some(d => d.siteId === siteId && d.deviceId === deviceId)) throw failure(404, '视频设备不存在或不可见')
  if (dataset.config.module === 'video' && dataset.config.mode !== 'normal') throw failure(dataset.config.mode === 'forbidden' ? 403 : 503, '本地视频来源不可用，请恢复场景后重试')
  const decision = capabilityDecision(device, key, { mock: true, permitted: key === 'video' || role === 'owner', moduleEnabled: true })
  if (!decision.allowed) throw failure(403, decision.reason)
  return device
}
export function privacyCommand(dataset, role, input) {
  const identity = identities.find(i => i.id === role)
  if (!identity) throw failure(401, '本地会话失效')
  if (role !== 'owner' || !identity.sites.includes(input.siteId)) throw failure(403, '仅负责人调整本厂站本地隐私记录')
  const device = dataset.entities.devices.find(d => d.siteId === input.siteId && d.deviceId === input.deviceId && d.type === 'HELMET')
  if (!device) throw failure(404, '对象不可见')
  if (!['ON', 'OFF'].includes(input.privacy)) throw failure(400, '隐私状态无效')
  if (device.profile.privacy !== input.expectedPrivacy) throw failure(409, '隐私状态已变化，请刷新')
  device.profile.privacy = input.privacy
  return { changedEntities: ['video', 'equipment', 'people'], privacy: input.privacy }
}
