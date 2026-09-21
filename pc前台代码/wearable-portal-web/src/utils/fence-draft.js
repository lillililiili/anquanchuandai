import { normalizeRing } from './fence-geometry.js'
export function validateFenceDraft(draft) {
  const fields = {}
  if (typeof draft.name !== 'string' || !draft.name.trim()) fields.name = '请输入围栏名称'
  else if (draft.name.trim().length > 100) fields.name = '围栏名称不能超过100字'
  if (!['ALL', 'HELMET', 'BELT', 'WATCH'].includes(draft.appliesTo)) fields.appliesTo = '请选择设备类型'
  if (typeof draft.teamId !== 'string' || !draft.teamId) fields.teamId = '请选择适用班组'
  let ring, geometryError = ''
  try { ring = normalizeRing(draft.nodes) } catch (e) { geometryError = e.message }
  return { fields, ring, geometryError, valid: !Object.keys(fields).length && !geometryError }
}
