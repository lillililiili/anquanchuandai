import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/devices.dart';
import 'package:rolling_intelligence_headband/wear/shared_models.dart';
import 'wear_session_test.dart' show MemoryCredentials;

void main() {
  testWidgets('live support does not create a two-way video call entry', (
    tester,
  ) async {
    await mount(tester, {
      'typeCode': 'helmet',
      'featureStates': {
        'video': {'supported': true, 'verified': true, 'available': true},
        'videoCall': {
          'supported': false,
          'verified': false,
          'available': false,
        },
      },
    });
    await tester.scrollUntilVisible(find.text('历史领用记录（0）'), 300);
    expect(find.text('视频通话'), findsNothing);
    expect(find.text('设备能力'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('belt voice keeps the backend pending-integration reason', (
    tester,
  ) async {
    final belt = SharedModels({}).device({
      'id': 'h',
      'type': 'B',
      'source': 'DIRECT_BELT',
      'featureStates': {
        'voice': {
          'supported': true,
          'verified': false,
          'available': false,
          'reason': '待接入',
        },
      },
    });
    await mount(tester, belt);
    await tester.scrollUntilVisible(find.text('对讲 · 待接入'), 300);
    expect(find.text('对讲 · 待联调'), findsNothing);
    expect(find.textContaining('实时观看'), findsNothing);
    expect(find.textContaining('拍照'), findsNothing);
    expect(find.textContaining('视频通话'), findsNothing);
    final button = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('对讲 · 待接入'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(button.onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> mount(WidgetTester tester, JsonMap device) async {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (request, handler) {
        expect(
          request.path,
          isIn(['/api/v1/devices/h', '/api/v1/devices/h/assignments']),
        );
        handler.resolve(
          Response(
            requestOptions: request,
            statusCode: 200,
            data: {
              'code': 200,
              'data': request.path.endsWith('/assignments')
                  ? []
                  : {'id': 'h', 'sn': 'DEVICE', ...device},
            },
          ),
        );
      },
    ),
  );
  // A local view-contract fixture, never a request against the daily database.
  final session =
      WearSession(dio: dio, mock: true, credentials: MemoryCredentials())
        ..token = 'test-token'
        ..siteId = '1'
        ..me = {
          'userId': '99',
          'roles': ['wear_platform_admin'],
        };
  addTearDown(session.dispose);
  await tester.pumpWidget(
    WearScope(
      session: session,
      child: const MaterialApp(home: DevicePage(id: 'h')),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text(device['sn']?.toString() ?? 'DEVICE'), findsOneWidget);
}
