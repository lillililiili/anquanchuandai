import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, identity, reply, transport;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('contacts contain one row per person and no device rows', (
    tester,
  ) async {
    final requests = <RequestOptions>[];
    final router = await openContacts(tester, requests, 'people-only');
    router.go('/communications');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('contact-p:1')), findsOneWidget);
    expect(find.byKey(const ValueKey('contact-p:2')), findsOneWidget);
    expect(find.byKey(const ValueKey('contact-p:3')), findsOneWidget);
    for (final id in ['h1', 'b1', 'unbound']) {
      expect(find.byKey(ValueKey('contact-d:$id')), findsNothing);
    }
    expect(find.text('联系对象筛选 · 3 项'), findsOneWidget);
    expect(find.text('陈建国的安全帽'), findsNothing);
    expect(find.text('陈建国的安全带'), findsNothing);
    expect(requests.where((r) => r.method != 'GET'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'contact scene switches tab and filters exact person on repeated entry',
    (tester) async {
      final requests = <RequestOptions>[];
      final router = await openContacts(tester, requests, 'event-contact');
      router.go('/communications');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '其他人员');
      for (var attempt = 0; attempt < 2; attempt++) {
        router.go('/events?eventId=159');
        await tester.pumpAndSettle();
        final contact = find.byKey(const ValueKey('event-communication'));
        await tester.ensureVisible(contact);
        await tester.tap(contact);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          1,
        );
        expect(find.byKey(const ValueKey('contact-p:1')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('contact-p:2')),
          findsNothing,
          reason: '同名人员必须按 ID 区分',
        );
        expect(find.byKey(const ValueKey('contact-p:3')), findsNothing);
        expect(find.text('1 项'), findsOneWidget);
        expect(find.text('语音群聊').hitTestable(), findsOneWidget);
        final clear = find.byTooltip('清除联系人筛选');
        await tester.ensureVisible(clear);
        await tester.tap(clear);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('contact-p:2')), findsOneWidget);
        final refresh = tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        await tester.pumpAndSettle();
        await refresh;
        expect(find.byKey(const ValueKey('contact-p:2')), findsOneWidget);
      }
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<GoRouter> openContacts(
  WidgetTester tester,
  List<RequestOptions> requests,
  String user,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Map<String, dynamic> device(String id) => {
    'id': id,
    'sn': id.toUpperCase(),
    'typeCode': id == 'b1' ? 'belt' : 'helmet',
    'capabilities': {
      'actions': ['intercom', 'tts'],
    },
    if (id != 'unbound')
      'currentAssignment': {'personId': '1', 'personName': '陈建国'},
  };
  const event = {
    'id': '159',
    'type': 'sos',
    'severity': 'emergency',
    'status': 'open',
    'personId': '1',
    'personName': '陈建国',
    'deviceId': 'h1',
    'siteId': '1',
    'version': 1,
  };
  final session =
      WearSession(
          credentials: MemoryCredentials(),
          dio: transport((r) {
            requests.add(r);
            if (r.path == '/api/v1/people') {
              return reply({
                'records': [
                  {'id': '1', 'name': '陈建国', 'personCode': 'P001'},
                  {'id': '2', 'name': '陈建国', 'personCode': 'P002'},
                  {'id': '3', 'name': '其他人员', 'personCode': 'P003'},
                ],
                'total': 3,
              });
            }
            if (r.path == '/api/v1/devices') {
              return reply({
                'records': [device('h1'), device('b1'), device('unbound')],
                'total': 3,
              });
            }
            if (r.path.startsWith('/api/v1/devices/')) {
              return reply(device(r.path.split('/').last));
            }
            if (r.path == '/api/v1/events/159') return reply(event);
            if (r.path == '/api/v1/events') {
              return reply({
                'records': [event],
                'total': 1,
              });
            }
            if (r.path.endsWith('/inbox/count')) return reply({'count': 1});
            if (r.path.endsWith('/summary')) return reply({'activeTasks': []});
            if (r.path.startsWith('/api/v1/work-tasks')) {
              return reply({'records': [], 'total': 0});
            }
            return reply([]);
          }),
        )
        ..initialized = true
        ..token = 'test'
        ..siteId = '1'
        ..me = {
          ...identity(user: user, roles: ['admin']),
          'permissions': ['*:*:*'],
        };
  addTearDown(session.dispose);
  await tester.pumpWidget(
    WearApp(session: session, enableNotifications: false),
  );
  await tester.pumpAndSettle();
  return GoRouter.of(tester.element(find.byType(NavigationBar)));
}
