import { isRealDevice, projectDevice } from './device-telemetry.js';
import { mapLocation } from './location.js';
import { isSimulatedWatch } from './sample-data.js';

// Demo data must be explicitly enabled at build time; a failed connection never enables it.
export function demoEnabled(value) { return value === 'true'; }
export const DEMO_MODE = demoEnabled(import.meta.env?.VITE_DEMO_MODE);

export function displayDevice(device, demoMode = false) {
  if (!device || demoMode || isRealDevice(device) || isSimulatedWatch(device)) return projectDevice(device);
  // Keep the ledger identity and bindings, but do not present preset telemetry as observations.
  return { ...device, online: null, battery: null, worn: null, hookAEngaged: null,
    hookBEngaged: null, video: 'unavailable', updated: null, sourceTime: null };
}

export function personMapPosition(person, demoMode = false) {
  const coordinates = mapLocation(person, { current: true });
  if (coordinates) return { coordinates };
  if (!demoMode || person?.coordinateSystem || person?.locationQuality) return null;
  const point = person?.position;
  return Array.isArray(point) && point.length === 2 && point.every(v => Number.isFinite(v) && v >= 0 && v <= 100) ? point : null;
}

export function demoVideoAvailable(device, demoMode = false) {
  return demoMode && !isRealDevice(device) && device?.video === 'available';
}

export function latestDeviceRecord(devices) {
  const times = devices.filter(isRealDevice).map(device => device.lastSeenAt || device.sourceTime || device.updated)
    .map(value => Date.parse(value || '')).filter(Number.isFinite);
  return times.length ? new Date(Math.max(...times)).toISOString() : null;
}
