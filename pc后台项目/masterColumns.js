import { beijingTime } from './tablePresentation'

// Columns describe only fields already returned by the current master provider.
export function masterColumns(entity, options, trees, site, displayTime) {
  const column = (key, label, value, width = 180, numeric = false) => ({ key, label, value, width, numeric })
  const name = (rows, id, fallback) => rows?.find(row => row.id === id)?.name || fallback
  const count = (key, label, value) => column(key, label, value, 120, true)
  const definitions = {
    people: [column('organization', '所属组织', r => name(trees.organizations || options.organizations, r.organizationId, '未关联或不可见'), 150)],
    sites: [],
    dutyShifts: [count('members', '成员数', r => r.personIds.length), column('start', '开始时间', r => displayTime(r.startsAt), 200), column('end', '结束时间', r => displayTime(r.endsAt), 200)],
    accounts: [],
    roles: [
      column('roleType', '角色类型', r => r.builtin ? '内置角色' : '自定义角色', 130),
      column('sites', '厂站范围', r => [...new Set((r.grants || []).flatMap(grant => grant.siteIds || []))].map(id => name(options.sites, id, '未命名厂站')).join('、') || '—', 260),
      column('createdAt', '创建时间', r => beijingTime(r.createdAt), 200)
    ],
    organizations: [column('parent', '上级组织', r => r.parentId ? name(trees.organizations, r.parentId, '未知') : '根节点')],
  }
  return definitions[entity] || []
}
