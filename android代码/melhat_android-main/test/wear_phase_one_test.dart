import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/mock_backend.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<WearSession> launch(
    WidgetTester tester,
    String account, {
    double scale = 1,
    bool linked = true,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final backend = MockBackend()
      ..account = account
      ..siteId = '1';
    final session = WearSession(dio: Dio()..httpClientAdapter = backend)
      ..initialized = true
      ..token = 'local-test'
      ..siteId = '1'
      ..me = {...backend.identity, if (!linked) 'personId': ''};
    addTearDown(session.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(
      WearApp(session: session, enableNotifications: false),
    );
    await tester.pumpAndSettle();
    return session;
  }

  Future<void> click(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> open(WidgetTester t, String path) async {
    unawaited(GoRouter.of(t.element(find.byType(NavigationBar))).push(path));
    await t.pumpAndSettle();
  }

  Future<void> enter(WidgetTester t, String key, String value) async {
    final f = find.byKey(ValueKey(key));
    await t.ensureVisible(f);
    await t.enterText(f, value);
    await t.pumpAndSettle();
  }

  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'member submits empty SOS then adds a separate observation at scale $scale',
      (t) async {
        final s = await launch(t, 'member', scale: scale);
        expect(find.byType(NavigationDestination), findsNWidgets(4));
        expect(find.text('发起值班交接'), findsNothing);
        expect(find.text('巡检工具'), findsNothing);
        await click(t, find.byKey(const ValueKey('home-manual-sos')));
        await click(t, find.byKey(const ValueKey('manual-sos-submit')));
        await click(t, find.text('确认求助'));
        expect(find.text('事件详情'), findsOneWidget);
        expect(find.text('手机手动求助'), findsOneWidget);
        expect(find.text('待值守人员核验'), findsOneWidget);
        expect(find.text('最终核验'), findsNothing);
        expect(find.byKey(const ValueKey('sos-join')), findsNothing);
        expect(find.byKey(const ValueKey('event-claim')), findsNothing);
        await enter(t, 'event-observation', '位置在东门，请安排人员协助');
        await click(t, find.byKey(const ValueKey('event-observation-submit')));
        final row = (await t.runAsync(
          () => s.api.page('/api/v1/events'),
        ))!.records.firstWhere((e) => e['source'] == 'manual_sos');
        expect(row['status'], 'open');
        expect(jsonList(row['observations']).single['comment'], contains('东门'));
        expect(find.textContaining('本地模拟：现场情况已补充'), findsOneWidget);
        await click(t, find.byTooltip('返回事件列表'));
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'expired member session closes event detail without navigation exceptions',
    (t) async {
      final s = await launch(t, 'member');
      await open(t, '/events?eventId=402');
      expect(find.text('事件详情'), findsOneWidget);
      s.expire();
      await t.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
      expect(find.text('事件详情'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'admin joins and ends assistance then separately submits final verification',
    (t) async {
      final s = await launch(t, 'demo');
      await open(t, '/events?eventId=402');
      await click(t, find.byKey(const ValueKey('sos-join')));
      await click(t, find.byKey(const ValueKey('sos-end')));
      await click(t, find.text('确认'));
      final ended = jsonMap(
        await t.runAsync(
          () async => jsonMap(await s.api.get('/api/v1/events/402')),
        ),
      );
      expect(ended['status'], 'handling');
      expect(jsonMap(ended['assistance'])['state'], 'ended');
      await click(t, find.byKey(const ValueKey('verification-conclusion')));
      await click(t, find.text('需现场处理').last);
      await enter(t, 'verification-situation', '已到现场，人员安全');
      await enter(t, 'verification-measures', '安排专人陪同');
      await click(t, find.byKey(const ValueKey('verification-save')));
      expect(
        jsonMap(
          await t.runAsync(
            () async => jsonMap(await s.api.get('/api/v1/events/402')),
          ),
        )['status'],
        'handling',
      );
      await click(t, find.byKey(const ValueKey('verification-submit')));
      await click(t, find.text('确认'));
      expect(
        jsonMap(
          await t.runAsync(
            () async => jsonMap(await s.api.get('/api/v1/events/402')),
          ),
        )['status'],
        'verified',
      );
      expect(find.text('核验结果（只读）'), findsOneWidget);
      expect(find.byKey(const ValueKey('event-observation')), findsNothing);
      expect(find.byKey(const ValueKey('verification-submit')), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'unlinked management account has no personal equipment or SOS entry',
    (t) async {
      await launch(t, 'demo', linked: false);
      expect(find.byKey(const ValueKey('home-manual-sos')), findsNothing);
      await t.tap(find.byType(NavigationDestination).at(3));
      await t.pumpAndSettle();
      expect(find.text('我的装备'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  for (final role in ['demo', 'member']) {
    testWidgets(
      '$role navigates read-only work, events, communications and mine',
      (t) async {
        await launch(t, role);
        await open(t, '/tasks/301');
        expect(find.text('调整人员'), findsNothing);
        expect(find.textContaining('巡检'), findsNothing);
        await click(t, find.byKey(const ValueKey('task-event-records')));
        expect(find.text('进入作业禁区'), findsOneWidget);
        expect(
          t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
          2,
        );
        await t.tap(find.byType(NavigationDestination).at(0));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('home-manual-sos')), findsOneWidget);
        await t.tap(find.byType(NavigationDestination).at(1));
        await t.pumpAndSettle();
        expect(find.text('视频群聊'), findsNothing);
        expect(find.text('设备语音'), findsOneWidget);
        await t.tap(find.byType(NavigationDestination).at(3));
        await t.pumpAndSettle();
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.text('开启通知'), findsNothing);
        expect(find.text('重试绑定'), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
