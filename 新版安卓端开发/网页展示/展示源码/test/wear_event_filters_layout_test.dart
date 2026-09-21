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
                  if (request.path.endsWith('/filter-options')) {
                    return reply([
                      {'code': 'helmet.removal', 'label': '核心脱帽名称'},
                      {'code': 'belt.future_alarm', 'label': '平台新增告警'},
                    ]);
                  }
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
        // Collapsed filter card is very compact, freeing viewport for event items.
        expect(height, lessThanOrEqualTo(scale == 1 ? 65 : 90));
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('应用筛选'), findsNothing);
        final toggle = find.byKey(const ValueKey('inline-filter-toggle'));
        expect(toggle, findsOneWidget);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        Finder key(String value) => find.byKey(ValueKey(value));
        Future<void> click(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pumpAndSettle();
        }

        await click(key('filter-status-open'));
        expect(reads.last['statuses'], 'open', reason: '一次点击替换默认未关闭预设');
        await click(key('filter-status-pending_review'));
        await click(key('filter-type-type:geofence'));
        await click(key('filter-type-alarm:belt.future_alarm'));
        await click(key('filter-device-helmet'));
        await click(key('filter-device-belt'));
        expect(reads.last['statuses'], 'open,pending_review');
        expect(reads.last['types'], 'geofence');
        expect(reads.last['alarmCodes'], 'belt.future_alarm');
        expect(reads.last['deviceTypes'], 'helmet,belt');
        expect(
          tester.widget<FilterChip>(key('filter-device-belt')).selected,
          true,
        );
        await click(key('filter-more'));
        await tester.enterText(find.byType(TextField).first, '101');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(reads.last['personId'], '101');
        await click(key('filter-reset'));
        expect(reads.last.containsKey('alarmCodes'), false);
        expect(reads.last.containsKey('deviceTypes'), false);
        expect(reads.last.containsKey('statuses'), false);
        expect(reads.last['status'], 'all');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
