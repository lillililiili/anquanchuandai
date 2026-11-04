const SUCCESS_STATUSES = new Set(['摘要成功', '回传成功', '同步成功', '已回传', 'SUCCESS', 'SUCCEEDED']);
const FAILURE_STATUSES = new Set(['回传失败', '同步失败', 'FAILED', 'ERROR']);
const legacyPlaceholder = value => /待联调|(?:尚|暂)?未接入|待接入|尚未部署/.test(value);
const text = value => typeof value === 'string' ? value.trim() : typeof value === 'number' && Number.isFinite(value) ? String(value) : '';

export function hasExternalSource(record) {
  return ['externalId', 'externalRecordId', 'externalSource', 'externalSystem'].some(key => {
    const value = text(record?.[key]);
    return value && value.toLowerCase() !== 'unknown' && !legacyPlaceholder(value);
  });
}

// Local verification and the absence of a pending flag never prove external delivery.
export function externalStatusPresentation(record) {
  if (!hasExternalSource(record)) return { label: '无外部关联', color: 'muted' };
  const label = text(record?.externalStatus);
  if (!label || legacyPlaceholder(label)) return { label: '状态待确认', color: 'muted' };
  return { label, color: SUCCESS_STATUSES.has(label) ? 'green' : FAILURE_STATUSES.has(label) ? 'red' : 'muted' };
}
