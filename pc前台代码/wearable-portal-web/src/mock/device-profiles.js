import { capabilityNames } from '../utils/device-profile.js'

// Declarations are document evidence, not protocol or instance capability proof.
const models = ['RLD1', 'RLV10', 'RL10pro', 'RL10pro低配版', '型号待确认']
export function enrichDeviceProfiles(dataset) {
  for (const d of dataset.entities.devices) {
    const index = Number(d.deviceId.split('-')[2]), helmet = d.type === 'HELMET'
    const model = helmet ? models[(index - 1) % models.length] : d.type === 'BELT' ? '安全带需求原型 Ver1.0.0' : '手表型号待确认'
    const base = helmet ? `智能安全帽1.pdf 第${(index - 1) % 5 + 1}页；型号由预置配置指定，非现场确认` : d.type === 'BELT' ? '安全带需求评估 Ver1.0.0 第3页；需求本地' : '用户界面原型需求；无独立手表规格'
    const capabilities = Object.fromEntries(Object.keys(capabilityNames).map(key => {
      const media = ['video', 'capture', 'record'].includes(key)
      let declaration = 'NOT_DECLARED', installation = 'UNKNOWN'
      if (helmet && model !== '型号待确认') {
        declaration = media ? ['RLD1', 'RLV10'].includes(model) && key !== 'record' ? 'DECLARED' : 'NOT_DECLARED' : ['location', 'talk'].includes(key) ? key === 'talk' && model.includes('低配') ? 'NOT_DECLARED' : 'DECLARED' : model === 'RLD1' || model === 'RLV10' && ['proximity', 'vitals'].includes(key) ? 'OPTIONAL' : 'NOT_DECLARED'
        installation = declaration === 'DECLARED' ? 'PRESENT' : declaration === 'OPTIONAL' ? 'ABSENT' : 'UNKNOWN'
        if (media && model === 'RL10pro') installation = 'ABSENT' // Explicit synthetic configuration, not inferred from omission.
        if (key === 'record' && ['RLD1', 'RLV10'].includes(model)) installation = 'PRESENT' // Synthetic prototype option; DOCX model correspondence remains unknown.
      }
      if (d.type === 'BELT' && ['location', 'talk'].includes(key)) declaration = 'DECLARED'
      if (d.type === 'WATCH' && key === 'vitals') installation = index === 7 ? 'UNKNOWN' : 'PRESENT'
      const evidence = key === 'record' && helmet ? '安全帽参数.docx录像条目未指定型号；当前装配仅为合成配置' : key === 'vitals' && helmet ? '智能安全帽1.pdf 第9页；DOCX选配蓝牙手环条目并非同一确认配置' : key === 'proximity' && helmet ? '智能安全帽1.pdf 第7页；型号/选配范围需确认' : base
      return [key, { declaration, installation, integration: installation === 'PRESENT' ? 'MOCK_READY' : 'NOT_INTEGRATED', verification: 'UNVERIFIED', evidence: model === '型号待确认' ? '型号未知，不能映射资料' : evidence }]
    }))
    if (helmet && model === 'RL10pro') { capabilities.proximity.declaration = 'CONFLICTING'; capabilities.proximity.evidence = '智能安全帽1.pdf 第3页与第7页型号/选配范围需核实' }
    const time = index % 6 === 0 ? null : new Date(Date.parse(dataset.meta.baseTime) - (index % 5 === 0 ? 86400000 : 300000)).toISOString()
    const observation = (label, value) => ({ label, value: index % 6 === 0 ? null : value, sourceTime: time, freshness: !time ? 'UNKNOWN' : index % 5 === 0 ? 'STALE' : 'FRESH', sourceKind: 'MOCK_REQUIREMENT' })
    const observations = helmet ? [observation('穿戴报告', '预置穿戴报告'), observation('设备CPU温度（非体温）', '38 ℃')] : d.type === 'BELT' ? [observation('锁扣闭合报告', '预置闭合报告'), observation('单钩悬挂报告', '预置单钩报告'), observation('姿态报告', '待核实'), observation('静默/跌落报告', '无本地报告'), observation('设备工作时长（非人员工时）', '2 小时')] : []
    d.model = model
    d.profile = { model, firmware: null, sourceKind: 'MOCK_REQUIREMENT', privacy: helmet ? index === 6 ? 'ON' : 'OFF' : 'UNKNOWN', capabilities, observations }
    for (const key of ['video', 'talk', 'location', 'capture', 'record']) {
      const c = capabilities[key]
      d.capabilities[key] = { state: c.installation === 'PRESENT' ? 'SUPPORTED' : c.installation === 'ABSENT' ? 'UNSUPPORTED' : 'UNKNOWN', verification: 'UNVERIFIED', reasonCode: 'PROTOCOL_PENDING' }
    }
  }
  return dataset
}

// Candidate classifications only; do not seed new events or derive alarms from readings.
export const deviceEventDictionary = [
  ...['OFF_HAT', 'SILENCE', 'IMPACT_REPORT', 'SOS', 'FENCE', 'OPTION_REPORT'].map(code => ({ code: 'HELMET_' + code, type: 'HELMET' })),
  ...['LOW_ANCHOR_REPORT', 'SUSPENSION_REPORT', 'FALL_REPORT', 'SILENCE', 'LOCK_REPORT', 'DURATION_REMINDER', 'SOS'].map(code => ({ code: 'BELT_' + code, type: 'BELT' }))
].map(item => ({ ...item, sourceKind: 'MOCK_REQUIREMENT', confirmedProtocol: false, generatesAlarm: false }))
