import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/event_models.dart';
import 'package:rolling_intelligence_headband/wear/events/event_location_card.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, identity, reply, transport;

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==';

void main() {
  test('invalid, infinite and out-of-range coordinates are never plotted', () {
    for (final values in [
      ['', ''],
      ['NaN', '120'],
      ['Infinity', '0'],
      ['91', '0'],
      ['31', '181'],
    ]) {
      expect(
        eventLocationPoint(
          WearEvent.fromJson({
            'id': '1',
            'locationLat': values[0],
            'locationLng': values[1],
          }),
        ),
        isNull,
      );
    }
    expect(
      eventLocationPoint(
        WearEvent.fromJson({'id': '1', 'locationLat': '0', 'locationLng': '0'}),
      ),
      isNotNull,
    );
  });

  for (final mode in ['normal', 'sos', 'missing', 'stale', 'failure']) {
    testWidgets('event location uses main backend and handles $mode', (
      tester,
    ) async {
      final requests = <RequestOptions>[];
      var failed = mode == 'failure';
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((request) {
                requests.add(request);
                return failed
                    ? reply(null, code: 503, msg: '底图暂不可用')
                    : reply(_png);
              }),
            )
            ..token = 'map-test-token'
            ..siteId = '1'
            ..me = identity();
      addTearDown(session.dispose);
      final event = WearEvent.fromJson({
        'id': '42',
        'type': mode == 'sos' ? 'sos' : 'realtime',
        'locationLat': mode == 'missing' ? '' : '31.2304',
        'locationLng': mode == 'missing' ? '' : '121.4737',
        'locationQuality': mode == 'stale' ? 'stale' : 'ok',
        'sn': 'QA-H001',
        'occurredAt': '2026-09-21T09:00:00+08:00',
      });
      await tester.pumpWidget(
        WearScope(
          session: session,
          child: MaterialApp(
            home: Scaffold(body: EventLocationCard(event: event)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('事件定位'), findsOneWidget);
      if (mode == 'missing') {
        expect(requests, isEmpty);
        expect(find.byType(FlutterMap), findsNothing);
        expect(find.text('暂无有效定位'), findsOneWidget);
      } else {
        expect(requests, isNotEmpty);
        for (final request in requests) {
          expect(request.uri.host, 'test.invalid');
          expect(request.path, startsWith('/api/v1/events/42/map-tiles/'));
          expect(request.headers['Authorization'], 'Bearer map-test-token');
          expect(request.headers['X-Site-Id'], '1');
        }
        final marker = tester
            .widget<MarkerLayer>(find.byType(MarkerLayer))
            .markers
            .single;
        expect(marker.point.latitude, 31.2304);
        expect(marker.point.longitude, 121.4737);
        if (mode == 'stale') expect(find.text('定位已陈旧'), findsOneWidget);
        if (!failed) {
          expect(find.text('底图暂时无法加载，坐标仍可查看'), findsNothing);
        }
        if (failed) {
          expect(find.text('底图暂时无法加载，坐标仍可查看'), findsOneWidget);
          failed = false;
          await tester.tap(find.text('重试'));
          await tester.pumpAndSettle();
          expect(find.text('底图暂时无法加载，坐标仍可查看'), findsNothing);
        }
        await tester.tap(find.byTooltip('回到事件位置'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
