import { normalizeMedia } from './media-presentation.js';

export function mergeDeviceMedia(current, deviceId, items, station) {
  const incoming = (Array.isArray(items) ? items : [])
    .filter(item => item?.id && item.deviceId === deviceId && ['photo', 'video'].includes(String(item.kind).toLowerCase()))
    .map(item => normalizeMedia(item, station));
  return [...current.filter(item => item.deviceId !== deviceId), ...incoming];
}
