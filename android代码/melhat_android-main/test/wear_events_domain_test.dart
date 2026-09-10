import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/events/event_models.dart';
import 'package:rolling_intelligence_headband/wear/events/event_policy.dart';

void main() {
  group('WearEvent', () {
    test('keeps occurrence-time person and device snapshots', () {
      final event = WearEvent.fromJson({
        'id': '41',
        'type': 'sos',
        'severity': 'high',
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

  group('EventPolicy', () {
    const duty = EventActor(
      userId: '12',
      roles: {'wear_duty'},
      permissions: {
        'wear:event:list',
        'wear:event:query',
        'wear:event:claim',
        'wear:task:edit',
      },
    );
    const reader = EventActor(
      userId: '88',
      roles: {'wear_readonly'},
      permissions: {'wear:event:list', 'wear:event:query'},
    );
    const reviewer = EventActor(
      userId: '21',
      roles: {'wear_reviewer'},
      permissions: {'wear:event:list', 'wear:event:query', 'wear:event:review'},
    );

    WearEvent event(String type, String status, {String? claimant}) =>
        WearEvent.fromJson({
          'id': '1',
          'type': type,
          'severity': {'sos', 'fall', 'impact'}.contains(type) ? 'high' : 'low',
          'status': status,
          'claimantUserId': claimant,
          'version': 1,
        });

    test('readers can acknowledge visible events but cannot mutate state', () {
      final open = event('sos', 'open');
      expect(EventPolicy.can(EventCommand.ack, open, reader), isTrue);
      expect(EventPolicy.can(EventCommand.claim, open, reader), isFalse);
    });

    test('claim, handle and transfer enforce role, status and ownership', () {
      expect(
        EventPolicy.can(EventCommand.claim, event('sos', 'open'), duty),
        isTrue,
      );
      expect(
        EventPolicy.can(
          EventCommand.handle,
          event('sos', 'claimed', claimant: '12'),
          duty,
        ),
        isTrue,
      );
      expect(
        EventPolicy.can(
          EventCommand.transfer,
          event('sos', 'handling', claimant: '77'),
          duty,
        ),
        isFalse,
      );
    });

    test('close and reopen follow backend risk-specific gates', () {
      expect(
        EventPolicy.can(
          EventCommand.close,
          event('geofence', 'handling'),
          duty,
        ),
        isTrue,
      );
      expect(
        EventPolicy.can(
          EventCommand.close,
          event('sos', 'pending_review'),
          duty,
        ),
        isFalse,
      );
      expect(
        EventPolicy.can(
          EventCommand.close,
          event('sos', 'pending_review'),
          reviewer,
        ),
        isTrue,
      );
      expect(
        EventPolicy.can(EventCommand.reopen, event('sos', 'closed'), reviewer),
        isTrue,
      );
    });

    test('only duty operators can manually resolve a pending task match', () {
      final pending = WearEvent.fromJson({
        'id': '1',
        'type': 'sos',
        'severity': 'high',
        'status': 'open',
        'taskMatch': 'pending',
        'version': 2,
      });
      expect(EventPolicy.can(EventCommand.assignTask, pending, duty), isTrue);
      expect(
        EventPolicy.can(EventCommand.assignTask, pending, reviewer),
        isFalse,
      );
      expect(
        EventPolicy.can(EventCommand.assignTask, pending, reader),
        isFalse,
      );
    });
  });
}
