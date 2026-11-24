import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/devices.dart';
import 'package:rolling_intelligence_headband/wear/shared_models.dart';
import 'wear_session_test.dart' show MemoryCredentials;

void main() {
  for (final source in ['DIRECT_HELMET', 'SPLIT_HELMET']) {
    testWidgets(
      '$source details show read-only assignment history without media or controls',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(400, 2200);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        const history = [
          {
            'personId': 'p1',
            'personName': '当前领用人',
            'issuedAt': '2026-10-27T08:00:00Z',
          },
          {
            'personId': 'p2',
            'personName': '前次领用人',
            'issuedAt': '2026-10-25T08:00:00Z',
            'returnedAt': '2026-10-26T08:00:00Z',
          },
        ];
        await mount(tester, {
          'source': source,
          'typeCode': 'helmet',
          'featureStates': {
            for (final key in [
              'photo',
              'video',
              'recording',
              'voice',
              'broadcast',
              'videoCall',
            ])
              key: {'supported': true, 'verified': true, 'available': true},
          },
        }, history: history);
        expect(find.text('产品型号'), findsOneWidget);
        if (source == 'SPLIT_HELMET') {
          expect(find.text('分体式安全帽状态'), findsOneWidget);
        }
        for (final label in ['设备本地录像 · 最后上报', '安全帽影像', '设备能力', '实时观看', '对讲']) {
          expect(find.text(label), findsNothing);
        }
        expect(find.text('历史领用记录（2）'), findsOneWidget);
        for (final record in history) {
          final name = find.text(record['personName']!);
          final end = record['returnedAt'];
          expect(
            find.text(
              '${formatTime(record['issuedAt'])} 至 ${end == null ? '当前' : formatTime(end)}',
            ),
            findsOneWidget,
          );
          final row = find.ancestor(of: name, matching: find.byType(ListTile));
          expect(tester.widget<ListTile>(row).trailing, isNull);
          expect(tester.semantics.find(name), isSemantics(hasTapAction: false));
          await tester.tap(name);
          await tester.pumpAndSettle();
          expect(find.byType(DevicePage), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'belt details omit voice controls without a supported call path',
    (tester) async {
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
      await tester.scrollUntilVisible(find.text('历史领用记录（0）'), 300);
      expect(find.text('对讲'), findsNothing);
      expect(find.textContaining('实时观看'), findsNothing);
      expect(find.textContaining('拍照'), findsNothing);
      expect(find.textContaining('视频通话'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> mount(
  WidgetTester tester,
  JsonMap device, {
  List<JsonMap> history = const [],
}) async {
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
                  ? history
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
