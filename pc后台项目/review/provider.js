import { createAdminService } from '../service'
import { createSeed } from '../seed'
const state = createSeed()
// Enough isolated records to inspect pagination, long values and detail history.
for (let i = 8; i < 26; i++) state.people.push({ ...structuredClone(state.people[0]), id: `review-person-${i}`, code: `QA-P${i}`, name: `验收人员${i}`, equipmentEvidence: structuredClone(state.people[0].equipmentEvidence) })
for (let i = 0; i < 24; i++) state.audit.push({ id: `review-audit-${i}`, siteId: 'site-1', actorId: 'demo-system', actorName: '系统管理员', objectId: 'RL-H001', action: 'devices.update', result: 'SUCCESS', occurredAt: '2026-10-15T08:00:00Z', before: { name: '安全帽', remark: '原备注' }, after: { name: '安全帽', remark: '隔离验收备注' } })
const values = new Map()
const provider = createAdminService({ initialState: state, delay: 30, storage: { getItem: key => values.get(key), setItem: (key, value) => values.set(key, value), removeItem: key => values.delete(key) }, now: () => '2026-10-15T08:00:00Z' })
provider.setRemoteSave(() => {})
const params = new URLSearchParams(location.search)
provider.login(params.get('identity') === 'audit' ? 'demo-audit' : 'demo-system', 'Admin@2026')
if (params.has('scenario')) provider.setScenario({ target: params.get('target') || 'devices', mode: params.get('scenario') })
export function getAdminProvider() { return provider }
