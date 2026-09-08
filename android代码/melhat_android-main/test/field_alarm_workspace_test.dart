import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rolling_intelligence_headband/field/field_alarms.dart';
import 'package:rolling_intelligence_headband/field/field_session.dart';
import 'package:rolling_intelligence_headband/http/index.dart';

class FakeAlarmServer {
  final records = <String, Map<String, dynamic>>{
    for (final id in ['1', '2'])
      id: {
        'id': id,
        'hatId': id,
        'hatNumber': 'H$id',
        'userName': id == '1' ? '人员A' : '人员B',
        'alarmType': 'sos',
        'alarmStartTime': '2026-09-06 08:00:00',
        'isHandled': 0,
      },
  };
  int writes = 0;
  bool failConfirmation = false;
  bool confirmationFailed = false;
  Completer<void>? heldRead;
  late final Interceptor interceptor = InterceptorsWrapper(
    onRequest: (options, handler) async {
      dynamic data;
      final path = options.path;
      if (options.method == 'PUT' && path == '/hat/alarm/handle') {
        writes++;
        if (!failConfirmation) {
          final record = records['${options.data['id']}']!;
          record['isHandled'] = 1;
          record['description'] = options.data['description'];
          record['handleTime'] = '2026-09-06 09:00:00';
        }
      } else if (path == '/hat/alarm/page') {
        data = {
          'records': records.values.map(Map<String, dynamic>.from).toList(),
          'total': records.length,
        };
      } else if (path == '/hat/safety/info/page') {
        data = {'records': <dynamic>[], 'total': 0};
      } else if (path == '/hat/fence/alarm/page' || path == '/hat/group/info') {
        data = {'records': <dynamic>[], 'total': 0};
      } else if (path.startsWith('/hat/alarm/')) {
        if (failConfirmation && writes > 0 && !confirmationFailed) {
          confirmationFailed = true;
          handler.resolve(
            Response(
              requestOptions: options,
              data: {'code': 500, 'msg': 'unconfirmed', 'data': null},
            ),
          );
          return;
        }
        final captured = Map<String, dynamic>.from(
          records[path.split('/').last]!,
        );
        if (path.endsWith('/1') && heldRead != null) await heldRead!.future;
        data = captured;
      } else {
        // Every request is intercepted, including unexpected ones; no network fallback.
        handler.reject(
          DioException(
            requestOptions: options,
            message: 'Unexpected request: $path',
          ),
        );
        return;
      }
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {'code': 200, 'msg': 'ok', 'data': data},
        ),
      );
    },
  );
}

