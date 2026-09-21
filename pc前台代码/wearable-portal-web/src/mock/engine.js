import { alarmTypes } from './event-reports.js'
import { available, missing, identities, permissionsFor } from './seed.js'
import { workSummary, workSection } from './work-model.js'
import { buildWorkbench } from './workbench.js'
import { buildStatistics } from './statistics-service.js'
import { failure } from './errors.js'
export { failure } from './errors.js'
import { projectDataset } from './assignment-model.js'
import { queryEquipment } from './equipment-service.js'
import { queryVitals } from './vitals.js'
const denied = () => ({ state: 'FORBIDDEN', data: null, reasonCode: 'SECTION_FORBIDDEN' })
const utc = v => typeof v === 'string' && /^\d{4}-\d\d-\d\dT.*Z$/.test(v) && Number.isFinite(Date.parse(v))
const clone = v => structuredClone(v)
export function moduleOf(path) {
  if (path.includes('/mock-dispatch/')) return 'dispatch'
  if (path.includes('/mock-works/')) return 'works'
  if (path.endsWith('/vitals')) return 'vitals'
  if (path.includes('/equipment')) return 'equipment'
  if (path.includes('/people')) return 'people'
  if (path.includes('/locations')) return 'locations'
  if (path.includes('/tracks')) return 'tracks'
  if (path.includes('/fences')) return 'fences'
  if (path.includes('/materials')) return 'materials'
  if (path.includes('/video-sources')) return 'video'
  if (path.includes('/events')) return 'events'
  return 'context'
}
function validateQuery(q, allowed) {
  for (const [key, value] of Object.entries(q)) if (value !== undefined && value !== null && value !== '' && !allowed.includes(key)) throw failure(400, `暂不支持筛选：${key}`, 'UNSUPPORTED_FILTER')
  for (const [key, max] of [['pageNum', 2147483647], ['pageSize', 100]]) if (q[key] != null && (!Number.isInteger(Number(q[key])) || Number(q[key]) < 1 || Number(q[key]) > max)) throw failure(400, '分页参数无效')
  if (q.keyword != null && (typeof q.keyword !== 'string' || q.keyword.length > 100)) throw failure(400, '关键词无效')
  if ((q.from || q.to) && (!utc(q.from) || !utc(q.to) || Date.parse(q.from) >= Date.parse(q.to))) throw failure(400, '请提供有效 UTC 起止时间')
}
function filter(items, q, dateKey) {
  return items.filter(i => (!q.keyword || [i.name, i.title, i.deviceCode, i.personCode, i.personName, i.id, i.personId].filter(Boolean).join(' ').toLowerCase().includes(q.keyword.toLowerCase())) && ['deviceId', 'personId', 'type', 'status', 'phase', 'eventType', 'areaId', 'workId', 'shiftId'].every(k => !q[k] || i[k] === q[k]) && (!q.teamId || i.team?.teamId === q.teamId) && (!q.from || dateKey && i[dateKey] && Date.parse(i[dateKey]) >= Date.parse(q.from) && Date.parse(i[dateKey]) <= Date.parse(q.to)))
}
export function queryDataset(dataset, role, path, q = {}) {
  if (path === '/api/portal/v1/vitals') return queryVitals(dataset, role, q)
  if (path.startsWith('/api/portal/v1/equipment')) return queryEquipment(dataset, role, path, q)
  dataset = projectDataset(dataset)
  const identity = identities.find(i => i.id === role)
  if (!identity) throw failure(401, '本地会话已失效，请重新选择身份')
  const e = dataset.entities, r = dataset.relations, config = dataset.config
  const permissions = permissionsFor(role), module = moduleOf(path)
  const root = '/api/portal/v1'
  if (!path.startsWith(root + '/')) throw failure(404, '该接口尚未接入')
  const p = path.slice(root.length)
  if (p === '/context') {
    validateQuery(q, [])
    const sites = e.sites.filter(s => identity.sites.includes(s.siteId))
    return { sites, selectedSiteId: sites[0]?.siteId || null, teams: e.teams.filter(t => identity.sites.includes(t.siteId)), areas: e.areas.filter(t => identity.sites.includes(t.siteId)), shifts: e.shifts.filter(t => identity.sites.includes(t.siteId)), permissions,
      availability: { roster: 'AVAILABLE', areas: 'AVAILABLE', teams: 'AVAILABLE', shifts: 'AVAILABLE' }, capabilities: Object.fromEntries(['dispatch', 'works', 'people', 'equipmentHistory', 'locations', 'tracks', 'fences', 'materials', 'video', 'events'].map(k => [k, { state: 'SUPPORTED', source: 'MOCK', reasonCode: null }])) }
  }
  if (!q.siteId || typeof q.siteId !== 'string') throw failure(400, '请选择有效厂站')
  if (!identity.sites.includes(q.siteId)) throw failure(403, '当前身份无权访问该厂站')
  if (p === '/workbench') { validateQuery(q, ['siteId']); return buildWorkbench(dataset, role, q.siteId) }
  if (p === '/statistics') return buildStatistics(dataset, role, q)
  const required = { people: 'person:read', locations: 'location:read', tracks: 'track:read', fences: 'fence:read', materials: 'material:read', video: 'video:read', events: 'event:read' }[module]
  if (required && !permissions.includes('portal:' + required)) throw failure(403, '当前身份无模块权限')
  const scoped = key => e[key].filter(i => i.siteId === q.siteId)
  const find = (key, id, field = 'id') => { const item = scoped(key).find(i => i[field] === id); if (!item) throw failure(404, '对象不存在或当前身份不可见'); return item }
  // Validate object scope before applying scenario responses.
  const parts = p.split('/').filter(Boolean)
  let object
  if (parts[0] === 'people' && parts[1]) object = find('people', parts[1], 'personId')
  if (['fences', 'materials'].includes(parts[0]) && parts[1]) object = find(parts[0], parts[1])
  if (parts[0] === 'video-sources' && parts[1]) object = find('videos', parts[1], 'deviceId')
  if (parts[0] === 'events' && parts[1] && parts[1] !== 'summary') object = find('events', parts[1], 'eventId')
  if (p === '/tracks') { if (!q.deviceId) throw failure(400, '请选择设备'); find('devices', q.deviceId, 'deviceId') }
  const mode = config.module === module ? config.mode : 'normal'
  if (mode === 'failure') throw failure(503, '预置数据故障；未降级为空数据', 'SOURCE_UNAVAILABLE')
  const section = data => mode === 'forbidden' ? denied() : mode === 'not-integrated' ? missing() : available(data)
  const page = (rows, defaultSize = 20, extra = {}) => {
    const pageNum = Number(q.pageNum || 1), pageSize = Number(q.pageSize || defaultSize)
    const unavailable = mode === 'not-integrated'
    return { state: unavailable ? 'NOT_INTEGRATED' : 'AVAILABLE', reasonCode: unavailable ? 'SOURCE_NOT_INTEGRATED' : null, scope: { siteId: q.siteId }, items: unavailable ? [] : rows.slice((pageNum - 1) * pageSize, pageNum * pageSize), total: unavailable ? null : rows.length, pageNum, pageSize, ...extra }
  }
  const proof = (i, id = i.id, name = i.name) => ({ id, siteId: q.siteId, name, attribution: 'CONFIRMED', evidenceId: 'mock-proof-' + id, snapshotKind: 'HISTORICAL', sourceTime: dataset.meta.baseTime })
  if (p === '/people') {
    validateQuery(q, ['siteId', 'keyword', 'teamId', 'shiftId', 'pageNum', 'pageSize'])
    return page(filter(scoped('people'), q).map(person => mode === 'forbidden' ? { ...person, works: denied() } : person))
  }
  if (parts[0] === 'people' && object && parts.length <= 3) {
    validateQuery(q, parts[2] === 'equipment-history' ? ['siteId', 'pageNum', 'pageSize'] : ['siteId'])
    if (parts[2] === 'equipment-history') return page(r.history.filter(i => i.siteId === q.siteId && i.personId === object.personId))
    if (parts.length !== 2) throw failure(404, '该接口尚未接入')
    const person = clone(object)
    if (mode !== 'normal') person.works = section(person.works.data)
    return { person, equipment: person.equipment, works: person.works, duty: person.duty, actions: person.actions,
      events: section(scoped('events').filter(i => i.person.data?.some(p => p.id === person.personId))), location: missing(), media: missing(), historySummary: section({ count: r.history.filter(i => i.personId === person.personId).length }) }
  }
  if (p === '/devices') {
    validateQuery(q, ['siteId', 'keyword', 'pageNum', 'pageSize'])
    if (!['location:read', 'track:read', 'material:read'].some(k => permissions.includes('portal:' + k))) throw failure(403, '无设备选择权限')
    return page(filter(scoped('devices'), q))
  }
  if (p === '/locations/latest') { validateQuery(q, ['siteId', 'keyword', 'pageNum', 'pageSize']); return mode === 'forbidden' ? page([], 20, { state: 'FORBIDDEN', total: null, reasonCode: 'SECTION_FORBIDDEN' }) : page(filter(scoped('locations'), q)) }
  if (p === '/tracks') {
    validateQuery(q, ['siteId', 'deviceId', 'personId', 'from', 'to'])
    if (!q.from || !q.to) throw failure(400, '请选择起止时间')
    const track = scoped('tracks').find(t => t.deviceId === q.deviceId)
    if (q.personId && track?.personId !== q.personId) throw failure(404, '该时段人员归属未确认')
    const within = t => Date.parse(t) >= Date.parse(q.from) && Date.parse(t) <= Date.parse(q.to)
    return section({ ...(track || { id: 'mock-empty-track', siteId: q.siteId, name: '预置空轨迹', deviceId: q.deviceId, personId: null, attribution: 'UNKNOWN', complete: true }), from: q.from, to: q.to, segments: (track?.segments || []).map(s => ({ ...s, points: s.points.filter(p => within(p.sourceTime)) })).filter(s => s.points.length), gaps: (track?.gaps || []).filter(g => within(g.from) && within(g.to)) })
  }
  if (parts[0] === 'fences' || parts[0] === 'materials') {
    const kind = parts[0]
    validateQuery(q, parts.length === 2 ? ['siteId'] : kind === 'fences' ? ['siteId', 'keyword', 'status', 'pageNum', 'pageSize'] : ['siteId', 'keyword', 'type', 'deviceId', 'personId', 'from', 'to', 'pageNum', 'pageSize'])
    if (q.status && !['ENABLED', 'DISABLED', 'UNKNOWN'].includes(q.status) || q.type && !['PHOTO', 'VIDEO', 'AUDIO'].includes(q.type)) throw failure(400, '筛选值无效')
    for (const [field, key, id] of [['deviceId', 'devices', 'deviceId'], ['personId', 'people', 'personId']]) if (q[field]) find(key, q[field], id)
    if (parts.length === 1) return page(filter(scoped(kind), q, 'capturedAt'))
    if (parts.length === 2) { if (mode === 'not-integrated') throw failure(503, '该模块本地场景为未接入', 'SOURCE_NOT_INTEGRATED'); if (mode === 'forbidden') throw failure(403, '本地详情无权限'); return object }
  }
  if (parts[0] === 'video-sources') {
    validateQuery(q, parts.length === 1 ? ['siteId', 'keyword', 'areaId', 'workId', 'pageNum', 'pageSize'] : ['siteId'])
    if (q.areaId && !e.areas.some(a => a.siteId === q.siteId && a.areaId === q.areaId) || q.workId && !scoped('works').some(w => w.workId === q.workId)) throw failure(400, '区域或作业筛选不可用')
    if (parts.length === 1) {
      const rows = filter(scoped('videos'), q)
      return page(rows, 8, { filters: { areas: available(e.areas.filter(a => a.siteId === q.siteId).map(a => ({ id: a.areaId, name: a.name }))), works: available(scoped('works').map(w => ({ id: w.id, name: w.name }))) }, statistics: section({ devices: rows.length, available: 0, interrupted: rows.filter(d => d.streamState === 'INTERRUPTED').length, notStarted: rows.filter(d => d.streamState === 'NOT_STARTED').length, sourceTime: dataset.meta.baseTime }) })
    }
    if (parts.length === 2) {
      const person = object.personId ? find('people', object.personId, 'personId') : null
      return { device: object, person: person ? section([{ ...proof(person, person.personId), snapshotKind: 'CURRENT', evidenceId: object.assignmentEvidenceId, sourceTime: object.assignmentTime }]) : missing('HISTORICAL_ATTRIBUTION_UNKNOWN'), equipment: section([proof(object, object.deviceId)]), works: workSection(dataset, section(scoped('works').filter(w => w.id === object.workId).map(w => ({ ...proof(w), ...workSummary(dataset, w) })))), location: missing(), events: section(scoped('events').filter(ev => ev.deviceId === object.deviceId).map(ev => proof(ev, ev.eventId, ev.title))), materials: section(scoped('materials').filter(m => m.deviceId === object.deviceId).map(m => ({ ...proof(m), receivedAt: m.receivedAt, type: m.type }))) }
    }
  }
  if (parts[0] === 'events') {
    const listRequest = parts.length === 1 || parts[1] === 'summary'
    validateQuery(q, listRequest ? ['siteId', 'keyword', 'from', 'to', 'eventType', 'handlingStatus', 'deviceType', ...(parts.length === 1 ? ['pageNum', 'pageSize'] : [])] : ['siteId'])
    if (q.handlingStatus && !['UNHANDLED', 'HANDLED'].includes(q.handlingStatus) || q.deviceType && !['HELMET', 'BELT', 'WATCH'].includes(q.deviceType)) throw failure(400, '告警筛选值无效')
    const types = [...alarmTypes]
    for (const ev of scoped('events')) if (!types.some(t => t.value === ev.eventType)) types.push({ value: ev.eventType, label: ev.eventTypeName || ev.title, deviceType: ev.deviceType })
    if (q.eventType && !types.some(t => t.value === q.eventType)) throw failure(400, '告警类型无效')
    if (mode === 'forbidden') throw failure(403, '无告警查询权限')
    const rows = scoped('events').filter(ev => (!q.handlingStatus || ev.handlingStatus === q.handlingStatus) && (!q.deviceType || ev.deviceType === q.deviceType) && (!q.eventType || ev.eventType === q.eventType) && (!q.keyword || [ev.deviceCode, ...(ev.person?.data || []).map(p => p.name)].join(' ').toLowerCase().includes(q.keyword.toLowerCase())) && (!q.from || ev.occurredAt && Date.parse(ev.occurredAt) >= Date.parse(q.from) && Date.parse(ev.occurredAt) < Date.parse(q.to)))
    if (parts.length === 1) return page(rows, 20, { filters: { keyword: true, timeRange: true, deviceType: true, handlingStatus: true, eventTypes: available(types) } })
    if (parts[1] === 'summary' && parts.length === 2) return section({ total: rows.length, counts: Object.fromEntries(['UNHANDLED', 'HANDLED'].map(status => [status, rows.filter(ev => ev.handlingStatus === status).length])), sourceTime: dataset.meta.baseTime })
    if (parts.length === 2 && object) {
      if (mode !== 'normal') return { state: 'NOT_INTEGRATED', event: null, reasonCode: 'SOURCE_NOT_INTEGRATED' }
      const frozen = (r.materialReferences || []).filter(m => m.siteId === q.siteId && m.eventId === object.eventId).map(m => ({ ...m, id: m.materialId, attribution: 'MANUAL_MOCK', associationSource: 'MANUAL_MOCK', evidenceId: 'mock-frozen-' + m.materialId }))
      const materials = [...frozen, ...scoped('materials').filter(m => m.eventId === object.eventId && !frozen.some(f => f.id === m.id)).map(m => ({ ...m, attribution: m.associationSource === 'MANUAL_MOCK' ? 'MANUAL_MOCK' : 'CONFIRMED', evidenceId: 'mock-evidence-' + m.id }))]
      return { event: object, materials: section(materials), location: missing('HISTORICAL_ATTRIBUTION_UNKNOWN'), video: scoped('videos').some(v => v.deviceId === object.deviceId) ? section([proof(find('devices', object.deviceId, 'deviceId'), object.deviceId)]) : missing('VIDEO_NOT_SUPPORTED') }
    }
  }
  throw failure(404, '该接口尚未接入')
}
