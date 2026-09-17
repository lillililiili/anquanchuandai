import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'wear_app_test.dart' show appSession;
import 'wear_session_test.dart' show MemoryCredentials, transport, reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'communications swaps the actual background asset with appearance',
    (tester) async {
      final session = appSession(authenticated: true);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      bool hasBackground(String asset) =>
          tester.widgetList<Container>(find.byType(Container)).any((widget) {
            final decoration = widget.decoration;
            final provider = decoration is BoxDecoration
                ? decoration.image?.image
                : null;
            return provider is AssetImage && provider.assetName == asset;
          });
      expect(hasBackground(WearThemes.darkBackground), isTrue);
      await tester.tap(find.byTooltip('切换浅色'));
      await tester.pumpAndSettle();
      expect(hasBackground(WearThemes.lightBackground), isTrue);
      expect(hasBackground(WearThemes.darkBackground), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('cancelled captcha is unknown, never interpreted as disabled', (
    tester,
  ) async {
    final response = Completer<ResponseBody>();
    final session = WearSession(
      credentials: MemoryCredentials(),
      dio: transport((_) => response.future),
    )..initialized = true;
    addTearDown(session.dispose);
    await tester.pumpWidget(
      WearApp(session: session, enableNotifications: false),
    );
    await tester.pump();
    session.api.invalidate();
    response.complete(reply({'code': 200, 'captchaEnabled': false}, raw: true));
    await tester.pumpAndSettle();
    final submit = find.widgetWithText(FilledButton, '进入值班台');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(find.text('重试登录验证'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'mobile starts in communications with three destinations and dark theme',
    (tester) async {
      final session = appSession(authenticated: true);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations.length, 3);
      expect(bar.selectedIndex, 0);
      expect((bar.destinations[0] as NavigationDestination).label, '通讯');
      expect((bar.destinations[1] as NavigationDestination).label, '告警');
      expect(
        Theme.of(tester.element(find.byType(NavigationBar))).brightness,
        Brightness.dark,
      );
      expect(find.text('RL-H001'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'theme toggles preserve login inputs and choice survives new app instance',
    (tester) async {
      final session = appSession();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('智能穿戴管理平台'), findsOneWidget);
      expect(find.text('临江示范电厂'), findsNothing);
      expect(find.byType(TextFormField), findsNWidgets(2));
      await tester.enterText(find.byType(TextFormField).at(0), 'field-leader');
      await tester.enterText(find.byType(TextFormField).at(1), 'test-secret');
      await tester.tap(find.byTooltip('切换浅色'));
      await tester.pumpAndSettle();
      expect(find.text('field-leader'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        'test-secret',
      );
      expect(
        Theme.of(tester.element(find.byType(TextFormField).first)).brightness,
        Brightness.light,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(TextFormField).first)).brightness,
        Brightness.light,
      );
      expect(find.byTooltip('切换深色'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
