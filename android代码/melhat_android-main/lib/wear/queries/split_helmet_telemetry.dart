import 'package:flutter/material.dart';
import '../core.dart';
import 'query_widgets.dart';

String splitTelemetryValue(JsonMap device, String field, {String unit = ''}) {
  final value = device[field];
  final reported = idOf(device['${field}ReportedAt']);
  if (value == null || idOf(value).isEmpty || reported.isEmpty) return '未收到';
  final freshness = idOf(device['${field}Freshness']).toUpperCase();
  final suffix = freshness == 'CURRENT' ? '' : '（历史上报）';
  return '$value$unit$suffix';
}

class SplitHelmetTelemetryPanel extends StatelessWidget {
  const SplitHelmetTelemetryPanel({super.key, required this.device});
  final JsonMap device;
  @override
  Widget build(BuildContext context) => QuerySection(
    title: '分体式安全帽状态',
    children: [
      WearCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DetailField(label: '接入类型', value: '分体式安全帽'),
            DetailField(
              label: '气压（设备原值）',
              value: splitTelemetryValue(device, 'pressure'),
            ),
            DetailField(
              label: '气压上报时间',
              value: formatTime(device['pressureReportedAt']),
            ),
            DetailField(
              label: '设备温度（设备原值）',
              value: splitTelemetryValue(device, 'temperature'),
            ),
            DetailField(
              label: '气压换算高度',
              value: splitTelemetryValue(
                device,
                'barometricAltitude',
                unit: ' m',
              ),
            ),
            const Text(
              '气压换算高度不表示离地高度。',
              style: TextStyle(color: WearColors.muted),
            ),
            DetailField(
              label: 'TF 卡状态',
              value: splitTelemetryValue(device, 'tfEnable'),
            ),
            DetailField(
              label: '已用容量（设备原值）',
              value: splitTelemetryValue(device, 'storageUsed'),
            ),
            DetailField(
              label: '可用容量（设备原值）',
              value: splitTelemetryValue(device, 'storageAvailable'),
            ),
            DetailField(
              label: '总容量（设备原值）',
              value: splitTelemetryValue(device, 'storageTotal'),
            ),
            DetailField(
              label: 'TF 卡上报时间',
              value: formatTime(device['tfEnableReportedAt']),
            ),
          ],
        ),
      ),
    ],
  );
}
