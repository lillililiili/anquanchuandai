import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/inspection.dart';
import 'package:rolling_intelligence_headband/wear/queries/workbench.dart';
import 'package:rolling_intelligence_headband/wear/queries/current_work.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, identity, reply, transport;

void main() {
  test(
    'selection crosses full completed pages and skips recorded abnormal work',
    () async {
      final pages = <int>[];
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) {
                if (r.path == '/api/v1/work-tasks/mine') {
                  final current = intOf(r.queryParameters['current']);
                  pages.add(current);
                  return reply({
                    'records': current == 1
                        ? List.generate(
                            20,
                            (i) => {
                              'id': '$i',
                              'inspectionStatus': 'completed',
                            },
                          )
                        : [
                            {
                              'id': '20',
                              'title': '已记录的异常组',
                              'status': 'in_progress',
                              'inspectionStatus': 'abnormal',
                            },
                            {
                              'id': '21',
                              'title': '下一未完成组',
                              'status': 'in_progress',
                              'inspectionStatus': 'abnormal',
                            },
                          ],
                    'current': current,
                    'size': 20,
                    'total': 22,
                  });
                }
                return reply({
                  'total': 2,
                  'completed': r.path.contains('/20/') ? 2 : 1,
                });
              }),
            )
            ..initialized = true
            ..token = 'test'
            ..siteId = '1'
            ..me = identity();
      addTearDown(session.dispose);
      expect((await loadCurrentWork(session))?['id'], '21');
      expect(pages, [1, 2]);
    },
  );

  test(
    'selection matches list sections and retains unfinished abnormal work',
    () async {
      var ongoingDone = false;
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) {
                if (r.path == '/api/v1/work-tasks/mine') {
                  return reply({
                    'records': [
                      {
                        'id': '1',
                        'status': 'in_progress',
                        'inspectionStatus': 'abnormal',
                      },
                      {
                        'id': '2',
                        'status': 'in_progress',
                        'inspectionStatus': ongoingDone
                            ? 'completed'
                            : 'in_progress',
                      },
                    ],
                    'total': 2,
                    'current': 1,
                    'size': 20,
                  });
                }
                return reply({'total': 2, 'completed': 1});
              }),
            )
            ..initialized = true
            ..token = 'test'
            ..siteId = '1'
            ..me = identity();
      addTearDown(session.dispose);
      expect((await loadCurrentWork(session))?['id'], '2');
      ongoingDone = true;
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

  testWidgets(
    'home advances after each real inspection refresh and becomes empty',
    (tester) async {
      final completed = <String>{'3'};
      JsonMap task(String id) => {
        'id': id,
        'title': '任务$id',
        'status': 'in_progress',
        'inspectionStatus': completed.contains(id)
            ? 'completed'
            : 'in_progress',
      };
      JsonMap snapshot(String id) => {
        'total': 1,
        'completed': completed.contains(id) ? 1 : 0,
        'items': [],
      };
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) {
                if (r.path.endsWith('/summary')) {
                  return reply({
                    'activeTasks': [task('3'), task('1'), task('2')],
                  });
                }
                if (r.path == '/api/v1/work-tasks/mine') {
                  return reply({
                    'records': [task('3'), task('2'), task('1')],
                    'total': 3,
                    'current': 1,
                    'size': 20,
                  });
                }
                final match = RegExp(
                  r'/work-tasks/(\d+)/inspection',
                ).firstMatch(r.path);
                if (match != null) {
                  final id = match.group(1)!;
                  if (r.method == 'POST') completed.add(id);
                  return reply(snapshot(id));
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
      expect(find.text('任务3'), findsNothing);
      expect(find.text('任务2'), findsOneWidget);
      for (final id in ['2', '1']) {
        final controller = InspectionController(session, id);
        await tester.pumpAndSettle();
        final recording = controller.record('item-$id');
        await tester.pumpAndSettle();
        expect(await recording, isTrue);
        controller.dispose();
        expect(find.text('任务$id'), findsNothing);
        if (id == '2') expect(find.text('任务1'), findsOneWidget);
      }
      expect(find.text('当前无任务'), findsOneWidget);
      expect(find.byKey(const ValueKey('view-current-work')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
