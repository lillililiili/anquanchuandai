import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/events/event_models.dart';
import 'package:rolling_intelligence_headband/wear/events/event_location_card.dart';
import 'package:rolling_intelligence_headband/wear/location_map.dart';

void main() {
  Map<String, dynamic> sample() => {
    'id': 'e1',
    'deviceId': 'h1',
    'locationLat': 31.2,
    'locationLng': 121.4,
    'locationQuality': 'valid',
    'coordinateSystem': 'GCJ02',
    'locationReportedAt': '2026-10-23T01:00:00Z',
  };
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
              event: WearEvent.fromJson({
                ...sample(),
                'coordinateSystem': 'UNKNOWN',
              }),
            ),
          ),
        ),
      );
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
