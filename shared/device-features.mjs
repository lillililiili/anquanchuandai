export const FEATURE_LABELS = Object.freeze({ battery: '电量', wear: '佩戴检测', hooks: '双钩状态', height: '相对高度', location: '定位', alarm: '设备告警', sos: 'SOS 求助', video: '实时视频', photo: '拍照', recording: '录像', voice: '语音对讲', broadcast: '语音播报', vitals: '生命体征' });
export const ACTION_FEATURES = Object.freeze({ video: 'video', start_video: 'video', stop_video: 'video', take_photo: 'photo', start_recording: 'recording', stop_recording: 'recording', list_recordings: 'recording', upload_recording: 'recording', intercom: 'voice', configure_sip: 'voice', tts: 'broadcast', broadcast: 'broadcast' });

const LIVE_HELMET_FEATURES = new Set(['video', 'videoCall', 'photo', 'recording', 'voice', 'broadcast']);
const FEATURE_RECOVERY = Object.freeze({
  voice: '语音服务不可用，请检查设备注册和服务连接',
  videoCall: '视频通话不可用，请检查设备注册和服务连接',
  video: '视频服务不可用，请检查设备网络和媒体服务',
  photo: '拍照服务不可用，请检查设备网络和媒体服务',
  recording: '录像服务不可用，请检查设备网络和媒体服务',
  broadcast: '语音播报不可用，请检查设备网络和播报服务',
  location: '暂无有效定位数据，请检查设备定位状态',
});

// Older service versions can still return generic implementation placeholders.
// Keep availability unchanged and give the user a recovery path, never success.
export function featureUnavailableReason(reason, key = '') {
  const text = String(reason || '');
  if (text && !/待联调|(?:尚未|暂未|未|待)接入|(?:尚未|未)部署/.test(text)) return text;
  if (text.includes('离线')) return '设备离线，请检查设备网络';
  return FEATURE_RECOVERY[key] || '暂无有效设备数据，请检查设备连接';
}

// Actual command readiness comes from the server's per-device runtime checks.
// Physical acceptance remains separate evidence, not a second client-side gate.
export function featureState(device, key) {
  const state = device?.featureStates?.[key];
  if (state && typeof state === 'object') {
    const supported = state.supported === true;
    const verified = supported && state.verified === true;
    const liveCommand = LIVE_HELMET_FEATURES.has(key) && device.source === 'DIRECT_HELMET' && ['H', 'HELMET'].includes(device.type) &&
      state.integrationStatus === 'CONNECTED' && (!['voice', 'videoCall'].includes(key) || String(device.communicationProtocol).toUpperCase() === 'SIP');
    const available = supported && (verified || liveCommand) && state.available === true;
    const reason = !supported ? state.reason || '该型号不支持' : state.reason;
    return { supported, verified, available, reason: available ? '' : featureUnavailableReason(reason, key) };
  }
  const declared = device?.capabilities;
  const actions = Array.isArray(declared) ? declared : declared?.actions || [];
  const metrics = Array.isArray(declared) ? declared : declared?.metrics || [];
  const supported = actions.some(action => ACTION_FEATURES[action] === key) || metrics.includes(key);
  return { supported, verified: false, available: false, reason: supported ? featureUnavailableReason('', key) : '该型号未声明支持' };
}
export function actionFeatureState(device, action) {
  return featureState(device, ACTION_FEATURES[action] || action);
}
export function featureLabel(device, key) {
  return FEATURE_LABELS[key] || key;
}
export function supportedFeatures(device) {
  return Object.keys(FEATURE_LABELS).filter(key => featureState(device, key).supported);
}
