import { emptyEvidence } from './relations'
export function extendSeed(state) {
  state.nextId = 1
  state.sites.forEach((s, i) => Object.assign(s, { code: `EQ-S${i + 1}`, enabled: true, version: 1, timezone: 'Asia/Shanghai' }))
  state.organizations.forEach((o, i) => Object.assign(o, { siteId: `site-${i + 1}`, code: `EQ-O${i + 1}`, parentId: null, areaId: `area-${i + 1}`, enabled: true, version: 1 }))
  state.areas.forEach((a, i) => Object.assign(a, { code: `EQ-A${i + 1}`, parentId: null, enabled: true, version: 1 }))
  state.people.forEach((p, i) => Object.assign(p, { code: `EQ-P${String(i + 1).padStart(3, '0')}`, organizationId: `org-${p.siteId.slice(-1)}`, enabled: true, remark: '' }))
  state.dutyShifts.forEach(s => Object.assign(s, { name: '预置历史班次', startsAt: '2026-09-18T00:00:00Z', endsAt: '2026-09-18T08:00:00Z', enabled: true, version: 1, memberSnapshots: s.personIds.map(id => ({ id, name: state.people.find(p => p.id === id).name })) }))
  const extraRead = ['organization:read', 'sites:read', 'duty:read']
  state.roles.forEach(r => { Object.assign(r, { name: { system: '系统管理员', site: '厂站管理员', asset: '资产管理员', audit: '审计员' }[r.id], builtin: true, enabled: true, version: 1 }); r.grants.forEach(g => { if (!g.operations.includes('*')) g.operations.push(...extraRead) }) })
  state.roles.find(r => r.id === 'site').grants[0].operations.push('organization:write', 'duty:write', 'accounts:write')
  for (const [id, name, writes] of [['viewer', '厂站查看员', []], ['people-editor', '人员维护员', ['people:write', 'duty:write']], ['asset-operator', '资产办理员', ['assets:write']]]) {
    state.roles.push({ id, name, builtin: true, enabled: true, version: 1, grants: [{ operations: ['overview:read', 'assets:read', 'people:read', ...extraRead, 'audit:read', ...writes], siteIds: state.sites.map(s => s.id), areaIds: '*' }] })
  }
  state.accounts.forEach(a => Object.assign(a, { loginName: { 'demo-system': 'admin', 'demo-site': 'siteadmin', 'demo-asset': 'assetadmin', 'demo-audit': 'auditor' }[a.id] || a.id, siteId: 'site-1', personId: null, builtin: true, version: 1, credentialVersion: 1 }))
  state.people.forEach(p => { p.equipmentEvidence = emptyEvidence() })
  state.people.filter(p => p.id.endsWith('-22')).forEach(p => { p.equipmentEvidence.BELT = 'UNKNOWN' })
  return state
}
