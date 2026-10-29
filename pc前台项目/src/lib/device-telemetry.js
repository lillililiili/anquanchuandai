import { actionFeatureState } from '../../../shared/device-features.mjs';
const REAL_SOURCES = new Set(["PLATFORM", "DIRECT_HELMET", "DIRECT_BELT"]);

export function isRealDevice(device) {
  return REAL_SOURCES.has(device?.source);
}

export function isCurrentDevice(device, now = Date.now()) {
  const observed = Date.parse(device?.sourceTime || device?.updated || "");
  const age = now - observed;
  return isRealDevice(device) && String(device.freshness).toUpperCase() === "CURRENT" &&
    Number.isFinite(observed) && age >= 0 && age <= 300000;
}

export function hasCurrentLocation(device, now = Date.now()) {
  const observed = Date.parse(device?.locationReportedAt || "");
  const age = now - observed;
  return isCurrentDevice(device, now) && device.online === true &&
    String(device.locationFreshness).toUpperCase() === "CURRENT" &&
    Number.isFinite(observed) && age >= 0 && age <= 300000;
}

export function projectDevice(device, now = Date.now()) {
  if (!device || !isRealDevice(device)) return device;
  const current = isCurrentDevice(device, now);
  const rawBattery = device.battery;
  const battery = rawBattery == null || rawBattery === "" ? NaN : Number(rawBattery);
  const fieldCurrent = field => current && (device.source !== 'DIRECT_HELMET' && device[`${field}Freshness`] == null || device[`${field}Freshness`] === 'CURRENT');
  return {
    ...device,
    sn: device.sn || device.deviceNumber || device.id,
    online: device.online === false ? false : current && device.online === true ? true : null,
    battery: fieldCurrent('battery') && Number.isFinite(battery) && battery >= 0 && battery <= 100 ? battery : null,
    worn: fieldCurrent('isWeared') && typeof device.worn === "boolean" ? device.worn : null,
    hookAEngaged: current && typeof device.hookAEngaged === "boolean" ? device.hookAEngaged : null,
    hookBEngaged: current && typeof device.hookBEngaged === "boolean" ? device.hookBEngaged : null,
    // Availability comes from a separately authorized live-media response.
    video: "unavailable",
  };
}

export function deviceActions(device) {
  const declared = device?.capabilities;
  const actions = Array.isArray(declared) ? declared : declared?.actions;
  return Array.isArray(actions) ? actions : [];
}

export function supportsDeviceAction(device, action) {
  if (!isCurrentDevice(device) || device.online !== true || device.active === false || device.type !== "H") return false;
  if (!actionFeatureState(device, action).available) return false;
  if (!deviceActions(device).includes(action)) return false;
  if (action === "intercom") {
    const protocol = String(device.communicationProtocol || "").toUpperCase();
    return protocol === "AGORA" || protocol === "SIP" || (!protocol && device.source === "PLATFORM");
  }
  return ["tts", "video", "take_photo", "start_recording", "stop_recording", "start_video", "stop_video", "list_recordings", "upload_recording", "set_config"].includes(action);
}

export function deviceStatus(device) {
  if (!device) return "未绑定";
  if (device.type === 'W' && device.source === 'DEMO_WATCH') return "模拟数据";
  if (device.online === false) return "离线";
  if (isRealDevice(device) && !isCurrentDevice(device)) {
    return String(device.freshness).toUpperCase() === "STALE" ? "数据陈旧" : "待刷新";
  }
  if (device.online == null) return "状态未知";
  return device.online ? "在线" : "离线";
}

export function deviceStatusTone(device) {
  const status = deviceStatus(device);
  return status === "在线" ? "green" : status === "离线" ? "red" : "yellow";
}
