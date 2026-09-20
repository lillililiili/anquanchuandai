export const simulated = false
export const read = async params => ({ data: { state: 'NOT_INTEGRATED', scope: { siteId: params.siteId, personId: params.personId || null, deviceId: params.deviceId || null }, items: [], reason: '真实体征来源尚未接入' } })
