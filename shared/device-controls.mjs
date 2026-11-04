import reference from './device-controls.json' with { type: 'json' };

export function deviceControlsReference(device) {
  const profile = reference.profiles[device?.source];
  const type = { HELMET: 'H', BELT: 'B' }[device?.type] || device?.type;
  return profile && profile.deviceType === type && device.simulated !== true && device.demo !== true ? profile : null;
}
