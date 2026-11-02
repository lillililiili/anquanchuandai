// Device coordinates remain in their original system. Conversion is only for
// the GCJ-02 basemap; unknown coordinate systems must never be guessed.
import { toMapCoordinates } from "../../../shared/map-coordinates.mjs";
import { formatBeijingDateTime } from './date-time.js';
export { coordinateSystem, toMapCoordinates, validLonLat, fromMapCoordinates } from "../../../shared/map-coordinates.mjs";

export function mapLocation(location, { current = false, now = Date.now() } = {}) {
  const quality = String(location?.locationQuality || "").toLowerCase();
  if (!["valid", "ok", "good"].includes(quality)) return null;
  if (current) {
    const stamp = Date.parse(location.locationReportedAt || location.reportedAt || "");
    const age = now - stamp;
    if (String(location.locationFreshness).toUpperCase() !== "CURRENT" || !Number.isFinite(age) || age < 0 || age > 300000) return null;
  }
  return toMapCoordinates(location);
}

export function beijingDate(now = Date.now()) {
  return new Date(now + 8 * 3600000).toISOString().slice(0, 10);
}

export function beijingTime(value) {
  const stamp = Date.parse(value || "");
  return Number.isFinite(stamp) ? new Date(stamp + 8 * 3600000).toISOString().slice(11, 19) : "—";
}

export function trackRange(date, start = "00:00", end = "23:59") {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !/^\d{2}:\d{2}$/.test(start) || !/^\d{2}:\d{2}$/.test(end) || start >= end) throw Error("请填写有效日期，结束时间必须晚于开始时间");
  const from = new Date(`${date}T${start}:00+08:00`), to = new Date(`${date}T${end}:59.999+08:00`);
  if (!Number.isFinite(from.getTime()) || !Number.isFinite(to.getTime()) || beijingDate(from.getTime()) !== date) throw Error("请选择有效日期");
  return { from: from.toISOString(), to: to.toISOString() };
}

export function trackQueryContext(saved = {}, routePersonId = '') {
  return routePersonId ? { ...saved, mode: 'person', personId: routePersonId, deviceId: '' }
    : { ...saved, mode: saved.mode === 'device' ? 'device' : 'person' };
}

export function prepareTracks(rows, gapMs = 300000) {
  const ordered = [...rows].sort((a, b) => Date.parse(trackTimestamp(a)) - Date.parse(trackTimestamp(b)));
  const points = [], seen = new Set();
  const interruptedDevices = new Set();
  for (const row of ordered) {
    const timeAt = trackTimestamp(row), stamp = Date.parse(timeAt), coordinates = mapLocation(row);
    if (!coordinates || !Number.isFinite(stamp)) { if (row.deviceId) interruptedDevices.add(row.deviceId); continue; }
    const key = row.id || `${row.deviceId}/${row.personId || ''}/${bindingKey(row)}/${timeAt}/${row.latitude}/${row.longitude}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const previous = points.at(-1);
    const gapReason = !previous ? '' : previous.deviceId !== row.deviceId ? 'DEVICE_CHANGED'
      : (previous.personId || '') !== (row.personId || '') || bindingKey(previous) !== bindingKey(row) ? 'ASSIGNMENT_CHANGED'
      : interruptedDevices.has(row.deviceId) ? 'INVALID_LOCATION' : row.gap ? 'REPORTED_GAP'
      : stamp - Date.parse(previous.timeAt) > gapMs ? 'TIME_GAP' : '';
    points.push({ ...row, coordinates, timeAt, time: beijingTime(timeAt), gap: Boolean(gapReason), gapReason });
    interruptedDevices.delete(row.deviceId);
  }
  return points;
}

function bindingKey(row) {
  return [row.bindingId ?? row.assignmentId ?? '', row.assignmentVersion ?? ''].join('/');
}

export function trackTimestamp(row) {
  // The server selects collected time only when the device actually provided
  // it. A known basis with a missing value must not silently use another basis.
  const basis = row.locationTimeBasis || (row.collectedAt ? 'DEVICE_COLLECTED_AT' : 'RECEIVED_AT');
  if (basis === 'DEVICE_COLLECTED_AT') return row.collectedAt || row.reportedAt || '';
  if (basis === 'RECEIVED_AT') return row.receivedAt || row.reportedAt || '';
  return '';
}

export function trackBreakLabel(point) {
  return ({ DEVICE_CHANGED: '来源设备切换', ASSIGNMENT_CHANGED: '历史领用关系变化',
    INVALID_LOCATION: '期间存在无有效定位的上报', REPORTED_GAP: '设备记录标记中断', TIME_GAP: '定位上报间隔超过5分钟' })[point.gapReason] || '轨迹中断';
}

export function trackEvents(events, { personId, deviceId, date, start = '00:00', end = '23:59' }) {
  const range = trackRange(date, start, end), from = Date.parse(range.from), to = Date.parse(range.to);
  const timestamp = event => {
    const value = formatBeijingDateTime(event.date && event.time ? `${event.date} ${event.time}` : event.time);
    return value === '—' ? NaN : Date.parse(value.replace(' ', 'T') + '+08:00');
  };
  return events.filter(event => (deviceId ? event.deviceId === deviceId : personId && event.personId === personId)
    && timestamp(event) >= from && timestamp(event) <= to).sort((a,b) => timestamp(a) - timestamp(b));
}

export function trackSegments(points) {
  const groups = [];
  for (const point of points) {
    if (!groups.length || point.gap) groups.push([]);
    groups.at(-1).push(point);
  }
  return groups;
}

export function eventLocation(event) {
  return { latitude: event?.locationLat, longitude: event?.locationLng, coordinateSystem: event?.coordinateSystem, locationQuality: event?.locationQuality, locationReportedAt: event?.locationReportedAt };
}
