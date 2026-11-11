export function featureDraft(device, feature) {
  const saved = device?.featureConfiguration?.[feature]?.status || {}
  return { feature, support: saved.support || 'DEFAULT', connection: saved.connection || 'DEFAULT', availability: saved.availability || 'DEFAULT' }
}

export function featurePayload(draft) {
  if (!draft.feature) throw Error('请选择配置功能。')
  if (!['DEFAULT', 'SUPPORTED', 'UNSUPPORTED', 'PENDING'].includes(draft.support)) throw Error('请选择设备支持状态。')
  if (!['DEFAULT', 'CONNECTED', 'NOT_CONNECTED', 'PENDING'].includes(draft.connection)) throw Error('请选择连接状态。')
  if (!['DEFAULT', 'AVAILABLE', 'UNAVAILABLE', 'PENDING'].includes(draft.availability)) throw Error('请选择可用状态。')
  if (draft.availability === 'AVAILABLE' && (draft.support !== 'SUPPORTED' || draft.connection !== 'CONNECTED')) throw Error('设为当前可用时，请同时选择“支持”和“已连接”。')
  return { feature: draft.feature, support: draft.support, connection: draft.connection, availability: draft.availability }
}
