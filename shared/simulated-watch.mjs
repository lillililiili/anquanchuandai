// Existing sample identity shared by the portal and admin ledger. Never create a
// replacement if this sample is absent, reassigned to another site, or now real.
export const SIMULATED_WATCH = Object.freeze({ id: 'RL-W001', stationId: 'S1', siteId: 'site-1' });

export function isSimulatedWatch(device) {
  return ['W', 'WATCH'].includes(device?.type) && device.source === 'DEMO_WATCH';
}

export function isSimulatedVital(record) {
  const source = String(record?.source || '').toUpperCase();
  if (['PLATFORM', 'DEVICE', 'DIRECT_WATCH', 'WATCH_DEVICE', 'DIRECT_HELMET', 'DIRECT_BELT', '设备上报'].includes(source)) return false;
  return ['预置观测', 'DEMO_WATCH'].includes(record?.source) || record?.demo === true;
}

export function selectedSimulatedWatch(device) {
  return isSimulatedWatch(device) && device.id === SIMULATED_WATCH.id &&
    (device.type === 'W' ? device.station === SIMULATED_WATCH.stationId : device.siteId === SIMULATED_WATCH.siteId);
}

// This is a read projection. The caller must persist the original input, never
// this filtered view, and all real/unknown sources pass through unchanged.
export function projectSingleSimulatedWatch(state) {
  if (!state || !Array.isArray(state.devices)) return state;
  const visible = state.businessConfig?.simulatedWatchVisible !== false;
  const devices = state.devices.filter(device => !isSimulatedWatch(device) || visible && selectedSimulatedWatch(device));
  const hidden = new Set(state.devices.filter(device => isSimulatedWatch(device) && !devices.some(kept => kept.id === device.id)).map(device => device.id));
  const result = { ...state, devices };
  // Simulated observations never enter the real safety-event ledger.
  if (Array.isArray(state.events)) result.events = state.events.filter(event => {
    const source = String(event.source || '').toUpperCase();
    if (['DEVICE', 'PLATFORM', 'DIRECT_HELMET', 'DIRECT_BELT', 'DIRECT_WATCH', '设备上报'].includes(source)) return true;
    return !isSimulatedVital(event) && !state.devices.some(device => isSimulatedWatch(device) && device.id === event.deviceId);
  });
  for (const key of ['bindings', 'assignments']) {
    if (Array.isArray(state[key])) result[key] = state[key].filter(item => !hidden.has(item.deviceId));
  }
  if (Array.isArray(state.vitals)) {
    const selected = devices.some(selectedSimulatedWatch);
    const bindingKey = Array.isArray(state.bindings) ? 'bindings' : 'assignments';
    const owners = new Set((state[bindingKey] || []).filter(item => item.deviceId === SIMULATED_WATCH.id &&
      (bindingKey === 'bindings' ? !item.end : item.active === true)).map(item => item.personId).filter(Boolean));
    result.vitals = state.vitals.filter(record => !isSimulatedVital(record) || selected &&
      owners.size === 1 && record.deviceId === SIMULATED_WATCH.id && owners.has(record.personId));
  }
  return result;
}
