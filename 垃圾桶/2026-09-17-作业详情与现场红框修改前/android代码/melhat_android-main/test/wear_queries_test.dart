import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/query_utils.dart';
import 'package:rolling_intelligence_headband/wear/queries/supervision.dart';
import 'package:rolling_intelligence_headband/wear/queries/workbench.dart';

void main() {
  test('unknown and stale device state are not presented as normal', () {
    expect(
      connectionLabel({'connectionQuality': null, 'online': null}),
      '状态未知',
    );
    expect(
      connectionLabel({'connectionQuality': 'stale', 'online': '1'}),
      '数据陈旧',
    );
    expect(
      connectionLabel({'connectionQuality': 'ok', 'online': null}),
      '状态未知',
    );
    expect(batteryLabel(null), '未知');
  });

  test('device actions come only from declared model capabilities', () {
    expect(deviceActions({'typeCode': 'helmet'}), isEmpty);
    expect(
      deviceActions({
        'typeCode': 'belt',
        'capabilities': {
          'actions': ['tts', 'intercom'],
        },
      }),
      ['tts', 'intercom'],
    );
  });

  test('nearest seek selects the closest server timestamp', () {
    final points = [
      {'occurredAt': '2026-09-10T01:00:00Z'},
      {'occurredAt': '2026-09-10T01:03:00Z'},
      {'occurredAt': '2026-09-10T01:08:00Z'},
    ];
    expect(
      nearestPointIndex(points, DateTime.parse('2026-09-10T01:05:00Z')),
      1,
    );
  });

  test('communications deep link carries stable ids', () {
    expect(
      communicationUri(deviceId: '42', personId: '7').toString(),
      '/communications?deviceId=42&personId=7',
    );
  });

  test('task status grouping is deterministic', () {
    expect(taskGroup('in_progress'), '进行中');
    expect(taskGroup('paused'), '进行中');
    expect(taskGroup('ready'), '待开始');
    expect(taskGroup('ended'), '已结束');
  });

  test('lost supervision aggregates distinct people across active tasks', () {
    final result = aggregateLostSupervision(
      [
        {'id': '11', 'title': '东区巡检'},
        {'id': '12', 'title': '高处作业'},
      ],
      {
        '11': [
          {
            'personId': '7',
            'personName': '张三',
            'typeCode': 'helmet',
            'result': 'missing',
          },
          {
            'personId': '8',
            'personName': '李四',
            'typeCode': 'belt',
            'result': 'unknown',
          },
        ],
        '12': [
          {
            'personId': '7',
            'personName': '张三',
            'typeCode': 'helmet',
            'result': 'unknown',
          },
        ],
      },
    );

    expect(result, hasLength(1));
    expect(result.single['personId'], '7');
    expect(jsonList(result.single['tasks']), hasLength(2));
  });

  test('recent event codes have Chinese presentation labels', () {
    expect(eventTypeLabel('geofence'), '围栏告警');
    expect(eventStatusLabel('pending_review'), '待复核');
    expect(eventTypeLabel('new_server_code'), '未知事件');
  });

  testWidgets('workbench presents authoritative duty counts', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.path, '/api/v1/duty/summary');
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'code': 200,
                'msg': 'ok',
                'data': {
                  'unclaimed': 17,
                  'mine': 4,
                  'overdue': 3,
                  'lostSupervision': 2,
                  'peopleCount': 61,
                  'deviceCount': 49,
                  'activeTasks': const [],
                  'recentEvents': [
                    {'id': '8', 'type': 'sos', 'status': 'open'},
                  ],
                },
              },
            ),
          );
        },
      ),
    );
    final session = WearSession(dio: dio, credentials: _MemoryCredentials())
      ..token = 'token'
      ..siteId = '1'
      ..me = {
        'userId': '7',
        'authorizedSites': [
          {'id': '1', 'name': '一号厂站'},
        ],
      };
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: WearScope(session: session, child: const WorkbenchPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('17'), findsOneWidget);
    expect(find.text('待认领事件'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.text('61'), findsOneWidget);
    expect(find.text('49'), findsOneWidget);
    expect(find.text('已领用人员'), findsOneWidget);
    expect(find.text('在用装备'), findsOneWidget);
    expect(find.text('近期未关闭事件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _MemoryCredentials implements CredentialStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String? token) async {}
}
