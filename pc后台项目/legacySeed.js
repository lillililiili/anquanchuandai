import { extendIntegrations } from './integrationData'
import { emptyEvidence } from './relations'

const TYPE_NAMES = { HELMET: '安全帽', BELT: '安全带', WATCH: '手表' }
const IDENTITIES = [
  { id: 'demo-system', name: '系统管理员', description: '全部预置厂站 · 管理权限', roleIds: ['system'] },
  { id: 'demo-site', name: '厂站管理员', description: '一号站 · 人员、资产、协助组', roleIds: ['site'] },
  { id: 'demo-asset', name: '资产管理员', description: '一号站 · 资产与运维', roleIds: ['asset'] },
  { id: 'demo-audit', name: '审计员', description: '一号站与空厂站 · 只读', roleIds: ['audit'] }
]
function extendDevices(state) {
  state.devices.forEach(d => Object.assign(d, { manufacturer: '预置厂商（非真实厂家）', sn: `EQ-SN-${d.code}`, modelId: d.type === 'HELMET' ? 'demo-helmet-basic' : `demo-${d.type.toLowerCase()}`, assetCode: '', purchasedOn: '', remark: '', assemblies: {}, connection: 'NOT_CONNECTED', verification: 'UNCONFIRMED', capabilitySource: '预置模板，非真机证据' }))
  return state
}

function extendSeed(state) {
  state.nextId = 1
  state.sites.forEach((s, i) => Object.assign(s, { code: `EQ-S${i + 1}`, enabled: true, version: 1, timezone: 'Asia/Shanghai' }))
  state.organizations.forEach((o, i) => Object.assign(o, { siteId: `site-${i + 1}`, code: `EQ-O${i + 1}`, parentId: null, areaId: `area-${i + 1}`, enabled: true, version: 1 }))
  state.areas.forEach((a, i) => Object.assign(a, { code: `EQ-A${i + 1}`, parentId: null, enabled: true, version: 1 }))
  state.people.forEach((p, i) => Object.assign(p, { code: `EQ-P${String(i + 1).padStart(3, '0')}`, organizationId: `org-${p.siteId.slice(-1)}`, enabled: true, remark: '' }))
  state.dutyShifts.forEach(s => Object.assign(s, { name: '预置历史班次', startsAt: '2026-09-18T00:00:00Z', endsAt: '2026-09-18T08:00:00Z', enabled: true, version: 1, memberSnapshots: s.personIds.map(id => ({ id, name: state.people.find(p => p.id === id).name })) }))
  const extraRead = ['organization:read', 'sites:read', 'duty:read']
  state.roles.forEach(r => { Object.assign(r, { name: { system: '系统管理员', site: '厂站管理员', asset: '资产管理员', audit: '审计员' }[r.id], builtin: true, enabled: true, version: 1 }); r.grants.forEach(g => { if (!g.operations.includes('*')) g.operations.push(...extraRead) }) })
  state.roles.find(r => r.id === 'site').grants[0].operations.push('organization:write', 'duty:write', 'accounts:write', 'groups:write')
  for (const [id, name, writes] of [['viewer', '厂站查看员', []], ['people-editor', '人员维护员', ['people:write', 'duty:write']], ['asset-operator', '资产办理员', ['assets:write']]]) {
    state.roles.push({ id, name, builtin: true, enabled: true, version: 1, grants: [{ operations: ['overview:read', 'assets:read', 'people:read', ...extraRead, 'audit:read', ...writes], siteIds: state.sites.map(s => s.id), areaIds: '*' }] })
  }
  state.accounts.forEach(a => Object.assign(a, { loginName: { 'demo-system': 'admin', 'demo-site': 'siteadmin', 'demo-asset': 'assetadmin', 'demo-audit': 'auditor' }[a.id] || a.id, siteId: 'site-1', personId: null, builtin: true, version: 1, credentialVersion: 1 }))
  state.people.forEach(p => { p.equipmentEvidence = emptyEvidence() })
  state.people.filter(p => p.id.endsWith('-22')).forEach(p => { p.equipmentEvidence.BELT = 'UNKNOWN' })
  return state
}

