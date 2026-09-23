import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/events_page.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, identity, reply, transport;

void main() {
  for (final mode in [
    'cancel',
    'back',
    'confirm',
    'network',
    'conflict',
    'reopen',
  ]) {
    testWidgets('event reason dialog survives $mode', (tester) async {
      final confirm = mode != 'cancel' && mode != 'back';
      final fails = mode == 'network' || mode == 'conflict';
      final reopen = mode == 'reopen';
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      var event = <String, dynamic>{
        'id': '169',
        'type': 'sos',
        'severity': 'emergency',
        'status': reopen ? 'closed' : 'pending_review',
        'alarmName': 'SOS 求救',
        'claimantUserId': 'close-$mode',
        'version': 3,
        'siteId': '1',
      };
      var writes = 0;
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((request) {
                if (request.method == 'POST') {
                  expect(
                    request.path,
                    '/api/v1/events/169/${reopen ? 'reopen' : 'close'}',
                  );
                  expect(request.data, {'reason': '已确认现场正常', 'version': 3});
                  writes++;
                  if (mode == 'network') {
                    throw DioException(
                      requestOptions: request,
                      type: DioExceptionType.connectionError,
                    );
                  }
                  if (mode == 'conflict') {
                    return reply(null, code: 409, msg: '状态已更新，请刷新');
                  }
                  event = {
                    ...event,
                    'status': reopen ? 'open' : 'closed',
                    'version': 4,
                  };
                  return reply(event);
                }
                if (request.path.endsWith('/actions')) return reply([]);
                if (request.path == '/api/v1/events/169') return reply(event);
                if (request.path == '/api/v1/events') {
                  return reply({
                    'records': [event],
                    'total': 1,
                    'current': 1,
                    'size': 20,
                  });
                }
                if (request.path.endsWith('/inbox/count')) {
                  return reply({'count': 1});
                }
                return reply({});
              }),
            )
            ..initialized = true
            ..token = 'test'
            ..siteId = '1'
            ..me = {
              ...identity(user: 'close-$mode'),
              'roles': ['wear_platform_admin'],
              'permissions': [
                'wear:event:list',
                'wear:event:claim',
                'wear:event:review',
              ],
            };
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearScope(
          session: session,
          child: const MaterialApp(home: EventsPage(eventId: '169')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '复核与记录'));
      await tester.pumpAndSettle();
      final close = reopen
          ? find.widgetWithText(OutlinedButton, '重开')
          : find.widgetWithText(FilledButton, '审批通过并结束').first;
      await tester.ensureVisible(close);
      await tester.pumpAndSettle();
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.text(reopen ? '重开事件' : '关闭事件'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      expect(find.text('请填写原因'), findsOneWidget);
      expect(writes, 0);
      final input = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(input, '已确认现场正常');
      await tester.pumpAndSettle();
      if (mode == 'back') {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.text(confirm ? '确认提交' : '取消'));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(writes, confirm ? 1 : 0);
      expect(
        event['status'],
        reopen ? 'open' : (confirm && !fails ? 'closed' : 'pending_review'),
      );
      if (!confirm || fails) {
        await tester.ensureVisible(close);
        await tester.pumpAndSettle();
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(input).controller!.text, '已确认现场正常');
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
