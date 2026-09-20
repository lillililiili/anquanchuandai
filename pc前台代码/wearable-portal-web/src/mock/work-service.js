import { identities, available } from './seed.js'
import { projectDataset } from './assignment-model.js'
import { workSummary } from './work-model.js'
import { failure } from './errors.js'
import { monitorLabels, sourceLabels, validUtc } from '../utils/work-route.js'
const copy = x => structuredClone(x)
function scope(d, role, siteId, write = false) {
  const i = identities.find(i => i.id === role)
  if (!i) throw failure(401, '本地会话失效')
  if (!i.sites.includes(siteId) || write && role !== 'owner') throw failure(403, '厂站不可见或当前身份无监护操作权限')
}
function state(d, module) {
  if (d.config.module !== module || d.config.mode === 'normal') return 'AVAILABLE'
  if (d.config.mode === 'failure') throw failure(503, '预置数据故障，请恢复场景后重试')
  return d.config.mode === 'forbidden' ? 'FORBIDDEN' : 'NOT_INTEGRATED'
}
function section(d, module, fn) {
  try { const s = state(d, module); return s === 'AVAILABLE' ? available(fn()) : { state: s, data: null, reasonCode: 'SOURCE_' + s } }
  catch (e) { return { state: 'ERROR', data: null, message: e.message } }
}
function object(d, q) {
  const w = d.entities.works.find(w => w.workId === q.workId && w.siteId === q.siteId)
  if (!w) throw failure(404, '作业不存在或不可见')
  return w
}
export function queryWorks(d, role, q = {}) {
  scope(d, role, q.siteId)
  const allowed = ['siteId', 'workId', 'keyword', 'state', 'sourceStatus', 'areaId', 'from', 'to', 'pageNum', 'pageSize']
  for (const [k, v] of Object.entries(q)) if (v != null && v !== '' && !allowed.includes(k)) throw failure(400, '不支持的作业筛选：' + k)
  const pageNum = Number(q.pageNum || 1), pageSize = Number(q.pageSize || 20)
  if (!Number.isSafeInteger(pageNum) || pageNum < 1 || pageNum > 2147483647 || !Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > 100 || q.keyword && (typeof q.keyword !== 'string' || q.keyword.length > 100) || q.state && !Object.hasOwn(monitorLabels, q.state) || q.sourceStatus && !Object.hasOwn(sourceLabels, q.sourceStatus)) throw failure(400, '筛选或分页参数无效')
  if ((q.from || q.to) && (!validUtc(q.from) || !validUtc(q.to) || Date.parse(q.from) >= Date.parse(q.to))) throw failure(400, '请填写完整 UTC 时间范围')
  if (q.areaId && !d.entities.areas.some(a => a.siteId === q.siteId && a.areaId === q.areaId)) throw failure(400, '区域不在当前厂站')
  const sourceState = state(d, 'works')
  if (sourceState !== 'AVAILABLE') return { state: sourceState, items: [], total: null, pageNum, pageSize, scope: { siteId: q.siteId }, reasonCode: 'SOURCE_' + sourceState }
  if (q.workId) {
    const w = object(d, q), m = d.relations.monitoring.find(m => m.workId === w.workId), projected = projectDataset(d)
    const people = projected.entities.people.filter(p => p.siteId === q.siteId && m.personIds.includes(p.personId))
    return { state: 'AVAILABLE', work: workSummary(d, w), monitoring: copy(m),
      people: section(d, 'people', () => people),
      events: section(d, 'events', () => d.entities.events.filter(e => e.siteId === q.siteId && e.workId === w.workId)),
      materials: section(d, 'materials', () => d.entities.materials.filter(e => e.siteId === q.siteId && e.workId === w.workId && ['CONFIRMED', 'MANUAL_MOCK'].includes(e.workAttribution))),
      videos: section(d, 'video', () => projected.entities.videos.filter(v => v.siteId === q.siteId && v.workId === w.workId)),
      locations: section(d, 'locations', () => d.entities.locations.filter(l => l.siteId === q.siteId && people.some(p => p.personId === l.personId))) }
  }
  const rows = d.entities.works.filter(w => w.siteId === q.siteId).map(w => workSummary(d, w)).filter(w => (!q.keyword || [w.name, w.sourceWorkNo, w.workId].join(' ').toLowerCase().includes(q.keyword.toLowerCase())) && (!q.areaId || w.area.areaId === q.areaId) && (!q.state || w.monitorState === q.state) && (!q.sourceStatus || w.sourceStatus === q.sourceStatus) && (!q.from || Date.parse(w.startsAt) < Date.parse(q.to) && Date.parse(w.endsAt) > Date.parse(q.from)))
  return { state: 'AVAILABLE', items: rows.slice((pageNum - 1) * pageSize, pageNum * pageSize), total: rows.length, pageNum, pageSize, scope: { siteId: q.siteId }, areas: d.entities.areas.filter(a => a.siteId === q.siteId), counts: Object.fromEntries(Object.keys(monitorLabels).map(s => [s, rows.filter(w => w.monitorState === s).length])) }
}
export function workEditor(d, role, q) {
  scope(d, role, q.siteId, true); const w = object(d, q)
  if (state(d, 'works') !== 'AVAILABLE' || state(d, 'people') !== 'AVAILABLE') throw failure(403, '作业或人员来源未开放')
  return { monitoring: copy(d.relations.monitoring.find(m => m.workId === w.workId)), people: d.entities.people.filter(p => p.siteId === q.siteId).map(p => ({ personId: p.personId, name: p.name })) }
}
export function workCommand(d, role, action, q) {
  scope(d, role, q.siteId, true); const w = object(d, q), m = d.relations.monitoring.find(m => m.workId === w.workId)
  if (state(d, 'works') !== 'AVAILABLE') throw failure(403, '作业来源未开放')
  if (!/^[\w-]{1,128}$/.test(q.operationId || '')) throw failure(400, '操作标识无效')
  const fingerprint = JSON.stringify({ action, ...q }), old = d.relations.monitorOperations.find(o => o.id === q.operationId)
  if (old) { if (old.role !== role || old.fingerprint !== fingerprint) throw failure(409, '操作标识已用于其他输入'); return { ...copy(old.result), replayed: true } }
  if (q.expectedVersion !== m.version || m.state === 'ENDED') throw failure(409, '版本已变化或监护已结束，请重新读取')
  const validPerson = id => d.entities.people.some(p => p.personId === id && p.siteId === q.siteId)
  let title
  if (action === 'arrange') {
    if (m.state !== 'PENDING') throw failure(409, '仅待开始阶段可调整人员')
    if (state(d, 'people') !== 'AVAILABLE') throw failure(403, '人员来源未开放')
    if (!Array.isArray(q.personIds) || q.personIds.length > 100 || new Set(q.personIds).size !== q.personIds.length || q.personIds.some(id => !validPerson(id)) || q.supervisorId && !validPerson(q.supervisorId)) throw failure(400, '请选择同厂站有效人员及监护人')
    m.personIds = [...q.personIds]; m.supervisorId = q.supervisorId || null; title = '本地安排人员与监护人'
  } else if (action === 'check') {
    if (!['PENDING', 'PAUSED'].includes(m.state) || !m.personIds.includes(q.personId) || !['ACKNOWLEDGED', 'NEEDS_REVIEW'].includes(q.result) || typeof q.note !== 'string' || !q.note.trim() || q.note.length > 500) throw failure(400, '仅待开始或暂停时记录参与人员检查，需说明；不是工作许可')
    if (state(d, 'people') !== 'AVAILABLE') throw failure(403, '人员来源未开放')
    m.checks.push({ personId: q.personId, result: q.result, note: q.note, actorId: 'mock-' + role, recordedAt: new Date().toISOString() }); title = '记录人工检查说明（非安全许可）'
  } else {
    const transitions = { start: ['PENDING', 'ACTIVE'], pause: ['ACTIVE', 'PAUSED'], resume: ['PAUSED', 'ACTIVE'] }
    if (action === 'finish') {
      if (!['ACTIVE', 'PAUSED'].includes(m.state) || q.confirmFinish !== true) throw failure(409, '请确认结束监护；仅监护中或暂停可结束')
      if (state(d, 'events') !== 'AVAILABLE') throw failure(403, '事件状态无法读取，无法确认结束影响')
      const count = workSummary(d, w).openEventCount
      if (q.expectedOpenCount !== count) throw failure(409, '未完成事件数量已变化，请重新读取后确认')
      m.state = 'ENDED'; title = `结束本地监护，保留${count}件未完成事件`
    } else {
      const t = transitions[action]
      if (!t || m.state !== t[0]) throw failure(409, '当前阶段不能执行该操作')
      if (['start', 'resume'].includes(action) && (state(d, 'people') !== 'AVAILABLE' || !validPerson(m.supervisorId) || !m.personIds.length || m.personIds.some(id => !validPerson(id)))) throw failure(400, '需安排有效监护人和至少一名参与人员；不等于安全许可')
      m.state = t[1]; title = { start: '开始本地监护', pause: '暂停本地监护', resume: '恢复本地监护' }[action]
    }
  }
  m.version++; m.timeline.unshift({ id: q.operationId, actorId: 'mock-' + role, title, time: new Date().toISOString() })
  const result = { version: m.version, changedEntities: ['works', 'people', 'events', 'workbench'] }
  d.relations.monitorOperations.push({ id: q.operationId, role, fingerprint, result: copy(result) })
  return result
}
