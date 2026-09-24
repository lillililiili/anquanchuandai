import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/communications/lab_calls.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, identity, reply, transport;

const legacySos = <String, dynamic>{
  'id': '159',
  'type': 'sos',
  'severity': 'high',
  'status': 'open',
  'siteId': '1',
  'personName': '陈建国',
  'sn': 'RL-H001',
  'deviceId': 'd1',
  'occurredAt': '2026-09-20 10:38:52',
  'escalated': true,
  'version': 1,
  'externalClosureStatus': 'not_synced',
  'verificationStatus': 'pending',
};

void main() {
  testWidgets(
    'legacy SOS list opens emergency detail and returns to messages',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final writes = <String>[];
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) {
                if (r.method != 'GET') writes.add(r.path);
                if (r.path == '/api/v1/events') {
                  return reply({
                    'records': [legacySos],
                    'total': 1,
                    'current': 1,
                    'size': 20,
                  });
                }
                if (r.path == '/api/v1/events/159') return reply(legacySos);
                if (r.path.endsWith('/inbox/count')) return reply({'count': 1});
                if (r.path.endsWith('/summary')) {
                  return reply({'activeTasks': []});
                }
                return reply([]);
              }),
            )
            ..initialized = true
            ..token = 'test'
            ..siteId = '1'
            ..me = {
              ...identity(user: 'legacy-sos-navigation', roles: ['wear_duty']),
              'permissions': ['wear:event:list'],
            };
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      expect(find.text('SOS 求助'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('wear-event-159')));
      await tester.pumpAndSettle();
      expect(find.text('事件详情'), findsOneWidget);
      expect(find.text('SOS 求助'), findsWidgets);
      expect(find.text('告警名称未提供'), findsNothing);
      expect(find.textContaining('紧急 ·'), findsOneWidget);
      expect(find.textContaining('陈建国'), findsWidgets);
      expect(find.textContaining('RL-H001'), findsWidgets);
      final submit = find.byKey(const ValueKey('event-handle-submit-159'));
      await tester.ensureVisible(submit);
      expect(
        find.descendant(of: submit, matching: find.text('提交待审批')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byTooltip('返回事件列表'));
      await tester.tap(find.byTooltip('返回事件列表'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'ending SOS assistance sends only a call end, not event review or closure',
    () async {
      var call = <String, dynamic>{
        'id': 'sos-159',
        'sos': true,
        'eventId': '159',
        'siteId': '1',
        'userId': '1',
        'state': 'connected',
      };
      final writes = <String>[];
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) {
                if (r.method != 'GET') {
                  writes.add(r.path);
                  if (r.path == '/api/v1/lab/calls/sos-159/end') {
                    call = {...call, 'state': 'ended'};
                    return reply({'call': call});
                  }
                  throw StateError('Unexpected event mutation: ${r.path}');
                }
                if (r.path == '/api/v1/lab/state') {
                  return reply({
                    'calls': [call],
                    'devices': [],
                  });
                }
                return reply(legacySos);
              }),
            )
            ..initialized = true
            ..token = 'test'
            ..siteId = '1'
            ..me = identity(user: '1', roles: ['admin']);
      final model = LabCallsModel(session)..calls = [call];
      addTearDown(session.dispose);
      addTearDown(model.dispose);
      await model.action('sos-159', 'end');
      expect(model.call('sos-159')?['state'], 'ended');
      expect(writes, ['/api/v1/lab/calls/sos-159/end']);
      expect(legacySos['verificationStatus'], 'pending');
      expect(legacySos['externalClosureStatus'], 'not_synced');
    },
  );
}
