import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';

import 'wear_session_test.dart'
    show MemoryCredentials, identity, reply, transport;

const _personA = {'id': 'person-a', 'name': '甲站张工', 'personCode': 'A-001'};
const _personB = {'id': 'person-b', 'name': '乙站李工', 'personCode': 'B-001'};
const _eventA = {
  'id': 'event-a',
  'siteId': '1',
  'type': 'sos',
  'severity': 'high',
  'status': 'open',
  'personId': 'person-a',
  'personName': '甲站张工',
  'occurredAt': '2026-09-17T08:00:00Z',
  'version': 1,
};

WearSession _session(String user, List<RequestOptions> requests) {
  final session = WearSession(
    credentials: MemoryCredentials(),
    dio: transport((request) {
      requests.add(request);
      final site = request.headers['X-Site-Id'];
      if (request.path == '/api/v1/me/current-site') {
        return reply({'currentSiteId': (request.data as Map)['siteId']});
      }
      if (request.path == '/api/v1/people/options') {
        return reply([site == '2' ? _personB : _personA]);
      }
      if (request.path == '/api/v1/people/person-a') {
        return site == '2'
            ? reply(null, code: 403, msg: '人员不属于当前厂站')
            : reply(_personA);
      }
      if (request.path == '/api/v1/events/event-a') {
        return site == '2'
            ? reply(null, code: 403, msg: '告警不属于当前厂站')
            : reply(_eventA);
      }
      if (request.path.endsWith('/equipment') ||
          request.path.endsWith('/actions')) {
        return reply([]);
      }
      if (request.path.endsWith('/inbox/count')) return reply({'count': 1});
      if (request.path == '/api/v1/events') {
        return reply({
          'records': site == '2' ? [] : [_eventA],
          'total': site == '2' ? 0 : 1,
          'current': 1,
          'size': 20,
        });
      }
      if (request.path == '/api/v1/devices') {
        return reply({'records': [], 'total': 0, 'current': 1, 'size': 50});
      }
      throw StateError('Unexpected request: ${request.method} ${request.path}');
    }),
  );
  session
    ..initialized = true
    ..token = 'test-only'
    ..siteId = '1'
    ..me = identity(user: user);
  return session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('从告警切站再回通讯清除旧人员选择及深链参数', (tester) async {
    final requests = <RequestOptions>[];
    final session = _session('scope-navigation-1', requests);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      WearApp(session: session, enableNotifications: false),
    );
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(NavigationBar)));
    router.go('/communications?personId=person-a&eventId=event-a&intent=voice');
    await tester.pumpAndSettle();
    expect(find.textContaining('已选 1 人'), findsWidgets);
    expect(find.text('甲站张工'), findsWidgets);

    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(WearSiteSwitcher).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('厂站二'));
    await tester.pumpAndSettle();
    expect(session.siteId, '2');
    expect(router.routeInformationProvider.value.uri.path, '/events');

    await tester.tap(find.byType(NavigationDestination).at(0));
    await tester.pumpAndSettle();
    final uri = router.routeInformationProvider.value.uri;
    expect(uri.path, '/communications');
    expect(uri.queryParameters, isEmpty, reason: '切站后不能恢复旧分支的人员、告警和呼叫意图');
    expect(find.text('甲站张工'), findsNothing);
    expect(find.text('乙站李工'), findsOneWidget);
    expect(find.textContaining('已选 1 人'), findsNothing);
    expect(
      requests.where(
        (r) =>
            r.path == '/api/v1/people/options' && r.headers['X-Site-Id'] == '2',
      ),
      isNotEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('再次点击当前告警主入口清除事件深链并返回列表', (tester) async {
    final session = _session('scope-navigation-2', []);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      WearApp(session: session, enableNotifications: false),
    );
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(NavigationBar)));
    router.go('/events?eventId=event-a');
    await tester.pumpAndSettle();
    expect(find.text('告警详情'), findsOneWidget);
    expect(find.byKey(const ValueKey('wear-events-workspace')), findsNothing);

    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/events');
    expect(router.routeInformationProvider.value.uri.queryParameters, isEmpty);
    expect(find.text('告警详情'), findsNothing);
    expect(find.byKey(const ValueKey('wear-events-workspace')), findsOneWidget);
    expect(find.byKey(const ValueKey('wear-event-event-a')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
