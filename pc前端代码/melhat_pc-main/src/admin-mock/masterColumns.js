// Columns describe only fields already returned by the current master provider.
export function masterColumns(entity, options, trees, site, displayTime) {
  const column = (key, label, value, width = 180, numeric = false) => ({ key, label, value, width, numeric })
  const name = (rows, id, fallback) => rows?.find(row => row.id === id)?.name || fallback
  const count = (key, label, value) => column(key, label, value, 120, true)
  const definitions = {
    people: [column('organization', '所属组织', r => name(options.organizations, r.organizationId, '组织未关联/已停用')), column('area', '所属区域', r => name(options.areas, r.areaId, '区域未关联/已停用')), column('account', '登录账号关联', r => r.accountId ? '已关联本地账号' : '无登录账号')],
    sites: [column('timezone', '时区', r => r.timezone || 'UTC')],
    dutyShifts: [count('members', '成员数', r => r.personIds.length), column('start', '开始时间', r => displayTime(r.startsAt), 200), column('end', '结束时间', r => displayTime(r.endsAt), 200), column('timezone', '时区', () => site?.timezone || 'UTC')],
    accounts: [count('roles', '角色数', r => r.roleIds.length), column('person', '人员关联', r => r.personId ? name(options.people, r.personId, '已关联（当前不可见）') : '无人员关联')],
    roles: [count('grants', '授权范围组数', r => r.grants.length)],
    organizations: [column('parent', '上级组织', r => r.parentId ? name(trees.organizations, r.parentId, '未知') : '根节点')],
    areas: [column('parent', '上级区域', r => r.parentId ? name(trees.areas, r.parentId, '未知') : '根节点')]
  }
  return definitions[entity] || []
}
