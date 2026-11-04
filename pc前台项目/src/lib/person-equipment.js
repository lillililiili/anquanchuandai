import { featureState, featureUnavailableReason } from '../../../shared/device-features.mjs';
import { isCurrentDevice, isRealDevice } from './device-telemetry.js';

const absent = reason => ({ supported: false, verified: false, available: false, reason });
export function personFeature(db, personId, key) {
  const person = db.person(personId);
  if (!person) return absent('人员不存在');
  const assigned = db.currentDevices(personId).filter(d => d.active !== false && (key !== 'voice' || d.type === 'H' && (db.demoMode || d.source === 'DIRECT_HELMET')));
  const context = db.state.personEquipmentContext?.[personId];
  const target = context?.features?.[key];
  const device = target?.deviceId ? assigned.find(d => d.id === target.deviceId) :
    assigned.find(d => featureState(d, key).supported);
  if (!device) return absent(key === 'voice' ? '未领用支持语音通话的安全帽' : '未领用支持此功能的设备');
  const declared = featureState(device, key);
  if (!declared.supported || target?.supported === false) return absent(featureUnavailableReason(target?.reason || declared.reason, key));
  const result = { ...declared, ...target, reason: featureUnavailableReason(target?.reason || declared.reason, key), personId, deviceId: device.id };
  if (person.active === false) return { ...result, available: false, reason: '人员已停用' };
  if (device.source === 'DEMO_WATCH') return { ...result, available: key === 'vitals' && db.state.businessConfig?.simulatedWatchVisible !== false, reason: '模拟数据' };
  if (!isRealDevice(device) && db.demoMode) return result;
  if (!target?.assignmentId || target.assignmentVersion == null) return { ...result, available: false, reason: '领用上下文未就绪，请刷新' };
  if (device.online !== true || !isCurrentDevice(device)) return { ...result, available: false, reason: device.online === false ? '设备离线' : '设备状态过期或未知' };
  if (key === 'voice') {
    const bindings = (db.state.bindings || []).filter(binding => !binding.end && binding.deviceId === device.id);
    const binding = bindings[0];
    if (bindings.length !== 1 || binding.personId !== personId || binding.assignmentId !== target.assignmentId || binding.assignmentVersion !== target.assignmentVersion) {
      return { ...result, available: false, reason: '领用关系已变化，请刷新' };
    }
    if (String(device.communicationProtocol).toUpperCase() !== 'SIP') return { ...result, available: false, reason: '安全帽语音配置异常，请检查 SIP 设置' };
    if (device.sipRegistered === false || !(device.voiceAvailable === true || device.sipRegistered === true || device.capabilities?.sipRegistered === true)) return { ...result, available: false, reason: '安全帽语音未注册，请检查设备网络和语音服务' };
  }
  const available = declared.available && target.available === true;
  const reason = featureUnavailableReason(target.reason || declared.reason, key);
  return { ...result, available, reason: available ? '' : reason };
}
export function personDevice(db, personId, key) {
  const feature = personFeature(db, personId, key);
  return feature.supported ? db.device(feature.deviceId) : null;
}
export function videoPeople(db, people) { return people.filter(person => person.active !== false && personFeature(db, person.id, 'video').supported); }
export function eventVideoSupported(db, event) {
  if (!event) return false;
  const device = db.device(event.deviceId);
  // A belt event has no video, even when its wearer also has a camera-equipped helmet.
  if (event.protocol === 'direct-belt' || device?.type === 'B' || device?.source === 'DIRECT_BELT') return false;
  return personFeature(db, event.personId, 'video').supported;
}
export function operationContext(feature) {
  if (!feature?.personId || !feature?.deviceId || !feature?.assignmentId || feature.assignmentVersion == null) throw Error('领用关系已变化，请刷新后重试');
  return { personId: feature.personId, deviceId: feature.deviceId, assignmentId: feature.assignmentId, assignmentVersion: feature.assignmentVersion };
}