export function createLegacySeed() {
  const sites = [{ id: 'site-1', name: '一号厂站' }, { id: 'site-2', name: '二号厂站' }, { id: 'site-empty', name: '空厂站' }]
  const read = ['overview:read', 'assets:read', 'people:read', 'access:read', 'integrations:read', 'audit:read']
  const roles = [
    { id: 'system', grants: [{ operations: ['*'], siteIds: sites.map(s => s.id), areaIds: '*' }] },
    { id: 'site', grants: [{ operations: [...read, 'people:write', 'assets:write', 'groups:write'], siteIds: ['site-1'], areaIds: '*' }] },
    { id: 'asset', grants: [{ operations: ['overview:read', 'assets:read', 'people:read', 'audit:read', 'assets:write'], siteIds: ['site-1'], areaIds: '*' }] },
    { id: 'audit', grants: [{ operations: read, siteIds: ['site-1', 'site-empty'], areaIds: '*' }] }
  ]
  const state = {
    revision: 0, sites, roles, accounts: structuredClone(IDENTITIES).map(a => ({ ...a, enabled: true })),
    organizations: [], areas: [], people: [], dutyShifts: [], devices: [], assignments: [], history: [],
    maintenanceOrders: [], maintenanceRecords: [], lifecycleHistory: [], groups: [], groupHistory: [], integrations: [], audit: [], idempotency: {}
  }
  for (let station = 1; station <= 2; station++) {
    const siteId = `site-${station}`, areaId = `area-${station}`
    state.organizations.push({ id: `org-${station}`, name: `检修班组${station}` })
    state.areas.push({ id: areaId, siteId, name: '设备区域' })
    for (let i = 0; i < 25; i++) state.people.push({ id: `person-${station}-${i}`, siteId, areaId, name: `人员${station}-${String(i + 1).padStart(2, '0')}`, accountId: null, version: 1 })
    state.dutyShifts.push({ id: `shift-${station}`, siteId, personIds: state.people.filter(p => p.siteId === siteId).map(p => p.id), source: 'MOCK' })
    for (let i = 0; i < 36; i++) {
      const id = `${station}9007199254740993${String(i).padStart(3, '0')}`
      const relation = i < 12 ? 'ASSIGNED' : i === 32 ? 'UNKNOWN' : i === 33 ? 'CONFLICT' : 'UNASSIGNED'
      const lifecycle = i < 12 ? 'IN_USE' : i >= 27 && i < 30 ? 'MAINTENANCE' : i === 30 ? 'DISABLED' : i === 31 ? 'SCRAPPED' : 'STOCK'
      state.devices.push({ id, siteId, areaId, code: `EQ-${station}-${String(i + 1).padStart(3, '0')}`, name: TYPE_NAMES[['HELMET', 'BELT', 'WATCH'][i % 3]], type: ['HELMET', 'BELT', 'WATCH'][i % 3], lifecycle, relation, communication: ['OFFLINE', 'UNKNOWN', 'ONLINE'][i % 3], freshness: i % 4 === 0 ? 'STALE' : 'UNKNOWN', sourceTime: i % 4 === 0 ? '2026-09-18T08:00:00Z' : null, capability: 'UNCONFIRMED', version: 1 })
      if (relation === 'ASSIGNED' || relation === 'CONFLICT') {
        const personIds = relation === 'CONFLICT' ? [`person-${station}-20`, `person-${station}-21`] : [`person-${station}-${Math.floor(i / 3)}`]
        for (const personId of personIds) state.assignments.push({ id: `assignment-${id}-${personId}`, deviceId: id, personId, siteId, active: true, startedAt: null, version: 1 })
      }
      if (lifecycle === 'MAINTENANCE') state.maintenanceOrders.push({ id: `repair-${id}`, deviceId: id, siteId, areaId, status: 'OPEN', reason: '预置检修样例，非真实工单', version: 1 })
    }
    state.groups.push({ id: `group-${station}`, siteId, areaId, code: `EQ-G${station}`, name: '协助组', personIds: [`person-${station}-0`], leaderId: null, sos: null, remark: '', enabled: true, version: 1 })
    state.integrations.push({ id: `connector-${station}`, siteId, status: 'NOT_CONNECTED', name: '安全帽连接器' })
  }
  return extendIntegrations(extendDevices(extendSeed(state)))
}
