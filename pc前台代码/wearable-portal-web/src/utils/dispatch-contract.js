import { personIdPattern } from './portal-route.js'
import { requireValue } from './portal-contract.js'
const id = v => typeof v === 'string' && personIdPattern.test(v)
const time = v => v == null || typeof v === 'string' && /Z$/.test(v) && Number.isFinite(Date.parse(v))
export function validateDispatch(data, q) {
  requireValue(data?.state === 'AVAILABLE' && data.siteId === q.siteId && Number.isSafeInteger(data.version) && data.version > 0, '协同响应范围或版本无效')
  requireValue(data.pageNum === Number(q.pageNum || 1) && data.pageSize === Number(q.pageSize || 20) && Number.isSafeInteger(data.total) && data.total >= data.items.length && data.items.length <= data.pageSize, '联系人分页无效')
  for (const key of ['items', 'suggested', 'sessions', 'groups', 'broadcasts', 'sos']) requireValue(Array.isArray(data[key]), '协同集合无效')
  for (const c of [...data.items, ...data.suggested]) requireValue(id(c.deviceId) && (c.personId == null || id(c.personId)) && Array.isArray(c.modes) && c.modes.every(m => ['VOICE','VIDEO'].includes(m)) && typeof c.reason === 'string', '联系人能力结构无效')
  requireValue(new Set(data.items.map(c => c.deviceId)).size === data.items.length, '联系人重复')
  requireValue(data.sessions.filter(s => s.state === 'ACTIVE').length <= 1, '多个活动会话')
  for (const s of data.sessions) {
    requireValue(id(s.id) && s.siteId === q.siteId && ['ACTIVE','ENDED'].includes(s.state) && ['VOICE','VIDEO'].includes(s.mode) && time(s.createdAt) && time(s.endedAt), '会话结构无效')
    requireValue(Array.isArray(s.participants) && s.participants.length > 0 && new Set(s.participants.map(p => p.deviceId)).size === s.participants.length, '会话参与者无效')
    s.participants.forEach(p => requireValue(id(p.deviceId) && ['RINGING','CONNECTED','REJECTED','TIMED_OUT','LEFT'].includes(p.state), '参与者状态无效'))
  }
  requireValue(data.active == null || data.sessions.some(s => s.id === data.active.id && s.state === 'ACTIVE'), '活动会话不匹配')
  for (const b of data.broadcasts) requireValue(id(b.id) && b.siteId === q.siteId && typeof b.text === 'string' && [...b.text].length <= 200 && b.recipients.every(r => id(r.deviceId) && ['PENDING','SUCCESS','FAILED'].includes(r.state) && time(r.time)), '广播任务无效')
  for (const g of data.groups) requireValue(id(g.id) && g.siteId === q.siteId && typeof g.name === 'string' && g.deviceIds.every(id), '协助组无效')
  for (const e of data.sos) requireValue(id(e.eventId) && e.siteId === q.siteId && /SOS$/.test(e.deviceReport?.category || ''), 'SOS范围无效')
  return data
}
