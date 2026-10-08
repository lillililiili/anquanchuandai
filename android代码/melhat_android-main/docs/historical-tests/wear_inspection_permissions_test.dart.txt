import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/events_page.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, identity, reply, transport;
import 'wear_app_test.dart' show appSession;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final mode in ['report', 'confirm', 'conflict', 'admin']) {
    testWidgets('$mode uses the group workflow at top and bottom', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var event = <String, dynamic>{
        'id': '1',
        'type': 'realtime',
        'siteId': '1',
        'taskId': '8',
        'status': mode == 'admin' ? 'pending_review' : 'open',
        'version': 2,
        'alarmName': mode == 'confirm' ? '低电量' : '安全带连接中断',
        'reminderOnly': mode == 'confirm',
      };
      final writes = <RequestOptions>[];
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) {
                if (r.method == 'POST') {
                  writes.add(r);
                  if (mode == 'conflict') {
                    return reply(null, code: 409, msg: '其他组员已处理，请刷新');
                  }
                  event = {
                    ...event,
                    'version': 3,
                    'status': mode == 'confirm' ? 'closed' : 'pending_review',
                  };
                  return reply(event);
                }
                if (r.path == '/api/v1/events/1') return reply(event);
                if (r.path.endsWith('/actions')) return reply([]);
                if (r.path.endsWith('/inbox/count')) return reply({'count': 1});
                if (r.path == '/api/v1/events') {
                  return reply({
                    'records': [event],
                    'total': 1,
                    'current': 1,
                    'size': 20,
                  });
                }
                return reply({});
              }),
            )
            ..initialized = true
            ..token = 'test'
            ..siteId = '1'
            ..me = {
              ...identity(user: 'member-$mode'),
              'admin': mode == 'admin',
              'roles': [mode == 'admin' ? 'admin' : 'wear_readonly'],
              'permissions': ['*:*:*'],
            };
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearScope(
          session: session,
          child: const MaterialApp(home: EventsPage(eventId: '1')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('认领事件'), findsNothing);
      expect(find.text('更多处置与记录'), findsNothing);
      if (mode == 'admin') {
        await tester.tap(find.text('复核与记录'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('复核并结束'));
        expect(find.text('复核并结束'), findsOneWidget);
      } else if (mode == 'confirm') {
        expect(
          find.byKey(const ValueKey('event-handle-input-1')),
          findsNothing,
        );
        final button = find.byKey(const ValueKey('event-confirm-reminder'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(writes.single.path, '/api/v1/events/1/confirm');
        expect(writes.single.data, {'version': 2});
        expect(find.textContaining('本次任务已结束'), findsOneWidget);
      } else {
        final input = find.byKey(const ValueKey('event-handle-input-1'));
        await tester.ensureVisible(input);
        await tester.enterText(input, '挂钩传感器松动，已检查现场');
        final submit = find.byKey(const ValueKey('event-handle-submit-1'));
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(writes.single.path, '/api/v1/events/1/handle');
        expect(writes.single.data, {'comment': '挂钩传感器松动，已检查现场', 'version': 2});
        if (mode == 'conflict') {
          expect(
            tester.widget<TextField>(input).controller!.text,
            '挂钩传感器松动，已检查现场',
          );
          expect(find.textContaining('草稿已保留'), findsWidgets);
        } else {
          expect(find.textContaining('已上报 · 已完成'), findsWidgets);
          expect(input, findsNothing);
          expect(find.text('复核并结束'), findsNothing);
          await tester.ensureVisible(find.text('查看上报记录'));
          await tester.tap(find.text('查看上报记录'));
          await tester.pumpAndSettle();
          expect(find.text('复核并结束'), findsNothing);
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'normal account retains navigation and only inspection/report tools',
    (tester) async {
      final session = appSession(authenticated: true);
      session.me = {
        ...session.me!,
        'roles': ['wear_team_lead', 'wear_reviewer'],
        'admin': false,
        'permissions': ['*:*:*'],
      };
      addTearDown(session.dispose);
      expect(session.can('wear:task:edit'), isFalse);
      expect(session.isReviewer, isFalse);
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('发起值班交接'), findsNothing);
      expect(find.text('人员档案'), findsNothing);
      await tester.ensureVisible(find.text('我的任务'));
      expect(find.text('巡检记录'), findsOneWidget);
      final context = tester.element(find.byType(NavigationBar));
      GoRouter.of(context).go('/people');
      await tester.pumpAndSettle();
      expect(
        GoRouter.of(context).routeInformationProvider.value.uri.path,
        '/workbench',
      );
      await tester.tap(find.text('我的任务'));
      await tester.pumpAndSettle();
      expect(find.text('我的任务'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
