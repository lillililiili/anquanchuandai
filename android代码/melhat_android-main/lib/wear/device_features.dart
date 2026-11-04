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
    this.integrationStatus = '',
  });
  final bool supported, verified, available;
  final String reason;
  final String integrationStatus;
  JsonMap toJson() => {
    'supported': supported,
    'verified': verified,
    'available': available,
    'reason': reason,
    'integrationStatus': integrationStatus,
  };
}

const _runtimeHelmetFeatures = {
  'voice',
  'video',
  'videoCall',
  'photo',
  'recording',
  'broadcast',
};

String _unavailableReason(JsonMap device, String key, bool supported) {
  if (!supported) return '该型号不支持此功能';
  if (device['active'] == false) return '设备已停用';
  if (const [false, 0, 'offline'].contains(device['online'])) return '设备离线';
  if (device['connectionQuality'] == 'stale') return '设备状态已过期，请刷新';
  if (key == 'voice' || key == 'videoCall') return '通话服务不可用，请检查设备连接';
  return '${deviceFeatureLabels[key] ?? '设备功能'}当前不可用，请刷新设备状态';
}

/// The backend establishes runtime availability. A recorded manual acceptance
/// result must not disable an operational direct-helmet service.
DeviceFeatureState deviceFeature(JsonMap device, String key) {
  if (device['source'] == 'DIRECT_BELT' &&
      _runtimeHelmetFeatures.contains(key)) {
    return const DeviceFeatureState(
      supported: false,
      verified: false,
      available: false,
      reason: '安全带不支持此功能，请使用已领用且在线的安全帽',
    );
  }
  final raw = jsonMap(jsonMap(device['featureStates'])[key]);
  if (raw.isNotEmpty) {
    final supported = raw['supported'] == true;
    final verified = supported && raw['verified'] == true;
    final runtimeReady =
        device['source'] == 'DIRECT_HELMET' &&
        raw['integrationStatus'] == 'CONNECTED' &&
        _runtimeHelmetFeatures.contains(key);
    final available =
        supported && (verified || runtimeReady) && raw['available'] == true;
    final reason = textOf(raw['reason'], '');
    final obsolete = RegExp('待联调|待接入|尚未接入|未接入|尚未部署|未部署').hasMatch(reason);
    return DeviceFeatureState(
      supported: supported,
      verified: verified,
      available: available,
      integrationStatus: textOf(raw['integrationStatus'], ''),
      reason: available
          ? ''
          : reason.isNotEmpty && !obsolete
          ? reason
          : _unavailableReason(device, key, supported),
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
    reason: _unavailableReason(device, key, supported),
  );
}

DeviceFeatureState actionFeature(JsonMap device, String action) =>
    deviceFeature(device, actionFeatures[action] ?? action);

String deviceFeatureLabel(JsonMap device, String key, [String? label]) {
  return label ?? deviceFeatureLabels[key] ?? key;
}
