import { deviceEventDictionary } from './device-profiles.js'
// Explicit synthetic source reports, not inferred from online status or sensor thresholds.
export function enrichEventReports(dataset) {
  for (const site of ['mock-site-1', 'mock-site-2']) {
    for (const [index, type, code, report] of [[1, 'helmet', 'HELMET_SOS', '本地设备SOS报告，事实需核验'], [2, 'belt', 'BELT_LOCK_REPORT', '本地锁扣状态报告，不证明挂点可靠或作业安全']]) {
      const event = dataset.entities.events.find(e => e.siteId === site && e.eventId.endsWith('-' + index))
      const device = dataset.entities.devices.find(d => d.siteId === site && d.deviceId === `device-${site.endsWith('1') ? 1 : 2}-${index}-${type}`)
      if (!event || !device || !deviceEventDictionary.some(c => c.code === code)) continue
      event.deviceId = device.deviceId; event.deviceCode = device.deviceCode
      event.deviceReport = { category: code, rawType: event.eventType, rawLevel: null, source: 'MOCK_REQUIREMENT', model: device.model, description: report, recovery: 'UNKNOWN', localFeedback: '当地声光/语音反馈未接入', evidence: type === 'belt' ? '安全带需求评估，非厂家协议确认' : '安全帽资料及候选事件字典，非真机报告' }
    }
  }
  return dataset
}
