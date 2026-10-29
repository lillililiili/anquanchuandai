import { isRealDevice } from './device-telemetry.js';
import { isSimulatedWatch, isSimulatedVital, projectSingleSimulatedWatch } from '../../../shared/simulated-watch.mjs';
export { isSimulatedWatch, isSimulatedVital, projectSingleSimulatedWatch };

function equal(left, right) {
  if (left === right) return true;
  if (!left || !right || typeof left !== 'object' || typeof right !== 'object') return false;
  const keys = Object.keys(left);
  return keys.length === Object.keys(right).length && keys.every(key => Object.hasOwn(right, key) && equal(left[key], right[key]));
}

// Old browser saves predate source labels. Only exact bundled records are samples;
// an identifier or a similar name alone never establishes provenance.
export function projectCachedSamples(snapshot, baseline) {
  const sample = (kind, record) => baseline[kind]?.some(original => equal(record, original));
  const hidden = new Set(snapshot.devices.filter(device => !isRealDevice(device) && ['H', 'B'].includes(device.type) && sample('devices', device)).map(device => device.id));
  const devices = snapshot.devices.filter(device => !hidden.has(device.id)).map(device =>
    device.type === 'W' && !isRealDevice(device) && sample('devices', device)
      ? { ...device, source: 'DEMO_WATCH', demo: true, dataOrigin: 'GUARDIAN_SEED' } : device);
  const simulated = new Set(devices.filter(isSimulatedWatch).map(device => device.id));
  const result = { ...snapshot, devices, bindings: snapshot.bindings.filter(binding => !hidden.has(binding.deviceId)) };
  for (const kind of ['events', 'media', 'calls', 'works']) {
    if (Array.isArray(snapshot[kind])) result[kind] = snapshot[kind].filter(record => !sample(kind, record));
  }
  if (equal(snapshot.sos, baseline.sos)) result.sos = { status: 'ended', members: [], timeline: [] };
  result.vitals = (snapshot.vitals || []).map(record => simulated.has(record.deviceId) && sample('vitals', record)
    ? { ...record, demo: true, dataOrigin: 'GUARDIAN_SEED' } : record);
  return projectSingleSimulatedWatch(result);
}
