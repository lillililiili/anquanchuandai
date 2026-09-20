import { personIdPattern } from './portal-route.js'
// Only explicit same-site object IDs can cross a workspace boundary.
export function workspaceTarget(item, siteId, selection = {}) {
  const query = { ...item.query }
  if (typeof siteId === 'string' && personIdPattern.test(siteId)) query.siteId = siteId
  if (selection.siteId === siteId && personIdPattern.test(selection.deviceId || '')) {
    if (item.path === '/video') query.selectedId = selection.deviceId
    if (item.path === '/location' && query.tab === 'tracks') query.deviceId = selection.deviceId
  }
  return { path: item.path, query }
}
