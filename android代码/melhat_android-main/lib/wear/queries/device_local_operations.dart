import 'dart:convert';

import 'package:flutter/material.dart';

import '../core.dart';
import '../device_report_time.dart';
import 'query_widgets.dart';

/// Only the matched real device family receives its model's local guidance.
String? localDeviceProfile(JsonMap device) {
  if (device['demo'] == true || device['simulated'] == true) return null;
  final type = device['typeCode'] ?? device['type'];
  if (device['source'] == 'DIRECT_HELMET' &&
      (type == 'helmet' || type == 'H')) {
    return 'DIRECT_HELMET';
  }
  if (device['source'] == 'DIRECT_BELT' && (type == 'belt' || type == 'B')) {
    return 'DIRECT_BELT';
  }
  return null;
}

class LocalRecordingReport extends StatelessWidget {
  const LocalRecordingReport({super.key, required this.device});

  final JsonMap device;

  @override
  Widget build(BuildContext context) {
    if (localDeviceProfile(device) != 'DIRECT_HELMET') {
      return const SizedBox.shrink();
    }
    final report = jsonMap(device['localRecording']);
    final recognizedSource =
        report['source'] == 'DIRECT_HELMET' &&
        report['reportAct'] == 'toggle_localrecord' &&
        report['timeBasis'] == 'RECEIVED_AT';
    final state = report.isEmpty
        ? '暂无上报'
        : !recognizedSource
        ? '状态未知'
        : switch ((report['state'], report['rawType'])) {
            ('RECORDING', '0') => '开启',
            ('STOPPED', '1') => '关闭',
            _ => '状态未知',
          };
    return QuerySection(
      title: '设备本地录像 · 最后上报',
      children: [
        WearCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DetailField(label: '上报状态', value: state),
              if (report.isNotEmpty) ...[
                DetailField(
                  label: '平台接收时间',
                  value: recognizedSource
                      ? deviceReportTimeLabel(report['receivedAt'])
                      : '未提供有效时间',
                ),
                if (recognizedSource)
                  DetailField(
                    label: '上报时人员',
                    value: textOf(
                      report['personName'],
                      textOf(report['personId'], '未关联人员'),
                    ),
                  ),
              ],
              const Text(
                '仅表示设备最后一次上报，不代表当前仍在录制或文件已生成；与平台录制分开。',
                style: TextStyle(color: WearColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The bundled JSON is a byte-identical mirror of shared/device-controls.json.
/// It is help content only: opening it never sends an operation to a device.
class DeviceLocalControlsHelp extends StatefulWidget {
  const DeviceLocalControlsHelp({super.key, required this.device});

  final JsonMap device;

  @override
  State<DeviceLocalControlsHelp> createState() =>
      _DeviceLocalControlsHelpState();
}

class _DeviceLocalControlsHelpState extends State<DeviceLocalControlsHelp> {
  AssetBundle? _bundle;
  Future<JsonMap>? _reference;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bundle = DefaultAssetBundle.of(context);
    if (identical(bundle, _bundle)) return;
    _bundle = bundle;
    _reference = bundle
        .loadString('assets/device-controls.json')
        .then((value) => jsonMap(jsonDecode(value)));
  }

  @override
  Widget build(BuildContext context) {
    final key = localDeviceProfile(widget.device);
    if (key == null) return const SizedBox.shrink();
    return FutureBuilder<JsonMap>(
      future: _reference,
      builder: (context, snapshot) {
        final profile = jsonMap(jsonMap(snapshot.data?['profiles'])[key]);
        if (profile.isEmpty) return const SizedBox.shrink();
        final source = jsonMap(profile['source']);
        return WearCard(
          padding: EdgeInsets.zero,
          child: ExpansionTile(
            key: ValueKey('local-controls-$key'),
            title: Text(textOf(profile['title'])),
            subtitle: const Text('设备本地操作说明'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(textOf(profile['description'])),
              for (final control in jsonList(profile['controls'])) ...[
                const Divider(height: 24),
                Text(
                  '${textOf(control['key'])} · ${textOf(control['gesture'])}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(textOf(control['deviceEffect'])),
                const SizedBox(height: 8),
                Text(
                  textOf(control['platformEffect']),
                  style: const TextStyle(color: WearColors.muted),
                ),
              ],
              const Divider(height: 24),
              Text(
                '依据：${textOf(source['document'])}，PDF 第 ${textOf(source['page'])} 页。',
                style: const TextStyle(color: WearColors.muted),
              ),
            ],
          ),
        );
      },
    );
  }
}
