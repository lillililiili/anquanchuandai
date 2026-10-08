import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

WearSession appSession({bool authenticated = false}) {
  final session = WearSession(
    credentials: MemoryCredentials(),
    dio: transport((request) {
      if (request.path == '/captchaImage') {
        return reply({'code': 200, 'captchaEnabled': false}, raw: true);
      }
      if (request.path == '/login') {
        return reply({'code': 200, 'token': 'test-only'}, raw: true);
      }
      if (request.path == '/api/v1/me') return reply(identity());
      if (request.path == '/api/v1/duty/summary') {
        return reply({
          'unclaimed': 2,
          'mine': 1,
          'overdue': 0,
          'lostSupervision': 1,
          'peopleCount': 1,
          'deviceCount': 2,
          'activeTasks': [],
          'recentEvents': [],
        });
      }
      if (request.path.endsWith('/inbox/count')) return reply({'count': 3});
      if (request.path == '/api/v1/duty/handovers' ||
          request.path.endsWith('/equipment')) {
        return reply([]);
      }
      return reply({'records': [], 'total': 0, 'current': 1, 'size': 20});
    }),
  );
  session.initialized = true;
  if (authenticated) {
    session.me = {...identity(), 'personId': '7'};
    session.siteId = '1';
    session.token = 'test-only';
  }
  return session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final path in ['/duty', '/duty/handovers']) {
    testWidgets('removed handover $path returns to workbench without actions', (
      tester,
    ) async {
      final session = appSession(authenticated: true);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.byType(NavigationBar)));
      router.go(path);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/workbench');
      expect(find.text('发起值班交接'), findsNothing);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('default login submits v1 identity and opens actual workbench', (
    tester,
  ) async {
    final session = appSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(
      WearApp(session: session, enableNotifications: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('欢迎登录'), findsOneWidget);
    expect(find.text('临江示范电厂'), findsOneWidget);
    expect(find.text('图形验证码'), findsNothing);
    expect(find.textContaining('联系管理员'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'operator');
    await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
    await tester.ensureVisible(find.text('登录'));
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.text('现场'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('360dp navigation and workbench remain usable at enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
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
    for (final label in ['现场', '通讯', '消息', '我的']) {
      expect(find.text(label), findsWidgets);
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(NavigationDestination).at(3));
    await tester.pumpAndSettle();
    expect(find.text('姓名'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'formal query routes and all tabs render at 360dp with large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
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
      final router = GoRouter.of(
        tester.element(find.byType(NavigationDestination).first),
      );
      for (final route in [
        '/events',
        '/communications',
        '/people?name=张',
        '/devices',
        '/tasks',
      ]) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: route);
        expect(
          find.byType(NavigationDestination),
          findsNWidgets(4),
          reason: route,
        );
      }
      session.callActive.value = true;
      router.go('/sites');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/communications');
      session.callActive.value = false;
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
