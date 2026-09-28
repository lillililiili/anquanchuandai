import { extendSeed } from './a1seed'
import { extendDevices } from './deviceData'
import { extendIntegrations } from './integrationData'
export const TOKEN_KEY = 'Wearable-Admin-Mock-Token'
export const SESSION_VERSION_KEY = 'Wearable-Admin-Mock-Session-Version'
export const BASE_TIME = '2026-09-15T00:00:00Z'
export const TYPE_NAMES = { HELMET: '安全帽', BELT: '安全带', WATCH: '手表' }
export const IDENTITIES = [
  { id: 'demo-system', name: '系统管理员', description: '全部预置厂站 · 管理权限', roleIds: ['system'] },
  { id: 'demo-site', name: '厂站管理员', description: '一号站 · 人员、资产、协助组', roleIds: ['site'] },
  { id: 'demo-asset', name: '资产管理员', description: '一号站 · 资产与运维', roleIds: ['asset'] },
  { id: 'demo-audit', name: '审计员', description: '一号站与空厂站 · 只读', roleIds: ['audit'] },
  { id: 'demo-duty', name: '值守员', description: '临江示范电厂 · 前台值守', roleIds: ['duty'] }
]

export function createSeed() {
  const sites = [
    { id: 'site-1', name: '临江示范电厂', code: 'LJ', timezone: 'Asia/Shanghai' },
    { id: 'site-2', name: '北江示范电厂', code: 'BJ', timezone: 'Asia/Shanghai' }
  ]
  const read = ['overview:read', 'assets:read', 'people:read', 'access:read', 'audit:read']
  const roles = [
    { id: 'system', grants: [{ operations: ['*'], siteIds: sites.map(s => s.id), areaIds: '*' }] },
    { id: 'site', grants: [{ operations: [...read, 'people:write', 'assets:write'], siteIds: ['site-1'], areaIds: '*' }] },
    { id: 'asset', grants: [{ operations: ['overview:read', 'assets:read', 'people:read', 'audit:read', 'assets:write'], siteIds: ['site-1'], areaIds: '*' }] },
    { id: 'audit', grants: [{ operations: read, siteIds: ['site-1', 'site-2'], areaIds: '*' }] },
    { id: 'duty', grants: [{ operations: read, siteIds: ['site-1'], areaIds: '*' }] }
  ]
  const state = {
    revision: 0, sites, roles, accounts: structuredClone(IDENTITIES).map(a => ({ ...a, enabled: true })),
    organizations: [
      { id: 'org-maint', siteId: 'site-1', name: '维护一班', areaId: 'area-boiler' },
      { id: 'org-run', siteId: 'site-1', name: '运行一班', areaId: 'area-turbine' },
      { id: 'org-elec', siteId: 'site-1', name: '电气一班', areaId: 'area-electric' }
    ],
    areas: [
      { id: 'area-boiler', siteId: 'site-1', name: '锅炉区', points: [[29, 20], [43, 20], [43, 58], [29, 58]] },
      { id: 'area-turbine', siteId: 'site-1', name: '汽机厂房', points: [[40, 64], [65, 64], [65, 83], [40, 83]] },
      { id: 'area-electric', siteId: 'site-1', name: '配电区', points: [[13, 61], [29, 61], [29, 87], [13, 87]] },
      { id: 'area-water', siteId: 'site-1', name: '循环水区', points: [[73, 27], [90, 27], [90, 75], [73, 75]] },
      { id: 'area-bei', siteId: 'site-2', name: '主厂区', points: [] }
    ],
    people: [], dutyShifts: [], devices: [], assignments: [], history: [],
    maintenanceOrders: [], maintenanceRecords: [], lifecycleHistory: [], groups: [], groupHistory: [], integrations: [], audit: [], idempotency: {}
  }
  const roster = [
    ['person-1-0', '陈建国', 'org-maint', 'area-boiler'],
    ['person-1-1', '李志远', 'org-maint', 'area-boiler'],
    ['person-1-2', '周明', 'org-maint', 'area-boiler'],
    ['person-1-3', '王海峰', 'org-run', 'area-turbine'],
    ['person-1-4', '赵晓东', 'org-run', 'area-turbine'],
    ['person-1-5', '刘洋', 'org-elec', 'area-electric'],
    ['person-1-6', '孙伟', 'org-elec', 'area-electric'],
    ['person-1-7', '何平', 'org-run', 'area-water']
  ]
  roster.forEach(([id, name, organizationId, areaId], index) => {
    state.people.push({ id, siteId: 'site-1', areaId, organizationId, name, code: `P${index + 1}`, accountId: null, version: 1 })
  })
  state.dutyShifts.push({
    id: 'shift-1', siteId: 'site-1', name: '当前当班', personIds: roster.map(([id]) => id),
    startsAt: '2026-09-15T00:00:00+08:00', endsAt: '2026-12-31T15:59:00Z', source: 'MOCK'
  })
  const issuedAt = '2026-09-15T00:00:00.000Z'
  roster.forEach(([personId, , , areaId], index) => {
    const n = String(index + 1).padStart(3, '0')
    for (const type of ['HELMET', 'BELT', 'WATCH']) {
      const code = `RL-${type === 'HELMET' ? 'H' : type === 'BELT' ? 'B' : 'W'}${n}`
      state.devices.push({ id: code, siteId: 'site-1', areaId, code, name: TYPE_NAMES[type], type, lifecycle: 'IN_USE', relation: 'ASSIGNED', communication: 'NOT_CONNECTED', freshness: 'UNKNOWN', sourceTime: null, capability: 'UNCONFIRMED', version: 1 })
      state.assignments.push({ id: `assignment-${code}`, deviceId: code, personId, siteId: 'site-1', active: true, startedAt: issuedAt, version: 1 })
    }
  })
  const stock = [
    ['RL-H009', 'HELMET', 'area-boiler'],
    ['RL-B009', 'BELT', 'area-boiler'],
    ['RL-W009', 'WATCH', 'area-boiler'],
    ['RL-H010', 'HELMET', 'area-turbine']
  ]
  for (const [code, type, areaId] of stock) {
    state.devices.push({ id: code, siteId: 'site-1', areaId, code, name: TYPE_NAMES[type], type, lifecycle: 'STOCK', relation: 'UNASSIGNED', communication: 'NOT_CONNECTED', freshness: 'UNKNOWN', sourceTime: null, capability: 'UNCONFIRMED', version: 1 })
  }
  for (const [code, type, areaId] of [['RL-H011', 'HELMET', 'area-electric'], ['RL-B010', 'BELT', 'area-electric']]) {
    state.devices.push({ id: code, siteId: 'site-1', areaId, code, name: TYPE_NAMES[type], type, lifecycle: 'MAINTENANCE', relation: 'UNASSIGNED', communication: 'NOT_CONNECTED', freshness: 'UNKNOWN', sourceTime: null, capability: 'UNCONFIRMED', version: 1 })
    state.maintenanceOrders.push({ id: `repair-${code}`, deviceId: code, siteId: 'site-1', areaId, status: 'OPEN', reason: '库存待修，非真实工单', version: 1 })
  }
  state.devices.push({ id: 'RL-W010', siteId: 'site-1', areaId: 'area-water', code: 'RL-W010', name: TYPE_NAMES.WATCH, type: 'WATCH', lifecycle: 'DISABLED', relation: 'UNASSIGNED', communication: 'NOT_CONNECTED', freshness: 'UNKNOWN', sourceTime: null, capability: 'UNCONFIRMED', version: 1 })
  state.devices.push({ id: 'RL-H012', siteId: 'site-1', areaId: 'area-water', code: 'RL-H012', name: TYPE_NAMES.HELMET, type: 'HELMET', lifecycle: 'SCRAPPED', relation: 'UNASSIGNED', communication: 'NOT_CONNECTED', freshness: 'UNKNOWN', sourceTime: null, capability: 'UNCONFIRMED', version: 1 })
  for (const [code, type] of [['RL-H201', 'HELMET'], ['RL-B201', 'BELT'], ['RL-W201', 'WATCH']]) {
    state.devices.push({ id: code, siteId: 'site-2', areaId: 'area-bei', code, name: TYPE_NAMES[type], type, lifecycle: 'STOCK', relation: 'UNASSIGNED', communication: 'NOT_CONNECTED', freshness: 'UNKNOWN', sourceTime: null, capability: 'UNCONFIRMED', version: 1 })
  }
  return extendIntegrations(extendDevices(extendSeed(state)))
}
