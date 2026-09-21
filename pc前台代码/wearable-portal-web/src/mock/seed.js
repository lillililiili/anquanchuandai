import { seedMonitoring } from './work-model.js'
import { sampleWorkArea } from './spatial-layout.js'
import { normalizeAssignments } from './assignment-model.js'
import { enrichDeviceProfiles } from './device-profiles.js'
import { seedVitals } from './vitals.js'
import { enrichEventReports } from './event-reports.js'
// Pure, deterministic fixtures. Never imported by the HTTP/production provider.
export const SCHEMA_VERSION = 1
export const SEED_VERSION = 2
export const available = data => ({ state: 'AVAILABLE', data })
export const missing = (reasonCode = 'SOURCE_NOT_INTEGRATED') => ({ state: 'NOT_INTEGRATED', data: null, reasonCode })
export const defaultScenario = () => ({ module: 'people', mode: 'normal', slowNext: false })
export const identities = [
  { id: 'owner', name: '负责人', sites: ['mock-site-1', 'mock-site-2', 'mock-site-empty'] },
  { id: 'verifier', name: '核验员', sites: ['mock-site-1'] },
  { id: 'reader', name: '只读查看员', sites: ['mock-site-1', 'mock-site-empty'] }
]
export function permissionsFor(role) {
  const result = ['person:read', 'person:history', 'location:read', 'track:read', 'fence:read', 'material:read', 'video:read', 'event:read']
  if (role !== 'reader') result.push('event:handle')
  return result.map(p => 'portal:' + p)
}
export function createSeed(baseTime = new Date().toISOString()) {
  const at = minutes => new Date(Date.parse(baseTime) + minutes * 60000).toISOString()
  const entities = { sites: [], teams: [], shifts: [], areas: [], people: [], devices: [], works: [], locations: [], tracks: [], fences: [], materials: [], videos: [], events: [] }
  const relations = { history: [], timeline: [], verifications: [] }
  for (let s = 1; s <= 2; s++) {
    const siteId = `mock-site-${s}`
    entities.sites.push({ siteId, name: `${s === 1 ? '一' : '二'}号厂站`, timeZone: 'Asia/Shanghai' })
    for (let n = 1; n <= 2; n++) {
      entities.teams.push({ siteId, teamId: `team-${s}-${n}`, name: `班组${n}` })
      entities.shifts.push({ siteId, shiftId: `shift-${s}-${n}`, name: `班次${n}` })
      entities.areas.push({ siteId, areaId: `area-${s}-${n}`, name: `区域${n}` })
    }
    for (let i = 1; i <= 25; i++) {
      const personId = String(9007199254740993000n + BigInt(s * 100 + i))
      const area = entities.areas.find(a => a.areaId === `area-${s}-${i % 2 + 1}`)
      const team = entities.teams.find(t => t.teamId === `team-${s}-${i % 2 + 1}`)
      const shiftId = `shift-${s}-${i % 2 + 1}`
      const work = { id: `work-${s}-${i}`, workId: `work-${s}-${i}`, siteId, name: `巡检作业${i}`, sourceWorkNo: `WORK-${s}-${i}`, area, source: '前端预置数据', startsAt: at(-180), endsAt: at(180), personRole: '巡检员', supervisor: { name: '监护员' }, responsible: { name: '负责人' } }
      entities.works.push(work)
      const equipment = {}
      for (const [k, type] of Object.entries({ helmet: 'HELMET', belt: 'BELT', watch: 'WATCH' })) {
        const deviceId = `device-${s}-${i}-${k}`
        const known = k === 'helmet', stale = i % 5 === 0
        const device = { id: deviceId, deviceId, siteId, type, name: `${{ helmet: '安全帽', belt: '安全带', watch: '手表' }[k]}${i}`, deviceCode: `EQ-${s}-${i}-${k}`, areaId: area.areaId, workId: work.workId,
          communication: { state: known ? (i % 4 === 0 ? 'OFFLINE' : 'ONLINE') : 'UNKNOWN', freshness: known ? (stale ? 'STALE' : 'FRESH') : 'UNKNOWN', sourceTime: known ? at(stale ? -1440 : -5) : null, receivedAt: known ? at(-2) : null, sourceKind: 'MOCK' },
          battery: { value: known ? 70 - i : null, freshness: known ? 'FRESH' : 'UNKNOWN', sourceTime: known ? at(-5) : null },
          capabilities: Object.fromEntries(['video', 'talk', 'location', 'capture', 'record'].map(c => [c, { state: known ? 'SUPPORTED' : 'UNKNOWN', verification: 'UNVERIFIED', reasonCode: known ? 'MODULE_NOT_ENABLED' : 'PROTOCOL_PENDING' }])) }
        entities.devices.push(device)
        const state = i === 2 ? 'UNASSIGNED' : i === 3 ? 'UNKNOWN' : i === 4 && known ? 'CONFLICT' : 'ASSIGNED'
        device.assignmentEvidence = state === 'UNKNOWN' ? 'UNKNOWN' : 'KNOWN'
        equipment[k] = { type, assignmentState: state, devices: state === 'ASSIGNED' || state === 'CONFLICT' ? [device] : [] }
        if (state === 'CONFLICT') {
          const extra = { ...structuredClone(device), id: deviceId + '-conflict', deviceId: deviceId + '-conflict', deviceCode: device.deviceCode + '-C' }
          entities.devices.push(extra); equipment[k].devices.push(extra)
        }
      }
      const person = { personId, siteId, name: `人员${s}-${String(i).padStart(2, '0')}`, personCode: `PERSON-${s}-${i}`, phoneMasked: null, team, area, shiftId, dataUpdatedAt: at(-5), equipment: available(equipment), works: available([work]), duty: available({ state: 'ON_DUTY', shiftId }), actions: Object.fromEntries(['viewHistory', 'viewVideo', 'talk', 'viewWork', 'viewEvent'].map(k => [k, { allowed: k === 'viewHistory', reasonCode: k === 'viewHistory' ? null : 'MODULE_NOT_ENABLED' }])) }
      entities.people.push(person)
      const helmet = entities.devices.find(d => d.deviceId === `device-${s}-${i}-helmet`)
      const confirmed = i % 3 !== 0 && equipment.helmet.assignmentState === 'ASSIGNED'
      const areaGeometry = sampleWorkArea(s, i)
      const position = { longitude: areaGeometry.longitude, latitude: areaGeometry.latitude, coordinateSystem: i === 3 ? 'UNKNOWN' : 'WGS84', quality: 'VALID', freshness: i === 5 ? 'STALE' : 'FRESH', sourceTime: at(i === 5 ? -1440 : -5), receivedAt: at(-2), source: '预置坐标（非真实现场）' }
      entities.locations.push({ id: `location-${s}-${i}`, siteId, name: helmet.name, deviceId: helmet.deviceId, deviceCode: helmet.deviceCode, personId: confirmed ? personId : null, personName: confirmed ? person.name : null, attribution: confirmed ? 'CONFIRMED' : 'UNKNOWN', communication: helmet.communication.state, position })
      const points = [0, 1, 2, 3, 4, 5].map(n => ({ ...position, coordinateSystem: 'WGS84', longitude: position.longitude + n * 0.0002, sourceTime: at(-60 + n * 5), freshness: 'FRESH' }))
      entities.tracks.push({ id: `track-${s}-${i}`, siteId, name: `预置轨迹${i}`, deviceId: helmet.deviceId, personId: confirmed ? personId : null, attribution: confirmed ? 'CONFIRMED' : 'UNKNOWN', complete: true, segments: [{ segmentId: `segment-${s}-${i}-a`, continuity: 'CONFIRMED', points: points.slice(0, 3) }, { segmentId: `segment-${s}-${i}-b`, continuity: 'UNKNOWN', points: points.slice(3) }], gaps: [{ from: at(-49), to: at(-46), reason: '本地采样缺口' }] })
      entities.fences.push({ id: `fence-${s}-${i}`, siteId, name: `围栏${i}`, status: i % 3 === 0 ? 'DISABLED' : 'ENABLED', coordinateSystem: 'WGS84', ring: areaGeometry.ring, rule: '本地区域，仅供查看；不代表真实违规规则', version: 1, sourceTime: at(-120), effectiveAt: null })
      const eventId = `event-${s}-${i}`
      const proof = { id: personId, siteId, name: person.name, attribution: 'CONFIRMED', evidenceId: `proof-${s}-${i}`, snapshotKind: 'HISTORICAL', sourceTime: at(-90) }
      entities.materials.push({ id: `material-${s}-${i}`, siteId, name: `资料${i}`, type: ['PHOTO', 'VIDEO', 'AUDIO'][(i - 1) % 3], deviceId: helmet.deviceId, deviceCode: helmet.deviceCode, capturedAt: i % 3 === 0 ? null : at(-90), receivedAt: at(-80), personId: confirmed ? personId : null, personName: confirmed ? person.name : null, attribution: confirmed ? 'CONFIRMED' : 'UNKNOWN', workId: work.workId, workName: work.name, workAttribution: 'CONFIRMED', eventId, eventAttribution: 'CONFIRMED', version: 1, digest: `LOCAL-DIGEST-${s}-${i}` })
      entities.videos.push({ deviceId: helmet.deviceId, siteId, name: helmet.name, deviceCode: helmet.deviceCode, type: 'HELMET', areaId: area.areaId, workId: work.workId, communication: helmet.communication, video: { state: 'SUPPORTED', verification: 'UNVERIFIED' }, streamState: i % 4 === 0 ? 'INTERRUPTED' : 'NOT_STARTED', freshness: 'UNKNOWN', sourceTime: null, unavailableReason: '前端本地视频元数据；本地合成播放需显式启动，真实媒体未接入', personId: confirmed ? personId : null })
      entities.events.push({ eventId, siteId, title: `事件${i}`, sourceSystem: 'FRONTEND_MOCK', sourceEventId: `EVT-${s}-${i}`, eventType: i % 2 ? 'MOCK_INSPECTION' : 'UNKNOWN', eventTypeName: i % 2 ? '本地人工巡检发现' : '本地未知类型', deviceId: helmet.deviceId, deviceCode: helmet.deviceCode, occurredAt: i % 7 === 0 ? null : at(-90), receivedAt: at(-80), sourceUpdatedAt: at(-60), freshness: i % 5 === 0 ? 'STALE' : 'FRESH', person: confirmed ? available([proof]) : missing('HISTORICAL_ATTRIBUTION_UNKNOWN'), workId: work.workId })
      for (let n = 0; n < (i === 1 ? 25 : 2); n++) {
        relations.history.push({ recordId: `history-${s}-${i}-${n}`, siteId, personId, deviceId: helmet.deviceId, deviceCode: helmet.deviceCode, action: n % 2 ? 'RETURN' : 'ISSUE', evidenceQuality: 'CONFIRMED', operator: { displayName: '经办人' }, occurredAt: at(-3000 - n * 60), startedAt: at(-3060 - n * 60), endedAt: at(-3000 - n * 60), state: 'CLOSED' })
        relations.timeline.push({ id: `timeline-${s}-${i}-${n}`, siteId, eventId, title: `预置来源记录 ${n + 1}`, kind: 'MOCK_FACT', sequence: n, sourceTime: n === 2 ? null : at(-90 + n), description: '本地事实记录，不代表真实处置或外部回传。' })
      }
    }
  }
  entities.sites.push({ siteId: 'mock-site-empty', name: '空厂站', timeZone: 'Asia/Shanghai' })
  return seedMonitoring(enrichEventReports(seedVitals(enrichDeviceProfiles(normalizeAssignments({ meta: { schemaVersion: SCHEMA_VERSION, seedVersion: SEED_VERSION, baseTime }, entities, relations, config: defaultScenario() })))))
}
