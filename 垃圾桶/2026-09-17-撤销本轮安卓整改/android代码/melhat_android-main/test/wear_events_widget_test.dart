import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/events_page.dart';

import 'wear_session_test.dart'
    show MemoryCredentials, identity, reply, transport;

Map<String, dynamic> _event({String status = 'claimed', int version = 1}) => {
  'id': 'event-1',
  'type': 'sos',
  'severity': 'high',
  'status': status,
  'occurredAt': '2026-09-10T08:00:00Z',
  'receivedAt': '2026-09-10T08:00:01Z',
  'personId': 'person-1',
  'personCode': 'P001',
  'personName': '张工',
  'siteId': '1',
  'claimantUserId': '12',
  'version': version,
};

WearSession _session(
  FutureOr<ResponseBody> Function(RequestOptions request) handler, {
  String user = '12',
}) {
  final session = WearSession(
    credentials: MemoryCredentials(),
    dio: transport(handler),
  );
  session
    ..initialized = true
    ..token = 'test-only'
    ..siteId = '1'
    ..me = {
      ...identity(user: user, roles: const ['wear_duty']),
      'userName': 'operator',
      'permissions': ['wear:event:list', 'wear:event:claim'],
    };
  return session;
}

Widget _app(WearSession session) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(viewInsets: const EdgeInsets.only(bottom: 280)),
    child: child!,
  ),
  home: WearScope(session: session, child: const EventsPage()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('独立详情返回保留列表位置，切主题保留草稿且不重新请求', (tester) async {
    var requests = 0;
    final session = _session((request) {
      requests++;
      if (request.path == '/api/v1/events') {
        expect(request.queryParameters['status'], 'claimed');
        expect(request.queryParameters['type'], 'sos');
        return reply({
          'records': List.generate(
            12,
            (i) => {..._event(), 'id': 'event-$i', 'claimantUserId': '14'},
          ),
          'total': 12,
          'current': 1,
          'size': 20,
        });
      }
      if (request.path.endsWith('/inbox/count')) return reply({'count': 12});
      if (request.path.endsWith('/actions')) return reply([]);
      if (request.path == '/api/v1/events/event-7') {
        return reply({..._event(), 'id': 'event-7', 'claimantUserId': '14'});
      }
      throw StateError('Unexpected request: ${request.method} ${request.path}');
    }, user: '14');
    addTearDown(session.dispose);
    final theme = ValueNotifier(ThemeMode.light);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: theme,
        builder: (context, mode, _) => MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: mode,
          home: WearScope(
            session: session,
            child: const EventsPage(
              initialStatus: 'claimed',
              initialType: 'sos',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(
      find.byKey(const ValueKey('wear-events-workspace')),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('wear-event-event-7')),
    );
    await tester.pumpAndSettle();
    final offset = list.controller!.offset;
    expect(offset, greaterThan(0));
    await tester.tap(find.byKey(const ValueKey('wear-event-event-7')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wear-events-workspace')), findsNothing);
    final input = find.byKey(const ValueKey('event-handle-input-event-7'));
    await tester.ensureVisible(input);
    await tester.enterText(input, '切换主题继续保留');
    await tester.pumpAndSettle();
    final beforeTheme = requests;
    theme.value = ThemeMode.dark;
    await tester.pumpAndSettle();
    expect(requests, beforeTheme);
    expect(tester.widget<TextFormField>(input).controller!.text, '切换主题继续保留');
    expect(find.text('转交'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('event-back')));
    await tester.pumpAndSettle();
    expect(find.text('告警详情'), findsNothing);
    expect(list.controller!.offset, closeTo(offset, .1));
    await tester.tap(find.byKey(const ValueKey('wear-event-event-7')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(input).controller!.text, '切换主题继续保留');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('来源安全带不作为呼叫终端，三种联系意图保留同人和事件，返回清除深链', (tester) async {
    final session = _session((request) {
      final event = {
        ..._event(),
        'deviceId': 'belt-1',
        'sn': 'BELT-001',
        'source': 'simulator',
        'taskId': 'task-1',
        'taskMatch': 'matched',
      };
      if (request.path == '/api/v1/events') {
        return reply({
          'records': [event],
          'total': 1,
          'current': 1,
          'size': 20,
        });
      }
      if (request.path.endsWith('/inbox/count')) return reply({'count': 1});
      if (request.path.endsWith('/actions')) return reply([]);
      if (request.path == '/api/v1/events/event-1') return reply(event);
      throw StateError('Unexpected request: ${request.method} ${request.path}');
    }, user: '15');
    addTearDown(session.dispose);
    Uri? contactUri;
    final router = GoRouter(
      initialLocation: '/events?eventId=event-1',
      routes: [
        GoRoute(
          path: '/events',
          builder: (context, state) =>
              EventsPage(eventId: state.uri.queryParameters['eventId']),
        ),
        GoRoute(
          path: '/communications',
          builder: (context, state) {
            contactUri = state.uri;
            return Scaffold(body: Text(state.uri.toString()));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => WearScope(session: session, child: child!),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('BELT-001 · ID belt-1'), findsNothing);
    final moreInfo = find.text('更多资料');
    await tester.ensureVisible(moreInfo);
    await tester.tap(moreInfo);
    await tester.pumpAndSettle();
    expect(find.text('BELT-001 · ID belt-1'), findsOneWidget);
    expect(find.text('演示数据'), findsOneWidget);
    expect(find.text('作业 task-1 · 已关联'), findsOneWidget);
    expect(find.text('simulator'), findsNothing);
    for (final intent in ['voice', 'video', 'tts']) {
      final button = find.byKey(ValueKey('event-contact-$intent'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      final uri = contactUri!;
      expect(uri.path, '/communications');
      expect(uri.queryParameters, {
        'eventId': 'event-1',
        'personId': 'person-1',
        'intent': intent,
      });
      router.pop();
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('event-back')));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.queryParameters.containsKey(
        'eventId',
      ),
      isFalse,
    );
    expect(find.byKey(const ValueKey('wear-events-workspace')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('wear-event-event-1')),
    );
    await tester.tap(find.byKey(const ValueKey('wear-event-event-1')));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.queryParameters['eventId'],
      'event-1',
    );
    router.go('/events');
    await tester.pumpAndSettle();
    expect(find.text('告警详情'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('本人已认领事件的内联处置草稿在离开后恢复，窄屏键盘下可提交且防重', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    var serverEvent = _event();
    var handleWrites = 0;
    Object? submittedBody;
    final heldHandle = Completer<ResponseBody>();
    final handleStarted = Completer<void>();
    FutureOr<ResponseBody> backend(RequestOptions request) {
      if (request.path == '/api/v1/events') {
        return reply({
          'records': [serverEvent],
          'total': 1,
          'current': 1,
          'size': 20,
        });
      }
      if (request.path == '/api/v1/events/inbox/count') {
        return reply({'count': 1});
      }
      if (request.path == '/api/v1/events/event-1') {
        return reply(serverEvent);
      }
      if (request.path == '/api/v1/events/event-1/actions') {
        return reply([]);
      }
      if (request.path == '/api/v1/events/event-1/handle') {
        handleWrites++;
        submittedBody = request.data;
        if (!handleStarted.isCompleted) handleStarted.complete();
        return heldHandle.future;
      }
      throw StateError('Unexpected request: ${request.method} ${request.path}');
    }

    final firstSession = _session(backend);
    await tester.pumpWidget(_app(firstSession));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('wear-event-event-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wear-event-event-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('wear-event-event-1')), findsNothing);
    expect(find.text('告警详情'), findsOneWidget);
    expect(find.text('区域未知 · 楼层未知'), findsOneWidget);
    expect(find.byKey(const ValueKey('event-contact-voice')), findsOneWidget);

    final firstInput = find.byKey(const ValueKey('event-handle-input-event-1'));
    await tester.ensureVisible(firstInput);
    await tester.pumpAndSettle();
    await tester.tap(firstInput);
    await tester.enterText(firstInput, '已联系现场，人员安全');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    firstSession.dispose();

    final secondSession = _session(backend);
    addTearDown(secondSession.dispose);
    await tester.pumpWidget(_app(secondSession));
    await tester.pumpAndSettle();

    final restoredInput = find.byKey(
      const ValueKey('event-handle-input-event-1'),
    );
    expect(restoredInput, findsOneWidget);
    final editable = tester.widget<EditableText>(
      find.descendant(of: restoredInput, matching: find.byType(EditableText)),
    );
    expect(editable.controller.text, '已联系现场，人员安全');

    await tester.ensureVisible(restoredInput);
    await tester.pumpAndSettle();
    await tester.tap(restoredInput);
    await tester.pump();
    final submit = find.byKey(const ValueKey('event-handle-submit-event-1'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tester.tap(submit);
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.tap(submit);
    await tester.pump();
    for (
      var attempt = 0;
      attempt < 20 && !handleStarted.isCompleted;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(handleStarted.isCompleted, isTrue);
    expect(handleWrites, 1);
    expect(submittedBody, {'comment': '已联系现场，人员安全', 'version': 1});

    serverEvent = _event(status: 'handling', version: 2);
    heldHandle.complete(reply(serverEvent));
    for (
      var attempt = 0;
      attempt < 20 && find.text('处置记录已提交').evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('处置记录已提交'), findsOneWidget);
    final clearedEditor = tester.widget<EditableText>(
      find.descendant(of: restoredInput, matching: find.byType(EditableText)),
    );
    expect(clearedEditor.controller.text, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
