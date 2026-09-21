import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('admin cancels with reason, takes over and sees duty intervals', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var cancelled = false, tookOver = false;
    final session =
        WearSession(
            credentials: MemoryCredentials(),
            dio: transport((r) {
              if (r.path == '/api/v1/duty/handovers/9/cancel') {
                expect(r.data['reason'], '计划调整');
                cancelled = true;
                return reply({'id': '9'});
              }
              if (r.path == '/api/v1/duty/takeover') {
                expect(r.data['expectedShiftId'], '7');
                expect(r.data['reason'], '管理员代班');
                tookOver = true;
                return reply({'id': '10'});
              }
              if (r.path == '/api/v1/duty/shifts')
                return reply({
                  'currentDuty': {
                    'id': tookOver ? '8' : '7',
                    'userId': tookOver ? '1' : '115',
                    'userName': tookOver ? '管理员（admin）' : '周明',
                    'startedAt': '2026-09-21T14:29:51+08:00',
                    'durationSeconds': 3900,
                  },
                  'records': [
                    {
                      'id': '6',
                      'userId': '109',
                      'userName': 'A站值班员',
                      'startedAt': '2026-09-21T08:00:00+08:00',
                      'endedAt': '2026-09-21T14:29:51+08:00',
                      'durationSeconds': 23391,
                      'changeType': 'handover',
                    },
                  ],
                  'total': 1,
                });
              if (r.path == '/api/v1/duty/handovers')
                return reply([
                  {
                    'id': '9',
                    'siteId': '1',
                    'fromUserId': '115',
                    'fromUserName': '周明',
                    'toUserId': '113',
                    'toUserName': '班组长',
                    'status': cancelled ? 'cancelled' : 'pending',
                    'canCancel': !cancelled,
                    if (cancelled)
                      'audit': {
                        'actorName': '管理员（admin）',
                        'reason': '计划调整',
                        'actedAt': '2026-09-21T15:00:00+08:00',
                      },
                  },
                ]);
              if (r.path.endsWith('/inbox/count')) return reply({'count': 0});
              return reply({'records': [], 'total': 0});
            }),
          )
          ..initialized = true
          ..me = {
            ...identity(roles: ['admin']),
            'userId': '1',
            'admin': true,
          }
          ..siteId = '1'
          ..token = 'test';
    addTearDown(session.dispose);
    await tester.pumpWidget(
      WearApp(session: session, enableNotifications: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('发起值班交接'));
    await tester.pumpAndSettle();
    expect(find.text('1 小时 5 分钟'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('handover-cancel-9')));
    await tester.tap(find.byKey(const ValueKey('handover-cancel-9')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '取消交接'));
    await tester.pumpAndSettle();
    expect(cancelled, isFalse);
    expect(find.text('请填写操作原因'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('duty-operation-reason')),
      '计划调整',
    );
    await tester.tap(find.widgetWithText(FilledButton, '取消交接'));
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
    await tester.ensureVisible(
      find.byKey(const ValueKey('handover-cancelled')),
    );
    await tester.tap(find.byKey(const ValueKey('handover-cancelled')));
    await tester.pumpAndSettle();
    expect(find.text('计划调整'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('duty-takeover')));
    await tester.tap(find.byKey(const ValueKey('duty-takeover')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('duty-operation-reason')),
      '管理员代班',
    );
    await tester.tap(find.widgetWithText(FilledButton, '确认接管'));
    await tester.pumpAndSettle();
    expect(tookOver, isTrue);
    expect(find.byKey(const ValueKey('duty-takeover')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('handover-shifts')));
    await tester.tap(find.byKey(const ValueKey('handover-shifts')));
    await tester.pumpAndSettle();
    expect(find.text('6 小时 29 分钟'), findsOneWidget);
    expect(find.text('已结束'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
