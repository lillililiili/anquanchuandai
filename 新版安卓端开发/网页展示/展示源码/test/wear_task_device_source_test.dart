import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/work_reference.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  test(
    'member status distinguishes missing, offline, stale and abnormal devices',
    () {
      expect(taskMemberDeviceStatus(null, 'helmet'), '未获取');
      expect(taskMemberDeviceStatus([], 'helmet'), '未关联');
      String state(Map<String, dynamic> fields) => taskMemberDeviceStatus([
        {'typeCode': 'helmet', ...fields},
      ], 'helmet');
      expect(state({'online': '1', 'connectionQuality': 'ok'}), '在线');
      expect(state({'online': '0', 'connectionQuality': 'ok'}), '离线');
      expect(state({'online': '1', 'connectionQuality': 'stale'}), '数据陈旧');
      expect(state({'online': '1', 'connectionQuality': 'unknown'}), '状态未知');
      expect(
        state({
          'online': '1',
          'connectionQuality': 'ok',
          'simulationStatus': 'abnormal',
          'simulationStatusLabel': '设备异常',
        }),
        '设备异常',
      );
      expect(
        taskMemberDeviceStatus([
          {'typeCode': 'helmet', 'online': '1', 'connectionQuality': 'ok'},
          {'typeCode': 'helmet', 'online': '0', 'connectionQuality': 'ok'},
        ], 'helmet'),
        '离线',
      );
    },
  );

  testWidgets(
    'task member badges read and refresh business assignments and telemetry',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final paths = <String>[];
      var online = '1';
      var assignmentFails = false;
      final task = <String, dynamic>{
        'id': '41',
        'title': '后端作业',
        'status': 'in_progress',
        'members': [
          {'personId': '77', 'name': '后端成员'},
        ],
      };
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((request) {
                paths.add(request.path);
                if (request.path == '/api/v1/duty/summary') {
                  return reply({
                    'activeTasks': [task],
                  });
                }
                if (request.path == '/api/v1/work-tasks/41') return reply(task);
                if (request.path.endsWith('/equipment-check')) {
                  return reply([
                    {
                      'personId': '77',
                      'typeCode': 'helmet',
                      'result': 'ok',
                      'sn': 'CHECK-77',
                    },
                  ]);
                }
                if (request.path == '/api/v1/people/77/equipment') {
                  if (assignmentFails) {
                    return reply(null, code: 503, msg: '暂不可用');
                  }
                  return reply([
                    {
                      'id': 'assignment-1',
                      'personId': '77',
                      'deviceId': '9',
                      'typeCode': 'helmet',
                    },
                  ]);
                }
                if (request.path == '/api/v1/devices/9') {
                  return reply({
                    'id': '9',
                    'online': online,
                    'connectionQuality': 'ok',
                  });
                }
                return reply([]);
              }),
            )
            ..initialized = true
            ..token = 'test-only'
            ..siteId = '1'
            ..me = identity();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('view-current-work')));
      await tester.pumpAndSettle();
      expect(find.text('帽在线'), findsOneWidget);
      expect(find.text('带未关联'), findsOneWidget);
      expect(find.text('表未关联'), findsOneWidget);
      expect(paths, contains('/api/v1/people/77/equipment'));
      expect(paths, contains('/api/v1/devices/9'));
      expect(paths.where((path) => path.contains('/lab/')), isEmpty);

      online = '0';
      final refreshing = tester
          .widget<TaskReferenceView>(find.byType(TaskReferenceView))
          .onRefresh();
      await tester.pumpAndSettle();
      await refreshing;
      expect(find.text('帽离线'), findsOneWidget);
      expect(find.text('帽正常'), findsNothing);
      expect(find.text('装备检查（1）'), findsOneWidget);

      assignmentFails = true;
      final retrying = tester
          .widget<TaskReferenceView>(find.byType(TaskReferenceView))
          .onRefresh();
      await tester.pumpAndSettle();
      await retrying;
      expect(find.text('帽未获取'), findsOneWidget);
      expect(find.text('帽未关联'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
