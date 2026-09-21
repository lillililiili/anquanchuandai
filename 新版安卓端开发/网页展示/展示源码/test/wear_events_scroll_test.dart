import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/events_page.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  testWidgets('scrolling reaches every batch without paging buttons', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final batches = <int>[];
    final session =
        WearSession(
            credentials: MemoryCredentials(),
            dio: transport((request) {
              if (request.path == '/api/v1/events') {
                final current = int.parse(
                  '${request.queryParameters['current']}',
                );
                batches.add(current);
                final start = (current - 1) * 20;
                return reply({
                  'records': [
                    for (var i = start; i < start + 20 && i < 45; i++)
                      {
                        'id': '$i',
                        'type': 'geofence',
                        'status': 'open',
                        'personName': '测试人员$i',
                        'siteId': '1',
                      },
                  ],
                  'total': 45,
                  'current': current,
                  'size': 20,
                });
              }
              if (request.path.endsWith('/inbox/count')) {
                return reply({'count': 45});
              }
              return reply({});
            }),
          )
          ..initialized = true
          ..token = 'test-only'
          ..siteId = '1'
          ..me = identity();
    addTearDown(session.dispose);
    await tester.pumpWidget(
      WearScope(
        session: session,
        child: const MaterialApp(home: EventsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('上一页'), findsNothing);
    expect(find.text('下一页'), findsNothing);
    final list = find.byKey(const ValueKey('wear-events-workspace'));
    final scroll = tester.widget<ListView>(list).controller!;
    final backToTop = find.byTooltip('回到顶部');
    expect(backToTop, findsNothing);
    scroll.jumpTo(scroll.position.viewportDimension);
    await tester.pumpAndSettle();
    expect(backToTop, findsNothing);
    scroll.jumpTo(scroll.position.viewportDimension + 1);
    await tester.pumpAndSettle();
    expect(backToTop.hitTestable(), findsOneWidget);
    final buttonPosition = tester.getTopRight(backToTop);
    expect(
      tester
          .getBottomRight(
            find.ancestor(of: backToTop, matching: find.byType(Positioned)).first,
          )
          .dy,
      closeTo(tester.getBottomRight(list).dy - 16, .01),
    );
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('wear-event-44')),
      list,
      const Offset(0, -550),
      maxIteration: 60,
    );
    await tester.pumpAndSettle();
    expect(batches, [1, 2, 3]);
    await tester.dragUntilVisible(
      find.text('没有更多事件了'),
      list,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('没有更多事件了'), findsOneWidget);
    expect(tester.getTopRight(backToTop), buttonPosition);
    await tester.tap(backToTop);
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(backToTop, findsNothing);
    expect(
      find.byKey(const ValueKey('wear-page-hero-events')).hitTestable(),
      findsOneWidget,
    );
    expect(batches, [1, 2, 3]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
