import { emptyEvidence } from './relations'
export function extendSeed(state) {
  state.nextId = 1
  state.sites.forEach((s, i) => Object.assign(s, { code: s.code || `EQ-S${i + 1}`, enabled: true, version: 1, timezone: s.timezone || 'Asia/Shanghai' }))
  state.organizations.forEach((o, i) => Object.assign(o, { code: o.code || `EQ-O${i + 1}`, parentId: o.parentId ?? null, enabled: true, version: 1 }))
  state.areas.forEach((a, i) => Object.assign(a, { code: a.code || `EQ-A${i + 1}`, parentId: a.parentId ?? null, enabled: true, version: 1 }))
  state.people.forEach((p, i) => Object.assign(p, { code: p.code || `EQ-P${String(i + 1).padStart(3, '0')}`, enabled: true, remark: p.remark || '' }))
  state.dutyShifts.forEach(s => Object.assign(s, { enabled: true, version: 1, memberSnapshots: s.memberSnapshots || s.personIds.map(id => ({ id, name: state.people.find(p => p.id === id)?.name || id })) }))
  const extraRead = ['organization:read', 'sites:read', 'duty:read']
  state.roles.forEach(r => { Object.assign(r, { name: { system: '系统管理员', site: '厂站管理员', asset: '资产管理员', audit: '审计员', duty: '平台值守员' }[r.id], builtin: true, enabled: true, version: 1 }); r.grants.forEach(g => { if (!g.operations.includes('*')) g.operations.push(...extraRead) }) })
  state.roles.find(r => r.id === 'site').grants[0].operations.push('organization:write', 'duty:write', 'accounts:write')
  for (const [id, name, writes] of [['viewer', '厂站查看员', []], ['people-editor', '人员维护员', ['people:write', 'duty:write']], ['asset-operator', '资产办理员', ['assets:write']]]) {
    state.roles.push({ id, name, builtin: true, enabled: true, version: 1, grants: [{ operations: ['overview:read', 'assets:read', 'people:read', ...extraRead, 'audit:read', ...writes], siteIds: ['site-1'], areaIds: '*' }] })
  }
  state.accounts.forEach(a => Object.assign(a, { loginName: { 'demo-system': 'admin', 'demo-site': 'siteadmin', 'demo-asset': 'assetadmin', 'demo-audit': 'auditor', 'demo-duty': 'duty' }[a.id] || a.id, siteId: 'site-1', personId: null, builtin: true, version: 1, credentialVersion: 1 }))
  state.people.forEach(p => { p.equipmentEvidence = emptyEvidence() })
  return state
}
