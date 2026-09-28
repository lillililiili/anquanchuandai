const SITE = { 'site-1': 'S1', 'site-2': 'S2' }
const TYPE = { HELMET: 'H', BELT: 'B', WATCH: 'W' }
const KNOWN_PEOPLE = {
  'person-1-0': 'P1',
  'person-1-1': 'P2',
  'person-1-2': 'P3',
  'person-1-3': 'P4',
  'person-1-4': 'P5',
  'person-1-5': 'P6',
  'person-1-6': 'P7',
  'person-1-7': 'P8',
}
const SNAPSHOT = '/api/guardian/v1/snapshot'

export function portalEnabled() {
  return typeof localStorage !== 'undefined' && typeof fetch === 'function'
}

export function projectPortal(adminState, snapshot) {
  if (!snapshot || snapshot.version !== 1 || !Array.isArray(snapshot.people) || !Array.isArray(snapshot.devices) || !Array.isArray(snapshot.bindings)) {
    throw Object.assign(new Error('监护数据不可用'), { code: 503 })
  }
  for (const person of adminState.people || []) ensurePerson(adminState, snapshot, person)
  for (const device of adminState.devices || []) syncDevice(adminState, snapshot, device)
  applyTelemetry(adminState, snapshot)
  return snapshot
}

export function applyTelemetry(adminState, snapshot) {
  const byId = new Map((snapshot.devices || []).map(device => [device.id, device]))
  for (const device of adminState.devices || []) {
    const remote = byId.get(device.portalDeviceId || device.code || device.id)
    if (!remote || !Object.hasOwn(remote, 'online')) continue
    device.communication = remote.online ? 'ONLINE' : 'OFFLINE'
    device.battery = remote.battery == null ? null : Number(remote.battery)
    device.freshness = 'CURRENT'
    device.sourceTime = remote.updated || null
  }
}

export async function readTelemetry(adminState, fetchImpl = fetch) {
  const snapshot = await readSnapshot(fetchImpl)
  if (!snapshot) return false
  applyTelemetry(adminState, snapshot)
  return true
}

export async function publishPortal(adminState, fetchImpl = fetch) {
  const snapshot = await readSnapshot(fetchImpl)
  if (!snapshot) throw Object.assign(new Error('后端未连接，修改未保存'), { code: 503 })
  projectPortal(adminState, snapshot)
  const response = await fetchImpl(SNAPSHOT, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify(snapshot),
  })
  if (!response.ok) {
    let message = '保存失败'
    try { message = (await response.json()).message || message } catch { /* 保留默认文案 */ }
    throw Object.assign(new Error(message), { code: response.status })
  }
}

async function readSnapshot(fetchImpl) {
  try {
    const response = await fetchImpl(SNAPSHOT)
    if (!response.ok) return null
    const body = await response.json()
    if (!body?.state || !/[\u4e00-\u9fff]/.test(body.state.stations?.[0]?.name || '')) return null
    return body.state
  } catch {
    return null
  }
}

function ensurePerson(adminState, snapshot, person) {
  const id = portalPersonId(snapshot, person)
  person.portalId = id
  const station = SITE[person.siteId] || 'S1'
  const existing = snapshot.people.find(item => item.id === id)
  const next = {
    name: person.name,
    team: organizationName(adminState, person),
    station,
    area: areaName(adminState, person.areaId),
    active: person.enabled !== false,
  }
  if (!existing) {
    snapshot.people.push({ id, phone: '', position: [50, 50], locationValid: true, updated: stamp(new Date()), ...next })
    return
  }
  Object.assign(existing, next)
}

function syncDevice(adminState, snapshot, device) {
  const id = device.portalDeviceId || device.code || device.id
  device.portalDeviceId = id
  const type = TYPE[device.type] || 'H'
  const station = SITE[device.siteId] || 'S1'
  const active = device.lifecycle !== 'DISABLED' && device.lifecycle !== 'SCRAPPED'
  let remote = snapshot.devices.find(item => item.id === id)
  if (!remote) {
    remote = { id, type, station, active, online: false, battery: null, video: type === 'H' ? 'available' : null, updated: stamp(new Date()) }
    snapshot.devices.push(remote)
  } else {
    remote.type = type
    remote.station = station
    remote.active = active
  }
  const assignment = (adminState.assignments || []).find(item => item.active && item.deviceId === device.id)
  const person = assignment && (adminState.people || []).find(item => item.id === assignment.personId && item.enabled !== false)
  const hold = active && device.lifecycle === 'IN_USE' && person ? portalPersonId(snapshot, person) : null
  if (hold) person.portalId = hold
  reconcileBinding(snapshot, id, hold, assignment?.startedAt)
}

function reconcileBinding(snapshot, deviceId, personId, startedAt) {
  let kept = null
  for (const binding of snapshot.bindings) {
    if (binding.deviceId !== deviceId || binding.end) continue
    if (personId && binding.personId === personId && !kept) kept = binding
    else binding.end = stamp(new Date())
  }
  if (!personId || kept) return
  snapshot.seq = (snapshot.seq || 100) + 1
  snapshot.bindings.push({
    id: 'BIND' + snapshot.seq,
    deviceId,
    personId,
    start: stamp(startedAt || new Date()),
    end: null,
    operator: '管理中心',
  })
}

function portalPersonId(snapshot, person) {
  if (person.portalId && snapshot.people.some(item => item.id === person.portalId)) return person.portalId
  if (KNOWN_PEOPLE[person.id]) return KNOWN_PEOPLE[person.id]
  const used = new Set(snapshot.people.map(item => item.id))
  let n = snapshot.people.reduce((max, item) => {
    const match = /^P(\d+)$/.exec(item.id)
    return match ? Math.max(max, Number(match[1])) : max
  }, 0) + 1
  while (used.has('P' + n)) n += 1
  return 'P' + n
}

function organizationName(adminState, person) {
  return (adminState.organizations || []).find(item => item.id === person.organizationId)?.name || person.team || ''
}

function areaName(adminState, areaId) {
  return (adminState.areas || []).find(item => item.id === areaId)?.name || ''
}

function stamp(value) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return stamp(new Date())
  const parts = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' }).formatToParts(date)
  const p = Object.fromEntries(parts.map(part => [part.type, part.value]))
  return `${p.year}-${p.month}-${p.day} ${p.hour}:${p.minute}:${p.second}`
}
