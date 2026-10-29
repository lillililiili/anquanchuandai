// Device coordinates remain in their original system. Conversion is only for
// the GCJ-02 basemap; unknown coordinate systems must never be guessed.
import { toMapCoordinates } from "../../../shared/map-coordinates.mjs";
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

export function prepareTracks(rows, gapMs = 300000) {
  const ordered = [...rows].sort((a, b) => Date.parse(a.reportedAt) - Date.parse(b.reportedAt));
  const points = [], seen = new Set();
  let interrupted = false;
  for (const row of ordered) {
    const stamp = Date.parse(row.reportedAt || ""), coordinates = mapLocation(row);
    if (!coordinates || !Number.isFinite(stamp)) { interrupted = true; continue; }
    const key = row.id || `${row.deviceId}/${row.reportedAt}/${row.latitude}/${row.longitude}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const previous = points.at(-1);
    points.push({ ...row, coordinates, time: beijingTime(row.reportedAt), gap: Boolean(previous && (interrupted || row.gap || stamp - Date.parse(previous.reportedAt) > gapMs || previous.deviceId !== row.deviceId)) });
    interrupted = false;
  }
  return points;
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
