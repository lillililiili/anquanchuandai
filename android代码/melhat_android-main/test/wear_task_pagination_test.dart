import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/tasks.dart';

import 'wear_session_test.dart'
    show MemoryCredentials, identity, reply, transport;

Future<List<int>> openTasks(WidgetTester tester, int total) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final pages = <int>[];
  final session =
      WearSession(
          credentials: MemoryCredentials(),
          dio: transport((request) {
            expect(request.path, '/api/v1/work-tasks/mine');
            final current = int.parse('${request.queryParameters['current']}');
            final size = int.parse('${request.queryParameters['size']}');
            pages.add(current);
            return reply({
              'records': List.generate(
                total,
                (index) => {
                  'id': '${index + 1}',
                  'title': '作业组${index + 1}',
                  'status': 'in_progress',
                  'inspectionStatus': 'in_progress',
                  'workType': 'patrol',
                  'spaceName': '测试区域',
                  'plannedStart': '2026-09-22T08:00:00',
                  'plannedEnd': '2026-09-22T18:00:00',
                },
              ).skip((current - 1) * size).take(size).toList(),
              'total': total,
              'current': current,
              'size': size,
            });
          }),
        )
        ..initialized = true
        ..token = 'test'
        ..siteId = '1'
        ..me = {
          ...identity(user: 'pagination-member'),
          'admin': false,
          'roles': ['wear_readonly'],
        };
  addTearDown(session.dispose);
  await tester.pumpWidget(
    WearScope(
      session: session,
      child: const MaterialApp(home: TasksPage()),
    ),
  );
  await tester.pumpAndSettle();
  return pages;
}

void main() {
  testWidgets('six tasks are all on one page without misleading page arrows', (
    tester,
  ) async {
    final pages = await openTasks(tester, 6);
    await tester.scrollUntilVisible(find.text('作业组6'), 250);
    expect(find.text('作业组6'), findsOneWidget);
    expect(pages, [1]);
    expect(find.text('共 6 条 · 已全部显示'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'next and previous request the correct task page and replace records',
    (tester) async {
      final pages = await openTasks(tester, 21);
      expect(find.text('作业组1'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(pages, [1, 2]);
      expect(find.text('作业组21'), findsOneWidget);
      expect(find.text('作业组1'), findsNothing);
      expect(find.text('共 21 条 · 第 2 页'), findsOneWidget);
      final next = find.ancestor(
        of: find.byIcon(Icons.chevron_right),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(next).onPressed, isNull);
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(pages, [1, 2, 1]);
      expect(find.text('作业组1'), findsOneWidget);
      expect(find.text('作业组21'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
