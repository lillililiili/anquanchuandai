import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/event_reference_view.dart';
import 'package:rolling_intelligence_headband/wear/queries/home_sos_banner.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'multiple SOS selects emergency messages and resets stale filters on reentry',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'wear.sos-multiple.events.1.state': jsonEncode({
          'filters': {
            'severity': 'warning',
            'statuses': ['closed'],
            'personId': '999',
            'deviceTypes': ['watch'],
          },
          'current': 3,
          'selectedEventId': 'old-event',
          'scrollOffset': 500,
        }),
      });
      final rows = List.generate(
        3,
        (i) => <String, dynamic>{
          'id': '${91 + i}',
          'type': 'sos',
          'severity': 'emergency',
          'siteId': '1',
          'status': 'open',
          'personName': '求助人员${i + 1}',
          'sn': 'SOS-00${i + 1}',
          'demo': true,
        },
      );
      final requests = <Map<String, dynamic>>[];
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) {
                if (r.path == '/api/v1/events') {
                  final banner = r.queryParameters['size'] == 1;
                  if (!banner) requests.add(Map.of(r.queryParameters));
                  return reply({
                    'records': banner ? [rows.first] : rows,
                    'total': 3,
                    'current': 1,
                    'size': r.queryParameters['size'],
                  });
                }
                for (final row in rows) {
                  if (r.path == '/api/v1/events/${row['id']}') {
                    return reply(row);
                  }
                }
                if (r.path.endsWith('/inbox/count')) return reply({'count': 3});
                return reply([]);
              }),
            )
            ..initialized = true
            ..me = identity(user: 'sos-multiple')
            ..siteId = '1'
            ..token = 'test';
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('SOS 紧急求助'), findsOneWidget);
      expect(find.text('SOS 紧急求助 · 演示'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('home-sos-banner')));
      await tester.pumpAndSettle();
      final emergency = find.byKey(const ValueKey('event-level-emergency'));
      expect(tester.widget<ChoiceChip>(emergency).selected, isTrue);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      expect(find.text('紧急求助列表'), findsNothing);
      expect(find.byType(EventReferenceView), findsNothing);
      expect(requests.single['severity'], 'emergency');
      expect(requests.single['current'], 1);
      expect(requests.single.containsKey('type'), isFalse);
      expect(requests.single.containsKey('personId'), isFalse);
      expect(requests.single.containsKey('deviceTypes'), isFalse);
      expect(requests.single['statuses'], isNot(contains('closed')));
      final router = GoRouter.of(tester.element(find.byType(NavigationBar)));
      final tile = find.byKey(const ValueKey('wear-event-93'));
      await tester.scrollUntilVisible(
        tile,
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EventReferenceView>(find.byType(EventReferenceView))
            .controller
            .selected!
            .id,
        '93',
      );
      router.pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(emergency);
      await tester.pumpAndSettle();
      await tester.tap(emergency);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(emergency).selected, isFalse);
      await tester.tap(find.byType(NavigationDestination).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-sos-banner')));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(emergency).selected, isTrue);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      expect(requests.last['severity'], 'emergency');
      router.go('/sos-events');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/events');
      expect(find.text('紧急求助列表'), findsNothing);
      expect(tester.widget<ChoiceChip>(emergency).selected, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'SOS shortcut opens matching detail and disappears after closure at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        var closed = false;
        var writes = 0;
        Map<String, dynamic> event() => {
          'id': '19',
          'type': 'sos',
          'siteId': '1',
          'status': closed ? 'verified' : 'pending_review',
          'severity': 'emergency',
          'version': closed ? 4 : 3,
          'personName': '测试人员',
          'demo': true,
        };
        final session =
            WearSession(
                credentials: MemoryCredentials(),
                dio: transport((r) {
                  if (r.method != 'GET') {
                    expect(r.path, '/api/v1/events/19/review');
                    expect(r.data, {'reason': '现场已确认安全', 'version': 3});
                    writes++;
                    closed = true;
                    return reply(event());
                  }
                  if (r.path == '/api/v1/duty/summary') {
                    return reply({
                      'activeTasks': [
                        {
                          'id': 'task-14',
                          'title': '东区巡检（联调14）',
                          'ownerUserId': '116',
                        },
                      ],
                      'recentEvents': [],
                    });
                  }
                  if (r.path == '/api/v1/events') {
                    if (r.queryParameters['size'] == 1) {
                      expect(r.queryParameters['type'], 'sos');
                    } else {
                      expect(r.queryParameters.containsKey('type'), false);
                    }
                    expect(r.queryParameters.containsKey('status'), false);
                    return reply({
                      'records': closed ? [] : [event()],
                      'total': closed ? 0 : 1,
                      'current': 1,
                      'size': r.queryParameters['size'],
                    });
                  }
                  if (r.path == '/api/v1/events/19') return reply(event());
                  if (r.path.endsWith('/inbox/count')) {
                    return reply({'count': 1});
                  }
                  return reply([]);
                }),
              )
              ..initialized = true
              ..me = {
                ...identity(
                  user: 'home-sos-$scale',
                  roles: ['wear_platform_admin'],
                ),
                'permissions': ['wear:event:list', 'wear:event:review'],
              }
              ..siteId = '1'
              ..token = 'test';
        addTearDown(session.dispose);
        await tester.pumpWidget(
          WearApp(session: session, enableNotifications: false),
        );
        await tester.pumpAndSettle();
        final banner = find.byKey(const ValueKey('home-sos-banner'));
        expect(banner, findsOneWidget);
        expect(find.text('SOS 紧急求助'), findsOneWidget);
        expect(find.text('SOS 紧急求助 · 演示'), findsNothing);
        expect(
          tester.getTopLeft(banner).dy,
          lessThan(tester.getTopLeft(find.text('当前作业')).dy),
        );
        await tester.ensureVisible(banner);
        await tester.pumpAndSettle();
        await tester.tap(banner);
        await tester.pumpAndSettle();
        final detail = tester.widget<EventReferenceView>(
          find.byType(EventReferenceView),
        );
        expect(detail.controller.selected!.id, '19');
        expect(detail.controller.selected!.type, 'sos');
        final approve = find.widgetWithText(FilledButton, '审批通过 · 完成核验');
        await tester.ensureVisible(approve);
        await tester.tap(approve);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          '现场已确认安全',
        );
        await tester.tap(find.text('确认提交'));
        await tester.pumpAndSettle();
        expect(closed, isTrue);
        expect(detail.controller.selected!.isPlatformComplete, isTrue);
        expect(detail.controller.selected!.status, 'verified');
        expect(detail.controller.selected!.externalClosureStatus, 'not_synced');
        expect(approve, findsNothing);
        GoRouter.of(tester.element(find.byType(EventReferenceView))).pop();
        await tester.pumpAndSettle();
        expect(banner, findsNothing);
        expect(writes, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'empty, non-SOS, closed, foreign site and failed query leave no banner gap',
    (tester) async {
      for (final state in ['empty', 'geofence', 'closed', 'foreign', 'error']) {
        final session =
            WearSession(
                credentials: MemoryCredentials(),
                dio: transport((r) {
                  if (state == 'error') return reply(null, code: 500);
                  return reply({
                    'records': state == 'empty'
                        ? []
                        : [
                            {
                              'id': '19',
                              'type': state == 'geofence' ? 'geofence' : 'sos',
                              'status': state == 'closed' ? 'closed' : 'open',
                              'siteId': state == 'foreign' ? '2' : '1',
                            },
                          ],
                    'total': 1,
                  });
                }),
              )
              ..initialized = true
              ..me = identity()
              ..siteId = '1'
              ..token = 'test';
        await tester.pumpWidget(
          WearScope(
            session: session,
            child: const MaterialApp(
              home: Scaffold(
                body: Column(children: [HomeSosBanner(refreshVersion: 0)]),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home-sos-banner')), findsNothing);
        expect(tester.getSize(find.byType(HomeSosBanner)).height, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        session.dispose();
      }
    },
  );

  testWidgets(
    'late response from previous site cannot show an SOS in new site',
    (tester) async {
      final delayed = Completer<void>();
      var calls = 0;
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) async {
                calls++;
                if (calls == 1) {
                  await delayed.future;
                  return reply({
                    'records': [
                      {
                        'id': '19',
                        'type': 'sos',
                        'status': 'open',
                        'siteId': '1',
                      },
                    ],
                    'total': 1,
                  });
                }
                return reply({'records': [], 'total': 0});
              }),
            )
            ..initialized = true
            ..me = identity()
            ..siteId = '1'
            ..token = 'test';
      addTearDown(session.dispose);
      Widget app(int version) => WearScope(
        session: session,
        child: MaterialApp(
          home: Scaffold(body: HomeSosBanner(refreshVersion: version)),
        ),
      );
      await tester.pumpWidget(app(0));
      await tester.pump();
      session.siteId = '2';
      await tester.pumpWidget(app(1));
      await tester.pumpAndSettle();
      delayed.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-sos-banner')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
