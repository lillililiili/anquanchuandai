export function vitalValue(value, digits) {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  return digits == null ? value : value.toFixed(digits);
}

export function bloodPressure(record) {
  const systolic = vitalValue(record?.systolic), diastolic = vitalValue(record?.diastolic);
  return systolic == null || diastolic == null ? null : `${systolic} / ${diastolic}`;
}
