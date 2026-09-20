import { requireValue, formatTime } from './portal-contract.js'
export const vitalMetrics = { heartRate: { label: '心率', unit: 'bpm' }, oxygen: { label: '血氧', unit: '%' }, temperature: { label: '体温', unit: '℃' }, bloodPressure: { label: '血压', unit: 'mmHg' } }
export const vitalStates = { AVAILABLE: '预置观测', EMPTY: '暂无本人观测', NO_WATCH: '未领用手表', UNKNOWN: '归属或能力未知', NOT_INTEGRATED: '体征未接入', FORBIDDEN: '无权查看体征', UNAVAILABLE: '体征读取失败', LOADING: '正在读取体征' }
export function validateVitals(data, query) {
  requireValue(data && data.scope?.siteId === query.siteId && data.scope?.personId === (query.personId || null) && data.scope?.deviceId === (query.deviceId || null) && Object.hasOwn(vitalStates, data.state) && Array.isArray(data.items))
  requireValue(data.state === 'AVAILABLE' || data.items.length === 0, '不可用分区不能包含体征')
  const keys = new Set()
  for (const item of data.items) {
    const spec = vitalMetrics[item.metric]
    requireValue(spec && !keys.has(item.metric) && item.unit === spec.unit)
    keys.add(item.metric)
    requireValue(typeof item.observationId === 'string' && typeof item.deviceId === 'string' && typeof item.personId === 'string' && item.siteId === query.siteId && !!item.evidenceId && item.sourceKind === 'MOCK_REQUIREMENT')
    requireValue(!query.personId || item.personId === query.personId, '体征人员归属不一致')
    requireValue(!query.deviceId || item.deviceId === query.deviceId, '体征来源设备不一致')
    requireValue(item.value === null || (item.metric === 'bloodPressure' ? Array.isArray(item.value) && item.value.length === 2 && item.value.every(Number.isFinite) : Number.isFinite(item.value)))
    requireValue(['FRESH', 'STALE', 'UNKNOWN'].includes(item.freshness))
    for (const t of [item.sourceTime, item.receivedAt]) requireValue(t === null || formatTime(t) !== '—')
    requireValue(item.freshness === 'UNKNOWN' || item.sourceTime !== null)
  }
  return data
}
export function vitalValue(item) { return item?.value == null ? '—' : Array.isArray(item.value) ? item.value.join(' / ') : String(item.value) }
