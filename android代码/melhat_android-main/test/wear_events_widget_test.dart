import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  FutureOr<ResponseBody> Function(RequestOptions request) handler,
) {
  final session = WearSession(
    credentials: MemoryCredentials(),
    dio: transport(handler),
  );
  session
    ..initialized = true
    ..token = 'test-only'
    ..siteId = '1'
    ..me = {
      ...identity(user: '12', roles: const ['wear_duty']),
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
