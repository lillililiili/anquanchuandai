import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/workbench.dart';
import 'package:rolling_intelligence_headband/wear/queries/current_work.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, identity, reply, transport;

void main() {
  test(
    'current work traverses read-only pages and prioritizes active work',
    () async {
      final paths = <String>[];
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) {
                paths.add(r.path);
                final page = intOf(r.queryParameters['current']);
                return reply({
                  'records': page == 1
                      ? [
                          for (var i = 0; i < 20; i++)
                            {'id': '$i', 'status': i == 0 ? 'ready' : 'ended'},
                        ]
                      : [
                          {'id': '20', 'status': 'in_progress'},
                        ],
                  'total': 21,
                  'size': 20,
                  'current': page,
                });
              }),
            )
            ..initialized = true
            ..token = 'test'
            ..siteId = '1'
            ..me = identity();
      addTearDown(session.dispose);
      expect((await loadCurrentWork(session))?['id'], '20');
      expect(paths, ['/api/v1/work-tasks/mine', '/api/v1/work-tasks/mine']);
    },
  );
  test(
    'legacy inspection completion does not change source work status',
    () async {
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) {
                expect(r.path, '/api/v1/work-tasks/mine');
                return reply({
                  'records': [
                    {
                      'id': '1',
                      'status': 'in_progress',
                      'inspectionStatus': 'completed',
                    },
                  ],
                  'total': 1,
                  'size': 20,
                  'current': 1,
                });
              }),
            )
            ..initialized = true
            ..token = 'test'
            ..siteId = '1'
            ..me = identity();
      addTearDown(session.dispose);
      expect((await loadCurrentWork(session))?['id'], '1');
    },
  );
  testWidgets(
    'failed task request is not empty; retry renders empty state at large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var fail = true;
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) {
                if (r.path.endsWith('/summary')) {
                  return reply({'activeTasks': []});
                }
                if (r.path == '/api/v1/work-tasks/mine') {
                  return fail
                      ? reply(null, code: 503)
                      : reply({
                          'records': [],
                          'total': 0,
                          'current': 1,
                          'size': 20,
                        });
                }
                return reply([]);
              }),
            )
            ..initialized = true
            ..token = 'test'
            ..siteId = '1'
            ..me = identity();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearScope(
          session: session,
          child: const MaterialApp(home: WorkbenchPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('当前任务加载失败'), findsOneWidget);
      expect(find.text('当前无任务'), findsNothing);
      fail = false;
      await tester.ensureVisible(find.text('重新加载'));
      await tester.tap(find.text('重新加载'));
      await tester.pumpAndSettle();
      expect(find.text('当前无任务'), findsOneWidget);
      expect(find.text('查看任务列表'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
