import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/shared_models.dart';
import 'package:rolling_intelligence_headband/wear/queries/my_equipment_page.dart';
import 'wear_shared_backend_test.dart' show nativeIdentity, contextData;
import 'wear_session_test.dart' show transport, reply, MemoryCredentials;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<WearSession> launch(
    WidgetTester t,
    FutureOr<ResponseBody> Function(RequestOptions) handle, {
    Widget? page,
    double scale = 1,
  }) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final s = WearSession(
      mock: false,
      credentials: MemoryCredentials(),
      dio: transport((r) {
        if (r.path.endsWith('/mobile/login')) {
          return reply({'token': 'test'}, raw: true);
        }
        if (r.path.endsWith('/mobile/identity')) {
          return reply(nativeIdentity(), raw: true);
        }
        return handle(r);
      }),
    );
    s.initialized = true;
    s.token = 'test';
    s.siteId = 'site-1';
    s.me = SharedModels.identity(nativeIdentity(), 'site-1');
    await t.pumpWidget(
      page == null
          ? WearApp(session: s, enableNotifications: false)
          : WearScope(
              session: s,
              child: MaterialApp(home: page),
            ),
    );
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      s.dispose();
    });
    return s;
  }

  Future<void> click(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'returned equipment history remains visible with no active device at $scale',
      (t) async {
        final data = contextData();
        data['devices'] = [];
        data['assignmentHistory'] = [
          {
            'assignmentId': 'assignment-1',
            'personId': 'person-1',
            'deviceCode': 'RL-H001',
            'type': 'HELMET',
            'startedAt': '2026-10-01T08:00:00Z',
          },
        ];
        data['assignments'][0].addAll({
          'active': false,
          'startedAt': '2026-10-01T08:00:00Z',
          'endedAt': '2026-10-07T08:00:00Z',
        });
        await launch(
          t,
          (_) => reply(data, raw: true),
          page: const MyEquipmentPage(),
          scale: scale,
        );
        expect(find.text('暂无领用装备'), findsOneWidget);
        await click(t, find.text('绑定历史'));
        expect(find.textContaining('归还 '), findsOneWidget);
        expect(find.textContaining('RL-H001'), findsOneWidget);
        expect(find.textContaining('未知类型'), findsNothing);
        expect(find.textContaining('领用 时间未知'), findsNothing);
        expect(find.text('暂无可查询的绑定历史'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'equipment refresh failure removes old status until retry succeeds',
    (t) async {
      var failed = false;
      final s = await launch(
        t,
        (_) => failed
            ? reply(null, code: 503, msg: '网络暂不可用')
            : reply(contextData(), raw: true),
        page: const MyEquipmentPage(),
      );
      expect(
        find.byKey(const ValueKey('equipment-card-RL-H001')),
        findsOneWidget,
      );
      expect(find.text('暂无真实遥测，后台台账已同步'), findsOneWidget);
      failed = true;
      s.requestRefresh();
      await t.pumpAndSettle();
      expect(find.text('装备信息暂不可用'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('equipment-card-RL-H001')),
        findsNothing,
      );
      failed = false;
      await click(t, find.text('重新加载'));
      expect(
        find.byKey(const ValueKey('equipment-card-RL-H001')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'home query failure preserves SOS and uncertain retry preserves its request',
    (t) async {
      final attempts = <JsonMap>[];
      await launch(t, (r) {
        if (r.path.endsWith('/sos')) {
          attempts.add(Map<String, dynamic>.from(r.data as Map));
          return reply(null, code: 503, msg: '连接中断');
        }
        return reply(null, code: 503, msg: '首页暂不可用');
      });
      expect(find.text('现场信息加载失败'), findsOneWidget);
      await click(t, find.byKey(const ValueKey('home-manual-sos')));
      final location = find.byKey(const ValueKey('manual-sos-location'));
      await t.enterText(location, '东门');
      await click(t, find.byKey(const ValueKey('manual-sos-submit')));
      await click(t, find.text('确认求助'));
      expect(find.textContaining('提交未确认'), findsOneWidget);
      expect(t.widget<TextFormField>(location).enabled, false);
      expect(find.text('事件详情'), findsNothing);
      await click(t, find.byKey(const ValueKey('manual-sos-submit')));
      await click(t, find.text('确认求助'));
      expect(attempts, hasLength(2));
      expect(attempts[1], attempts[0]);
      expect(attempts[0]['locationDescription'], '东门');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'real communications explains missing permission and disables device actions',
    (t) async {
      await launch(
        t,
        (r) => reply(
          r.path.endsWith('/mobile/calls') ? [] : contextData(),
          raw: true,
        ),
      );
      await click(t, find.byType(NavigationDestination).at(1));
      expect(
        find.byKey(const ValueKey('communications-capability-notice')),
        findsOneWidget,
      );
      expect(find.textContaining('未获设备语音或广播权限'), findsOneWidget);
      expect(
        t.widget<TextButton>(find.widgetWithText(TextButton, '设备语音')).onPressed,
        isNull,
      );
      expect(
        t.widget<TextButton>(find.widgetWithText(TextButton, '文字播报')).onPressed,
        isNull,
      );
      expect(find.text('视频群聊'), findsNothing);
      expect(
        t
            .widget<IconButton>(find.byKey(const ValueKey('contact-call-p:P1')))
            .onPressed,
        isNull,
      );
      expect(t.takeException(), isNull);
    },
  );
}
