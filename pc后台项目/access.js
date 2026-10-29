export const OPERATIONS = ['overview:read', 'assets:read', 'people:read', 'people:write', 'organization:read', 'organization:write', 'sites:read', 'sites:write', 'duty:read', 'duty:write', 'access:read', 'accounts:write', 'roles:write', 'audit:read', 'integrations:read', 'integrations:write', 'assets:write', 'groups:write', 'self:read', 'events:read', 'events:claim', 'events:observe', 'events:verify', 'sos:create', 'sos:assist', 'works:read', 'communications:voice', 'communications:broadcast']
export const DELEGATE_ROLES = ['viewer', 'people-editor', 'asset-operator', 'mobile-user']
export function effectiveGrants(state, actor) {
  if (!actor?.enabled) return []
  return state.roles.filter(r => r.enabled !== false && actor.roleIds.includes(r.id)).flatMap(role => role.grants.map(g => ({ operations: g.operations, siteIds: g.siteIds })))
}
export function can(state, actor, operation, object) {
  if (state.sites.find(s => s.id === object.siteId)?.enabled === false && operation !== 'sites:write') return false
  return effectiveGrants(state, actor).some(g => (g.operations.includes('*') || g.operations.includes(operation)) && g.siteIds.includes(object.siteId))
}
export function hasSite(state, actor, siteId, operation = 'overview:read') {
  return state.sites.some(s => s.id === siteId && s.enabled !== false) && effectiveGrants(state, actor).some(g => g.siteIds.includes(siteId) && (g.operations.includes('*') || g.operations.includes(operation)))
}
export function system(actor) { return actor?.id === 'demo-system' && actor.enabled }
export function accountManageable(state, actor, account) {
  if (system(actor)) return account.id !== 'demo-system'
  if (account.builtin || actor.id === account.id || !can(state, actor, 'accounts:write', account)) return false
  return account.roleIds.every(id => DELEGATE_ROLES.includes(id)) && effectiveGrants(state, account).every(g => g.siteIds.every(siteId => g.operations.every(op => can(state, actor, op, { siteId }))))
}
