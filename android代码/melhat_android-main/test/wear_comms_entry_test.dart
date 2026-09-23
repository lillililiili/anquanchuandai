import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/communications/communications_page.dart';
import 'package:rolling_intelligence_headband/wear/queries/devices.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final entry in {'TTS': 'tts', '对讲': 'intercom', '视频': 'video'}.entries) {
    testWidgets(
      'device ${entry.key} opens reachable operation without sending',
      (tester) async {
        final requests = <RequestOptions>[];
        await openDevice(tester, requests);
        final button = find.widgetWithText(
          entry.key == '视频' ? FilledButton : OutlinedButton,
          entry.key,
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(
          GoRouterState.of(
            tester.element(find.byType(CommunicationsPage)),
          ).uri.queryParameters['action'],
          entry.value,
        );
        final operation = find.text(entry.value == 'tts' ? '提交播报指令' : '语音群聊');
        expect(operation.hitTestable(), findsOneWidget);
        expect(find.text('安全帽呼叫'), findsNothing);
        expect(find.text('视频呼叫'), findsNothing);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(requests.where((r) => r.method != 'GET'), isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('selection enables fixed actions without moving the list', (
    tester,
  ) async {
    final requests = <RequestOptions>[];
    final router = await openDevice(tester, requests);
    router.go('/communications');
    await tester.pumpAndSettle();
    expect(find.text('联系人00').hitTestable(), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '语音群聊'))
          .onPressed,
      isNull,
    );
    expect(find.byType(ChoiceChip), findsNothing);
    await tester.scrollUntilVisible(
      find.text('联系人07'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('联系人07'));
    await tester.pumpAndSettle();
    expect(find.text('语音群聊').hitTestable(), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(requests.where((r) => r.method != 'GET'), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'changing an existing route hides the old target until the new equipment loads',
    (tester) async {
      final requests = <RequestOptions>[];
      final pending = Completer<void>();
      var delayNewTarget = false;
      final router = await openDevice(
        tester,
        requests,
        beforeDeviceRead: (id) async {
          if (delayNewTarget && id == '41') await pending.future;
        },
      );
      router.go('/communications?deviceId=42&action=intercom');
      await tester.pumpAndSettle();
      delayNewTarget = true;
      router.go('/communications?deviceId=41&action=tts');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('提交播报指令').hitTestable(), findsNothing);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('提交播报指令').hitTestable(), findsOneWidget);
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) => widget is TextField && widget.maxLength == 300,
        ),
        '请返回集合点',
      );
      await tester.tap(find.text('提交播报指令'));
      await tester.pumpAndSettle();
      final command = requests.where((r) => r.method == 'POST').single;
      expect(command.path, '/api/v1/commands/tts');
      expect(command.data['deviceIds'], ['41']);
      expect(command.data['text'], '请返回集合点');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a TTS link cannot enable a capability absent from the device', (
    tester,
  ) async {
    final requests = <RequestOptions>[];
    final router = await openDevice(
      tester,
      requests,
      actions: const ['intercom'],
    );
    router.go('/communications?deviceId=42&action=tts');
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '提交播报指令'),
    );
    expect(button.onPressed, isNull);
    expect(requests.where((r) => r.method != 'GET'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'legacy video entry opens voice call and four controls stay reachable without another call',
    (tester) async {
      final requests = <RequestOptions>[];
      final router = await openDevice(tester, requests);
      router.go('/communications?deviceId=42&action=video');
      await tester.pumpAndSettle();
      expect(find.text('视频呼叫'), findsNothing);
      expect(find.text('语音群聊').hitTestable(), findsOneWidget);
      await tester.tap(find.text('语音群聊'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(640, 360);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('结束通话').hitTestable(), findsOneWidget);
      expect(find.text('麦克风').hitTestable(), findsOneWidget);
      expect(find.text('扬声器').hitTestable(), findsOneWidget);
      expect(find.text('参与人员').hitTestable(), findsOneWidget);
      expect(find.text('开启视频').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('开启视频'));
      await tester.pumpAndSettle();
      expect(find.textContaining('真实通道尚未接入'), findsOneWidget);
      final starts = requests
          .where((r) => r.method == 'POST' && r.path == '/api/v1/calls')
          .toList();
      expect(starts, hasLength(1));
      expect(starts.single.data['video'], false);
      expect(find.text('结束通话').hitTestable(), findsOneWidget);
      await tester.tap(find.text('结束通话'));
      await tester.pumpAndSettle();
      expect(
        requests.where(
          (r) => r.method == 'POST' && r.path == '/api/v1/calls/c42/end',
        ),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'explicit device remains call target and active controls stay reachable while scrolling',
    (tester) async {
      final requests = <RequestOptions>[];
      final router = await openDevice(tester, requests);
      router.go('/communications?deviceId=42&personId=7&action=intercom');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('语音群聊'));
      await tester.tap(find.text('语音群聊'));
      await tester.pumpAndSettle();
      final create = requests
          .where((r) => r.method == 'POST' && r.path == '/api/v1/calls')
          .single;
      expect(create.data['deviceId'], '42');
      expect(create.data['video'], false);
      expect(find.text('结束通话').hitTestable(), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(find.text('结束通话').hitTestable(), findsOneWidget);
      await tester.tap(find.text('结束通话'));
      await tester.pumpAndSettle();
      expect(
        requests.where(
          (r) => r.method == 'POST' && r.path == '/api/v1/calls/c42/end',
        ),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<GoRouter> openDevice(
  WidgetTester tester,
  List<RequestOptions> requests, {
  List<String> actions = const ['tts', 'intercom', 'video'],
  String? fontFamily,
  Future<void> Function(String)? beforeDeviceRead,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  JsonMap device(String id) => {
    'id': id,
    'sn': 'REAL-H$id',
    'typeCode': 'helmet',
    'modelName': '现场安全帽',
    'capabilities': {'actions': actions},
    'currentAssignment': {'personId': '7'},
  };
  var callVideo = false;
  JsonMap call(String status) => {
    'id': 'c42',
    'deviceId': '42',
    'sn': 'REAL-H42',
    'kind': 'single',
    'requesterUserId': '12',
    'status': status,
    'demo': true,
    'video': callVideo,
  };
  final session =
      WearSession(
          credentials: MemoryCredentials(),
          dio: transport((request) async {
            requests.add(request);
            if (request.path == '/api/v1/people') {
              return reply({
                'records': List.generate(
                  30,
                  (i) => {
                    'id': '$i',
                    'name': '联系人${i.toString().padLeft(2, '0')}',
                    'personCode': 'P$i',
                  },
                ),
                'total': 30,
                'size': 100,
              });
            }
            if (request.path == '/api/v1/work-tasks') {
              return reply({'records': [], 'total': 0});
            }
            if (request.path == '/api/v1/devices') {
              return reply({
                'records': [device('41'), device('42')],
                'total': 2,
              });
            }
            if (request.path == '/api/v1/devices/42' ||
                request.path == '/api/v1/devices/41') {
              final id = request.path.split('/').last;
              await beforeDeviceRead?.call(id);
              return reply(device(id));
            }
            if (request.path == '/api/v1/people/7/equipment') {
              return reply([
                {'deviceId': '41', 'personId': '7', 'personName': '联系人07'},
                {'deviceId': '42', 'personId': '7', 'personName': '联系人07'},
              ]);
            }
            if (request.path == '/api/v1/calls' && request.method == 'POST') {
              callVideo = request.data['video'] == true;
              return reply(call('offered'));
            }
            if (request.path == '/api/v1/calls/c42/end') {
              return reply(call('ended'));
            }
            if (request.path == '/api/v1/calls/c42') {
              return reply(call('offered'));
            }
            if (request.path.endsWith('/inbox/count')) {
              return reply({'count': 0});
            }
            if (request.path == '/api/v1/duty/summary') {
              return reply({'activeTasks': [], 'recentEvents': []});
            }
            return reply([]);
          }),
        )
        ..initialized = true
        ..token = 'test-only'
        ..siteId = '1'
        ..me = {
          // Communications and device administration are administrator-only.
          ...identity(roles: const ['wear_platform_admin']),
          'permissions': ['wear:call:start', 'wear:command:tts'],
        };
  addTearDown(session.dispose);
  await tester.pumpWidget(
    WearApp(session: session, enableNotifications: false, fontFamily: fontFamily),
  );
  await tester.pumpAndSettle();
  final router = GoRouter.of(tester.element(find.byType(NavigationBar)));
  router.push('/devices/42');
  await tester.pumpAndSettle();
  expect(find.byType(DevicePage), findsOneWidget);
  return router;
}
