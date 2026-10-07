import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/communications/contact_filters.dart';
import 'package:rolling_intelligence_headband/wear/communications/models.dart';
import 'wear_session_test.dart' show transport, reply;

void main() {
  test(
    'one failed device detail does not discard other contact updates',
    () async {
      final api = WearApi(
        token: () => null,
        siteId: () => '1',
        epoch: () => 0,
        dio: transport((r) {
          if (r.path == '/api/v1/devices') {
            return reply({
              'records': [
                for (var i = 1; i <= 8; i++)
                  {'id': '$i', 'typeCode': 'helmet', 'online': '1'},
              ],
              'total': 8,
              'current': 1,
              'size': 100,
            });
          }
          if (r.path.endsWith('/1')) {
            return reply(null, code: 503, msg: '暂时不可用');
          }
          return reply({
            'id': r.path.split('/').last,
            'online': '1',
            'connectionQuality': 'ok',
            'typeCode': 'helmet',
            'currentAssignment': {'personId': '7'},
          });
        }),
      );
      final devices = await ContactRoster.loadDevices(api);
      expect(devices.length, 8);
      expect(devices.last.online, 'online');
      expect(devices.last.personId, '7');
      expect(devices.first.online, 'unknown');
    },
  );
  test(
    'transient failure preserves wearer for display then recovers real status',
    () async {
      var fail = true;
      final api = WearApi(
        token: () => null,
        siteId: () => '1',
        epoch: () => 0,
        dio: transport((r) {
          if (r.path == '/api/v1/devices') {
            return reply({
              'records': [
                {'id': '42', 'sn': 'H42', 'typeCode': 'helmet', 'online': '1'},
              ],
              'total': 1,
            });
          }
          if (fail) return reply(null, code: 503);
          return reply({
            'id': '42',
            'typeCode': 'helmet',
            'online': '1',
            'connectionQuality': 'ok',
            'currentAssignment': {'personId': '8'},
            'capabilities': {
              'actions': ['intercom'],
            },
          });
        }),
      );
      var devices = await ContactRoster.loadDevices(
        api,
        previous: const [
          CommunicationDevice(
            id: '42',
            sn: 'H42',
            typeCode: 'helmet',
            personId: '7',
            online: 'online',
            actions: {'intercom'},
          ),
        ],
      );
      expect(PersonHelmetStatus('7', devices).label, '安全帽状态未知');
      expect(devices.single.supports('intercom'), isFalse);
      fail = false;
      devices = await ContactRoster.loadDevices(api, previous: devices);
      expect(devices.single.personId, '8');
      expect(devices.single.online, 'online');
      expect(devices.single.supports('intercom'), isTrue);
    },
  );
  test('expired authorization is not swallowed as a device outage', () async {
    final api = WearApi(
      token: () => 'expired',
      siteId: () => '1',
      epoch: () => 0,
      dio: transport(
        (r) => r.path == '/api/v1/devices'
            ? reply({
                'records': [
                  {'id': '42'},
                ],
                'total': 1,
              })
            : reply(null, code: 401),
      ),
    );
    await expectLater(
      ContactRoster.loadDevices(api),
      throwsA(isA<WearApiException>().having((e) => e.code, 'code', 401)),
    );
  });
}
