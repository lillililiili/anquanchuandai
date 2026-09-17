import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'wear_app_test.dart' show appSession;
import 'package:rolling_intelligence_headband/wear/preview_appearance.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'scale $scale: appearance changes only its panel and survives app recreation without changing identity',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final session = appSession(authenticated: true);
        addTearDown(session.dispose);
        final identity = session.me;
        final token = session.token;
        await tester.pumpWidget(
          WearApp(session: session, enableNotifications: false),
        );
        await tester.pumpAndSettle();
        final router = GoRouter.of(tester.element(find.byType(NavigationBar)));
        await tester.tap(find.byType(NavigationDestination).at(3));
        await tester.pumpAndSettle();
        expect(find.text('设置'), findsOneWidget);
        await tester.ensureVisible(find.text('设置'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        expect(find.text('外观设置'), findsOneWidget);
        session.callActive.value = true;
        await tester.tap(find.text('深色'));
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.text('外观设置'))).brightness,
          Brightness.dark,
        );
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          ThemeMode.light,
        );
        expect(GoRouter.of(tester.element(find.text('外观设置'))), same(router));
        expect(router.routeInformationProvider.value.uri.path, '/me');
        expect(session.me, same(identity));
        expect(session.siteId, '1');
        expect(session.token, token);
        expect(session.callActive.value, isTrue);
        session.callActive.value = false;
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('wear.preview.appearance'), 'dark');
        await tester.tap(find.byTooltip('关闭外观设置'));
        await tester.pumpAndSettle();
        expect(find.byType(NavigationDestination), findsNWidgets(4));
        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.text('外观设置'))).brightness,
          Brightness.dark,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          WearApp(session: session, enableNotifications: false),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          0,
        );
        await tester.tap(find.byType(NavigationDestination).at(3));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('设置'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.text('外观设置'))).brightness,
          Brightness.dark,
        );
        await tester.tap(find.text('浅色'));
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.text('外观设置'))).brightness,
          Brightness.light,
        );
        expect(prefs.getString('wear.preview.appearance'), 'light');
        expect(session.me, same(identity));
        expect(session.siteId, '1');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  test(
    'late preference load cannot replace the user choice even when saving fails',
    () async {
      SharedPreferences.setMockInitialValues({
        'wear.preview.appearance': 'dark',
      });
      final prefs = await SharedPreferences.getInstance();
      final delayedRead = Completer<SharedPreferences>();
      var requests = 0;
      final controller = PreviewAppearanceController(
        preferences: () {
          if (requests++ == 0) return delayedRead.future;
          return Future.error(StateError('storage unavailable'));
        },
      );
      addTearDown(controller.dispose);
      final loading = controller.load();
      expect(await controller.setMode(PreviewMode.light), isFalse);
      delayedRead.complete(prefs);
      await loading;
      expect(controller.mode, PreviewMode.light);
      expect(controller.saveFailed, isTrue);
    },
  );
  test(
    'rapid choices persist in order and restore the final visible selection',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final gate = Completer<SharedPreferences>();
      var requests = 0;
      final controller = PreviewAppearanceController(
        preferences: () {
          if (requests++ == 0) return gate.future;
          return Future.value(prefs);
        },
      );
      addTearDown(controller.dispose);
      final first = controller.setMode(PreviewMode.dark);
      final second = controller.setMode(PreviewMode.light);
      await Future<void>.delayed(Duration.zero);
      expect(controller.mode, PreviewMode.light);
      expect(requests, 1);
      gate.complete(prefs);
      expect(await first, isTrue);
      expect(await second, isTrue);
      final restored = PreviewAppearanceController();
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.mode, PreviewMode.light);
      expect(prefs.getString('wear.preview.appearance'), 'light');
    },
  );
  test(
    'read failure defaults to light and pending work is safe after disposal',
    () async {
      final failing = PreviewAppearanceController(
        preferences: () => Future.error(StateError('unavailable')),
      );
      await failing.load();
      expect(failing.mode, PreviewMode.light);
      failing.dispose();
      final gate = Completer<SharedPreferences>();
      final disposed = PreviewAppearanceController(
        preferences: () => gate.future,
      );
      final loading = disposed.load();
      final saving = disposed.setMode(PreviewMode.dark);
      disposed.dispose();
      gate.complete(await SharedPreferences.getInstance());
      await loading;
      expect(await saving, isTrue);
    },
  );
  testWidgets(
    'failed persistence keeps the chosen appearance and offers retry in the panel',
    (tester) async {
      var fail = true;
      final controller = PreviewAppearanceController(
        preferences: () {
          if (fail) return Future.error(StateError('unavailable'));
          return SharedPreferences.getInstance();
        },
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PreviewAppearancePanel(controller: controller)),
        ),
      );
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('外观设置'))).brightness,
        Brightness.dark,
      );
      expect(find.text('偏好未保存，请重新选择后重试'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(find.text('偏好未保存，请重新选择后重试'), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'wear.preview.appearance',
        ),
        'dark',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
