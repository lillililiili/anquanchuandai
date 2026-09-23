import 'event_photo_fixture.dart';
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
    'empty_abnormal',
    'empty_emergency',
    'mixed_media',
  ]) {
    testWidgets(
      'non-SOS submit preserves notes and reports $mode at the form',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final emergency = ['high_risk', 'empty_emergency'].contains(mode);
        final empty = mode.startsWith('empty_');
        var serverEvent = <String, dynamic>{
          'id': '169',
          'type': emergency ? 'sos' : 'realtime',
          'severity': emergency ? 'emergency' : 'abnormal',
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
                      'status': emergency ? 'pending_review' : 'closed',
                      'version': (serverEvent['version'] as int) + 1,
                    };
                    actions.insert(0, {
                      'id': '${actions.length + 1}',
                      'action': 'handle',
                      'reason': Map.fromEntries(
                        (request.data as FormData).fields,
                      )['comment'],
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

        expect(find.textContaining('当前状态 ·'), findsNothing);
        expect(find.text('紧急事件处理进度'), findsNothing);
        if (!empty) {
          await tester.ensureVisible(input);
          await tester.enterText(input, '正常');
          if (mode == 'mixed_media') {
            await attachTestCameraPhoto(tester, withVideo: true);
            expect(find.byTooltip('移除附件'), findsNWidgets(3));
            final add = find.byKey(const ValueKey('event-capture-photo'));
            await tester.ensureVisible(add);
            await tester.tap(add);
            await tester.pumpAndSettle();
            expect(find.text('现场拍照'), findsOneWidget);
            expect(find.text('现场录像'), findsOneWidget);
            expect(find.text('从相册选择照片或视频'), findsOneWidget);
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
          }
        }
        await tapSubmit();
        expect(writes.single.path, '/api/v1/events/169/report');
        expect(Map.fromEntries((writes.single.data as FormData).fields), {
          'comment': empty ? '' : '正常',
          'version': '2',
        });
        expect(
          (writes.single.data as FormData).files,
          hasLength(mode == 'mixed_media' ? 3 : 0),
        );
        if (mode == 'mixed_media') {
          expect(
            (writes.single.data as FormData).files.last.value.filename,
            'test-video.mp4',
          );
        }
        final feedback = find.byKey(
          const ValueKey('event-handle-feedback-169'),
        );
        final message = tester.widget<Text>(feedback).data!;
        if (mode == 'conflict' || mode == 'network') {
          expect(tester.widget<TextField>(input).controller!.text, '正常');
          expect(message, contains('填写内容已保留'));
          expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
        } else {
          expect(message, contains('已保存'));
          expect(input, findsNothing);
          expect(submit, findsNothing);
          expect(find.byType(SnackBar), findsOneWidget);
          if (mode == 'refresh_failed') expect(message, contains('刷新失败'));
          if (mode != 'refresh_failed') {
            expect(message, contains(emergency ? '等待管理员审批' : '事件已关闭'));
          }
          if (mode == 'success') {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            await tester.pumpWidget(app());
            await tester.pumpAndSettle();
            expect(input, findsNothing);
            expect(find.textContaining('已关闭'), findsWidgets);
            expect(writes.length, 1);
          }
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
