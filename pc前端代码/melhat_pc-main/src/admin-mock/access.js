export const OPERATIONS = ['overview:read', 'assets:read', 'people:read', 'people:write', 'organization:read', 'organization:write', 'sites:read', 'sites:write', 'duty:read', 'duty:write', 'access:read', 'accounts:write', 'roles:write', 'audit:read', 'integrations:read', 'assets:write', 'groups:write']
export const DELEGATE_ROLES = ['viewer', 'people-editor', 'asset-operator']
export function effectiveGrants(state, actor) {
  if (!actor?.enabled) return []
  return state.roles.filter(r => r.enabled !== false && actor.roleIds.includes(r.id)).flatMap(role => role.grants.map(g => {
    const limit = actor.roleScopes?.[role.id]
    return { operations: g.operations, siteIds: limit ? g.siteIds.filter(id => limit.siteIds.includes(id)) : g.siteIds,
      areaIds: !limit || limit.areaIds === '*' ? g.areaIds : g.areaIds === '*' ? limit.areaIds : g.areaIds.filter(id => limit.areaIds.includes(id)) }
  }))
}
export function can(state, actor, operation, object) {
  if (state.sites.find(s => s.id === object.siteId)?.enabled === false && operation !== 'sites:write') return false
  return effectiveGrants(state, actor).some(g => (g.operations.includes('*') || g.operations.includes(operation)) && g.siteIds.includes(object.siteId) && (g.areaIds === '*' || (object.areaId && g.areaIds.includes(object.areaId))))
}
export function hasSite(state, actor, siteId, operation = 'overview:read') {
  return state.sites.some(s => s.id === siteId && s.enabled !== false) && effectiveGrants(state, actor).some(g => g.siteIds.includes(siteId) && (g.operations.includes('*') || g.operations.includes(operation)) && (g.areaIds === '*' || g.areaIds.some(id => state.areas.some(a => a.id === id && a.siteId === siteId && a.enabled !== false))))
}
export function system(actor) { return actor?.id === 'demo-system' && actor.enabled }
export function accountManageable(state, actor, account) {
  if (system(actor)) return account.id !== 'demo-system'
  if (account.builtin || actor.id === account.id || !can(state, actor, 'accounts:write', account)) return false
  return account.roleIds.every(id => DELEGATE_ROLES.includes(id)) && effectiveGrants(state, account).every(g => g.siteIds.every(siteId => g.operations.every(op => {
    if (g.areaIds === '*') return can(state, actor, op, { siteId })
    return g.areaIds.every(areaId => can(state, actor, op, { siteId, areaId }))
  })))
}
