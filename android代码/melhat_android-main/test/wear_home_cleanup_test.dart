import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/my_equipment_page.dart';
import 'package:rolling_intelligence_headband/wear/queries/people.dart';
import 'package:rolling_intelligence_headband/wear/events/events_page.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'message shortcuts preserve server filters and expose claim before the form',
    (tester) async {
      final reads = <Map<String, dynamic>>[];
      final writes = <String>[];
      var claimed = false;
      Map<String, dynamic> event() => {
        'id': 'a',
        'type': 'geofence',
        'status': claimed ? 'claimed' : 'open',
        'claimantUserId': claimed ? '7' : '',
        'version': claimed ? 2 : 1,
        'siteId': '1',
        'personName': '测试人员',
      };
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) {
                if (r.method != 'GET') {
                  writes.add(r.path);
                  claimed = true;
                  return reply(event());
                }
                if (r.path.endsWith('/summary')) {
                  return reply({
                    'activeTasks': [],
                    'unclaimed': 17,
                    'mine': 4,
                    'overdue': 3,
                  });
                }
                if (r.path == '/api/v1/events') {
                  reads.add(Map.of(r.queryParameters));
                  return reply({
                    'records': [event()],
                    'total': 1,
                    'current': 1,
                    'size': 20,
                  });
                }
                if (r.path == '/api/v1/events/a') return reply(event());
                if (r.path.endsWith('/inbox/count')) return reply({'count': 1});
                return reply([]);
              }),
            )
            ..initialized = true
            ..token = 'test'
            ..siteId = '1'
            ..me = {
              ...identity(user: '7', roles: ['wear_duty']),
              'permissions': ['wear:event:list', 'wear:event:claim'],
            };
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      Future<void> click(Finder f) async {
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      await click(find.byKey(const ValueKey('events-quick-mine')));
      expect(reads.last['claimantUserId'], '7');
      await click(find.byKey(const ValueKey('events-quick-escalated')));
      expect(reads.last['escalated'], 'true');
      expect(reads.last.containsKey('claimantUserId'), isFalse);
      await click(find.byKey(const ValueKey('wear-event-a')));
      expect(find.byType(EventsPage), findsWidgets);
      await click(find.text('更多处置与记录'));
      expect(
        find.byKey(const ValueKey('event-claim')).hitTestable(),
        findsOneWidget,
      );
      await click(find.byKey(const ValueKey('event-next-claim')));
      expect(writes, ['/api/v1/events/a/claim']);
      expect(find.byKey(const ValueKey('event-next-claim')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'home retains tools and opens personal equipment directly at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final session =
            WearSession(
                credentials: MemoryCredentials(),
                dio: transport((r) {
                  if (r.path.endsWith('/summary')) {
                    return reply({
                      'activeTasks': [],
                      'unclaimed': 2,
                      'lostSupervision': 1,
                    });
                  }
                  if (r.path.endsWith('/inbox/count')) {
                    return reply({'count': 2});
                  }
                  if (r.path.endsWith('/equipment')) return reply([]);
                  return reply({'records': [], 'total': 0});
                }),
              )
              ..initialized = true
              ..token = 'test'
              ..siteId = '1'
              ..me = identity();
        addTearDown(session.dispose);
        await tester.pumpWidget(
          WearApp(session: session, enableNotifications: false),
        );
        await tester.pumpAndSettle();
        Future<void> click(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        await tester.ensureVisible(find.text('我的装备'));
        await tester.pumpAndSettle();
        expect(find.text('暂无已绑定装备'), findsOneWidget);
        expect(find.text('安全带连接中断'), findsNothing);
        expect(find.text('RL-H001'), findsNothing);
        await click(find.byKey(const ValueKey('home-my-equipment')));
        expect(find.byType(MyEquipmentPage), findsOneWidget);
        expect(find.byTooltip('返回现场'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await click(find.byKey(const ValueKey('home-tool-people')));
        expect(find.byType(PeoplePage), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('home-tool-supervision')),
        );
        await tester.pumpAndSettle();
        expect(find.text('近期未关闭事件'), findsNothing);
        expect(find.text('已领用人员'), findsNothing);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
