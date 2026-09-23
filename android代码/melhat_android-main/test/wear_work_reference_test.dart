import 'package:dio/dio.dart';
import 'package:rolling_intelligence_headband/wear/queries/queries.dart';
import 'package:rolling_intelligence_headband/wear/events/events_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/communications/communications.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final code in [404, 403]) {
    testWidgets(
      'task unavailable $code keeps explicit read-only preview boundary',
      (tester) async {
        final calls = <RequestOptions>[];
        final session =
            WearSession(
                credentials: MemoryCredentials(),
                dio: transport((request) {
                  calls.add(request);
                  if (request.path == '/api/v1/duty/summary') {
                    return reply({
                      'activeTasks': [
                        {'id': '41', 'title': '待加载作业'},
                      ],
                    });
                  }
                  if (request.path.startsWith('/api/v1/work-tasks/')) {
                    return reply(null, code: code, msg: '接口暂不可用');
                  }
                  return reply([]);
                }),
              )
              ..initialized = true
              ..token = 'test-only'
              ..siteId = '1'
              ..me = {...identity(), 'admin': true};
        addTearDown(session.dispose);
        await tester.pumpWidget(
          WearApp(session: session, enableNotifications: false),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('view-current-work')));
        await tester.pumpAndSettle();
        if (code == 404) {
          await tester.tap(find.text('查看界面示例'));
          await tester.pumpAndSettle();
          expect(find.text('界面示例 · 非真实业务'), findsOneWidget);
          await tester.ensureVisible(find.text('联系监护人'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('联系监护人'));
          await tester.pumpAndSettle();
          expect(find.text('界面示例：未连接真实人员、事件或通话服务'), findsOneWidget);
          expect(calls.where((r) => r.path.contains('preview')), isEmpty);
          expect(calls.where((r) => r.method != 'GET'), isEmpty);
        } else {
          expect(find.text('查看界面示例'), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'work reference keeps task data, fields and guardian at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final calls = <RequestOptions>[];
        final task = <String, dynamic>{
          'id': '41',
          'title': '真实平台检修',
          'status': 'in_progress',
          'workType': 'height',
          'spaceName': '东区真实平台',
          'ownerUserId': '12',
          'guardianPersonId': '77',
          'ticketRequired': true,
          'ticketStatus': 'provided',
          'ticketNo': 'REAL-041',
          'members': [
            {'personId': '77', 'name': '真实监护人', 'personCode': 'P-77'},
          ],
        };
        final session =
            WearSession(
                credentials: MemoryCredentials(),
                dio: transport((request) {
                  calls.add(request);
                  if (request.path == '/api/v1/duty/summary') {
                    return reply({
                      'unclaimed': 2,
                      'activeTasks': [task],
                    });
                  }
                  if (request.path == '/api/v1/people') {
                    return reply({
                      'records': [
                        {'id': '77', 'name': '真实监护人', 'personCode': 'P-77'},
                      ],
                      'total': 1,
                    });
                  }
                  if (request.path == '/api/v1/work-tasks') {
                    return reply({
                      'records': [task],
                      'total': 1,
                    });
                  }
                  if (request.path == '/api/v1/work-tasks/41') {
                    return reply(task);
                  }
                  if (request.path.endsWith('/equipment-check')) {
                    return reply([
                      {
                        'personId': '77',
                        'personName': '真实监护人',
                        'typeCode': 'helmet',
                        'result': 'ok',
                        'sn': 'REAL-H77',
                      },
                    ]);
                  }
                  if (request.path == '/api/v1/work-tasks/41/events') {
                    return reply([
                      {
                        'id': 'e41',
                        'type': 'sos',
                        'status': 'open',
                        'personName': '真实监护人',
                        'occurredAt': '2026-09-17T10:39:00+08:00',
                      },
                    ]);
                  }
                  if (request.path.endsWith('/inbox/count')) {
                    return reply({'count': 2});
                  }
                  if (request.path.endsWith('/equipment') ||
                      request.path.endsWith('/operators')) {
                    return reply([]);
                  }
                  return reply({'records': [], 'total': 0});
                }),
              )
              ..initialized = true
              ..token = 'test-only'
              ..siteId = '1'
              ..me = {...identity(), 'admin': true};
        addTearDown(session.dispose);
        await tester.pumpWidget(
          WearApp(session: session, enableNotifications: false),
        );
        await tester.pumpAndSettle();
        expect(find.text('查看待认领事件'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('view-current-work')));
        await tester.pumpAndSettle();
        expect(find.text('作业详情'), findsOneWidget);
        expect(find.text('进行中'), findsOneWidget);
        expect(find.text('待核验事件'), findsNothing);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.text('REAL-041'), findsOneWidget);
        expect(find.text('参与人员 · 1 人'), findsOneWidget);
        Future<void> open(String label) async {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
        }

        await open('更多作业信息');
        expect(find.text('计划时间'), findsOneWidget);
        expect(find.text('东区真实平台'), findsOneWidget);
        await open('更多作业信息');
        await open('参与人员 · 1 人');
        await open('装备检查（1）');
        expect(find.text('设备 REAL-H77'), findsOneWidget);
        await open('装备检查（1）');
        for (final entry in {'task-person-77': '/people/77'}.entries) {
          final link = find.byKey(ValueKey(entry.key));
          await tester.ensureVisible(link);
          await tester.pumpAndSettle();
          await tester.tap(link);
          await tester.pumpAndSettle();
          if (entry.key == 'task-person-77') {
            expect(tester.widget<PersonPage>(find.byType(PersonPage)).id, '77');
          } else {
            expect(
              tester.widget<EventsPage>(find.byType(EventsPage)).eventId,
              'e41',
            );
          }
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.text('作业详情'), findsOneWidget);
        }
        await open('联系监护人');
        expect(
          tester
              .widget<CommunicationsPage>(find.byType(CommunicationsPage))
              .personId,
          '77',
        );

        expect(calls.where((r) => r.method != 'GET'), isEmpty);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('作业详情'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('返回来源页面'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('返回来源页面'));
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
