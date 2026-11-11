import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/api.dart';
import 'package:rolling_intelligence_headband/wear/device_location.dart';
import 'package:rolling_intelligence_headband/wear/location_map.dart';
import 'package:rolling_intelligence_headband/wear/queries/belt_telemetry.dart';
import 'package:rolling_intelligence_headband/wear/server_clock.dart';
import 'package:rolling_intelligence_headband/wear/shared_models.dart';

import 'wear_session_test.dart' show transport;

void main() {
  final serverTime = DateTime.utc(2040, 1, 2, 3, 4, 5);
  final header = HttpDate.format(serverTime);

  setUp(serverClock.reset);
  tearDown(serverClock.reset);

  test(
    'server Date handles fast and slow phone clocks and second precision',
    () {
      for (final skew in [-3, 3]) {
        final clock = ServerClock(
          wallNow: () => serverTime.add(Duration(seconds: skew)),
          elapsed: () => Duration.zero,
        );
        expect(clock.observeHttpDate(header), true);
        final report = serverTime.add(const Duration(milliseconds: 900));
        expect(
          clock.now().difference(report),
          const Duration(milliseconds: 99),
        );
      }
    },
  );

  test('monotonic elapsed expires data despite phone wall-clock changes', () {
    var wall = serverTime.subtract(const Duration(seconds: 3));
    var elapsed = Duration.zero;
    final clock = ServerClock(wallNow: () => wall, elapsed: () => elapsed);
    expect(clock.now(), wall);
    clock.observeHttpDate(header);
    final observed = clock.now();
    wall = wall.subtract(const Duration(days: 1));
    elapsed = const Duration(minutes: 5);
    expect(clock.now().difference(observed), const Duration(minutes: 5));
    elapsed += const Duration(milliseconds: 1);
    expect(
      clock.now().difference(observed),
      greaterThan(const Duration(minutes: 5)),
    );
    clock.reset();
    expect(clock.now(), wall);
  });

  test('missing, malformed, repeated and late dates never roll time back', () {
    var elapsed = Duration.zero;
    final clock = ServerClock(
      wallNow: () => serverTime,
      elapsed: () => elapsed,
    );
    final oldRequest = clock.startRequest();
    elapsed = const Duration(seconds: 1);
    final newerRequest = clock.startRequest();
    expect(clock.observeHttpDate(header, requestStartedAt: newerRequest), true);
    elapsed += const Duration(milliseconds: 200);
    final current = clock.now();
    expect(clock.observeHttpDate(null), false);
    expect(clock.observeHttpDate('not a date'), false);
    expect(clock.observeHttpDate(header), true);
    expect(clock.now(), current);
    expect(
      clock.observeHttpDate(
        HttpDate.format(serverTime.add(const Duration(hours: 1))),
        requestStartedAt: oldRequest,
      ),
      false,
    );
    expect(clock.now(), current);
  });

  ResponseBody response({
    String? date,
    int status = 200,
    Object? data = const {},
  }) => ResponseBody.fromString(
    jsonEncode({'code': status, 'data': data}),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      if (date != null) 'date': [date],
    },
  );

  WearApi api(
    FutureOr<ResponseBody> Function(RequestOptions) handler, {
    int Function()? epoch,
  }) => WearApi(
    mock: false,
    dio: transport(handler),
    token: () => 'test-token',
    siteId: () => 'site-1',
    epoch: epoch ?? () => 1,
  );

  test(
    'successful API Date synchronizes device, feature and location freshness',
    () async {
      final client = api((_) => response(date: header));
      await client.get('/api/guardian/v1/mobile/context');
      final reportTime = serverTime
          .add(const Duration(milliseconds: 900))
          .toIso8601String();
      final state = {
        'personEquipmentContext': {
          'P1': {
            'personId': 'P1',
            'devices': [
              {
                'deviceId': 'helmet-1',
                'assignmentId': 'A1',
                'assignmentVersion': 1,
              },
            ],
            'features': {
              'voice': {
                'deviceId': 'helmet-1',
                'assignmentId': 'A1',
                'assignmentVersion': 1,
                'supported': true,
                'verified': true,
                'available': true,
              },
            },
          },
        },
      };
      final helmet = <String, dynamic>{
        'id': 'helmet-1',
        'type': 'H',
        'source': 'DIRECT_HELMET',
        'online': true,
        'freshness': 'CURRENT',
        'sourceTime': reportTime,
        'battery': 67,
        'batteryFreshness': 'CURRENT',
        'latitude': 35.4,
        'longitude': 112.5,
        'coordinateSystem': 'GCJ02',
        'locationFreshness': 'CURRENT',
        'locationReportedAt': reportTime,
      };
      final belt = {
        ...helmet,
        'id': 'belt-1',
        'type': 'B',
        'source': 'DIRECT_BELT',
        'telemetryFreshness': 'CURRENT',
        'telemetryReportedAt': reportTime,
      };
      final models = SharedModels(state);
      for (final device in [helmet, belt]) {
        expect(models.device(device)['online'], 1);
        expect(models.device(device)['battery'], 67);
        expect(deviceLocation(device).status, '近期上报');
        expect(isCurrentLocation(device), true);
      }
      expect(
        models.device(helmet)['featureStates']['voice']['available'],
        true,
      );
      expect(BeltTelemetryView(belt).current, true);

      final futureTime = serverTime
          .add(const Duration(minutes: 1))
          .toIso8601String();
      expect(
        models.device({...helmet, 'sourceTime': futureTime})['online'],
        isNull,
      );
      expect(
        isCurrentLocation({...helmet, 'locationReportedAt': futureTime}),
        false,
      );
      expect(
        BeltTelemetryView({...belt, 'telemetryReportedAt': futureTime}).current,
        false,
      );
      expect(models.device({...helmet, 'online': false})['online'], 0);
      expect(
        models.device({...helmet, 'freshness': 'STALE'})['online'],
        isNull,
      );

      serverClock.observeHttpDate(
        HttpDate.format(serverTime.add(const Duration(minutes: 6))),
      );
      expect(models.device(helmet)['online'], isNull);
      expect(
        models.device(helmet)['featureStates']['voice']['available'],
        false,
      );
      expect(isCurrentLocation(helmet), false);
      expect(deviceLocation(helmet).status, '最后上报（已过期）');
      expect(BeltTelemetryView(belt).current, false);
      client.invalidate();
      expect(
        serverClock.now().difference(DateTime.now()).abs(),
        lessThan(const Duration(seconds: 1)),
      );
    },
  );

  test(
    'missing, invalid and failed API dates preserve the local fallback',
    () async {
      for (final date in [null, 'invalid date']) {
        await api(
          (_) => response(date: date),
        ).get('/api/guardian/v1/mobile/context');
        expect(
          serverClock.now().difference(DateTime.now()).abs(),
          lessThan(const Duration(seconds: 1)),
        );
      }
      await expectLater(
        api(
          (_) => response(date: header, status: 401),
        ).get('/api/guardian/v1/mobile/context'),
        throwsA(isA<WearApiException>()),
      );
      expect(
        serverClock.now().difference(DateTime.now()).abs(),
        lessThan(const Duration(seconds: 1)),
      );
    },
  );

  test(
    'late response from a previous session cannot calibrate the new session',
    () async {
      final pending = Completer<ResponseBody>();
      var epoch = 1;
      final client = api((_) => pending.future, epoch: () => epoch);
      final request = client.get('/api/guardian/v1/mobile/context');
      epoch++;
      pending.complete(response(date: header));
      await expectLater(request, throwsA(isA<StaleSessionException>()));
      expect(
        serverClock.now().difference(DateTime.now()).abs(),
        lessThan(const Duration(seconds: 1)),
      );
    },
  );

  test('captured cleanup response cannot calibrate a newer session', () async {
    final client = api((_) => response(date: header));
    final cleanup = client.captureViewerRelease(
      deviceId: 'helmet-1',
      viewerSessionId: 'viewer-1',
      identity: {
        'personId': 'P1',
        'assignmentId': 'A1',
        'assignmentVersion': 1,
      },
    );
    await cleanup();
    expect(
      serverClock.now().difference(DateTime.now()).abs(),
      lessThan(const Duration(seconds: 1)),
    );
  });
}
