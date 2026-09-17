import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/queries/queries.dart';
import 'wear_app_test.dart' show appSession;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
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
        expect(find.byType(EquipmentPanel), findsOneWidget);
        await tester.tap(find.byTooltip('返回我的'));
        await tester.pumpAndSettle();
        await open('通讯服务');
        expect(find.text('接警状态'), findsOneWidget);
        expect(find.text('开启通知'), findsOneWidget);
        await tester.tap(find.byTooltip('返回我的'));
        await tester.pumpAndSettle();
        await open('设置');
        expect(find.text('值班交接'), findsOneWidget);
        expect(find.text('切换厂站'), findsOneWidget);
        expect(find.text('外观设置'), findsNothing);
        expect(find.text('深色'), findsNothing);
        await tester.tap(find.byTooltip('返回我的'));
        await tester.pumpAndSettle();
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
