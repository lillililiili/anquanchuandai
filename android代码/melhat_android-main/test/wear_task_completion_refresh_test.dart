import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/tasks.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, identity, reply, transport;

void main() {
  testWidgets(
    'complete height inspection then return moves task to completed',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var completed = false;
      var listReads = 0;
      JsonMap task() => {
        'id': '15',
        'title': '锅炉平台检修（联调13）',
        'workType': 'height',
        'status': 'ready',
        'inspectionStatus': completed ? 'completed' : 'in_progress',
        'members': <JsonMap>[],
      };
      JsonMap snapshot() => {
        'completed': completed ? 1 : 0,
        'total': 1,
        'accountProgress': {'completed': completed ? 4 : 3, 'total': 6},
        'currentItemId': completed ? null : '22',
        'items': [
          {
            'id': '22',
            'title': '本组巡检',
            'status': completed ? 'completed' : 'in_progress',
            'recordedAt': completed ? '2026-09-22T15:19:00+08:00' : null,
          },
        ],
        'records': <JsonMap>[],
        'reports': <JsonMap>[],
      };
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) {
                if (r.path.endsWith('/inspection/records')) {
                  completed = true;
                  return reply(snapshot());
                }
                if (r.path.endsWith('/inspection')) return reply(snapshot());
                if (r.path == '/api/v1/work-tasks/mine') {
                  listReads++;
                  return reply({
                    'records': [task()],
                    'total': 1,
                    'current': 1,
                    'size': 20,
                  });
                }
                if (r.path == '/api/v1/work-tasks/15') return reply(task());
                return reply([]);
              }),
            )
            ..initialized = true
            ..token = 'test'
            ..siteId = '1'
            ..me = identity();
      final router = GoRouter(
        initialLocation: '/tasks',
        routes: [
          GoRoute(path: '/tasks', builder: (_, _) => const TasksPage()),
          GoRoute(
            path: '/tasks/:id',
            builder: (_, s) => TaskPage(id: s.pathParameters['id']!),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearScope(
          session: session,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('进行中（1）'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('task-15')));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('inspection-continue'));
      await tester.scrollUntilVisible(
        button,
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(find.text('本组巡检已全部记录'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(listReads, greaterThan(1));
      expect(find.text('进行中（1）'), findsNothing);
      expect(find.text('已完成（1）'), findsOneWidget);
      expect(find.byKey(const ValueKey('task-15')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
