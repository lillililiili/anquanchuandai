import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:rolling_intelligence_headband/wear/shared_models.dart';
import 'package:rolling_intelligence_headband/wear/shared_backend.dart';
import 'package:rolling_intelligence_headband/wear/location_map.dart';
import 'package:rolling_intelligence_headband/wear/communications/models.dart';

void main() {
  test('public API deployment prefix survives an absolute API path', () {
    expect(
      RequestOptions(
        baseUrl: 'https://example.invalid/wear-api',
        path: '/api/guardian/v1/mobile/login',
      ).uri.path,
      '/wear-api/api/guardian/v1/mobile/login',
    );
  });
  test(
    'fresh SOS/connection cannot refresh omitted battery or wear fields',
    () {
      final row = SharedModels({}).device({
        'id': 'h',
        'type': 'H',
        'source': 'DIRECT_HELMET',
        'freshness': 'CURRENT',
        'updated': DateTime.now()
            .subtract(const Duration(seconds: 1))
            .toIso8601String(),
        'online': true,
        'battery': 90,
        'batteryFreshness': 'STALE',
        'worn': true,
        'isWearedFreshness': 'UNKNOWN',
      });
      expect(row['online'], 1);
      expect(row['battery'], isNull);
      expect(row['worn'], isNull);
    },
  );
  test(
    'authorized history forwards cursors without requesting synthetic context',
    () async {
      final calls = <String>[];
      final shared = SharedBackend(
        (method, path, {data, query, contentType}) async {
          calls.add(path);
          expect(query!['cursor'], 'next');
          return {'rows': [], 'nextCursor': null};
        },
        () => 's1',
        () => 1,
      );
      await shared.route(
        'GET',
        '/api/v1/locations/history',
        query: {'personId': 'p', 'cursor': 'next'},
      );
      expect(calls, ['/api/guardian/v1/locations/history']);
    },
  );
  test('track breaks on missing quality, large gaps and different devices', () {
    Map<String, dynamic> p(
      int minute, {
      String device = 'h',
      String quality = 'valid',
    }) => {
      'latitude': 31.2 + minute * .001,
      'longitude': 121.4,
      'coordinateSystem': 'GCJ02',
      'locationQuality': quality,
      'deviceId': device,
      'reportedAt': DateTime.utc(2026, 10, 23, 0, minute).toIso8601String(),
    };
    final segments = locationSegments([
      p(0),
      p(1),
      p(2, quality: 'unknown'),
      p(3),
      p(9),
      p(10, device: 'h2'),
    ], 'GCJ02');
    expect(segments.map((s) => s.length).toList(), [2, 1, 1, 1]);
  });
  test('SIP credential validation cannot fall through into Agora', () {
    final c = RtcCredentials.fromJson({
      'protocol': 'SIP',
      'server': 'wss://example.invalid/sip',
      'uri': 'sip:a@example.invalid',
      'target': 'sip:room@example.invalid',
      'authorizationUsername': 'a',
      'authorizationPassword': 'test-only',
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 5))
          .toIso8601String(),
    });
    expect(c.isUsable, isTrue);
    expect(c.appId, isEmpty);
    expect(c.protocol, 'SIP');
    expect(
      RtcCredentials.fromJson({
        'protocol': 'SIP',
        'agoraAppId': 'x',
        'agoraUid': 1,
        'agoraToken': 'x',
        'channelName': 'x',
      }).isUsable,
      isFalse,
    );
  });
}
