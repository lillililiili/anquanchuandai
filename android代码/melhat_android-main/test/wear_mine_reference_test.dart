import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/queries.dart';
import 'package:rolling_intelligence_headband/wear/queries/my_equipment_page.dart';
import 'wear_app_test.dart' show appSession;
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'four tabs share proportions and mine header switches real site',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((request) {
                if (request.path == '/api/v1/me/current-site') {
                  expect(request.method, 'PUT');
                  expect(request.data, {'siteId': '2'});
                  return reply({'currentSiteId': '2'});
                }
                if (request.path.endsWith('/inbox/count')) {
                  return reply({'count': 0});
                }
                if (request.path.endsWith('/equipment') ||
                    request.path == '/api/v1/duty/handovers') {
                  return reply([]);
                }
                return reply({
                  'records': [],
                  'total': 0,
                  'current': 1,
                  'size': 20,
                });
              }),
            )
            ..initialized = true
            ..me = identity(user: 'header-site-test')
            ..siteId = '1'
            ..token = 'test-only';
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      for (var index = 0; index < 4; index++) {
        await tester.tap(find.byType(NavigationDestination).at(index));
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(NavigationBar)).height, 60);
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          index,
        );
      }
      final switchSite = find.byKey(const ValueKey('mine-header-site'));
      expect(switchSite.hitTestable(), findsOneWidget);
      session.callActive.value = true;
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(switchSite).onPressed, isNull);
      expect(session.siteId, '1');
      session.callActive.value = false;
      await tester.pumpAndSettle();
      await tester.tap(switchSite);
      await tester.pumpAndSettle();
      expect(find.text('选择工作厂站'), findsOneWidget);
      await tester.tap(find.text('厂站二'));
      await tester.pumpAndSettle();
      expect(session.siteId, '1');
      await tester.ensureVisible(find.byKey(const ValueKey('sites-enter')));
      await tester.tap(find.byKey(const ValueKey('sites-enter')));
      await tester.pumpAndSettle();
      expect(session.siteId, '2');
      expect(session.siteName, '厂站二');
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: switchSite, matching: find.text('厂站二')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'mine reference menus preserve real workflows at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final session = appSession(authenticated: true);
        addTearDown(session.dispose);
        await tester.pumpWidget(
          WearApp(session: session, enableNotifications: false),
        );
        await tester.pumpAndSettle();
        final originalNavHeight = tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .height;
        await tester.tap(find.byType(NavigationDestination).at(3));
        await tester.pumpAndSettle();
        expect(find.text('通讯服务'), findsOneWidget);
        expect(find.text('SIP ID'), findsOneWidget);
        expect(find.text('值班交接'), findsNothing);
        expect(find.byType(EquipmentPanel), findsNothing);
        Future<void> open(String label) async {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
        }

        await open('我的装备');
        expect(find.byType(MyEquipmentPage), findsOneWidget);
        await tester.tap(find.byTooltip('返回我的'));
        await tester.pumpAndSettle();
        await open('通讯服务');
        expect(find.text('接警状态'), findsOneWidget);
        expect(find.text('开启通知'), findsOneWidget);
        await tester.tap(find.byTooltip('返回我的'));
        await tester.pumpAndSettle();
        expect(find.text('设置'), findsNothing);
        await open('帮助与反馈');
        expect(find.text('复制诊断信息'), findsOneWidget);
        await tester.tap(find.byTooltip('返回我的'));
        await tester.pumpAndSettle();
        await open('切换账号');
        expect(find.text('切换当前账号？'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(session.siteId, '1');
        expect(session.me, isNotNull);
        await open('退出登录');
        expect(find.text('退出当前账号？'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        session.callActive.value = true;
        await tester.pumpAndSettle();
        final switchButton = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, '切换账号'),
        );
        expect(switchButton.onPressed, isNull);
        session.callActive.value = false;
        await tester.pumpAndSettle();
        await tester.tap(find.byType(NavigationDestination).first);
        await tester.pumpAndSettle();
        expect(
          tester.widget<NavigationBar>(find.byType(NavigationBar)).height,
          originalNavHeight,
        );
        expect(find.byType(NavigationDestination), findsNWidgets(4));
        expect(tester.takeException(), isNull);
        // Full account exit is checked at normal text size; the existing login
        // page's large-text layout is outside this mine-only change.
        if (scale == 1.0) {
          await tester.tap(find.byType(NavigationDestination).at(3));
          await tester.pumpAndSettle();
          await open('切换账号');
          await tester.tap(find.text('确认切换'));
          await tester.pumpAndSettle();
          expect(session.me, isNull);
          expect(session.token, isNull);
          expect(find.text('欢迎登录'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
