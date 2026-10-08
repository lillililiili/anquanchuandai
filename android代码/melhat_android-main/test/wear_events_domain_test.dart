import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/events/event_models.dart';
import 'package:rolling_intelligence_headband/wear/events/event_policy.dart';

void main() {
  group('WearEvent', () {
    test(
      'platform completion remains separate from external closure and legacy history',
      () {
        for (final status in ['verified', 'confirmed', 'closed']) {
          final event = WearEvent.fromJson({
            'id': '41',
            'status': status,
            'type': 'sos',
            'fieldReportStatus': 'submitted',
            'verificationStatus': status == 'verified' ? 'verified' : 'unknown',
            'reviewStatus': status == 'verified' ? 'approved' : 'unknown',
            'externalClosureStatus': 'not_synced',
          });
          expect(event.isPlatformComplete, isTrue);
          expect(event.externalClosureStatus, 'not_synced');
          expect(event.fieldReportStatus, 'submitted');
          expect(
            event.statusLabel,
            {'verified': '已核验', 'confirmed': '已确认', 'closed': '历史已处理'}[status],
          );
        }
        expect(
          WearEvent.fromJson({
            'id': '42',
            'status': 'pending_review',
          }).isPlatformComplete,
          isFalse,
        );
      },
    );

    test('keeps occurrence-time person and device snapshots', () {
      final event = WearEvent.fromJson({
        'id': '41',
        'type': 'sos',
        'severity': 'emergency',
        'status': 'claimed',
        'personId': '7',
        'personCode': 'P-007',
        'personName': '张工',
        'deviceId': '9',
        'sn': 'MH-009',
        'claimantUserId': '12',
        'version': 3,
        'demo': true,
      });

      expect(event.personName, '张工');
      expect(event.personCode, 'P-007');
      expect(event.deviceId, '9');
      expect(event.sn, 'MH-009');
      expect(event.isHighRisk, isTrue);
      expect(event.version, 3);
      expect(event.demo, isTrue);
    });

    test('rejects an event without a stable id', () {
      expect(
        () => WearEvent.fromJson({'type': 'sos'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('shared verification permissions', () {
    const member = EventActor(
      userId: '13',
      roles: {'wear_member'},
      permissions: {'wear:event:list', 'wear:event:report'},
    );
    const duty = EventActor(
      userId: '14',
      roles: {'wear_duty'},
      permissions: {
        'wear:event:list',
        'wear:event:report',
        'wear:event:claim',
        'wear:event:review',
      },
    );
    const admin = EventActor(
      userId: '12',
      roles: {'admin'},
      permissions: {'*:*:*'},
    );
    WearEvent event(String status, {String state = 'waiting'}) =>
        WearEvent.fromJson({
          'id': '1',
          'type': 'sos',
          'status': status,
          'assistance': {'state': state, 'members': []},
        });
    test(
      'members supplement authorized active events without acquiring review authority',
      () {
        for (final state in ['open', 'field_pending', 'claimed', 'handling']) {
          expect(
            EventPolicy.can(EventCommand.handle, event(state), member),
            isTrue,
          );
          for (final cmd in [
            EventCommand.claim,
            EventCommand.saveVerification,
            EventCommand.verify,
            EventCommand.joinAssistance,
          ]) {
            expect(EventPolicy.can(cmd, event(state), member), isFalse);
          }
        }
        expect(
          EventPolicy.can(EventCommand.handle, event('verified'), member),
          isFalse,
        );
      },
    );
    test(
      'authorized duty and admin can claim, draft and verify using shared states',
      () {
        for (final actor in [duty, admin]) {
          expect(
            EventPolicy.can(EventCommand.claim, event('open'), actor),
            isTrue,
          );
          expect(
            EventPolicy.can(EventCommand.claim, event('handling'), actor),
            isFalse,
          );
          expect(
            EventPolicy.can(
              EventCommand.saveVerification,
              event('handling'),
              actor,
            ),
            isTrue,
          );
          expect(
            EventPolicy.can(EventCommand.verify, event('field_pending'), actor),
            isTrue,
          );
          expect(
            EventPolicy.can(EventCommand.verify, event('verified'), actor),
            isFalse,
          );
          expect(
            EventPolicy.can(EventCommand.joinAssistance, event('open'), actor),
            isTrue,
          );
          expect(
            EventPolicy.can(
              EventCommand.endAssistance,
              event('handling', state: 'active'),
              actor,
            ),
            isTrue,
          );
          expect(
            EventPolicy.can(
              EventCommand.joinAssistance,
              event('handling', state: 'ended'),
              actor,
            ),
            isFalse,
          );
        }
      },
    );
    test(
      'old approval, reopen, transfer, acknowledge and work editing are hidden for everyone',
      () {
        for (final actor in [member, duty, admin]) {
          for (final cmd in [
            EventCommand.ack,
            EventCommand.confirm,
            EventCommand.close,
            EventCommand.reopen,
            EventCommand.transfer,
            EventCommand.assignTask,
          ]) {
            for (final state in [
              'open',
              'handling',
              'pending_review',
              'verified',
              'closed',
            ]) {
              expect(EventPolicy.can(cmd, event(state), actor), isFalse);
            }
          }
        }
      },
    );
  });
}
