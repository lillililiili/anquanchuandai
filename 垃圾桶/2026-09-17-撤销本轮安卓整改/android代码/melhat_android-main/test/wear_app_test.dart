import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/events_page.dart';
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
    session.me = identity();
    session.siteId = '1';
    session.token = 'test-only';
  }
  return session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('alert destination opens unified alert list at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = appSession(authenticated: true);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      WearApp(session: session, enableNotifications: false),
    );
    await tester.pumpAndSettle();
    final action = find.byType(NavigationDestination).at(1);
    expect(action.hitTestable(), findsOneWidget);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(
      tester.widget<EventsPage>(find.byType(EventsPage)).initialStatus,
      isNull,
    );
    expect(find.text('统一告警流水'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'duty operator can create a handover and current user is excluded',
    (tester) async {
      final requests = <RequestOptions>[];
      final session = WearSession(
        credentials: MemoryCredentials(),
        dio: transport((request) {
          requests.add(request);
          if (request.path == '/api/v1/duty/summary') {
            return reply({
              'unclaimed': 0,
              'mine': 0,
              'overdue': 0,
              'lostSupervision': 0,
              'peopleCount': 0,
              'deviceCount': 0,
              'activeTasks': [],
              'recentEvents': [],
            });
          }
          if (request.path == '/api/v1/duty/operators') {
            return reply([
              {'userId': '12', 'userName': 'current', 'nickName': '当前用户'},
              {'userId': '23', 'userName': 'leader', 'nickName': '王班长'},
            ]);
          }
          if (request.path == '/api/v1/duty/handovers' &&
              request.method == 'POST') {
            return reply({'id': '9', 'status': 'pending'});
          }
          if (request.path.endsWith('/inbox/count')) return reply({'count': 0});
          return reply({'records': [], 'total': 0, 'current': 1, 'size': 20});
        }),
      );
      session
        ..initialized = true
        ..me = identity()
        ..siteId = '1'
        ..token = 'test-only';
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('值班交接'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发起交接'));
      await tester.pumpAndSettle();
      expect(find.text('当前用户'), findsNothing);
      expect(find.text('王班长'), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('王班长').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('提交交接'));
      await tester.pumpAndSettle();
      final created = requests.lastWhere(
        (request) =>
            request.path == '/api/v1/duty/handovers' &&
            request.method == 'POST',
      );
      expect((created.data as Map)['toUserId'], '23');
      expect((created.data as Map).containsKey('eventIds'), false);
      expect(find.text('交接已发起，等待接班人确认'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('default login submits v1 identity and opens communications', (
    tester,
  ) async {
    final session = appSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(
      WearApp(session: session, enableNotifications: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('智能穿戴管理平台'), findsOneWidget);
    expect(find.text('临江示范电厂'), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('登录遇到问题'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'operator');
    await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
    await tester.ensureVisible(find.text('进入值班台'));
    await tester.tap(find.text('进入值班台'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(find.text('通讯'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('360dp mobile navigation remains usable at enlarged text', (
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
    for (final label in ['通讯', '告警', '我的']) {
      expect(find.text(label), findsWidgets);
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(NavigationDestination).at(2));
    await tester.pumpAndSettle();
    expect(find.text('我的装备'), findsOneWidget);
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
        '/supervision',
        '/tasks',
        '/tracks',
        '/fences',
      ]) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: route);
        expect(
          find.byType(NavigationDestination),
          route == '/events' || route == '/communications'
              ? findsNWidgets(3)
              : findsNothing,
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
