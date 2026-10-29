import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/data.dart';
import 'package:rolling_intelligence_headband/wear/shared_models.dart';
import 'package:rolling_intelligence_headband/wear/shared_backend.dart';
import 'package:rolling_intelligence_headband/wear/api.dart';
import 'package:rolling_intelligence_headband/wear/person_equipment_context.dart';
import 'package:rolling_intelligence_headband/wear/communications/models.dart'
    hide JsonMap;
import 'package:rolling_intelligence_headband/wear/communications/policy.dart';

void main() {
  JsonMap device() => {
    'id': 'h',
    'ledgerId': 'LH',
    'type': 'H',
    'source': 'DIRECT_HELMET',
    'active': true,
    'online': true,
    'freshness': 'CURRENT',
    'updated': DateTime.now()
        .subtract(const Duration(seconds: 1))
        .toIso8601String(),
    'communicationProtocol': 'SIP',
    'capabilities': ['intercom'],
    'featureStates': {
      'voice': {'supported': true, 'verified': true, 'available': true},
      'video': {'supported': true, 'verified': true, 'available': true},
    },
  };
  JsonMap context() => {
    'personId': 'P1',
    'devices': [
      {
        'deviceId': 'h',
        'ledgerDeviceId': 'LH',
        'assignmentId': 'A1',
        'assignmentVersion': 2,
      },
    ],
    'features': {
      'voice': {
        'supported': true,
        'verified': true,
        'available': true,
        'deviceId': 'h',
        'assignmentId': 'A1',
        'assignmentVersion': 2,
      },
    },
  };
  test(
    'live actions require exact server person and issue context, not only online hardware',
    () {
      final d = device();
      expect(
        SharedModels({
          'devices': [d],
        }).device(d)['capabilities']['actions'],
        isEmpty,
      );
      final model = SharedModels({
        'personEquipmentContext': {'P1': context()},
        'devices': [d],
      });
      final projected = model.device(d);
      expect(projected['capabilities']['actions'], ['intercom']);
      expect(projected['equipmentContext']['personId'], 'P1');
      final changed = context();
      changed['features']['voice']['assignmentVersion'] = 1;
      expect(
        SharedModels({
          'personEquipmentContext': {'P1': changed},
        }).device(d)['capabilities']['actions'],
        isEmpty,
      );
      expect(d['featureStates']['voice']['available'], true);
    },
  );
  test('live video support is distinct from a two-way video call', () {
    const policy = CommunicationsPolicy(
      userId: 'u',
      permissions: {'wear:call:start'},
    );
    final d = CommunicationDevice.fromJson(device());
    expect(policy.canStartVoice(d), true);
    expect(policy.canStartVideo(d), false);
  });
  test('same person reissue is a different context', () {
    expect(
      sameEquipmentContext(
        {'personId': 'P', 'assignmentId': 'A', 'assignmentVersion': 1},
        {'personId': 'P', 'assignmentId': 'A', 'assignmentVersion': 2},
      ),
      false,
    );
  });
  test(
    'missing call and broadcast context is rejected before transport',
    () async {
      var sent = 0;
      final backend = SharedBackend(
        (method, path, {data, query, contentType}) async {
          sent++;
          return {};
        },
        () => 'site-1',
        () => 0,
        testSiteMode: false,
      );
      await expectLater(
        backend.route('POST', '/api/v1/calls', data: {'deviceId': 'h'}),
        throwsA(isA<WearApiException>()),
      );
      await expectLater(
        backend.route(
          'POST',
          '/api/v1/commands/tts',
          data: {
            'deviceIds': ['h'],
            'text': 'test',
          },
        ),
        throwsA(isA<WearApiException>()),
      );
      expect(sent, 0);
    },
  );
  test(
    'uncertain write retry keeps the original issuance and request key',
    () async {
      final sent = <JsonMap>[];
      final backend = SharedBackend(
        (method, path, {data, query, contentType}) async {
          sent.add(jsonMap(data));
          if (sent.length == 1) throw const WearApiException(503, 'unknown');
          return {'id': 'call'};
        },
        () => 'site-1',
        () => 0,
        testSiteMode: false,
      );
      final input = {
        'deviceId': 'h',
        'personId': 'P1',
        'assignmentId': 'A1',
        'assignmentVersion': 2,
      };
      await expectLater(
        backend.route('POST', '/api/v1/calls', data: input),
        throwsA(isA<WearApiException>()),
      );
      await backend.route('POST', '/api/v1/calls', data: input);
      expect(sent[0]['idempotencyKey'], sent[1]['idempotencyKey']);
      expect(sent[1]['assignmentVersion'], 2);
    },
  );
}
