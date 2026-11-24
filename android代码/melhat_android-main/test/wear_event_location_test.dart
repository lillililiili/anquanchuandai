import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/event_models.dart';
import 'package:rolling_intelligence_headband/wear/events/event_location.dart';
import 'package:rolling_intelligence_headband/wear/events/event_location_card.dart';
import 'package:rolling_intelligence_headband/wear/location_map.dart';
import 'wear_session_test.dart' show reply, transport;

void main() {
  Map<String, dynamic> sample() => {
    'id': 'e1',
    'deviceId': 'h1',
    'personId': 'p1',
    'siteId': 's1',
    'bindingId': 'b1',
    'protocol': 'direct-helmet',
    'locationLat': 31.2,
    'locationLng': 121.4,
    'locationQuality': 'valid',
    'coordinateSystem': 'GCJ02',
    'locationReportedAt': '2026-10-23T01:00:00Z',
  };
  WearApi history(List<JsonMap> rows, {String? cursor}) => WearApi(
    mock: false,
    token: () => 'test',
    siteId: () => 's1',
    epoch: () => 1,
    dio: transport((request) {
      expect(request.method, 'GET');
      expect(request.path, '/api/guardian/v1/locations/history');
      expect(request.queryParameters['personId'], 'p1');
      return reply({'rows': rows, 'nextCursor': cursor}, raw: true);
    }),
  );
  final recorded = {
    'deviceId': 'h1',
    'personId': 'p1',
    'siteId': 's1',
    'bindingId': 'b1',
    'source': 'direct-helmet',
    'latitude': 31.2,
    'longitude': 121.4,
    'locationQuality': 'valid',
    'coordinateSystem': 'GCJ02',
    'locationReportedAt': '2026-10-23T00:59:59.750Z',
  };
  WearEvent sos([JsonMap overrides = const {}]) => WearEvent.fromJson({
    ...sample(),
    'coordinateSystem': 'UNKNOWN',
    'locationQuality': 'unknown',
    'occurredAt': '2026-10-23T01:00:03Z',
    ...overrides,
  });
  test(
    'direct SOS uses its matching archived report and original coordinates',
    () async {
      final event = sos();
      final fix = await historicalEventFix(history([recorded]), event);
      expect(fix?.point.latitude, 31.2);
      expect(fix?.point.longitude, 121.4);
      expect(fix?.system, 'GCJ02');
      expect(event.coordinateSystem, 'UNKNOWN');
    },
  );
  test(
    'historical evidence must agree on ownership, time, coordinates and quality',
    () async {
      for (final patch in <JsonMap>[
        {'siteId': 'other-site'},
        {'personId': 'other-person'},
        {'bindingId': 'next-issuance'},
        {'deviceId': 'other-device'},
        {'source': 'offline'},
        {'longitude': 121.400001},
        {'coordinateSystem': 'UNKNOWN'},
        {'locationQuality': 'unknown'},
        {'locationSource': 'CACHED'},
        {'locationReportedAt': '2026-10-23T00:59:50Z'},
        {'locationReportedAt': '2026-10-23T01:00:01Z'},
      ]) {
        expect(
          await historicalEventFix(
            history([
              {...recorded, ...patch},
            ]),
            sos(),
          ),
          isNull,
          reason: '$patch',
        );
      }
      expect(
        await historicalEventFix(
          history([
            recorded,
            {...recorded, 'coordinateSystem': 'WGS84'},
          ]),
          sos(),
        ),
        isNull,
      );
      expect(
        await historicalEventFix(
          history([
            recorded,
            {
              ...recorded,
              'latitude': 32,
              'locationReportedAt': '2026-10-23T01:00:00Z',
            },
          ]),
          sos(),
        ),
        isNull,
      );
      expect(
        await historicalEventFix(history([recorded], cursor: 'more'), sos()),
        isNull,
      );
      expect(
        await historicalEventFix(
          history([recorded]),
          sos({'locationReportedAt': ''}),
        ),
        isNull,
      );
      expect(
        await historicalEventFix(
          history([recorded]),
          sos({'locationQuality': 'stale'}),
        ),
        isNull,
      );
      expect(
        await historicalEventFix(
          history([recorded]),
          sos({'protocol': 'split-helmet'}),
        ),
        isNull,
      );
    },
  );
  test(
    'known valid event preserves its original coordinate system and snapshot',
    () {
      final e = WearEvent.fromJson(sample());
      expect(eventLocationPoint(e)!.latitude, 31.2);
      expect(e.coordinateSystem, 'GCJ02');
      expect(e.locationReportedAt, '2026-10-23T01:00:00Z');
    },
  );
  test('unknown, stale and invalid event fixes are never plotted', () {
    for (final patch in [
      {'coordinateSystem': 'UNKNOWN'},
      {'coordinateSystem': null},
      {'locationQuality': 'unknown'},
      {'locationQuality': 'stale'},
      {'locationLat': double.nan},
      {'locationLat': 91},
      {'locationLng': 181},
      {'locationLat': 0, 'locationLng': 0},
    ]) {
      expect(
        eventLocationPoint(WearEvent.fromJson({...sample(), ...patch})),
        isNull,
      );
    }
  });
  testWidgets(
    'unknown event retains raw evidence without rendering a misleading map',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventLocationCard(
              api: history([]),
              event: WearEvent.fromJson({
                ...sample(),
                'coordinateSystem': 'UNKNOWN',
              }),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(VerifiedLocationMap), findsNothing);
      expect(find.textContaining('原始纬度 31.2'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('event-location-unavailable')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
