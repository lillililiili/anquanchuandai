export const FEATURE_LABELS = Object.freeze({ battery: '电量', wear: '佩戴检测', hooks: '双钩状态', height: '相对高度', location: '定位', alarm: '设备告警', sos: 'SOS 求助', video: '实时视频', photo: '拍照', recording: '录像', voice: '语音对讲', broadcast: '语音播报', vitals: '生命体征' });
export const ACTION_FEATURES = Object.freeze({ video: 'video', start_video: 'video', stop_video: 'video', take_photo: 'photo', start_recording: 'recording', stop_recording: 'recording', list_recordings: 'recording', upload_recording: 'recording', intercom: 'voice', configure_sip: 'voice', tts: 'broadcast', broadcast: 'broadcast' });

// A declared protocol command is not physical acceptance evidence. Older
// servers may describe support, but only featureStates may enable an action.
export function featureState(device, key) {
  const state = device?.featureStates?.[key];
  if (state && typeof state === 'object') {
    const supported = state.supported === true;
    const verified = supported && state.verified === true;
    return { supported, verified, available: verified && state.available === true,
      reason: String(state.reason || (!supported ? '该型号不支持' : !verified ? '待联调' : state.available === true ? '' : '当前不可用')) };
  }
  const declared = device?.capabilities;
  const actions = Array.isArray(declared) ? declared : declared?.actions || [];
  const metrics = Array.isArray(declared) ? declared : declared?.metrics || [];
  const supported = actions.some(action => ACTION_FEATURES[action] === key) || metrics.includes(key);
  return { supported, verified: false, available: false, reason: supported ? '待联调' : '该型号未声明支持' };
}
export function actionFeatureState(device, action) {
  return featureState(device, ACTION_FEATURES[action] || action);
}
export function featureLabel(device, key) {
  const state = featureState(device, key);
  return `${FEATURE_LABELS[key] || key}${state.supported && !state.verified ? ' · 待联调' : ''}`;
}
export function supportedFeatures(device) {
  return Object.keys(FEATURE_LABELS).filter(key => featureState(device, key).supported);
}
