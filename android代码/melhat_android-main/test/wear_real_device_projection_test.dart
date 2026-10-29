import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/shared_models.dart';

void main() {
  Map<String, dynamic> device({
    String source = 'DIRECT_HELMET',
    String protocol = 'SIP',
    Object? capabilities,
  }) => {
    'id': 'portal-helmet-1',
    'sn': 'SN-1020-1',
    'deviceNumber': 'device-1020-1',
    'type': 'H',
    'source': source,
    'communicationProtocol': protocol,
    'freshness': 'CURRENT',
    'updated': DateTime.now()
        .subtract(const Duration(seconds: 1))
        .toUtc()
        .toIso8601String(),
    'online': true,
    'battery': 67,
    'batteryFreshness': 'CURRENT',
    'isWearedFreshness': 'CURRENT',
    'worn': true,
    'capabilities': capabilities,
  };
  final model = SharedModels({});

  test(
    'device detail uses its authorized site and actual report timestamp',
    () {
      const reportedAt = '2026-10-29T07:36:30Z';
      final scoped = SharedModels({
        'operator': {
          'sites': [
            {'id': 'site-other', 'name': '另一厂站'},
            {'id': 'site-1', 'name': '测试厂区'},
          ],
        },
      });
      final projected = scoped.device({
        ...device(source: 'DIRECT_BELT'),
        'siteId': 'site-1',
        'sourceTime': reportedAt,
        'online': false,
      });
      expect(projected['siteName'], '测试厂区');
      expect(projected['lastReportedAt'], reportedAt);
      expect(projected['online'], 0);

      final unknown = scoped.device({
        ...device(),
        'siteId': 'unavailable-site',
        'locationReportedAt': reportedAt,
      });
      expect(unknown['siteName'], isNull);
      expect(unknown['lastReportedAt'], isNull);
    },
  );

  test(
    'direct belt keeps unknown hook meanings and cannot use helmet media',
    () {
      final raw = {
        ...device(
          source: 'DIRECT_BELT',
          protocol: 'WEBSOCKET',
          capabilities: ['intercom', 'tts'],
        ),
        'type': 'B',
        'worn': null,
        'isWeared': '2',
        'hangerAStatus': '1',
        'hangerBStatus': '0',
        'hookAEngaged': null,
        'hookBEngaged': null,
      };
      final projected = model.device(raw);
      expect(projected['typeCode'], 'belt');
      expect(projected['online'], 1);
      expect(projected['battery'], 67);
      expect(projected['worn'], isNull);
      expect(projected['isWeared'], '2');
      expect(projected['hangerAStatus'], '1');
      expect(projected['hangerBStatus'], '0');
      expect(projected['hookAEngaged'], isNull);
      expect(projected['hookBEngaged'], isNull);
      expect(projected['capabilities']['actions'], isEmpty);
      final stale = model.device({
        ...raw,
        'freshness': 'STALE',
        'hookAEngaged': true,
        'hookBEngaged': false,
      });
      expect(stale['hookAEngaged'], isNull);
      expect(stale['hookBEngaged'], isNull);
      expect(stale['online'], isNull);
    },
  );

  test(
    'direct helmet retains physical identity and actual current telemetry',
    () {
      final projected = model.device(device());
      expect(projected['id'], 'portal-helmet-1');
      expect(projected['sn'], 'SN-1020-1');
      expect(projected['deviceNumber'], 'device-1020-1');
      expect(projected['communicationProtocol'], 'SIP');
      expect(projected['online'], 1);
      expect(projected['battery'], 67);
      expect(projected['worn'], true);
      expect(projected['connectionQuality'], 'ok');
      expect(projected['capabilities']['actions'], isEmpty);
    },
  );

  test('legacy platform source alone never grants voice or broadcast', () {
    expect(
      model.device(
        device(source: 'PLATFORM', protocol: ''),
      )['capabilities']['actions'],
      isEmpty,
    );
    final explicit = model.device(
      device(
        source: 'PLATFORM',
        protocol: 'AGORA',
        capabilities: {
          'actions': ['intercom', 'tts'],
        },
      ),
    );
    expect(explicit['capabilities']['actions'], isEmpty);
    expect(explicit['featureStates']['voice']['supported'], true);
    expect(explicit['featureStates']['voice']['verified'], false);
  });

  test('declared SIP commands require shared backend acceptance', () {
    final projected = model.device(device(capabilities: ['intercom', 'tts']));
    expect(projected['capabilities']['actions'], isEmpty);
    expect(projected['featureStates']['voice']['reason'], '请先办理人员领用');
    final verified = model.device({
      ...device(capabilities: ['intercom', 'tts']),
      'featureStates': {
        'voice': {'supported': true, 'verified': true, 'available': true},
        'broadcast': {'supported': true, 'verified': true, 'available': true},
      },
    });
    expect(verified['capabilities']['actions'], isEmpty);
  });

  test('stale, future and missing observation times are never current', () {
    for (final patch in [
      {'freshness': 'STALE'},
      {
        'updated': DateTime.now()
            .subtract(const Duration(minutes: 6))
            .toIso8601String(),
      },
      {
        'updated': DateTime.now()
            .add(const Duration(minutes: 1))
            .toIso8601String(),
      },
      {'updated': null},
    ]) {
      final projected = model.device({
        ...device(capabilities: ['tts']),
        ...patch,
      });
      expect(projected['online'], isNull);
      expect(projected['battery'], isNull);
      expect(projected['worn'], isNull);
      expect(projected['capabilities']['actions'], isEmpty);
      expect(projected['connectionQuality'], isNot('ok'));
    }
  });

  test('offline and unknown are distinct and invalid battery stays absent', () {
    final offline = model.device({...device(), 'online': false, 'battery': -1});
    expect(offline['online'], 0);
    expect(offline['battery'], isNull);
    final unknown = model.device({
      ...device(),
      'online': null,
      'battery': 'bad',
    });
    expect(unknown['online'], isNull);
    expect(unknown['connectionQuality'], 'unknown');
    expect(unknown['battery'], isNull);
  });

  test(
    'explicit disconnect stays offline even when the last observation is stale',
    () {
      final projected = model.device({
        ...device(),
        'online': false,
        'freshness': 'STALE',
      });
      expect(projected['online'], 0);
      expect(projected['connectionQuality'], 'ok');
      expect(projected['battery'], isNull);
    },
  );

  test(
    'flat device capabilities retain real metrics without inventing commands',
    () {
      final projected = model.device(
        device(capabilities: ['battery', 'wear', 'location', 'alarm', 'sos']),
      );
      expect(projected['capabilities']['metrics'], [
        'battery',
        'wear',
        'location',
      ]);
      expect(projected['capabilities']['actions'], isEmpty);
    },
  );

  test('missing SN falls back to physical device number before portal ID', () {
    final row = device()..remove('sn');
    expect(model.device(row)['sn'], 'device-1020-1');
  });

  test(
    'current assignment retains device SN without replacing platform keys',
    () {
      final row = {...device(), 'ledgerId': 'ledger-1'};
      final models = SharedModels({
        'devices': [row],
      });
      final assignment = models.assignment({
        'deviceId': 'ledger-1',
        'personId': 'P1',
      });
      expect(assignment['deviceId'], 'portal-helmet-1');
      expect(assignment['sn'], 'SN-1020-1');
    },
  );
}
