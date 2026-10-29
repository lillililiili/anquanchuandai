import { normalizePersonDutyStatus, personDutyStatusLabel } from '../../../shared/person-duty.mjs';
import { formatBeijingDateTime } from './date-time.js';

export function personDutyPresentation(person) {
  const status = normalizePersonDutyStatus(person?.dutyStatus);
  if (status === 'UNKNOWN') return { status, label: '在岗待确认', color: 'muted', title: '尚未维护在岗状态' };
  const updatedAt = formatBeijingDateTime(person.dutyStatusUpdatedAt);
  const details = [
    person.dutyStatusSource === 'MANUAL' ? '后台人工维护' : '人员在岗状态',
    person.dutyStatusUpdatedBy ? `维护人：${person.dutyStatusUpdatedBy}` : '',
    updatedAt !== '—' ? `更新时间：${updatedAt}` : '',
  ];
  return { status, label: personDutyStatusLabel(status), color: status === 'ON_DUTY' ? 'green' : 'muted', title: details.filter(Boolean).join(' · ') };
}
