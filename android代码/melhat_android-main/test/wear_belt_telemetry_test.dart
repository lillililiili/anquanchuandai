import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/queries/belt_telemetry.dart';

void main() {
  final now = DateTime.parse('2026-10-26T03:00:00Z');
  final report = <String, dynamic>{
    'source': 'DIRECT_BELT',
    'featureStates': {
      'wear': {'supported': true, 'verified': true, 'available': true},
      'hooks': {'supported': true, 'verified': true, 'available': true},
    },
    'telemetryFreshness': 'CURRENT',
    'telemetryReportedAt': '2026-10-26T02:59:50Z',
    'wearMappingConfirmed': true,
    'hookMappingConfirmed': true,
    'worn': true,
    'hookAEngaged': true,
    'hookBEngaged': false,
    'isWeared': '1',
    'hangerAStatus': '1',
    'hangerBStatus': '0',
  };

  test('unknown mappings retain raw values without inferring safety', () {
    final view = BeltTelemetryView({
      ...report,
      'wearMappingConfirmed': false,
      'hookMappingConfirmed': false,
      'hangerAStatus': '-1',
    }, now: now);
    expect(view.worn, '待确认');
    expect(view.hookA, '待确认');
    expect(view.hookB, '待确认');
    expect(view.raw('hangerAStatus'), '-1');
    expect(view.raw('hangerBStatus'), '0');
  });

  test(
    'stale, future and missing report times never show a current safe state',
    () {
      for (final patch in [
        {'telemetryFreshness': 'STALE'},
        {'telemetryReportedAt': '2026-10-26T02:54:00Z'},
        {'telemetryReportedAt': '2026-10-26T03:00:01Z'},
        {'telemetryReportedAt': null},
      ]) {
        final view = BeltTelemetryView({...report, ...patch}, now: now);
        expect(view.current, false);
        expect(view.worn, startsWith('未知'));
        expect(view.hookA, startsWith('未知'));
        expect(view.raw('isWeared'), '1');
      }
    },
  );

  test('fresh confirmed values preserve different hook states', () {
    final view = BeltTelemetryView(report, now: now);
    expect(view.worn, '已佩戴');
    expect(view.hookA, '已挂扣');
    expect(view.hookB, '未挂扣');
    expect(view.freshness, '近期上报');
  });

  testWidgets(
    'unassigned belt details expose all three raw states on a narrow large-text screen',
    (tester) async {
      tester.view.physicalSize = const Size(375, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: BeltTelemetryPanel(
                  device: {
                    ...report,
                    'currentAssignment': null,
                    'wearMappingConfirmed': false,
                    'hookMappingConfirmed': false,
                    'telemetryReportedAt': DateTime.now()
                        .toUtc()
                        .toIso8601String(),
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('佩戴状态'), findsOneWidget);
      expect(find.text('A 挂钩'), findsOneWidget);
      expect(find.text('B 挂钩'), findsOneWidget);
      expect(find.text('待确认'), findsNWidgets(3));
      expect(find.text('1'), findsNWidgets(2));
      expect(find.text('0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
