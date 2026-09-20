import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, identity, reply, transport;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'event types open reference children and retain drafts at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final writes = <RequestOptions>[];
        Map<String, dynamic> event(String id) => {
          'id': id,
          'type': id == 'a' ? 'geofence' : 'sos',
          'alarmCode': id == 'a' ? 'helmet.fence_exit' : 'helmet.sos',
          'alarmName': id == 'a' ? '离开指定区域（核心系统名称）' : 'SOS 紧急求救',
          'alarmDescription': id == 'a' ? '已离开指定作业区域，请核实现场情况' : '',
          'sourceEventId': 'call-lab:helmet.fence_exit:fixture',
          'severity': 'high',
          'status': 'claimed',
          'claimantUserId': 'event-ui-$scale',
          'siteId': '1',
          'personId': 'p1',
          'personName': '现场人员',
          'sn': 'REAL-01',
          'deviceId': 'd1',
          'version': 3,
          'demo': true,
          'occurredAt': '2026-09-17T10:39:00+08:00',
        };
        final session =
            WearSession(
                credentials: MemoryCredentials(),
                dio: transport((r) {
                  if (r.method != 'GET') {
                    writes.add(r);
                    return reply({
                      ...event('a'),
                      'status': 'handling',
                      'version': 4,
                    });
                  }
                  if (r.path == '/api/v1/events') {
                    return reply({
                      'records': [event('a'), event('s')],
                      'total': 2,
                      'current': 1,
                      'size': 20,
                    });
                  }
                  if (r.path == '/api/v1/events/a' ||
                      r.path == '/api/v1/events/s') {
                    return reply(event(r.path.split('/').last));
                  }
                  if (r.path.endsWith('/actions')) return reply([]);
                  if (r.path.endsWith('/inbox/count')) {
                    return reply({'count': 2});
                  }
                  if (r.path.endsWith('/summary')) {
                    return reply({'activeTasks': []});
                  }
                  return reply([]);
                }),
              )
              ..initialized = true
              ..token = 'test'
              ..siteId = '1'
              ..me = {
                ...identity(user: 'event-ui-$scale', roles: ['wear_duty']),
                'permissions': ['wear:event:list', 'wear:event:claim'],
              };
        addTearDown(session.dispose);
        await tester.pumpWidget(
          WearApp(session: session, enableNotifications: false),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(NavigationDestination).at(2));
        await tester.pumpAndSettle();
        Future<void> click(Finder f) async {
          if (f.evaluate().isEmpty) {
            await tester.scrollUntilVisible(f, 180);
          }
          await tester.ensureVisible(f);
          await tester.pumpAndSettle();
          await tester.tap(f);
          await tester.pumpAndSettle();
        }

        expect(find.text('离开指定区域（核心系统名称）'), findsOneWidget);
        await click(find.byKey(const ValueKey('wear-event-a')));
        expect(find.text('异常核验'), findsOneWidget);
        expect(find.text('离开指定区域（核心系统名称）'), findsWidgets);
        expect(find.text('已离开指定作业区域，请核实现场情况'), findsOneWidget);
        expect(find.text('围栏异常'), findsNothing);
        expect(find.text('原安监事件'), findsNothing);
        expect(find.byType(NavigationBar), findsNothing);
        final input = find.byKey(const ValueKey('event-handle-input-a'));
        await tester.ensureVisible(input);
        await tester.enterText(input, '已核查，等待现场确认');
        await tester.pumpAndSettle();
        await click(find.text('添加照片'));
        await click(find.text('添加示例照片'));
        expect(find.text('现场照片（示例）'), findsOneWidget);
        await click(find.byTooltip('删除示例照片'));
        expect(find.text('现场照片（示例）'), findsNothing);
        await click(find.text('保存草稿'));
        expect(writes, isEmpty);
        await click(find.byTooltip('返回事件列表'));
        await click(find.byKey(const ValueKey('wear-event-a')));
        expect(tester.widget<TextField>(input).controller!.text, '已核查，等待现场确认');
        await click(find.byKey(const ValueKey('event-handle-submit-a')));
        expect(writes.single.path, '/api/v1/events/a/handle');
        expect(writes.single.data, {'comment': '已核查，等待现场确认', 'version': 3});
        expect(tester.widget<TextField>(input).controller!.text, '已核查，等待现场确认');
        expect(find.text('已提交核验'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('event-handle-submit-a')),
              )
              .onPressed,
          isNull,
        );
        await click(find.byTooltip('返回事件列表'));
        await click(find.byKey(const ValueKey('wear-event-s')));
        expect(find.text('SOS协助'), findsOneWidget);
        expect(find.text('厂区示意 · 非实时地图'), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        final before = writes.length;
        await click(find.text('加入协助'));
        expect(find.text('协助组服务尚未接入'), findsOneWidget);
        await click(find.text('关闭'));
        expect(writes.length, before);
        await click(find.byTooltip('返回事件列表'));
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
