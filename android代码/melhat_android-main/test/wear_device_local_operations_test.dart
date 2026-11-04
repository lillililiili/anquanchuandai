import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/device_local_operations.dart';
import 'package:rolling_intelligence_headband/wear/shared_models.dart';

class _ReferenceBundle extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      SynchronousFuture(File(key).readAsStringSync());

  @override
  Future<ByteData> load(String key) =>
      SynchronousFuture(ByteData.sublistView(File(key).readAsBytesSync()));
}

void main() {
  JsonMap report([JsonMap changes = const {}]) => {
    'state': 'RECORDING',
    'rawType': '0',
    'source': 'DIRECT_HELMET',
    'reportAct': 'toggle_localrecord',
    'receivedAt': '2026-10-01T01:02:03Z',
    'timeBasis': 'RECEIVED_AT',
    'personId': 'original-person',
    'personName': '上报时人员甲',
    'siteId': 'original-site',
    'bindingId': 'original-binding',
    ...changes,
  };

  JsonMap helmet([JsonMap changes = const {}]) => {
    'id': 'h',
    'type': 'H',
    'source': 'DIRECT_HELMET',
    'online': false,
    'sourceTime': '2026-11-02T05:06:07Z',
    'currentAssignment': {'personName': '当前人员乙'},
    ...changes,
  };

  Future<void> mountReport(WidgetTester tester, JsonMap device) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LocalRecordingReport(device: device),
          ),
        ),
      ),
    );
  }

  test('packaged button reference exactly matches the shared source', () {
    final project = Directory(Directory.current.resolveSymbolicLinksSync());
    final shared = File(
      '${project.parent.parent.path}/shared/device-controls.json',
    ).readAsBytesSync();
    final bundled = File('assets/device-controls.json').readAsBytesSync();
    expect(bundled, orderedEquals(shared));
  });

  testWidgets('offline report retains original person and receive time', (
    tester,
  ) async {
    final original = report();
    final projected = SharedModels(
      {},
    ).device(helmet({'localRecording': original}));
    expect(projected['localRecording'], original);
    await mountReport(tester, projected);
    expect(find.text('开启'), findsOneWidget);
    expect(find.text('上报时人员甲'), findsOneWidget);
    expect(find.text('当前人员乙'), findsNothing);
    expect(find.text(formatTime(original['receivedAt'])), findsOneWidget);
    expect(find.text(formatTime(projected['sourceTime'])), findsNothing);
    expect(find.textContaining('不代表当前仍在录制或文件已生成'), findsOneWidget);
    await mountReport(tester, {
      ...projected,
      'localRecording': report({'state': 'STOPPED', 'rawType': '1'}),
    });
    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('开启'), findsNothing);
  });

  testWidgets('no report remains unknown instead of defaulting to stopped', (
    tester,
  ) async {
    await mountReport(tester, helmet());
    expect(find.text('暂无上报'), findsOneWidget);
    expect(find.text('关闭'), findsNothing);
    expect(find.text('平台接收时间'), findsNothing);
    expect(find.textContaining('当前人员乙'), findsNothing);
  });

  testWidgets('unknown or conflicting protocol fields never imply recording', (
    tester,
  ) async {
    for (final mismatch in <JsonMap>[
      {'state': 'FUTURE_STATE'},
      {'rawType': '9'},
      {'rawType': '1'},
      {'rawType': 0},
      {'source': 'DIRECT_BELT'},
      {'reportAct': 'heartbeat'},
      {'timeBasis': 'DEVICE_TIME'},
    ]) {
      await mountReport(tester, helmet({'localRecording': report(mismatch)}));
      expect(find.text('状态未知'), findsOneWidget, reason: '$mismatch');
      expect(find.text('开启'), findsNothing);
      expect(find.text('关闭'), findsNothing);
      if (mismatch.containsKey('source') ||
          mismatch.containsKey('reportAct') ||
          mismatch.containsKey('timeBasis')) {
        expect(find.text('未提供有效时间'), findsOneWidget);
        expect(find.text('上报时人员甲'), findsNothing);
      }
    }
  });

  testWidgets(
    'missing receive time and ownership are never filled from device',
    (tester) async {
      await mountReport(
        tester,
        helmet({
          'localRecording': report({
            'receivedAt': null,
            'personName': null,
            'personId': null,
          }),
        }),
      );
      expect(find.text('未提供有效时间'), findsOneWidget);
      expect(find.text('未关联人员'), findsOneWidget);
      expect(find.text('当前人员乙'), findsNothing);
    },
  );

  testWidgets('receipt requires an actual ISO time with explicit timezone', (
    tester,
  ) async {
    for (final value in [
      'not-a-date',
      '2026-10-01',
      '2026-10-01T01:02:03',
      '2026-02-31T01:02:03Z',
      '2026-10-01T25:02:03Z',
      '2026-10-01T01:02:03+99:00',
    ]) {
      await mountReport(
        tester,
        helmet({
          'localRecording': report({'receivedAt': value}),
        }),
      );
      expect(find.text('未提供有效时间'), findsOneWidget, reason: value);
    }
    const offsetTime = '2026-10-01T09:02:03+08:00';
    await mountReport(
      tester,
      helmet({
        'localRecording': report({'receivedAt': offsetTime}),
      }),
    );
    expect(find.text(formatTime(offsetTime)), findsOneWidget);
  });

  testWidgets('belt watch mismatched and demo sources hide helmet recording', (
    tester,
  ) async {
    for (final changes in <JsonMap>[
      {'source': 'DIRECT_BELT', 'type': 'B'},
      {'source': 'SIMULATED', 'type': 'W'},
      {'typeCode': 'belt'},
      {'demo': true},
      {'simulated': true},
    ]) {
      await mountReport(
        tester,
        helmet({...changes, 'localRecording': report()}),
      );
      expect(find.text('设备本地录像 · 最后上报'), findsNothing);
      expect(find.text('开启'), findsNothing);
    }
  });

  testWidgets('model help is collapsed, read-only and limited to real family', (
    tester,
  ) async {
    Future<void> mount(JsonMap device) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DefaultAssetBundle(
                bundle: _ReferenceBundle(),
                child: DeviceLocalControlsHelp(device: device),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await mount(helmet());
    expect(find.text('RD-D1+ 安全帽按键参考'), findsOneWidget);
    expect(find.textContaining('长按 3 秒'), findsNothing);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.textContaining('长按 3 秒'), findsOneWidget);
    expect(find.textContaining('不是远程控制'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);

    await mount({'source': 'DIRECT_BELT', 'type': 'B'});
    expect(find.text('RD-1102 智能挂钩按键参考'), findsOneWidget);
    expect(find.textContaining('长按 3 秒'), findsNothing);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.textContaining('近电选配尚未确认'), findsOneWidget);
    expect(find.textContaining('当前安全带仅支持求助上报'), findsOneWidget);
    expect(find.textContaining('语音通话请使用已领用且在线的安全帽'), findsOneWidget);

    await mount({'source': 'DIRECT_HELMET', 'type': 'W'});
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets(
    'recording report and help wrap at phone widths with large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final size in [const Size(375, 812), const Size(812, 375)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        LocalRecordingReport(
                          device: helmet({'localRecording': report()}),
                        ),
                        DefaultAssetBundle(
                          bundle: _ReferenceBundle(),
                          child: DeviceLocalControlsHelp(device: helmet()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(ExpansionTile));
        await tester.tap(find.byType(ExpansionTile));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
