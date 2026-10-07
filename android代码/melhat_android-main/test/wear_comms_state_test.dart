import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/communications/models.dart';
import 'package:rolling_intelligence_headband/wear/communications/policy.dart';

void main() {
  group('CallSession server truth', () {
    test(
      'maps every documented server state without treating unknown as connected',
      () {
        final expected = <String, WearCallStatus>{
          'requesting': WearCallStatus.requesting,
          'offered': WearCallStatus.offered,
          'connected': WearCallStatus.connected,
          'ended': WearCallStatus.ended,
          'failed': WearCallStatus.failed,
          'timed_out': WearCallStatus.timedOut,
          'future_state': WearCallStatus.unknown,
        };

        for (final entry in expected.entries) {
          final call = CallSession.fromJson({
            'id': '17',
            'status': entry.key,
            'deviceId': '9',
            'requesterUserId': '4',
          });
          expect(call.status, entry.value);
          expect(call.isConnected, entry.key == 'connected');
        }
      },
    );

    test('demo call never presents a production connected label', () {
      final call = CallSession.fromJson({
        'id': '17',
        'status': 'connected',
        'deviceId': '9',
        'requesterUserId': '4',
        'demo': true,
      });

      expect(call.isConnected, isFalse);
      expect(call.statusLabel, '演示状态（未连接真实设备）');
    });
  });

  group('communications policy', () {
    const device = CommunicationDevice(
      id: '9',
      sn: 'MH-009',
      personId: '21',
      personName: '张三',
      actions: {'tts', 'intercom'},
    );

    test('uses person and stable device ids while honoring capabilities', () {
      final policy = CommunicationsPolicy(
        userId: '4',
        permissions: const {'wear:call:start', 'wear:command:tts'},
      );

      expect(device.personId, '21');
      expect(device.id, '9');
      expect(policy.canStartVoice(device), isTrue);
      expect(policy.canStartVideo(device), isFalse);
      expect(policy.canSendTts(device), isTrue);
    });

    test('only requester can join, fetch credentials, or hang up', () {
      final policy = CommunicationsPolicy(
        userId: '4',
        permissions: const {'wear:call:start'},
      );
      final offered = CallSession.fromJson({
        'id': '17',
        'status': 'offered',
        'deviceId': '9',
        'requesterUserId': '5',
      });

      expect(policy.canJoin(offered), isFalse);
      expect(policy.canReadCredentials(offered), isFalse);
      expect(policy.canEnd(offered), isFalse);
    });
  });
}
