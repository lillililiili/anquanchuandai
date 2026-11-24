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
      'severity and processing state can be combined at text scale $scale',
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
        final paths = <String>[];
        final userId = scale == 1 ? '7' : '8';
        final session =
            WearSession(
                credentials: MemoryCredentials(),
                dio: transport((request) {
                  paths.add(request.path);
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
        expect(find.text('事件筛选'), findsNothing);
        expect(find.byKey(const ValueKey('event-level-warning')), findsNothing);
        expect(find.byType(ChoiceChip), findsNWidgets(4));
        expect(
          find.byKey(const ValueKey('inline-filter-toggle')),
          findsNothing,
        );
        final header = find.text('事件列表');
        expect(header.hitTestable(), findsOneWidget);
        expect(find.textContaining('待办 2'), findsOneWidget);
        final defaultQuery = Map.of(reads.last);
        expect(defaultQuery.containsKey('severity'), isFalse);
        expect(defaultQuery.containsKey('statuses'), isFalse);
        final emergency = find.byKey(const ValueKey('event-level-emergency'));
        final abnormal = find.byKey(const ValueKey('event-level-abnormal'));
        final unclaimed = find.byKey(const ValueKey('event-status-unclaimed'));
        final processing = find.byKey(
          const ValueKey('event-status-processing'),
        );
        expect(find.text('处理状态').hitTestable(), findsOneWidget);
        for (final (chip, label) in [(unclaimed, '待认领'), (processing, '处理中')]) {
          expect(
            find.descendant(of: chip, matching: find.text(label)),
            findsOneWidget,
          );
          expect(chip.hitTestable(), findsOneWidget);
          expect(
            tester.getTopLeft(chip).dy,
            greaterThan(tester.getBottomLeft(emergency).dy),
          );
          expect(
            tester.getBottomLeft(chip).dy,
            lessThan(tester.getTopLeft(header).dy),
          );
        }
        for (final level in const {
          'emergency': '紧急',
          'abnormal': '异常',
        }.entries) {
          final chip = find.byKey(ValueKey('event-level-${level.key}'));
          expect(
            find.descendant(of: chip, matching: find.text(level.value)),
            findsOneWidget,
          );
          expect(chip.hitTestable(), findsOneWidget);
          expect(
            tester.getBottomLeft(chip).dy,
            lessThan(tester.getTopLeft(header).dy),
          );
          await tester.tap(chip);
          await tester.pumpAndSettle();
          expect(reads.last, {...defaultQuery, 'severity': level.key});
        }
        Future<void> tapFilter(Finder chip) async {
          await tester.tap(chip);
          await tester.pumpAndSettle();
        }

        await tapFilter(unclaimed);
        expect(reads.last, {
          ...defaultQuery,
          'severity': 'abnormal',
          'statuses': 'open',
        });
        await tapFilter(processing);
        expect(tester.widget<ChoiceChip>(unclaimed).selected, isFalse);
        expect(reads.last, {
          ...defaultQuery,
          'severity': 'abnormal',
          'statuses': 'claimed,handling',
        });
        await tapFilter(emergency);
        expect(reads.last, {
          ...defaultQuery,
          'severity': 'emergency',
          'statuses': 'claimed,handling',
        });
        await tapFilter(emergency);
        expect(reads.last, {...defaultQuery, 'statuses': 'claimed,handling'});
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          WearScope(
            session: session,
            child: const MaterialApp(home: EventsPage()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(processing).selected, isTrue);
        expect(reads.last, {...defaultQuery, 'statuses': 'claimed,handling'});
        await tapFilter(abnormal);
        await tapFilter(processing);
        expect(reads.last, {...defaultQuery, 'severity': 'abnormal'});
        await tapFilter(abnormal);
        expect(reads.last, defaultQuery);
        expect(find.text('暂无事件'), findsOneWidget);
        await tester.pumpWidget(
          WearScope(
            session: session,
            child: const MaterialApp(
              home: EventsPage(initialSeverity: 'warning', personId: '42'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(reads.last, {...defaultQuery, 'personId': '42'});
        expect(paths, isNot(contains('/api/v1/events/filter-options')));
        expect(paths, isNot(contains('/api/v1/duty/summary')));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
