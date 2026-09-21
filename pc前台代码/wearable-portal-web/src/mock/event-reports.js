export const alarmTypes = [
  ['HELMET_SOS', 'SOS求助', 'HELMET', 'sos'], ['BELT_LOCK_REPORT', '锁扣状态告警', 'BELT'],
  ['HELMET_OFF_HAT', '脱帽告警', 'HELMET', 'removal'], ['HELMET_FALL', '跌落告警', 'HELMET', 'fall'],
  ['HELMET_PROXIMITY', '近电告警', 'HELMET', 'proximity'], ['HELMET_SILENCE', '静默告警', 'HELMET', 'silent'],
  ['HELMET_IMPACT_REPORT', '撞击告警', 'HELMET'], ['BELT_LOW_ANCHOR_REPORT', '低挂告警', 'BELT'],
  ['BELT_SUSPENSION_REPORT', '悬挂状态告警', 'BELT'], ['BELT_FALL_REPORT', '跌落告警', 'BELT'],
  ['BELT_SILENCE', '静默告警', 'BELT'], ['BELT_DURATION_REMINDER', '工作时长提醒', 'BELT'],
  ['BELT_SOS', 'SOS求助', 'BELT'], ['WATCH_UNKNOWN', '设备告警（类型待确认）', 'WATCH']
].map(([value, label, deviceType, rawType]) => ({ value, label, deviceType, rawType: rawType || null }))
export function enrichEventReports(dataset) {
  for (const event of dataset.entities.events) {
    const index = Number(event.eventId.split('-').at(-1)), type = alarmTypes[(index - 1) % alarmTypes.length]
    const suffix = { HELMET: 'helmet', BELT: 'belt', WATCH: 'watch' }[type.deviceType]
    const device = dataset.entities.devices.find(d => d.deviceId === 'device-' + (event.siteId.endsWith('1') ? 1 : 2) + '-' + index + '-' + suffix)
    Object.assign(event, { deviceId: device.deviceId, deviceCode: device.deviceCode, deviceType: device.type, deviceName: device.name, eventType: type.value, eventTypeName: type.label, title: type.label, version: 1,
      handlingStatus: index % 4 === 0 ? 'HANDLED' : 'UNHANDLED', handledBy: null, handledAt: null, handlingNote: null,
      deviceReport: { category: type.value, rawType: type.rawType, rawLevel: null, source: 'MOCK_REQUIREMENT', model: device.model, description: '模拟' + type.label + '上报，非真实设备告警', recovery: 'UNKNOWN', evidence: type.rawType ? '类型参照原安全帽源码；当前记录为模拟' : '候选类型，厂家协议待确认' } })
    if (device.type !== 'HELMET') event.person = { state: 'NOT_INTEGRATED', data: null, reasonCode: 'HISTORICAL_ATTRIBUTION_UNKNOWN' }
    if (event.handlingStatus === 'HANDLED') Object.assign(event, { handledBy: { id: 'mock-owner', name: '负责人' }, handledAt: dataset.meta.baseTime, handlingNote: '模拟处理记录：已联系现场人员检查设备。' })
    delete event.phase; delete event.ownerUserId; delete event.legacyHandled
  }
  dataset.relations.verifications = []
  dataset.entities.materials.forEach(m => { m.frozen = m.attribution === 'CONFIRMED' })
  return dataset
}
