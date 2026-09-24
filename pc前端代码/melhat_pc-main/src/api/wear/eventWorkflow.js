// Shared platform workflow; external closure can only come from the authority system.
export function canReviewVerification(event, actor, actions = []) {
  if (!actor.isPlatformAdmin || !actor.canReviewEvent || event.severity !== 'emergency' || event.status !== 'pending_review') return false
  if (event.source === 'manual_sos') return String(event.reporterUserId) !== String(actor.userId)
  const report = actions.find(item => item.action === 'handle')
  return !!report && (event.type === 'sos' || report.actor !== actor.name)
}

export function verificationStepLabel(value) {
  return { pending: '待完成', submitted: '已上报', verified: '已核验', approved: '已通过',
    not_submitted: '待现场上报', not_required: '无需此步骤', unknown: '历史结果待确认' }[value] || '未同步'
}

export function reviewActorHint(event) {
  if (event.source === 'manual_sos') return '由管理员审批，审批人与报警人须为不同账号。'
  return event.type === 'sos' ? '由管理员审批；设备 SOS 允许管理员审批自己上报的现场记录。'
    : '由管理员审批，审批人与现场上报人须为不同账号。'
}
