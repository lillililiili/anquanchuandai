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
    'success',
    'conflict',
    'network',
    'refresh_failed',
    'high_risk',
  ]) {
    testWidgets('non-SOS submit preserves notes and reports $mode at the form', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      var serverEvent = <String, dynamic>{
        'id': '169',
        'type': mode == 'high_risk' ? 'fall' : 'realtime',
        'alarmName': '静默 / 长时间静止',
        'status': 'claimed',
        'claimantUserId': mode,
        'version': 2,
        'siteId': '1',
      };
      final writes = <RequestOptions>[];
      final actions = <Map<String, dynamic>>[];
      var postSucceeded = false;
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((request) {
                if (request.method == 'POST') {
                  writes.add(request);
                  if (mode == 'conflict') {
                    serverEvent = {...serverEvent, 'version': 3};
                    return reply(null, code: 409, msg: '状态已更新，请刷新');
                  }
                  if (mode == 'network') {
                    throw DioException(
                      requestOptions: request,
                      type: DioExceptionType.connectionError,
                    );
                  }
                  postSucceeded = true;
                  serverEvent = {
                    ...serverEvent,
                    'status': mode == 'high_risk'
                        ? 'pending_review'
                        : 'handling',
                    'version': (serverEvent['version'] as int) + 1,
                  };
                  actions.insert(0, {
                    'id': '${actions.length + 1}',
                    'action': 'handle',
                    'reason': request.data['comment'],
                    'actor': 'operator',
                    'toStatus': serverEvent['status'],
                  });
                  return reply(serverEvent);
                }
                if (mode == 'refresh_failed' && postSucceeded) {
                  throw DioException(
                    requestOptions: request,
                    type: DioExceptionType.connectionError,
                  );
                }
                if (request.path.endsWith('/actions')) return reply(actions);
                if (request.path == '/api/v1/events/169') {
                  return reply(serverEvent);
                }
                if (request.path == '/api/v1/events') {
                  return reply({
                    'records': [serverEvent],
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
              ...identity(user: mode),
              'permissions': ['wear:event:list', 'wear:event:claim'],
            };
      addTearDown(session.dispose);
      Widget app() => WearScope(
        session: session,
        child: const MaterialApp(home: EventsPage(eventId: '169')),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('event-handle-input-169'));
      final submit = find.byKey(const ValueKey('event-handle-submit-169'));
      Future<void> tapSubmit() async {
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        await tester.tap(submit);
        await tester.pumpAndSettle();
      }

      await tapSubmit();
      expect(writes, isEmpty);
      expect(find.textContaining('请填写现场核验说明'), findsWidgets);
      await tester.ensureVisible(input);
      await tester.enterText(input, '正常');
      await tapSubmit();
      expect(writes.single.path, '/api/v1/events/169/handle');
      expect(writes.single.data, {'comment': '正常', 'version': 2});
      expect(tester.widget<TextField>(input).controller!.text, '正常');
      final feedback = find.byKey(const ValueKey('event-handle-feedback-169'));
      final message = tester.widget<Text>(feedback).data!;
      if (mode == 'conflict' || mode == 'network') {
        expect(message, contains('填写内容已保留'));
        expect(find.text('已提交核验'), findsNothing);
        expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      } else {
        expect(message, contains('核验已提交，内容已保存'));
        expect(tester.widget<FilledButton>(submit).onPressed, isNull);
        expect(find.byType(SnackBar), findsOneWidget);
        if (mode == 'refresh_failed') expect(message, contains('刷新失败'));
        if (mode == 'high_risk') expect(message, contains('待复核'));
        if (mode == 'success') {
          expect(message, contains('关闭事件'));
          // Re-entering uses the server timeline and does not erase confirmed text.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await tester.pumpWidget(app());
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(input).controller!.text, '正常');
          expect(tester.widget<FilledButton>(submit).onPressed, isNull);
          await tester.ensureVisible(input);
          await tester.enterText(input, '补充：已联系现场');
          await tapSubmit();
          expect(writes.length, 2);
          expect(writes.last.data, {'comment': '补充：已联系现场', 'version': 3});
          expect(tester.widget<TextField>(input).controller!.text, '补充：已联系现场');
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
