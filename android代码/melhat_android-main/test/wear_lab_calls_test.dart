import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/communications/lab_calls.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

JsonMap row({
  String state = 'ringing',
  String user = '12',
  String site = '1',
  bool video = false,
}) => {
  'id': 'call-1',
  'siteId': site,
  'userId': user,
  'state': state,
  'direction': 'incoming',
  'video': video,
  'sos': true,
  'createdAt': DateTime.now().millisecondsSinceEpoch,
  'connectedAt': state == 'connected'
      ? DateTime.now().millisecondsSinceEpoch - 3000
      : null,
  'participants': [
    {'deviceId': 'd1', 'sn': 'RL-H001', 'personId': 'p1', 'state': state},
  ],
};
WearSession sessionWith(
  FutureOr<ResponseBody> Function(RequestOptions) handler,
) => WearSession(credentials: MemoryCredentials(), dio: transport(handler))
  ..initialized = true
  ..me = {
    ...identity(),
    'permissions': ['wear:event:list', 'wear:call:start'],
  }
  ..token = 'test'
  ..siteId = '1';

void main() {
  testWidgets(
    'ringing page waits, then toggles one-way helmet view in place with four controls',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var current = {...row(video: true), 'videoEnabled': false};
      final posts = <String>[];
      final session = sessionWith((request) {
        if (request.method == 'POST') posts.add(request.path);
        if (request.path.endsWith('/accept')) {
          current = {
            ...current,
            'state': 'connected',
            'connectedAt': DateTime.now().millisecondsSinceEpoch,
            'participants': [
              {
                'deviceId': 'd1',
                'sn': 'RL-H001',
                'personId': 'p1',
                'state': 'connected',
              },
            ],
          };
        }
        if (request.path.endsWith('/video')) {
          current = {
            ...current,
            'videoEnabled': (request.data as Map)['enabled'],
          };
        }
        return reply(
          request.path.endsWith('/state')
              ? {
                  'calls': [current],
                  'devices': [],
                }
              : current,
        );
      });
      final model = LabCallsModel(session);
      await tester.runAsync(model.poll);
      await tester.pumpWidget(
        WearScope(
          session: session,
          child: MaterialApp(
            home: LabCallScope(
              model: model,
              child: const LabCallPage(id: 'call-1'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('语音通话'), findsOneWidget);
      expect(find.text('联调视频 · 主平台转发'), findsNothing);
      expect(find.text('--:--'), findsOneWidget);
      IconButton videoButton() => tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.videocam_outlined),
          matching: find.byType(IconButton),
        ),
      );
      expect(videoButton().onPressed, isNull);
      await tester.runAsync(() => model.action('call-1', 'accept'));
      await tester.pump();
      final connectedAt = model.call('call-1')?['connectedAt'];
      await tester.ensureVisible(find.byIcon(Icons.videocam_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.videocam_outlined));
      await tester.pumpAndSettle();
      expect(model.call('call-1')?['videoEnabled'], isTrue);
      await tester.drag(find.byType(ListView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(find.text('通话与现场画面'), findsOneWidget);
      expect(find.text('关闭视频'), findsOneWidget);
      expect(find.text('参与人员'), findsOneWidget);
      expect(find.text('联调视频 · 主平台转发'), findsOneWidget);
      await tester.ensureVisible(find.byIcon(Icons.videocam_off_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.videocam_off_outlined));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(find.text('语音通话'), findsOneWidget);
      expect(find.text('开启视频'), findsOneWidget);
      expect(find.text('联调视频 · 主平台转发'), findsNothing);
      expect(model.call('call-1')?['connectedAt'], connectedAt);
      expect(posts, [
        '/api/v1/lab/calls/call-1/accept',
        '/api/v1/lab/calls/call-1/video',
        '/api/v1/lab/calls/call-1/video',
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      session.dispose();
    },
    skip: !callLabEnabled,
  );
  test('only duty and allowed administrators can open helmet view', () async {
    final session = sessionWith(
      (request) => reply({
        'calls': [row(state: 'connected')],
        'devices': [],
      }),
    );
    final model = LabCallsModel(session);
    await model.poll();
    session.me!['roles'] = ['wear_viewer'];
    expect(model.canViewHelmetVideo, isFalse);
    await expectLater(
      model.setVideo('call-1', enabled: true),
      throwsA(isA<WearApiException>()),
    );
    session.me!['roles'] = ['wear_platform_admin'];
    expect(model.canViewHelmetVideo, isTrue);
    session.me!['permissions'] = [];
    expect(model.canViewHelmetVideo, isFalse);
    session.me!['admin'] = true;
    expect(model.canViewHelmetVideo, isTrue);
    model.dispose();
    session.dispose();
  });
  test(
    'helmet video toggles on the same connected call without new invitation or resetting time',
    () async {
      final requests = <RequestOptions>[];
      var current = {...row(state: 'connected'), 'videoEnabled': false};
      final connectedAt = current['connectedAt'];
      final session = sessionWith((request) {
        requests.add(request);
        if (request.path.endsWith('/video')) {
          current = {
            ...current,
            'videoEnabled': (request.data as Map)['enabled'],
          };
        }
        return reply(
          request.path.endsWith('/state')
              ? {
                  'calls': [current],
                  'devices': [],
                }
              : current,
        );
      });
      final model = LabCallsModel(session);
      await model.poll();
      await model.setVideo('call-1', enabled: true);
      expect(model.call('call-1')?['videoEnabled'], isTrue);
      await model.setVideo('call-1', enabled: false);
      expect(model.call('call-1')?['videoEnabled'], isFalse);
      expect(model.call('call-1')?['connectedAt'], connectedAt);
      expect(requests.where((r) => r.method == 'POST').map((r) => r.path), [
        '/api/v1/lab/calls/call-1/video',
        '/api/v1/lab/calls/call-1/video',
      ]);
      model.dispose();
      session.dispose();
    },
  );
  test('ringing call cannot enable helmet video', () async {
    var posts = 0;
    final session = sessionWith((request) {
      if (request.method == 'POST') posts++;
      return reply({
        'calls': [row(video: true)],
        'devices': [],
      });
    });
    final model = LabCallsModel(session);
    await model.poll();
    await expectLater(
      model.setVideo('call-1', enabled: true),
      throwsA(isA<WearApiException>()),
    );
    expect(posts, 0);
    model.dispose();
    session.dispose();
  });
  testWidgets(
    'WearApp pushed call hides return banner; popping restores it',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var current = row();
      final session = sessionWith((request) {
        if (request.path == '/api/v1/lab/state') {
          return reply({
            'calls': [current],
            'devices': [],
          });
        }
        if (request.path.endsWith('/accept')) {
          current = row(state: 'connected');
          return reply(current);
        }
        if (request.path.endsWith('/duty/summary')) {
          return reply({'recentEvents': [], 'activeTasks': []});
        }
        if (request.path.endsWith('/equipment')) return reply([]);
        if (request.path.endsWith('/inbox/count')) return reply({'count': 0});
        return reply({'records': [], 'total': 0});
      });
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('紧急 SOS 来电'), findsOneWidget);
      await tester.tap(find.text('接听'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(LabCallPage), findsOneWidget);
      expect(find.text('状态联调进行中 · 返回通话'), findsNothing);
      await tester.tap(find.byTooltip('返回通讯'));
      await tester.pumpAndSettle();
      expect(find.byType(LabCallPage), findsNothing);
      expect(find.text('状态联调进行中 · 返回通话'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
    skip: !callLabEnabled,
  );
  test(
    'creating a call reserves station lock before response; empty pending poll cannot unlock',
    () async {
      final creation = Completer<ResponseBody>();
      JsonMap? current;
      final session = sessionWith(
        (request) => request.path.endsWith('/calls')
            ? creation.future
            : reply({
                'calls': current == null ? [] : [current],
                'devices': [],
              }),
      );
      final model = LabCallsModel(session);
      final starting = model.start(['d1']);
      await Future<void>.delayed(Duration.zero);
      expect(session.callActive.value, isTrue);
      await model.poll();
      expect(session.callActive.value, isTrue);
      await expectLater(
        session.selectSite('2'),
        throwsA(isA<WearApiException>()),
      );
      current = {...row(), 'direction': 'outgoing'};
      creation.complete(reply(current));
      expect(await starting, 'call-1');
      expect(session.callActive.value, isTrue);
      model.dispose();
      session.dispose();
    },
  );
  test(
    'ambiguous creation error keeps lock offline then releases after fresh empty state',
    () async {
      var offline = true;
      final session = sessionWith(
        (request) => request.path.endsWith('/calls') || offline
            ? reply({}, code: 503)
            : reply({'calls': [], 'devices': []}),
      );
      final model = LabCallsModel(session);
      await expectLater(model.start(['d1']), throwsA(isA<WearApiException>()));
      expect(model.busy, isFalse);
      expect(model.fresh, isFalse);
      expect(session.callActive.value, isTrue);
      offline = false;
      await model.poll();
      expect(session.callActive.value, isFalse);
      model.dispose();
      session.dispose();
    },
  );
  test(
    'active native session blocks lab creation without stealing termination',
    () async {
      var requests = 0;
      final session = sessionWith((request) {
        requests++;
        return reply({});
      });
      Future<void> nativeEnd() async {}
      session.callActive.value = true;
      session.terminateCall = nativeEnd;
      final model = LabCallsModel(session);
      await expectLater(model.start(['d1']), throwsA(isA<WearApiException>()));
      expect(requests, 0);
      expect(session.terminateCall, nativeEnd);
      model.dispose();
      expect(session.callActive.value, isTrue);
      session.dispose();
    },
  );
  test(
    'legacy video start becomes voice, deduplicates devices and prohibits overlapping calls',
    () async {
      final requests = <RequestOptions>[];
      final outgoing = {...row(video: true), 'direction': 'outgoing'};
      final session = sessionWith((request) {
        requests.add(request);
        return reply(
          request.path.endsWith('/state')
              ? {
                  'calls': [outgoing],
                  'devices': [],
                }
              : outgoing,
        );
      });
      final model = LabCallsModel(session);
      expect(await model.start(['d1', 'd2', 'd1'], video: true), 'call-1');
      expect(requests.first.data, {
        'deviceIds': ['d1', 'd2'],
        'video': false,
      });
      expect(session.callActive.value, isTrue);
      await expectLater(model.start(['d2']), throwsA(isA<WearApiException>()));
      model.dispose();
      session.dispose();
    },
  );
  test(
    'incoming only belongs to current duty user and site; state failure is not connected',
    () async {
      var fail = false;
      final session = sessionWith(
        (r) => fail
            ? reply({}, code: 503)
            : reply({
                'calls': [row(user: '99'), row(site: '2'), row()],
                'devices': [],
              }),
      );
      final model = LabCallsModel(session);
      await model.poll();
      expect(model.calls, hasLength(1));
      expect(model.incoming?['sos'], isTrue);
      expect(session.callActive.value, isTrue);
      fail = true;
      await model.poll();
      expect(model.fresh, isFalse);
      expect(model.incoming, isNull);
      expect(session.callActive.value, isTrue);
      model.dispose();
      session.dispose();
    },
  );
  test(
    'answer and end are server confirmed, preserve existing termination callback',
    () async {
      var current = row();
      final session = sessionWith((r) {
        if (r.path.endsWith('/accept')) current = row(state: 'connected');
        if (r.path.endsWith('/end')) current = row(state: 'ended');
        return reply(
          r.path.endsWith('/state')
              ? {
                  'calls': [current],
                  'devices': [],
                }
              : current,
        );
      });
      Future<void> original() async {}
      session.terminateCall = original;
      final model = LabCallsModel(session);
      await model.poll();
      await model.action('call-1', 'accept');
      expect(model.call('call-1')?['state'], 'connected');
      expect(model.incoming, isNull);
      await model.action('call-1', 'end');
      expect(session.callActive.value, isFalse);
      expect(session.terminateCall, original);
      model.dispose();
      session.dispose();
    },
  );
  test('late poll cannot contaminate switched user or station', () async {
    final delayed = Completer<ResponseBody>();
    final session = sessionWith((r) => delayed.future);
    final model = LabCallsModel(session);
    final pending = model.poll();
    await Future<void>.delayed(Duration.zero);
    session.siteId = '2';
    model.sessionChanged();
    delayed.complete(
      reply({
        'calls': [row()],
        'devices': [],
      }),
    );
    await pending;
    expect(model.calls, isEmpty);
    expect(session.callActive.value, isFalse);
    model.dispose();
    session.dispose();
  });
  testWidgets('global SOS overlay can answer without opening communications', (
    tester,
  ) async {
    var current = row();
    String? opened;
    final session = sessionWith((r) {
      if (r.path.endsWith('/accept')) current = row(state: 'connected');
      return reply(
        r.path.endsWith('/state')
            ? {
                'calls': [current],
                'devices': [],
              }
            : current,
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: LabCallHost(
          enabled: true,
          session: session,
          openCall: (id) => opened = id,
          child: const Scaffold(body: Text('现场')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('紧急 SOS 来电'), findsOneWidget);
    expect(find.text('语音状态联调 · 支持测试视频'), findsOneWidget);
    await tester.tap(find.text('接听'));
    await tester.pumpAndSettle();
    expect(opened, 'call-1');
    expect(find.text('紧急 SOS 来电'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });
  testWidgets(
    'voice/video reference pages fit narrow viewport and show honest media labels',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final mode in [0, 1, 2]) {
        final video = mode > 0;
        // Legacy incoming.video is deliberately true in all cases: only the
        // new server-confirmed videoEnabled controls helmet image visibility.
        final current = {
          ...row(state: 'connected', video: true),
          'videoEnabled': video,
        };
        if (mode == 2) {
          current['participants'] = List.generate(
            3,
            (i) => {
              'deviceId': 'd$i',
              'sn': 'RL-H00$i',
              'personId': 'p$i',
              'state': i < 2 ? 'connected' : 'rejected',
            },
          );
        }
        final session = sessionWith(
          (r) => reply({
            'calls': [current],
            'devices': [],
          }),
        );
        final model = LabCallsModel(session);
        await tester.runAsync(model.poll);
        await tester.pumpWidget(
          WearScope(
            session: session,
            child: MaterialApp(
              home: LabCallScope(
                model: model,
                child: const LabCallPage(id: 'call-1'),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text(video ? '通话与现场画面' : '语音通话'), findsOneWidget);
        expect(find.text('语音状态联调 · 支持测试视频'), findsOneWidget);
        expect(find.text('麦克风'), findsOneWidget);
        expect(find.text('扬声器'), findsOneWidget);
        expect(find.text('参与人员'), findsOneWidget);
        expect(find.text(video ? '关闭视频' : '开启视频'), findsOneWidget);
        final micY = tester.getTopLeft(find.text('麦克风')).dy;
        expect(tester.getTopLeft(find.text('扬声器')).dy, micY);
        expect(tester.getTopLeft(find.text('参与人员')).dy, micY);
        expect(tester.getTopLeft(find.text(video ? '关闭视频' : '开启视频')).dy, micY);
        expect(find.text('麦克风（模拟）'), findsNothing);
        expect(find.text('扬声器（模拟）'), findsNothing);
        expect(find.byTooltip('模拟麦克风已开启，点击关闭；不采集音频'), findsOneWidget);
        if (video) {
          expect(find.text('联调视频 · 主平台转发'), findsNWidgets(mode == 2 ? 2 : 1));
        } else {
          expect(find.text('联调视频 · 主平台转发'), findsNothing);
        }
        if (mode == 1) {
          // The compact video info row and 16:9 picture leave room for the
          // timer and primary controls in the first 360x640 viewport.
          expect(
            tester
                .getBottomLeft(find.byKey(const ValueKey('lab-call-timer')))
                .dy,
            lessThan(560),
          );
          expect(find.byIcon(Icons.mic_none).hitTestable(), findsOneWidget);
          expect(find.byIcon(Icons.fullscreen).hitTestable(), findsOneWidget);
          final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
          expect(avatar.radius, 16);
          expect(
            tester.getSize(
              find.ancestor(
                of: find.byIcon(Icons.mic_none),
                matching: find.byType(IconButton),
              ),
            ),
            const Size(48, 48),
          );
        }
        await tester.drag(find.byType(ListView), const Offset(0, -650));
        await tester.pump();
        expect(find.text('结束通话'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (video) {
          await tester.ensureVisible(find.byIcon(Icons.fullscreen));
          await tester.tap(find.byIcon(Icons.fullscreen));
          await tester.pumpAndSettle();
          expect(find.text('安全帽画面 · 联调视频'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('关闭全屏'));
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
        session.dispose();
      }
    },
    skip: !callLabEnabled,
  );
}
