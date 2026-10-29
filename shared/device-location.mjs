function coordinate(value, limit) {
  if ((typeof value !== 'number' && typeof value !== 'string') || String(value).trim() === '') return null;
  const number = Number(value);
  return Number.isFinite(number) && Math.abs(number) <= limit ? number : null;
}

// Report receipt time is not a measurement timestamp or a precision guarantee.
export function deviceLocation(device, now = Date.now()) {
  const lat = coordinate(device?.latitude, 90);
  const lon = coordinate(device?.longitude, 180);
  const valid = lat != null && lon != null && !(lat === 0 && lon === 0);
  const reported = Date.parse(device?.locationReportedAt || '');
  const reportedAt = valid && Number.isFinite(reported) ? new Date(reported).toISOString() : null;
  const age = now - reported;
  const freshness = String(device?.locationFreshness || '').toUpperCase();
  let status = '未收到有效位置';
  if (valid) {
    if (device?.online === false || device?.online === 0) status = '最后上报（设备离线）';
    else if (freshness === 'STALE' || (Number.isFinite(age) && age > 300000)) status = '最后上报（已过期）';
    else if (freshness === 'CURRENT' && reportedAt && age >= 0) status = '近期上报';
    else status = '最后上报（时效未知）';
  }
  return {
    position: valid ? `纬度 ${lat.toFixed(6)}，经度 ${lon.toFixed(6)}` : '未收到有效位置',
    reportedAt,
    status,
  };
}
