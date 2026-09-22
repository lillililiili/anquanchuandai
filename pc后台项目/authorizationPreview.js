import { can, hasSite, OPERATIONS } from './access'

export function authorizationEffects(state, account) {
  const effects = []
  for (const site of state.sites) {
    const areas = [{ id: null, name: '全厂及未指定区域' }, ...state.areas.filter(a => a.siteId === site.id)]
    for (const area of areas) for (const operation of OPERATIONS) if (can(state, account, operation, { siteId: site.id, areaId: area.id })) effects.push({ key: JSON.stringify([operation, site.id, area.id]), operation, siteId: site.id, siteName: site.name, areaId: area.id, areaName: area.name })
  }
  return effects
}
export function authorizationDiff(before, after, type, input) {
  const ids = type.startsWith('accounts.') ? [input.id] : before.accounts.filter(a => a.roleIds.includes(input.id)).map(a => a.id)
  return ids.map(id => {
    const a = before.accounts.find(a => a.id === id), b = after.accounts.find(a => a.id === id)
    const old = authorizationEffects(before, a), next = authorizationEffects(after, b), oldKeys = new Set(old.map(v => v.key)), newKeys = new Set(next.map(v => v.key))
    return { id, name: a.name, added: next.filter(v => !oldKeys.has(v.key)), removed: old.filter(v => !newKeys.has(v.key)), retained: next.filter(v => oldKeys.has(v.key)), lostSites: before.sites.filter(s => hasSite(before, a, s.id) && !hasSite(after, b, s.id)).map(s => ({ id: s.id, name: s.name })), noScope: !after.sites.some(s => hasSite(after, b, s.id)) }
  })
}
export function needsAuthorizationPreview(before, after, type, input) {
  if (type === 'roles.status') return true
  if (!['accounts.update', 'roles.update'].includes(type)) return false
  const entity = type.split('.')[0], a = before[entity].find(r => r.id === input.id), b = after[entity].find(r => r.id === input.id)
  if (entity === 'roles') return JSON.stringify(a.grants) !== JSON.stringify(b.grants)
  const bindings = (state, row) => row.roleIds.slice().sort().map(id => { const role = state.roles.find(r => r.id === id), scope = row.roleScopes?.[id]; return { id, siteIds: (scope?.siteIds || role.grants.flatMap(g => g.siteIds)).slice().sort(), areaIds: scope?.areaIds || role.grants[0]?.areaIds } })
  return JSON.stringify(bindings(before, a)) !== JSON.stringify(bindings(after, b))
}
