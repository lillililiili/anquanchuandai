export const OPERATION_NAMES = { 'self:read': '本人资料与装备查看', 'events:read': '范围内事件查看', 'events:claim': '事件认领', 'events:observe': '现场补充', 'events:verify': '最终核验', 'sos:create': '手机发起求助', 'sos:assist': 'SOS协助', 'works:read': '作业查看', 'communications:voice': '设备语音', 'communications:broadcast': '文字广播', 'overview:read': '厂站范围访问', 'people:read': '人员查看', 'people:write': '人员维护', 'organization:read': '组织班组查看', 'organization:write': '组织班组维护', 'sites:read': '厂站查看', 'sites:write': '厂站维护（仅系统身份执行）', 'duty:read': '名册查看', 'duty:write': '名册维护', 'access:read': '账号角色查看', 'accounts:write': '账号维护与有限委派', 'roles:write': '角色维护（仅系统身份执行）', 'assets:read': '资产查看', 'assets:write': '资产办理', 'audit:read': '操作日志查看', 'integrations:read': '接入配置查看', 'integrations:write': '接入配置维护', '*': '全部操作', 'groups:write': '常设协助组维护' }

export function operationLabel(operation) {
  return OPERATION_NAMES[operation] || '未命名操作'
}

export function roleOperationLabels(role) {
  const operations = [...new Set((role?.grants || []).flatMap(grant => grant.operations || []))]
  return operations.includes('*') ? [operationLabel('*')] : [...new Set(operations.map(operationLabel))]
}
