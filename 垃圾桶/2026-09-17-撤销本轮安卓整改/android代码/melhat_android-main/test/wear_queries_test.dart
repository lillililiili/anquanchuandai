import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/query_utils.dart';
import 'package:rolling_intelligence_headband/wear/queries/supervision.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wear_app_test.dart' show appSession;

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

  testWidgets('legacy workbench link opens the mobile communications home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final session = appSession(authenticated: true);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      WearApp(session: session, enableNotifications: false),
    );
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(NavigationBar)));
    router.go('/workbench');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/communications');
    expect(
      tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .destinations
          .length,
      3,
    );
    expect(find.text('RL-H001'), findsNothing);
    expect(find.text('安全带连接中断'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
