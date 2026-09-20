import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/events_page.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'event filter card stays compact and preserves filtering at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final reads = <Map<String, dynamic>>[];
        final userId = scale == 1 ? '7' : '8';
        final session =
            WearSession(
                credentials: MemoryCredentials(),
                dio: transport((request) {
                  if (request.path.endsWith('/summary')) {
                    return reply({'unclaimed': 2, 'mine': 0, 'overdue': 1});
                  }
                  if (request.path == '/api/v1/events') {
                    reads.add(Map.of(request.queryParameters));
                    return reply({
                      'records': [],
                      'total': 0,
                      'current': 1,
                      'size': 20,
                    });
                  }
                  if (request.path.endsWith('/inbox/count')) {
                    return reply({'count': 2});
                  }
                  return reply([]);
                }),
              )
              ..initialized = true
              ..token = 'test-only'
              ..siteId = '1'
              ..me = identity(user: userId);
        addTearDown(session.dispose);
        await tester.pumpWidget(
          WearScope(
            session: session,
            child: const MaterialApp(home: EventsPage()),
          ),
        );
        await tester.pumpAndSettle();
        final card = find.ancestor(
          of: find.text('事件筛选'),
          matching: find.byType(WearCard),
        );
        final height = tester.getSize(card).height;
        // Measure the rendered card, including header and all four real controls.
        expect(height, lessThanOrEqualTo(scale == 1 ? 150 : 220));
        final first = find.byKey(const ValueKey('events-quick-active'));
        expect(find.text('未关闭 2'), findsOneWidget);
        final last = find.byKey(const ValueKey('events-quick-escalated'));
        if (scale == 1) {
          expect(tester.getCenter(first).dy, tester.getCenter(last).dy);
        }
        Future<void> click(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        for (final key in ['open', 'mine', 'escalated', 'active']) {
          await click(find.byKey(ValueKey('events-quick-$key')));
          expect(reads.last['status'], key == 'open' ? 'open' : isNull);
          expect(reads.last['claimantUserId'], key == 'mine' ? userId : isNull);
          expect(reads.last['escalated'], key == 'escalated' ? 'true' : isNull);
        }
        await click(find.text('筛选'));
        expect(find.text('筛选事件'), findsOneWidget);
        await click(find.byType(DropdownButtonFormField<String>).at(1));
        expect(find.text('SOS 求助'), findsNothing);
        await click(find.text('围栏').last);
        await click(find.text('应用筛选'));
        expect(reads.last['type'], 'geofence');
        expect(find.text('围栏'), findsOneWidget);
        await click(find.byKey(const ValueKey('events-quick-open')));
        expect(reads.last.containsKey('type'), false);
        expect(find.text('围栏'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
