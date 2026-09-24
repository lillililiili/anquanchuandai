import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/event_reference_view.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'opening home emergency detail must not limit later unclaimed list to SOS',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'wear.filter-leak.events.1.state': jsonEncode({
          'filters': {'type': 'sos', 'status': 'open'},
          'current': 1,
        }),
      });
      final queries = <Map<String, dynamic>>[];
      Map<String, dynamic> event(int n) => {
        'id': '$n',
        'type': n == 1 ? 'sos' : 'geofence',
        'status': 'open',
        'siteId': '1',
        'personName': '测试人员$n',
        'escalated': n == 1,
      };
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) {
                if (r.path.endsWith('/summary')) {
                  return reply({
                    'activeTasks': [],
                    'unclaimed': 24,
                    'mine': 0,
                    'overdue': 1,
                  });
                }
                if (r.path.endsWith('/inbox/count')) {
                  return reply({'count': 35});
                }
                if (r.path == '/api/v1/events') {
                  queries.add(Map.of(r.queryParameters));
                  final onlySos = r.queryParameters['type'] == 'sos';
                  final total =
                      onlySos || r.queryParameters['escalated'] == 'true'
                      ? 1
                      : r.queryParameters['status'] == 'open'
                      ? 24
                      : 35;
                  final current = intOf(r.queryParameters['current']);
                  final size = intOf(r.queryParameters['size']);
                  final start = (current - 1) * size;
                  final count = (total - start).clamp(0, size);
                  return reply({
                    'records': List.generate(
                      count,
                      (i) => event(start + i + 1),
                    ),
                    'total': total,
                    'current': current,
                    'size': size,
                  });
                }
                if (r.path == '/api/v1/events/1') return reply(event(1));
                return reply([]);
              }),
            )
            ..initialized = true
            ..me = identity(user: 'filter-leak')
            ..siteId = '1'
            ..token = 'test';
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-sos-banner')));
      await tester.pumpAndSettle();
      expect(find.byType(EventReferenceView), findsOneWidget);
      expect(
        GoRouter.of(tester.element(find.byType(EventReferenceView)))
            .routeInformationProvider
            .value
            .uri
            .queryParameters
            .containsKey('type'),
        false,
      );
      GoRouter.of(tester.element(find.byType(EventReferenceView))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('inline-filter-toggle'));
      if (toggle.evaluate().isNotEmpty) {
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      }
      final open = find.byKey(const ValueKey('filter-status-open'));
      if (!tester.widget<FilterChip>(open).selected) {
        await tester.tap(open);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
      }
      expect(
        queries.last['statuses'] == 'open' || queries.last['status'] == 'open',
        true,
      );
      expect(
        queries.last.containsKey('type'),
        false,
        reason: '待认领24的入口不应保留首页详情带入的type=sos',
      );
      final collapse = find.byKey(const ValueKey('inline-filter-collapse-top'));
      if (collapse.evaluate().isNotEmpty) {
        await tester.tap(collapse);
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('共 24 条'), findsOneWidget);
      expect(find.textContaining('我的待办 35'), findsOneWidget);
      final workspace = find.byKey(const ValueKey('wear-events-workspace'));
      for (var i = 0; i < 14; i++) {
        await tester.drag(workspace, const Offset(0, -650));
        await tester.pumpAndSettle();
      }
      expect(
        queries.any(
          (q) =>
              q['current'] == 2 &&
              (q['status'] == 'open' || q['statuses'] == 'open'),
        ),
        true,
      );
      expect(find.byKey(const ValueKey('wear-event-24')), findsOneWidget);
      expect(find.text('没有更多事件了'), findsOneWidget);
      tester.widget<ListView>(workspace).controller!.jumpTo(0);
      await tester.pumpAndSettle();
      if (toggle.evaluate().isNotEmpty) {
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      }
      final reset = find.byKey(const ValueKey('filter-reset'));
      await tester.tap(reset);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final escalated = find.byKey(const ValueKey('filter-flags-escalated'));
      await tester.ensureVisible(escalated);
      await tester.pumpAndSettle();
      await tester.tap(escalated);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(queries.last['escalated'], 'true');
      expect(queries.last.containsKey('type'), false);
      expect(
        queries.last['status'] == 'all' || !queries.last.containsKey('status'),
        true,
      );
      expect(queries.last.containsKey('statuses'), false);
      final collapse2 = find.byKey(
        const ValueKey('inline-filter-collapse-top'),
      );
      if (collapse2.evaluate().isNotEmpty) {
        await tester.ensureVisible(collapse2);
        await tester.pumpAndSettle();
        await tester.tap(collapse2);
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('共 1 条'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
