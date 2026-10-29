import { can, hasSite, OPERATIONS } from './access'

export function authorizationEffects(state, account) {
  const effects = []
  for (const site of state.sites) {
    for (const operation of OPERATIONS) if (can(state, account, operation, { siteId: site.id })) effects.push({ key: JSON.stringify([operation, site.id]), operation, siteId: site.id, siteName: site.name })
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
  if (entity === 'roles') return JSON.stringify(a.grants.map(({ operations, siteIds }) => ({ operations, siteIds }))) !== JSON.stringify(b.grants.map(({ operations, siteIds }) => ({ operations, siteIds })))
  return JSON.stringify(a.roleIds.slice().sort()) !== JSON.stringify(b.roleIds.slice().sort())
}
