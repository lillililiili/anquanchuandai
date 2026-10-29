export const PERSON_DUTY_STATUSES = Object.freeze({
  ON_DUTY: '在岗',
  OFF_DUTY: '离岗',
  UNKNOWN: '待确认',
});

export function normalizePersonDutyStatus(value) {
  return typeof value === 'string' && Object.hasOwn(PERSON_DUTY_STATUSES, value) ? value : 'UNKNOWN';
}

export function personDutyStatusLabel(value) {
  return PERSON_DUTY_STATUSES[normalizePersonDutyStatus(value)];
}
