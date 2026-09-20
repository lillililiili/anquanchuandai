import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/tracks.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, identity, reply, transport;

void main() {
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'track preview plays and seeks without querying real tracks at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final requests = <RequestOptions>[];
        final session =
            WearSession(
                credentials: MemoryCredentials(),
                dio: transport((r) {
                  requests.add(r);
                  return reply({
                    'records': [],
                    'total': 0,
                    'current': 1,
                    'size': 100,
                  });
                }),
              )
              ..initialized = true
              ..token = 'test'
              ..siteId = '1'
              ..me = identity();
        addTearDown(session.dispose);
        await tester.pumpWidget(
          WearScope(
            session: session,
            child: MaterialApp(
              theme: ThemeData(useMaterial3: true),
              home: const TracksPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('track-preview')));
        await tester.pumpAndSettle();
        expect(find.text('陈建国（示例）'), findsOneWidget);
        Future<void> click(Finder f) async {
          await tester.ensureVisible(f);
          await tester.pumpAndSettle();
          await tester.tap(f);
          await tester.pumpAndSettle();
        }

        await click(find.byKey(const ValueKey('track-play')));
        await tester.pump(const Duration(milliseconds: 900));
        expect(
          tester
              .widget<Slider>(find.byKey(const ValueKey('track-progress')))
              .value,
          greaterThan(0),
        );
        await tester.tap(find.byKey(const ValueKey('track-play')));
        await tester.pumpAndSettle();
        final slider = tester.widget<Slider>(
          find.byKey(const ValueKey('track-progress')),
        );
        slider.onChanged!(5);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Slider>(find.byKey(const ValueKey('track-progress')))
              .value,
          5,
        );
        await click(find.text('回放选项'));
        await click(find.text('2x'));
        await click(find.text('定位时间'));
        expect(find.byType(DatePickerDialog), findsOneWidget);
        Navigator.of(tester.element(find.byType(DatePickerDialog))).pop();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('当前数据'));
        await tester.pumpAndSettle();
        expect(find.text('9 个示例轨迹点'), findsOneWidget);
        expect(requests.where((r) => r.path.endsWith('/tracks')), isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('person picker retains stable-id query dates and empty state', (
    tester,
  ) async {
    final queries = <RequestOptions>[];
    final session =
        WearSession(
            credentials: MemoryCredentials(),
            dio: transport((r) {
              if (r.path == '/api/v1/people') {
                return reply({
                  'records': [
                    {
                      'id': 'p-7',
                      'name': '测试人员',
                      'personCode': 'P007',
                      'status': '0',
                    },
                  ],
                  'total': 1,
                  'current': 1,
                  'size': 100,
                });
              }
              if (r.path.endsWith('/tracks')) queries.add(r);
              return reply({
                'records': [],
                'total': 0,
                'current': 1,
                'size': 100,
              });
            }),
          )
          ..initialized = true
          ..token = 'test'
          ..siteId = '1'
          ..me = identity();
    addTearDown(session.dispose);
    await tester.pumpWidget(
      WearScope(
        session: session,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const TracksPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('track-person-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('track-person-p-7')));
    await tester.pumpAndSettle();
    expect(queries.single.path, '/api/v1/locations/people/p-7/tracks');
    expect(queries.single.queryParameters['from'], isNotEmpty);
    expect(queries.single.queryParameters['to'], isNotEmpty);
    expect(find.text('该时段没有轨迹点'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('track-play')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('track-query')));
    await tester.pumpAndSettle();
    expect(queries.length, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
