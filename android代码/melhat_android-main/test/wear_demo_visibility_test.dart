import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/shared_models.dart';
import 'package:rolling_intelligence_headband/wear/queries/query_utils.dart';

void main() {
  test(
    'only explicit helmet and belt examples and their assignments are hidden',
    () {
      final source = {
        'devices': [
          {'id': 'h-demo', 'ledgerId': 'lh', 'type': 'H', 'demo': true},
          {'id': 'b-demo', 'type': 'B', 'dataOrigin': 'ADMIN_SEED'},
          {
            'id': 'RL-W001',
            'station': 'S1',
            'type': 'W',
            'source': 'DEMO_WATCH',
            'online': true,
            'battery': 78,
          },
          {'id': 'h-real', 'type': 'H', 'source': 'DIRECT_HELMET'},
          {'id': 'b-stock', 'type': 'B', 'source': 'MANUAL'},
        ],
        'assignments': [
          {'id': 'hidden', 'deviceId': 'lh'},
          {'id': 'kept', 'deviceId': 'h-real'},
        ],
        'events': [
          {'id': 'demo-event', 'deviceId': 'h-demo', 'demo': true},
          {'id': 'real-event', 'deviceId': 'h-demo', 'source': 'DIRECT_HELMET'},
          {'id': 'watch-event', 'deviceType': 'watch', 'demo': true},
        ],
      };
      final model = SharedModels(source);
      expect(model.rows('devices').map((d) => d['id']), [
        'RL-W001',
        'h-real',
        'b-stock',
      ]);
      expect(model.rows('assignments').map((d) => d['id']), ['kept']);
      expect(model.rows('events').map((d) => d['id']), [
        'real-event',
        'watch-event',
      ]);
      expect((source['devices'] as List).length, 5);
      final watch = model.device(model.find('devices', 'RL-W001'));
      expect(watch['battery'], 78);
      expect(watch['online'], 1);
      expect(watch['demo'], true);
      expect(connectionLabel(watch), '模拟数据');
      expect(watch['capabilities']['actions'], isEmpty);
    },
  );

  test('physical devices with simulated connectivity remain registered', () {
    final model = SharedModels({
      'devices': [
        {'id': 'h', 'type': 'H', 'source': 'DIRECT_HELMET', 'simulation': true},
      ],
    });
    expect(model.rows('devices'), hasLength(1));
    expect(model.device(model.find('devices', 'h'))['online'], isNull);
  });

  test(
    'only RL-W001 demo and its demo vitals remain; real watches and evidence survive',
    () {
      final source = {
        'devices': [
          {
            'id': 'RL-W002',
            'ledgerId': 'ledger-2',
            'type': 'W',
            'station': 'S1',
            'source': 'DEMO_WATCH',
          },
          {
            'id': 'RL-W001',
            'ledgerId': 'ledger-1',
            'type': 'W',
            'siteId': 'site-1',
            'source': 'DEMO_WATCH',
          },
          {
            'id': 'real-watch',
            'type': 'W',
            'siteId': 'site-1',
            'source': 'PLATFORM',
            'demo': true,
          },
          {
            'id': 'registered-watch',
            'type': 'W',
            'siteId': 'site-1',
            'source': 'MANUAL',
          },
        ],
        'assignments': [
          {'id': 'a1', 'deviceId': 'ledger-1'},
          {'id': 'a2', 'deviceId': 'ledger-2'},
          {'id': 'ar', 'deviceId': 'real-watch'},
        ],
        'vitals': [
          {'id': 'v1', 'deviceId': 'RL-W001', 'source': 'DEMO_WATCH'},
          {'id': 'v2', 'deviceId': 'RL-W002', 'demo': true},
          {'id': 'unbound-demo', 'deviceId': 'missing', 'source': 'DEMO_WATCH'},
          {
            'id': 'real-vital',
            'deviceId': 'real-watch',
            'source': 'PLATFORM',
            'demo': true,
          },
          {'id': 'real-history', 'deviceId': 'RL-W002', 'source': 'DEVICE'},
        ],
        'events': [
          {'id': 'hidden-demo', 'deviceId': 'RL-W002', 'demo': true},
          {'id': 'real-event', 'deviceId': 'RL-W002', 'source': 'DEVICE'},
        ],
      };
      final model = SharedModels(source);
      expect(model.rows('devices').map((row) => row['id']), [
        'RL-W001',
        'real-watch',
        'registered-watch',
      ]);
      expect(model.rows('assignments').map((row) => row['id']), ['a1', 'ar']);
      expect(model.rows('vitals').map((row) => row['id']), [
        'v1',
        'real-vital',
        'real-history',
      ]);
      expect(model.rows('events').map((row) => row['id']), ['real-event']);
      expect(source['devices'], hasLength(4));
      expect(source['vitals'], hasLength(5));
      expect(model.device(model.find('devices', 'real-watch'))['demo'], false);
    },
  );

  test(
    'missing retained watch or an explicit different site never creates a replacement',
    () {
      for (final row in [
        {'id': 'RL-W001', 'type': 'W', 'station': 'S2', 'demo': true},
        {'id': 'RL-W002', 'type': 'W', 'station': 'S1', 'demo': true},
      ]) {
        final model = SharedModels({
          'devices': [row],
          'vitals': [
            {'deviceId': row['id'], 'source': 'DEMO_WATCH'},
          ],
        });
        expect(model.rows('devices'), isEmpty);
        expect(model.rows('vitals'), isEmpty);
      }
    },
  );
}
