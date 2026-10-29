import { featureState } from '../../../shared/device-features.mjs';
import { isCurrentDevice, isRealDevice } from './device-telemetry.js';

const absent = reason => ({ supported: false, verified: false, available: false, reason });
export function personFeature(db, personId, key) {
  const person = db.person(personId);
  if (!person) return absent('人员不存在');
  const assigned = db.currentDevices(personId).filter(d => d.active !== false);
  const context = db.state.personEquipmentContext?.[personId];
  const target = context?.features?.[key];
  const device = target?.deviceId ? assigned.find(d => d.id === target.deviceId) :
    assigned.find(d => featureState(d, key).supported);
  if (!device) return absent('未领用支持此功能的设备');
  const declared = featureState(device, key);
  if (!declared.supported || target?.supported === false) return absent(target?.reason || declared.reason);
  const result = { ...declared, ...target, personId, deviceId: device.id };
  if (person.active === false) return { ...result, available: false, reason: '人员已停用' };
  if (device.source === 'DEMO_WATCH') return { ...result, available: key === 'vitals' && db.state.businessConfig?.simulatedWatchVisible !== false, reason: '模拟数据' };
  if (!isRealDevice(device) && db.demoMode) return result;
  if (!target?.assignmentId || target.assignmentVersion == null) return { ...result, available: false, reason: '领用上下文未就绪，请刷新' };
  if (device.online !== true || !isCurrentDevice(device)) return { ...result, available: false, reason: device.online === false ? '设备离线' : '设备状态过期或未知' };
  return { ...result, available: declared.available && target.available === true, reason: target.reason || declared.reason };
}
export function personDevice(db, personId, key) {
  const feature = personFeature(db, personId, key);
  return feature.supported ? db.device(feature.deviceId) : null;
}
export function videoPeople(db, people) { return people.filter(person => person.active !== false && personFeature(db, person.id, 'video').supported); }
export function operationContext(feature) {
  if (!feature?.personId || !feature?.deviceId || !feature?.assignmentId || feature.assignmentVersion == null) throw Error('领用关系已变化，请刷新后重试');
  return { personId: feature.personId, deviceId: feature.deviceId, assignmentId: feature.assignmentId, assignmentVersion: feature.assignmentVersion };
}