Future<GoRouter> mountWorkspace(
  WidgetTester tester,
  FakeAlarmServer server, {
  String initialSelectedKey = '',
}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  FieldSession.instance.clear();
  FieldSession.instance.selectedKey = initialSelectedKey;
  http.dio.interceptors.insert(0, server.interceptor);
  addTearDown(() {
    http.dio.interceptors.remove(server.interceptor);
    FieldSession.instance.clear();
  });
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: TextButton(
            onPressed: () => context.push('/alarms'),
            child: const Text('打开告警'),
          ),
        ),
      ),
      GoRoute(
        path: '/alarms',
        builder: (_, state) => FieldAlarmWorkspace(onAdvanced: () {}),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.text('打开告警'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return router;
}

Future<void> selectPerson(
  WidgetTester tester,
  String person, {
  bool settle = true,
}) async {
  // Closing the independent pane returns to the original list and keeps drafts.
  if (find.byTooltip('收起详情').evaluate().isNotEmpty) {
    await tester.tap(find.byTooltip('收起详情'));
    await tester.pumpAndSettle();
  }
  final results = find.descendant(
    of: find.byKey(const ValueKey('alarm-results')),
    matching: find.byType(Scrollable),
  );
  tester.state<ScrollableState>(results.first).position.jumpTo(0);
  await tester.pump();
  final row = find.widgetWithText(ListTile, 'SOS 求助 · $person');
  await tester.ensureVisible(row);
  await tester.tap(row);
  if (settle)
    await tester.pumpAndSettle();
  else
    await tester.pump(const Duration(milliseconds: 100));
}

Future<void> fillDraft(WidgetTester tester, String prefix) async {
  for (var i = 0; i < 3; i++) {
    final input = find.byType(TextFormField).at(i);
    await tester.ensureVisible(input);
    await tester.enterText(input, '$prefix-$i');
  }
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

Future<void> submitDraft(WidgetTester tester) async {
  await tester.ensureVisible(find.text('确认完成处理'));
  await tester.tap(find.text('确认完成处理'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('only genuinely newer alarms emphasize once after refresh', (
    tester,
  ) async {
    final server = FakeAlarmServer();
    await mountWorkspace(tester, server);
    final initialColor = tester
        .widget<Card>(find.byKey(const ValueKey('device:1')))
        .color;
    server.records['3'] = {
      ...server.records['1']!,
      'id': '3',
      'alarmStartTime': '2026-09-06 09:00:00',
    };
    server.records['4'] = {
      ...server.records['1']!,
      'id': '4',
      'alarmStartTime': '2026-09-05 09:00:00',
    };
    await tester.tap(find.byTooltip('刷新后台数据'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Card>(find.byKey(const ValueKey('device:3'))).color,
      isNot(initialColor),
    );
    expect(
      tester.widget<Card>(find.byKey(const ValueKey('device:4'))).color,
      initialColor,
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Card>(find.byKey(const ValueKey('device:3'))).color,
      initialColor,
    );
    await tester.tap(find.byTooltip('刷新后台数据'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Card>(find.byKey(const ValueKey('device:3'))).color,
      initialColor,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('system back closes detail and retains the unsent draft', (
    tester,
  ) async {
    final server = FakeAlarmServer();
    final router = await mountWorkspace(tester, server);
    await selectPerson(tester, '人员A');
    await fillDraft(tester, '暂存');
    expect(find.text('已填写 3/3 项 · 草稿已暂存'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      '/alarms',
    );
    expect(find.byTooltip('收起详情'), findsNothing);
    await selectPerson(tester, '人员A');
    expect(FieldSession.instance.draft('device:1').inquiry, '暂存-0');
    expect(find.text('已填写 3/3 项 · 草稿已暂存'), findsOneWidget);
    expect(server.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'home-selected alarm opens its detail directly even beyond the first 100 rows',
    (tester) async {
      final server = FakeAlarmServer();
      for (var i = 3; i <= 150; i++) {
        server.records['$i'] = {
          ...server.records['1']!,
          'id': '$i',
          'hatId': '$i',
          'hatNumber': 'H$i',
          'userName': '人员$i',
        };
      }
      await mountWorkspace(tester, server, initialSelectedKey: 'device:150');
      expect(FieldSession.instance.selectedKey, 'device:150');
      expect(find.text('告警详情').hitTestable(), findsOneWidget);
      expect(
        find.text('人员150 · H150').hitTestable(),
        findsOneWidget,
      );
      await fillDraft(tester, '首页待办');
      expect(FieldSession.instance.draft('device:150').inquiry, '首页待办-0');
      expect(server.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'filter edits apply only on confirmation and preserve the selected alarm draft',
    (tester) async {
      final server = FakeAlarmServer();
      await mountWorkspace(tester, server);
      await selectPerson(tester, '人员A');
      await fillDraft(tester, '保留');
      await tester.tap(find.byTooltip('收起详情'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('筛选'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('围栏').last);
      await tester.pumpAndSettle();
      expect(FieldSession.instance.source, '');
      expect(find.text('符合条件 0 条 · 应用后更新列表'), findsOneWidget);
      await tester.tap(find.byTooltip('取消筛选'));
      await tester.pumpAndSettle();
      expect(FieldSession.instance.source, '');
      expect(find.widgetWithText(ListTile, 'SOS 求助 · 人员A'), findsOneWidget);
      await tester.tap(find.text('筛选'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('围栏').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('应用筛选'));
      await tester.tap(find.text('应用筛选'));
      await tester.pumpAndSettle();
      expect(FieldSession.instance.source, 'fence');
      expect(find.widgetWithText(ListTile, 'SOS 求助 · 人员A'), findsNothing);
      expect(FieldSession.instance.draft('device:1').inquiry, '保留-0');
      expect(server.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'refresh reconciles an open alarm with the server and clears its completed draft',
    (tester) async {
      final server = FakeAlarmServer();
      await mountWorkspace(tester, server);
      await selectPerson(tester, '人员A');
      await fillDraft(tester, '刷新前');
      server.records['1']!['isHandled'] = 1;
      server.records['1']!['handleTime'] = '2026-09-06 10:00:00';
      await tester.tap(find.byTooltip('刷新后台数据'));
      await tester.pumpAndSettle();
      expect(find.text('已处理 · 2026-09-06 10:00:00'), findsOneWidget);
      expect(find.text('确认完成处理'), findsNothing);
      expect(FieldSession.instance.drafts.containsKey('device:1'), isFalse);
      expect(server.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'drafts stay with each alarm across switching and route return at 375dp',
    (tester) async {
      final router = await mountWorkspace(tester, FakeAlarmServer());
      await selectPerson(tester, '人员A');
      await fillDraft(tester, 'A');
      await selectPerson(tester, '人员B');
      await fillDraft(tester, 'B');
      await selectPerson(tester, '人员A');
      expect(find.text('A-0'), findsOneWidget);
      expect(find.text('B-0'), findsNothing);
      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开告警'));
      await tester.pumpAndSettle();
      expect(find.text('A-0'), findsOneWidget);
      await selectPerson(tester, '人员B');
      expect(find.text('B-0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmed write updates pending list and next alarm without duplicate submit',
    (tester) async {
      final server = FakeAlarmServer();
      await mountWorkspace(tester, server);
      await selectPerson(tester, '人员A');
      await fillDraft(tester, '处理A');
      await submitDraft(tester);
      expect(server.writes, 1);
      expect(find.text('处理已保存到后台，待办数量已更新。'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'SOS 求助 · 人员A'), findsNothing);
      expect(FieldSession.instance.drafts.containsKey('device:1'), isFalse);
      await tester.ensureVisible(find.text('处理下一条'));
      await tester.tap(find.text('处理下一条'));
      await tester.pumpAndSettle();
      expect(FieldSession.instance.selectedKey, 'device:2');
      expect(find.text('处理A-0'), findsNothing);
      expect(server.writes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'uncertain save blocks retry and late verification cannot overwrite another selection',
    (tester) async {
      final server = FakeAlarmServer()..failConfirmation = true;
      await mountWorkspace(tester, server);
      await selectPerson(tester, '人员A');
      await fillDraft(tester, '未确认A');
      await submitDraft(tester);
      expect(server.writes, 1);
      final submit = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '确认完成处理'),
      );
      expect(submit.onPressed, isNull);
      expect(FieldSession.instance.draft('device:1').inquiry, '未确认A-0');
      final gate = Completer<void>();
      server.heldRead = gate;
      await tester.ensureVisible(find.text('核对后台结果'));
      await tester.tap(find.text('核对后台结果'));
      await tester.pump(const Duration(milliseconds: 100));
      await selectPerson(tester, '人员B', settle: false);
      await tester.pump(const Duration(milliseconds: 500));
      gate.complete();
      await tester.pumpAndSettle();
      expect(FieldSession.instance.selectedKey, 'device:2');
      expect(find.text('未确认A-0'), findsNothing);
      expect(find.text('人员B · H2'), findsOneWidget);
      expect(server.writes, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
