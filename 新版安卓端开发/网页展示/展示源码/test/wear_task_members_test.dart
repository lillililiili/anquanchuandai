import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'task member editor persists exact additions and removals then rereads',
    (tester) async {
      final members = <String>{'1'};
      final writes = <String>[];
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) {
                if (r.path == '/api/v1/people')
                  return reply({
                    'records': [
                      {
                        'id': '1',
                        'name': '甲',
                        'personCode': 'P1',
                        'status': '0',
                      },
                      {
                        'id': '2',
                        'name': '乙',
                        'personCode': 'P2',
                        'status': '0',
                      },
                    ],
                    'total': 2,
                  });
                if (r.path == '/api/v1/work-tasks/41/members') {
                  expect(r.method, 'POST');
                  expect(r.data, {
                    'personIds': ['2'],
                  });
                  writes.add('add');
                  members.add('2');
                  return reply({});
                }
                if (r.path == '/api/v1/work-tasks/41/members/1') {
                  expect(r.method, 'DELETE');
                  writes.add('remove');
                  members.remove('1');
                  return reply({});
                }
                if (r.path == '/api/v1/work-tasks/41')
                  return reply({
                    'id': '41',
                    'title': '联调作业',
                    'status': 'in_progress',
                    'members': members
                        .map(
                          (id) => {
                            'personId': id,
                            'name': id == '1' ? '甲' : '乙',
                            'personCode': 'P$id',
                          },
                        )
                        .toList(),
                  });
                if (r.path.endsWith('/equipment-check') ||
                    r.path.endsWith('/events'))
                  return reply([]);
                return reply({'records': [], 'total': 0});
              }),
            )
            ..initialized = true
            ..me = identity()
            ..siteId = '1'
            ..token = 'test-only';
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.byType(NavigationBar))).go('/tasks/41');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('调整人员'));
      await tester.tap(find.text('调整人员'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, '甲'));
      await tester.tap(find.widgetWithText(CheckboxListTile, '乙'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存 · 1 人'));
      await tester.pumpAndSettle();
      expect(writes, ['add', 'remove']);
      expect(members, {'2'});
      expect(find.byKey(const ValueKey('task-person-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('task-person-1')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
