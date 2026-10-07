import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/inspection.dart';
import 'package:rolling_intelligence_headband/wear/queries/inspection_pages.dart';
import 'package:rolling_intelligence_headband/wear/queries/tasks.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'ordinary height-work member can inspect and report with account progress at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final task = <String, dynamic>{
          'id': '41',
          'title': '本组巡检',
          'workType': 'height',
          'status': 'in_progress',
          'spaceName': '汽机房',
          'ownerUserId': '99',
          'guardianPersonId': '88',
          'members': [
            {'personId': '7', 'name': '周明'},
          ],
        };
        var current = '1';
        final done = <String>{};
        final writes = <String>[];
        JsonMap snapshot() => {
          'currentItemId': current,
          'completed': done.length,
          'total': 2,
          'accountProgress': {'completed': 3, 'total': 6},
          'items': [
            for (final id in ['1', '2'])
              {
                'id': id,
                'title': '巡检项$id',
                'location': '汽机房',
                'status': done.contains(id) ? 'completed' : 'in_progress',
                'recordedAt': done.contains(id)
                    ? '2026-09-22T10:20:00+08:00'
                    : null,
                'inspector': done.contains(id) ? '周明' : null,
              },
          ],
          'records': [],
          'reports': [],
        };
        final session =
            WearSession(
                credentials: MemoryCredentials(),
                dio: transport((r) {
                  if (r.path.endsWith('/inspection/select')) {
                    writes.add('select');
                    current = r.data['itemId'];
                    return reply(snapshot());
                  }
                  if (r.path.endsWith('/inspection/records')) {
                    writes.add('record');
                    expect((r.data as Map).keys.toSet(), {
                      'itemId',
                      'requestId',
                    });
                    done.add(r.data['itemId']);
                    current = done.contains('1') ? '' : '1';
                    return reply(snapshot());
                  }
                  if (r.path.endsWith('/inspection')) return reply(snapshot());
                  if (r.path == '/api/v1/work-tasks/mine') {
                    return reply({
                      'records': [task],
                      'total': 1,
                      'current': 1,
                      'size': 20,
                    });
                  }
                  if (r.path.endsWith('/summary')) {
                    return reply({
                      'activeTasks': [task],
                    });
                  }
                  if (r.path.endsWith('/work-tasks/41')) return reply(task);
                  if (r.path.endsWith('/inbox/count')) {
                    return reply({'count': 0});
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
          WearApp(session: session, enableNotifications: false),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('巡检记录'),
          250,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        expect(find.text('我的任务'), findsOneWidget);
        expect(find.byType(NavigationBar), findsOneWidget);
        await tester.tap(find.text('巡检记录'));
        await tester.pumpAndSettle();
        expect(find.byType(InspectionRecordsPage), findsOneWidget);
        expect(find.text('巡检记录'), findsOneWidget);
        expect(find.text('本组巡检'), findsOneWidget);
        expect(find.text('已完成 0 / 2'), findsOneWidget);
        expect(writes, isEmpty);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('view-current-work')),
          -250,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('view-current-work')));
        await tester.pumpAndSettle();
        expect(find.text('待核验事件'), findsNothing);
        expect(find.byKey(const ValueKey('task-person-7')), findsNothing);
        Future<void> click(Finder f) async {
          if (f.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              f,
              200,
              scrollable: find.byType(Scrollable).last,
            );
          }
          ScaffoldMessenger.of(tester.element(f)).clearSnackBars();
          await tester.pumpAndSettle();
          await tester.ensureVisible(f);
          await tester.pumpAndSettle();
          await tester.tap(f);
          await tester.pumpAndSettle();
        }

        await click(find.text('参与人员 · 1 人'));
        expect(find.byKey(const ValueKey('task-person-7')), findsOneWidget);
        await click(find.text('参与人员 · 1 人'));
        await click(find.byKey(const ValueKey('inspection-records')));
        expect(find.text('全站作业'), findsNothing);
        expect(find.text('待巡检'), findsNothing);
        await click(find.byKey(const ValueKey('inspection-select-2')));
        expect(current, '2');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('我的全部作业 · 已完成 3 / 6'), findsOneWidget);
        await click(find.byKey(const ValueKey('inspection-continue')));
        expect(writes, ['select', 'record']);
        expect(done, {'2'});
        expect(find.byType(InspectionReportPage), findsNothing);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        await click(find.byKey(const ValueKey('inspection-report')));
        expect(find.text('照片 / 视频'), findsOneWidget);
        await click(find.text('提交异常'));
        expect(find.text('请填写异常位置和异常描述'), findsOneWidget);
        expect(writes, ['select', 'record']);
        await tester.ensureVisible(find.text('录视频'));
        await tester.pumpAndSettle();
        expect(find.text('拍照'), findsOneWidget);
        expect(find.text('从相册选择'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets('non-admin cannot request all-site even when forced by route', (
    tester,
  ) async {
    final reads = <String>[];
    final session =
        WearSession(
            credentials: MemoryCredentials(),
            dio: transport((r) {
              reads.add(r.path);
              return reply({'records': [], 'total': 0});
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
        child: const MaterialApp(home: TasksPage(allSite: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('全站作业'), findsNothing);
    expect(reads, ['/api/v1/work-tasks/mine']);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'record failure retains idempotency key on retry and other member updates synchronize',
    (tester) async {
      var fail = true;
      var completed = 0;
      final ids = <String>[];
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) {
                if (r.method == 'POST') {
                  ids.add(r.data['requestId']);
                  if (fail) return reply(null, code: 500);
                  completed = 1;
                }
                return reply({
                  'completed': completed,
                  'total': 2,
                  'accountProgress': {'completed': completed + 3, 'total': 6},
                  'items': [],
                  'records': [],
                  'reports': [],
                });
              }),
            )
            ..initialized = true
            ..token = 'test'
            ..siteId = '1'
            ..me = identity();
      final controller = InspectionController(session, '41');
      await tester.pumpAndSettle();
      final failed = controller.record('1');
      await tester.pumpAndSettle();
      expect(await failed, false);
      expect(controller.completed, 0);
      expect(controller.accountCompleted, 3);
      expect(controller.accountTotal, 6);
      fail = false;
      final retried = controller.record('1');
      await tester.pumpAndSettle();
      expect(await retried, true);
      expect(controller.completed, 1);
      expect(controller.accountCompleted, 4);
      expect(ids[0], ids[1]);
      completed = 2;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(controller.completed, 2);
      expect(controller.accountCompleted, 5);
      controller.dispose();
      session.dispose();
    },
  );
}
