import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/events_page.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, identity, reply, transport;

void main() {
  for (final role in [
    'wear_duty',
    'wear_leader',
    'admin',
    'wear_platform_admin',
  ]) {
    testWidgets('$role shows the correct event scope and server count', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final admin = role == 'admin' || role == 'wear_platform_admin';
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((request) {
                if (request.path == '/api/v1/events') {
                  expect(request.headers['X-Site-Id'], '1');
                  return reply({
                    'records': [],
                    'total': 0,
                    'current': 1,
                    'size': 20,
                  });
                }
                if (request.path == '/api/v1/events/inbox/count') {
                  return reply({'count': admin ? 45 : 3});
                }
                return reply({});
              }),
            )
            ..initialized = true
            ..token = 'test'
            ..siteId = '1'
            ..me = identity(roles: [role]);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearScope(
          session: session,
          child: const MaterialApp(home: EventsPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(admin ? '共 0 条 · 全站未关闭 45' : '共 0 条 · 我的待办 3'),
        findsOneWidget,
      );
      if (!admin) {
        expect(find.text('进行中组内告警 · 本人设备提醒'), findsOneWidget);
        expect(find.textContaining('全站未关闭'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
