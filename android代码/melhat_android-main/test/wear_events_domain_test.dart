import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/events/event_models.dart';
import 'package:rolling_intelligence_headband/wear/events/event_policy.dart';

void main() {
  group('WearEvent', () {
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

  group('inspection event permissions', () {
    const inspector = EventActor(
      userId: '12',
      roles: {'wear_duty'},
      permissions: {
        'wear:event:list',
        'wear:event:claim',
        'wear:task:edit',
        'wear:event:review',
      },
    );
    const formerReviewer = EventActor(
      userId: '21',
      roles: {'wear_reviewer'},
      permissions: {'*:*:*'},
    );
    const admin = EventActor(
      userId: '1',
      roles: {'admin'},
      permissions: {'*:*:*'},
    );
    WearEvent event(String status, {bool reminder = false}) =>
        WearEvent.fromJson({
          'id': '1',
          'type': 'realtime',
          'status': status,
          'claimantUserId': '99',
          'taskMatch': 'pending',
          'reminderOnly': reminder,
          'severity': reminder ? 'warning' : 'emergency',
        });
    test('any returned group member can report without claim or ownership', () {
      for (final status in ['open', 'claimed', 'handling']) {
        expect(
          EventPolicy.can(EventCommand.handle, event(status), inspector),
          isTrue,
        );
        expect(
          EventPolicy.can(EventCommand.claim, event(status), inspector),
          isFalse,
        );
        expect(
          EventPolicy.can(EventCommand.transfer, event(status), inspector),
          isFalse,
        );
      }
      expect(
        EventPolicy.can(
          EventCommand.handle,
          event('pending_review'),
          inspector,
        ),
        isFalse,
      );
      expect(event('pending_review').statusFor(admin: false), '待管理员审批');
    });
    test('only administrators review, reopen and associate tasks', () {
      for (final actor in [inspector, formerReviewer]) {
        expect(
          EventPolicy.can(EventCommand.close, event('pending_review'), actor),
          isFalse,
        );
        expect(
          EventPolicy.can(EventCommand.reopen, event('closed'), actor),
          isFalse,
        );
        expect(
          EventPolicy.can(EventCommand.assignTask, event('open'), actor),
          isFalse,
        );
      }
      expect(
        EventPolicy.can(EventCommand.close, event('pending_review'), admin),
        isTrue,
      );
      expect(
        EventPolicy.can(EventCommand.reopen, event('closed'), admin),
        isTrue,
      );
      expect(
        EventPolicy.can(EventCommand.assignTask, event('open'), admin),
        isTrue,
      );
    });
    test('only server-classified reminders can confirm without a report', () {
      expect(
        EventPolicy.can(EventCommand.confirm, event('open'), inspector),
        isFalse,
      );
      expect(
        EventPolicy.can(
          EventCommand.confirm,
          event('open', reminder: true),
          inspector,
        ),
        isTrue,
      );
      expect(
        EventPolicy.can(
          EventCommand.handle,
          event('open', reminder: true),
          inspector,
        ),
        isFalse,
      );
      expect(
        EventPolicy.can(
          EventCommand.confirm,
          event('closed', reminder: true),
          inspector,
        ),
        isFalse,
      );
      expect(
        EventPolicy.can(
          EventCommand.close,
          event('pending_review', reminder: true),
          admin,
        ),
        isFalse,
      );
    });
  });
}
