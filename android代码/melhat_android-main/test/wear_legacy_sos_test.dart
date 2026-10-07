import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/events/event_models.dart';
import 'package:rolling_intelligence_headband/wear/events/event_policy.dart';

void main() {
  const inspector = EventActor(
    userId: '9',
    roles: {'wear_duty'},
    permissions: {'wear:event:list'},
  );
  const admin = EventActor(
    userId: '1',
    roles: {'admin'},
    permissions: {'*:*:*'},
  );
  for (final severity in [null, '', 'high', 'abnormal', 'warning']) {
    test('legacy SOS retains identity and review rules with $severity', () {
      final json = <String, dynamic>{
        'id': '159',
        'type': 'sos',
        'severity': severity,
        'status': 'open',
        'personName': '陈建国',
        'sn': 'RL-H001',
        'occurredAt': '2026-09-20 10:38:52.000000',
        'escalated': true,
        'reminderOnly': true,
      };
      final event = WearEvent.fromJson(json);
      expect(event.alarmLabel, 'SOS 求助');
      expect(event.severity, 'emergency');
      expect(event.severityLabel, '紧急');
      expect(event.isWarning, isFalse);
      expect(event.reminderOnly, isFalse);
      expect(event.id, '159');
      expect(event.personName, '陈建国');
      expect(event.sn, 'RL-H001');
      expect(event.occurredAt, json['occurredAt']);
      expect(event.escalated, isTrue);
      expect(EventPolicy.can(EventCommand.confirm, event, inspector), isFalse);
      expect(EventPolicy.can(EventCommand.close, event, admin), isFalse);
      final reported = WearEvent.fromJson({
        ...json,
        'status': 'pending_review',
      });
      expect(EventPolicy.can(EventCommand.close, reported, inspector), isFalse);
      expect(EventPolicy.can(EventCommand.close, reported, admin), isTrue);
    });
  }
  test(
    'SOS placeholder falls back to type, valid source names stay intact',
    () {
      for (final name in [null, '', '告警名称未提供']) {
        expect(
          WearEvent.fromJson({
            'id': '159',
            'type': 'sos',
            'alarmName': name,
            'alarmCode': 'helmet.sos',
          }).alarmLabel,
          'SOS 求助',
        );
      }
      expect(
        WearEvent.fromJson({
          'id': '159',
          'type': 'sos',
          'alarmName': '手动 SOS 报警',
        }).alarmLabel,
        '手动 SOS 报警',
      );
      final ordinary = WearEvent.fromJson({
        'id': '160',
        'type': 'fall',
        'severity': 'high',
        'alarmName': '设备跌落',
      });
      expect(ordinary.isEmergency, isFalse);
      expect(ordinary.alarmLabel, '设备跌落');
    },
  );
}
