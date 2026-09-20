import { validateProfile } from './device-profile.js'
export const sectionStates = ['AVAILABLE', 'NOT_INTEGRATED', 'UNAVAILABLE', 'FORBIDDEN']
export const deviceTypes = { helmet: '安全帽', belt: '安全带', watch: '智能手表' }
export const labels = {
  AVAILABLE: '已接入', NOT_INTEGRATED: '数据待接入', UNAVAILABLE: '数据暂时无法读取', FORBIDDEN: '无权查看',
  ASSIGNED: '已领用', UNASSIGNED: '未领用', UNKNOWN: '未知', CONFLICT: '领用关系冲突',
  ONLINE: '在线', OFFLINE: '离线', FRESH: '数据有效', STALE: '数据已过期', NOT_APPLICABLE: '未接入',
  ON_DUTY: '在岗', OFF_DUTY: '不在当班', OPEN: '使用中', CLOSED: '已结束',
  ISSUE: '领取', RETURN: '归还', CORRECTION: '更正', MIGRATION_SNAPSHOT: '当前关系快照（非领用流水）'
}
export const reasons = {
  EVENT_NOT_INTEGRATED: '事件来源待接入', TIMELINE_NOT_INTEGRATED: '事实时间线待接入', VERIFICATION_NOT_INTEGRATED: '核验记录来源待接入', STATISTICS_NOT_INTEGRATED: '统计来源待接入',
  DEVICE_SOURCE_NOT_INTEGRATED: '设备选择来源待接入', LOCATION_NOT_INTEGRATED: '定位数据待接入', TRACK_NOT_INTEGRATED: '轨迹数据待接入', FENCE_NOT_INTEGRATED: '围栏数据待接入', MATERIAL_NOT_INTEGRATED: '现场资料待接入', FILE_ACCESS_NOT_ENABLED: '真实文件访问暂未开放',
  SITE_SCOPE_NOT_INTEGRATED: '厂站数据待接入', NO_AUTHORIZED_SITE: '当前账号暂无授权厂站',
  ROSTER_NOT_INTEGRATED: '当班名册未接入', SHIFT_UNRESOLVED: '当前班次待确认',
  HISTORY_NOT_INTEGRATED: '领用历史待接入', HISTORICAL_ATTRIBUTION_UNKNOWN: '历史人员归属未知',
  SOURCE_NOT_INTEGRATED: '数据待接入', PROTOCOL_PENDING: '厂家协议待确认',
  SOURCE_UNAVAILABLE: '数据源暂时不可用，请稍后重试', SECTION_FORBIDDEN: '当前账号无权查看',
  MODULE_NOT_ENABLED: '本阶段暂未开放', SOURCE_TIME_MISSING: '源时间未知', ASSIGNMENT_CONFLICT: '领用关系冲突，待管理员核实'
}
export const missingSection = (reasonCode = 'SOURCE_NOT_INTEGRATED') => ({ state: 'NOT_INTEGRATED', data: null, reasonCode })
export function requireValue(condition, message = '接口响应格式异常') {
  if (!condition) throw Object.assign(new Error(message), { code: 'INVALID_RESPONSE' })
}
export function idString(value) {
  requireValue(typeof value === 'string' && value.length > 0 || Number.isSafeInteger(value), '标识不完整或存在精度损失')
  return String(value)
}
export function formatTime(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T.*Z$/.test(value) && Number.isFinite(Date.parse(value))
    ? value.replace('T', ' ').replace(/\.\d+Z$/, ' UTC').replace('Z', ' UTC') : '—'
}
export function validateSection(value) {
  requireValue(value && sectionStates.includes(value.state))
  requireValue(value.state === 'AVAILABLE' ? value.data !== null && value.data !== undefined : value.data === null && !!value.reasonCode)
  return value
}
export function validateEquipment(value) {
  validateSection(value)
  if (value.state !== 'AVAILABLE') return value
  for (const [key, type] of Object.entries({ helmet: 'HELMET', belt: 'BELT', watch: 'WATCH' })) {
    const slot = value.data[key]
    requireValue(slot && slot.type === type && Array.isArray(slot.devices))
    const n = slot.devices.length
    requireValue(['ASSIGNED', 'UNASSIGNED', 'UNKNOWN', 'CONFLICT'].includes(slot.assignmentState))
    requireValue(slot.assignmentState === 'ASSIGNED' ? n === 1 : slot.assignmentState === 'CONFLICT' ? n >= 2 : n === 0)
    for (const device of slot.devices) {
      validateProfile(device.profile)
      requireValue(typeof device.deviceId === 'string' && device.type === type && typeof device.deviceCode === 'string')
      const c = device.communication
      requireValue(c && ['ONLINE', 'OFFLINE', 'UNKNOWN', 'NOT_INTEGRATED'].includes(c.state))
      for (const reading of [c, device.battery]) {
        requireValue(reading && ['FRESH', 'STALE', 'UNKNOWN', 'NOT_APPLICABLE'].includes(reading.freshness))
        if (['FRESH', 'STALE'].includes(reading.freshness)) requireValue(formatTime(reading.sourceTime) !== '—')
      }
      requireValue(c.sourceKind !== 'LEGACY_SNAPSHOT' || c.state === 'UNKNOWN')
      requireValue(device.battery.value === null || Number.isFinite(device.battery.value) && device.battery.value >= 0 && device.battery.value <= 100)
      for (const key of ['video', 'talk', 'location', 'capture', 'record']) {
        const cap = device.capabilities?.[key]
        requireValue(cap && ['SUPPORTED', 'UNSUPPORTED', 'UNKNOWN'].includes(cap.state) && ['VERIFIED', 'UNVERIFIED'].includes(cap.verification))
      }
    }
  }
  return value
}
export function validatePerson(p) {
  requireValue(p && typeof p.personId === 'string' && typeof p.siteId === 'string' && typeof p.name === 'string' && !!p.name)
  validateEquipment(p.equipment)
  validateSection(p.works)
  validateSection(p.duty)
  requireValue(p.actions && ['viewHistory', 'viewVideo', 'talk', 'viewWork', 'viewEvent'].every(k => typeof p.actions[k]?.allowed === 'boolean'))
  return p
}
export function validatePage(data, history = false) {
  requireValue(data && sectionStates.includes(data.state) && Array.isArray(data.items))
  requireValue(Number.isInteger(data.pageNum) && data.pageNum > 0 && Number.isInteger(data.pageSize) && data.pageSize > 0 && data.pageSize <= 100)
  requireValue(data.state === 'AVAILABLE' ? Number.isInteger(data.total) && data.total >= data.items.length : data.total === null && data.items.length === 0 && !!data.reasonCode)
  for (const item of data.items) {
    if (!history) validatePerson(item)
    else {
      requireValue(typeof item.recordId === 'string' && typeof item.personId === 'string')
      if (item.action === 'MIGRATION_SNAPSHOT') requireValue(item.evidenceQuality === 'CURRENT_SNAPSHOT_ONLY' && item.state === 'UNKNOWN' && [item.startedAt, item.endedAt, item.occurredAt].every(v => v === null))
    }
  }
  return data
}
export function validateContext(data) {
  requireValue(data && ['sites', 'teams', 'areas', 'shifts', 'permissions'].every(k => Array.isArray(data[k])))
  requireValue(data.capabilities?.people && data.availability)
  requireValue(data.sites.every(s => typeof s.siteId === 'string' && typeof s.name === 'string'))
  requireValue(data.selectedSiteId === null || data.sites.some(s => s.siteId === data.selectedSiteId))
  return data
}
export function validateDetail(data) {
  validatePerson(data?.person)
  for (const key of ['equipment', 'works', 'duty', 'events', 'location', 'media', 'historySummary']) validateSection(data[key])
  for (const key of ['equipment', 'works', 'duty', 'actions']) requireValue(JSON.stringify(data[key]) === JSON.stringify(data.person[key]), '人员详情快照不一致')
  return data
}
