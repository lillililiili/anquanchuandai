import 'data.dart';

const deviceFeatureLabels = <String, String>{
  'battery': '电量',
  'wear': '佩戴检测',
  'hooks': '双钩状态',
  'height': '相对高度',
  'location': '定位',
  'alarm': '设备告警',
  'sos': 'SOS 求助',
  'video': '实时视频',
  'videoCall': '视频通话',
  'photo': '拍照',
  'recording': '录像',
  'voice': '语音对讲',
  'broadcast': '语音播报',
  'vitals': '生命体征',
};

const actionFeatures = <String, String>{
  'video': 'video',
  'video_call': 'videoCall',
  'start_video': 'video',
  'stop_video': 'video',
  'take_photo': 'photo',
  'start_recording': 'recording',
  'stop_recording': 'recording',
  'list_recordings': 'recording',
  'upload_recording': 'recording',
  'intercom': 'voice',
  'configure_sip': 'voice',
  'tts': 'broadcast',
  'broadcast': 'broadcast',
};

class DeviceFeatureState {
  const DeviceFeatureState({
    required this.supported,
    required this.verified,
    required this.available,
    required this.reason,
  });
  final bool supported, verified, available;
  final String reason;
  JsonMap toJson() => {
    'supported': supported,
    'verified': verified,
    'available': available,
    'reason': reason,
  };
}

/// Device declarations establish support only. Acceptance and availability
/// must be supplied by the shared backend, never inferred from a button name.
DeviceFeatureState deviceFeature(JsonMap device, String key) {
  final raw = jsonMap(jsonMap(device['featureStates'])[key]);
  if (raw.isNotEmpty) {
    final supported = raw['supported'] == true;
    final verified = supported && raw['verified'] == true;
    final available = verified && raw['available'] == true;
    return DeviceFeatureState(
      supported: supported,
      verified: verified,
      available: available,
      reason: textOf(
        raw['reason'],
        !supported
            ? '该型号不支持'
            : !verified
            ? '待联调'
            : available
            ? ''
            : '当前不可用',
      ),
    );
  }
  final declared = device['capabilities'];
  final actions = declared is List
      ? declared
      : jsonMap(declared)['actions'] as List? ?? const [];
  final metrics = declared is List
      ? declared
      : jsonMap(declared)['metrics'] as List? ?? const [];
  final supported =
      actions.any((action) => actionFeatures[idOf(action)] == key) ||
      metrics.contains(key);
  return DeviceFeatureState(
    supported: supported,
    verified: false,
    available: false,
    reason: supported ? '待联调' : '该型号未声明支持',
  );
}

DeviceFeatureState actionFeature(JsonMap device, String action) =>
    deviceFeature(device, actionFeatures[action] ?? action);

String deviceFeatureLabel(JsonMap device, String key, [String? label]) {
  final feature = deviceFeature(device, key);
  final pending = feature.reason == '待接入' ? '待接入' : '待联调';
  return '${label ?? deviceFeatureLabels[key] ?? key}${feature.supported && !feature.verified ? ' · $pending' : ''}';
}
