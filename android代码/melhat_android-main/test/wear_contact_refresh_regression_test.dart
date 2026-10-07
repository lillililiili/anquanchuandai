import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/communications/contact_filters.dart';
import 'package:rolling_intelligence_headband/wear/communications/communications_page.dart';
import 'wear_lab_calls_test.dart' show sessionWith;
import 'wear_session_test.dart' show reply, transport;

ResponseBody rosterReply(RequestOptions r) {
  if (r.path == '/api/v1/people') {
    return reply({
      'records': [
        {'id': '7', 'name': '通讯测试人员'},
      ],
      'total': 1,
    });
  }
  if (r.path == '/api/v1/devices') {
    return reply({
      'records': [
        {'id': '42'},
      ],
      'total': 1,
    });
  }
  if (r.path == '/api/v1/devices/42') {
    return reply({
      'id': '42',
      'sn': 'TEST-42',
      'typeCode': 'helmet',
      'online': '1',
      'connectionQuality': 'ok',
      'currentAssignment': {'personId': '7'},
      'capabilities': {
        'actions': ['intercom'],
      },
    });
  }
  return reply({'records': [], 'total': 0});
}

void main() {
  test(
    'forbidden task filters must not discard the full station contact roster',
    () async {
      final requests = <String>[];
      final api = WearApi(
        token: () => null,
        siteId: () => '1',
        epoch: () => 0,
        dio: transport((r) {
          requests.add(r.path);
          if (r.path.startsWith('/api/v1/work-tasks')) {
            return reply(null, code: 403, msg: '仅管理员可以查看全站作业');
          }
          return rosterReply(r);
        }),
      );
      final roster = await ContactRoster.load(api, lab: false);
      expect(roster.people.single.id, '7');
      expect(roster.devices.single.online, 'online');
      expect(roster.tasks, isEmpty);
      expect(roster.tasksUnavailable, isTrue);
      expect(requests, contains('/api/v1/work-tasks/mine'));
      expect(requests, isNot(contains('/api/v1/work-tasks')));
    },
  );

  test('mine tasks never truncate the all-person paginated roster', () async {
    final api = WearApi(
      token: () => null,
      siteId: () => '1',
      epoch: () => 0,
      dio: transport((r) {
        expect(r.headers['X-Site-Id'], '1');
        if (r.path == '/api/v1/people') {
          final page = r.queryParameters['current'] as int;
          return reply({
            'records': [
              for (var i = (page - 1) * 100; i < page * 100 && i < 205; i++)
                {'id': '$i', 'name': '人员$i'},
            ],
            'total': 205,
            'current': page,
            'size': 100,
          });
        }
        if (r.path == '/api/v1/work-tasks/mine') {
          return reply({
            'records': [
              {'id': '99'},
            ],
            'total': 1,
          });
        }
        if (r.path == '/api/v1/work-tasks/99') {
          return reply({
            'id': '99',
            'members': [
              {'personId': '1'},
            ],
          });
        }
        expect(r.path, isNot('/api/v1/work-tasks'));
        return reply({'records': [], 'total': 0});
      }),
    );
    final roster = await ContactRoster.load(api, lab: false);
    expect(roster.people, hasLength(205));
    expect(roster.tasks.single['id'], '99');
  });

  test(
    'optional tasks preserve unauthorized and stale-session failures',
    () async {
      for (final code in [401, -1]) {
        var epoch = 0;
        final api = WearApi(
          token: () => null,
          siteId: () => '1',
          epoch: () => epoch,
          dio: transport((r) {
            if (r.path == '/api/v1/work-tasks/mine') {
              if (code == -1) {
                epoch++;
                return reply({'records': [], 'total': 0});
              }
              return reply(null, code: 401);
            }
            return rosterReply(r);
          }),
        );
        await expectLater(
          ContactRoster.load(api, lab: false),
          throwsA(isA<WearApiException>().having((e) => e.code, 'code', code)),
        );
      }
    },
  );

  testWidgets(
    'forbidden call history does not discard contacts or prevent selection',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var historyReads = 0;
      final session = sessionWith((r) {
        if (r.path.endsWith('/calls')) {
          historyReads++;
          return reply(null, code: 403, msg: '无通话历史权限');
        }
        return rosterReply(r);
      });
      session.me = {
        ...session.me!,
        'roles': ['wear_platform_admin'],
      };
      addTearDown(session.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: CommunicationsPage()),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        WearScope(
          session: session,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('通讯测试人员'));
      await tester.tap(find.text('通讯测试人员'));
      await tester.pumpAndSettle();
      expect(find.text('通讯测试人员'), findsOneWidget);
      expect(find.text('通讯数据加载失败'), findsNothing);
      expect(historyReads, greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'repeated failed background refresh keeps roster stable and marks stale status unknown',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Completer<ResponseBody>? pending;
      final session = sessionWith(
        (r) => r.path == '/api/v1/devices' && pending != null
            ? pending.future
            : rosterReply(r),
      );
      addTearDown(session.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: CommunicationsPage()),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        WearScope(
          session: session,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      final visible = <bool>[];
      for (var i = 0; i < 3; i++) {
        pending = Completer<ResponseBody>();
        session.requestRefresh();
        await tester.pump();
        visible.add(find.text('通讯测试人员').evaluate().isNotEmpty);
        pending.complete(reply(null, code: 503, msg: '暂时无法刷新'));
        await tester.pumpAndSettle();
        visible.add(find.text('通讯测试人员').evaluate().isNotEmpty);
      }
      expect(
        visible,
        everyElement(isTrue),
        reason:
            'background requests must not alternate the contact list and a full-page error',
      );
      expect(find.text('安全帽状态未知'), findsOneWidget);
      expect(find.text('通讯数据加载失败'), findsNothing);
      pending = null;
      session.requestRefresh();
      await tester.pumpAndSettle();
      expect(find.text('安全帽状态未知'), findsNothing);
      expect(find.text('通讯刷新失败，在线状态暂不可用，请下拉重试'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
