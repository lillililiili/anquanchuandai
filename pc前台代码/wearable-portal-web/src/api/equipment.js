import * as provider from '@equipment-provider'
import { requireValue } from '@/utils/portal-contract'
import { validateProfile } from '@/utils/device-profile'
import { personIdPattern } from '@/utils/portal-route'
import { assignmentLabels, equipmentTypes } from '@/utils/equipment-route'
import { useWorkspaceStore } from '@/store/workspace'
import { useUserStore } from '@/store/user'
export const equipmentEnabled = provider.enabled
function device(d, siteId) {
  validateProfile(d?.profile)
  requireValue(d && typeof d.deviceId === 'string' && personIdPattern.test(d.deviceId) && d.siteId === siteId && Object.hasOwn(equipmentTypes, d.type) && Object.hasOwn(assignmentLabels, d.assignmentState))
  requireValue(Number.isSafeInteger(d.version) && d.version > 0)
  requireValue(d.assignmentState !== 'ASSIGNED' || d.currentAssignment?.personId === d.currentPerson?.personId && !!d.currentPerson)
  return d
}
export async function getEquipment(q, signal) {
  const response = await provider.list(q, signal), p = response.data
  requireValue(p.scope.siteId === q.siteId && Array.isArray(p.items))
  requireValue(p.pageNum === Number(q.pageNum || 1) && p.pageSize === Number(q.pageSize || 20) && p.items.length <= p.pageSize)
  requireValue(p.state === 'AVAILABLE' ? Number.isSafeInteger(p.total) && p.total >= p.items.length : p.total === null && p.items.length === 0)
  p.items.forEach(d => device(d, q.siteId)); return response
}
export async function getEquipmentDetail(id, siteId, signal) {
  const response = await provider.detail(id, siteId, signal)
  requireValue(response.data.scope.siteId === siteId)
  if (response.data.state === 'AVAILABLE') { device(response.data.device, siteId); requireValue(response.data.device.deviceId === id) }
  return response
}
export async function getAssignmentOptions(q, signal) {
  const response = await provider.options(q, signal), d = response.data
  requireValue(d.scope.siteId === q.siteId && Array.isArray(d.choices) && Array.isArray(d.current) && typeof d.allowed === 'boolean')
  for (const pair of [...d.choices, ...d.current]) {
    device(pair.device, q.siteId); requireValue(typeof pair.person.personId === 'string' && pair.person.siteId === q.siteId)
    requireValue(Number.isSafeInteger(pair.expectedVersion.slot) && Number.isSafeInteger(pair.expectedVersion.device))
    requireValue(!q.personId || pair.person.personId === q.personId); requireValue(!q.deviceId || pair.device.deviceId === q.deviceId)
  }
  return response
}
async function command(action, input, signal) {
  const response = await provider[action](input, signal)
  requireValue(typeof response.data.recordId === 'string' && Array.isArray(response.data.changedEntities))
  if (!response.data.replayed) {
    const workspace = useWorkspaceStore()
    const user = useUserStore(), token = user.token
    setTimeout(() => { if (user.token === token) workspace.invalidate(response.data.changedEntities) }, 0)
  }
  return response
}
export const issueEquipment = (input, signal) => command('issue', input, signal)
export const returnEquipment = (input, signal) => command('returnAssignment', input, signal)
