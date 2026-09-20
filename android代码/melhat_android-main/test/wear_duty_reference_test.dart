import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:go_router/go_router.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;
import 'wear_app_test.dart' show appSession;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'handover tabs, recipient confirmation and settings keep real workflows',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var confirmed = false;
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((request) {
                if (request.path == '/api/v1/duty/handovers/9/confirm') {
                  expect(request.method, 'POST');
                  confirmed = true;
                  return reply({'id': '9'});
                }
                if (request.path == '/api/v1/duty/handovers') {
                  return reply([
                    {
                      'id': '9',
                      'siteId': '1',
                      'fromUserName': '周明',
                      'toUserName': '陈建国',
                      'toUserId': '12',
                      'status': confirmed ? 'confirmed' : 'pending',
                      'createTime': '2026-09-20 08:00:00',
                      'payloadJson': '{"eventIds":[1,2,3],"taskIds":[4,5]}',
                      'comment': '锅炉平台设备连接异常，请持续跟进现场核验。',
                    },
                    {
                      'id': '10',
                      'siteId': '1',
                      'fromUserName': '李志远',
                      'toUserName': '王班长',
                      'toUserId': '23',
                      'status': 'pending',
                    },
                    {
                      'id': '11',
                      'siteId': '2',
                      'fromUserName': '其他厂站',
                      'status': 'pending',
                    },
                  ]);
                }
                if (request.path.endsWith('/inbox/count')) {
                  return reply({'count': 0});
                }
                return reply({'records': [], 'total': 0});
              }),
            )
            ..initialized = true
            ..me = identity()
            ..siteId = '1'
            ..token = 'test-only';
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('发起值班交接'));
      await tester.pumpAndSettle();
      expect(find.text('周明 → 陈建国'), findsOneWidget);
      expect(find.text('3 条'), findsOneWidget);
      expect(find.text('2 项'), findsOneWidget);
      expect(find.textContaining('其他厂站'), findsNothing);
      expect(find.byKey(const ValueKey('handover-confirm-10')), findsNothing);
      final confirm = find.byKey(const ValueKey('handover-confirm-9'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '确认接班').last);
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
      await tester.ensureVisible(
        find.byKey(const ValueKey('handover-confirmed')),
      );
      await tester.tap(find.byKey(const ValueKey('handover-confirmed')));
      await tester.pumpAndSettle();
      expect(find.text('周明 → 陈建国'), findsOneWidget);
      expect(find.text('李志远 → 王班长'), findsNothing);
      final router = GoRouter.of(tester.element(find.byType(NavigationBar)));
      router.go('/settings');
      await tester.pumpAndSettle();
      expect(find.text('当前：厂站一'), findsOneWidget);
      session.callActive.value = true;
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('settings-switch-site')),
            )
            .enabled,
        false,
      );
      session.callActive.value = false;
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('查看交接记录'));
      await tester.tap(find.text('查看交接记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回上页'));
      await tester.pumpAndSettle();
      expect(find.text('工作环境与值班信息'), findsOneWidget);
      expect(tester.getSize(find.byType(NavigationBar)).height, 60);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('home replaces unclaimed link with handover page entry', (
    tester,
  ) async {
    final session = appSession(authenticated: true);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      WearApp(session: session, enableNotifications: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('查看待认领事件'), findsNothing);
    await tester.tap(find.text('发起值班交接'));
    await tester.pumpAndSettle();
    expect(find.text('待办清楚，交接有据'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'non-duty user can read handovers at enlarged text without write actions',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final session = appSession(authenticated: true)
        ..me = identity(roles: ['wear_worker']);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('发起值班交接'));
      await tester.pumpAndSettle();
      expect(find.text('发起交接'), findsNothing);
      expect(find.text('确认接班'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('显示当前厂站最近 20 条交接记录'),
        150,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('handover-scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(NavigationBar)).height, 60);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
