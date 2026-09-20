import { idString, requireValue } from './portal-contract.js'
export function adaptHatPage(response) {
  const p = response?.data
  requireValue(response?.code === 200 && p && Array.isArray(p.records) && Number.isInteger(p.total) && p.total >= 0 && Number.isInteger(p.current) && p.current > 0 && Number.isInteger(p.size) && p.size > 0)
  return { items: p.records.map(r => ({ ...r, id: idString(r.id) })), total: p.total, pageNum: p.current, pageSize: p.size }
}
export function adaptUserTable(response) {
  requireValue(response?.code === 200 && Array.isArray(response.rows) && Number.isInteger(response.total) && response.total >= 0)
  return { items: response.rows.map(r => ({ ...r, userId: idString(r.userId) })), total: response.total }
}
export function communicationFromLegacy(status, sourceKind = 'LEGACY_SNAPSHOT', observedAt = null) {
  const state = sourceKind === 'PLATFORM_QUERY' ? ({ '1': 'ONLINE', '0': 'OFFLINE' }[String(status)] || 'UNKNOWN') : 'UNKNOWN'
  return { state, sourceKind, sourceTime: null, receivedAt: null, observedAt, freshness: 'UNKNOWN', reasonCode: 'SOURCE_TIME_MISSING' }
}

