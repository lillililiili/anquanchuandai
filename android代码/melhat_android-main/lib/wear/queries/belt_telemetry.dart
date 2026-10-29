import 'package:flutter/material.dart';

import '../core.dart';
import '../device_features.dart';
import 'query_widgets.dart';

/// Display meanings only after the backend confirms the firmware's mapping.
class BeltTelemetryView {
  BeltTelemetryView(this.device, {DateTime? now}) : now = now ?? DateTime.now();

  final JsonMap device;
  final DateTime now;

  String get reportedAt => idOf(device['telemetryReportedAt']);

  bool get current {
    final observed = DateTime.tryParse(reportedAt);
    final age = observed == null ? null : now.difference(observed);
    return device['source'] == 'DIRECT_BELT' &&
        idOf(device['telemetryFreshness']).toUpperCase() == 'CURRENT' &&
        age != null &&
        !age.isNegative &&
        age <= const Duration(minutes: 5);
  }

  String get freshness => current
      ? '近期上报'
      : reportedAt.isEmpty
      ? '尚未收到状态上报'
      : '最后上报（当前状态未知）';

  String raw(String key) {
    final value = device[key];
    return value == null || value.toString().isEmpty
        ? '尚未上报'
        : value.toString();
  }

  String state(String key, String mapping, String yes, String no) {
    if (!current) return '未知（暂无最新上报）';
    if (device[mapping] != true) return '待确认';
    return device[key] == true
        ? yes
        : device[key] == false
        ? no
        : '待确认';
  }

  String get worn => state('worn', 'wearMappingConfirmed', '已佩戴', '未佩戴');
  String get hookA =>
      state('hookAEngaged', 'hookMappingConfirmed', '已挂扣', '未挂扣');
  String get hookB =>
      state('hookBEngaged', 'hookMappingConfirmed', '已挂扣', '未挂扣');
}

class BeltTelemetryPanel extends StatelessWidget {
  const BeltTelemetryPanel({super.key, required this.device});

  final JsonMap device;

  @override
  Widget build(BuildContext context) {
    final view = BeltTelemetryView(device);
    return WearCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('安全带上报', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (deviceFeature(device, 'wear').supported) ...[
            DetailField(
              label: deviceFeatureLabel(device, 'wear', '佩戴状态'),
              value: deviceFeature(device, 'wear').verified ? view.worn : '待联调',
            ),
            DetailField(label: '佩戴原始值', value: view.raw('isWeared')),
          ],
          if (deviceFeature(device, 'hooks').supported) ...[
            DetailField(
              label: deviceFeatureLabel(device, 'hooks', 'A 挂钩'),
              value: deviceFeature(device, 'hooks').verified
                  ? view.hookA
                  : '待联调',
            ),
            DetailField(label: 'A 原始值', value: view.raw('hangerAStatus')),
            DetailField(
              label: deviceFeatureLabel(device, 'hooks', 'B 挂钩'),
              value: deviceFeature(device, 'hooks').verified
                  ? view.hookB
                  : '待联调',
            ),
            DetailField(label: 'B 原始值', value: view.raw('hangerBStatus')),
          ],
          if (deviceFeature(device, 'height').supported)
            DetailField(
              label: deviceFeatureLabel(device, 'height'),
              value: !deviceFeature(device, 'height').verified
                  ? '待联调'
                  : view.current && device['relativeAltitude'] != null
                  ? '${device['relativeAltitude']} m'
                  : '暂无最新上报',
            ),
          DetailField(label: '状态新鲜度', value: view.freshness),
          DetailField(
            label: '状态上报时间',
            value: view.reportedAt.isEmpty
                ? '尚未上报'
                : formatTime(view.reportedAt),
          ),
          const Text(
            '原始值来自设备上报。状态含义未确认时显示待确认，陈旧读数不代表当前状态。',
            style: TextStyle(color: WearColors.muted),
          ),
        ],
      ),
    );
  }
}
