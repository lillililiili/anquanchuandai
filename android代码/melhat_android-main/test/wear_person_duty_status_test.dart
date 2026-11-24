import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/person_duty_status.dart';
import 'package:rolling_intelligence_headband/wear/queries/people.dart';

import 'wear_session_test.dart' show MemoryCredentials, reply, transport;

WearSession peopleSession(List<JsonMap> people, {VoidCallback? onRead}) =>
    WearSession(
        mock: false,
        credentials: MemoryCredentials(),
        dio: transport((request) {
          if (request.method == 'GET' &&
              request.path == '/api/guardian/v1/locations/people/P2') {
            return reply({'personId': 'P2'}, raw: true);
          }
          if (request.method != 'GET' ||
              request.path != '/api/guardian/v1/mobile/context' ||
              request.queryParameters['siteId'] != 'site-1') {
            throw StateError(
              'Unexpected request ${request.method} ${request.uri}',
            );
          }
          onRead?.call();
          return reply({
            'people': people,
            'businessConfig': {'version': 1, 'workBusinessEnabled': false},
          }, raw: true);
        }),
      )
      ..token = 'test-token'
      ..siteId = 'site-1'
      ..me = {'userId': 'operator'};

void main() {
  test(
    'duty uses the admin field independently of personnel activation and pagination',
    () async {
      final people = <JsonMap>[
        for (var i = 0; i < 21; i++)
          {'id': 'old-$i', 'name': '未维护$i', 'active': i.isEven},
        {'id': 'on', 'name': '值班甲', 'active': false, 'dutyStatus': 'ON_DUTY'},
        {'id': 'off', 'name': '值班乙', 'active': true, 'dutyStatus': 'OFF_DUTY'},
        {'id': 'invalid', 'name': '旧值', 'active': true, 'dutyStatus': '0'},
      ];
      final session = peopleSession(people);
      addTearDown(session.dispose);
      for (final entry in {'ON_DUTY': 'on', 'OFF_DUTY': 'off'}.entries) {
        final result = await session.api.page(
          '/api/v1/people',
          size: 1,
          query: {'dutyStatus': entry.key, 'name': '值班'},
        );
        expect(result.total, 1);
        expect(result.records.single['id'], entry.value);
        final detail = jsonMap(
          await session.api.get('/api/v1/people/${entry.value}'),
        );
        expect(detail['dutyStatus'], entry.key);
        expect(detail['status'], entry.key == 'ON_DUTY' ? '1' : '0');
      }
      final old = await session.api.page(
        '/api/v1/people',
        query: {'dutyStatus': 'UNKNOWN'},
      );
      expect(old.total, 22);
      expect(
        jsonMap(await session.api.get('/api/v1/people/invalid'))['dutyStatus'],
        'UNKNOWN',
      );
    },
  );

  testWidgets(
    'list, filter and person detail follow the same current duty record',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final people = <JsonMap>[
        {
          'id': 'P1',
          'name': '张甲',
          'code': '01',
          'active': false,
          'dutyStatus': 'ON_DUTY',
        },
        {
          'id': 'P2',
          'name': '张乙',
          'code': '02',
          'active': true,
          'dutyStatus': 'OFF_DUTY',
        },
        {'id': 'P3', 'name': '李丙', 'code': '03', 'active': true},
      ];
      var contextReads = 0;
      final session = peopleSession(people, onRead: () => contextReads++);
      addTearDown(session.dispose);
      final router = GoRouter(
        initialLocation: '/people',
        routes: [
          GoRoute(path: '/people', builder: (_, _) => const PeoplePage()),
          GoRoute(
            path: '/people/:id',
            builder: (_, s) => PersonPage(id: s.pathParameters['id']!),
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

      void expectBadge(String id, String label) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('person-$id')),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }

      Future<void> refreshVisiblePage() async {
        final previousReads = contextReads;
        session.requestRefresh();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(contextReads, greaterThan(previousReads));
      }

      Future<void> selectDuty(String label) async {
        await tester.tap(find.byTooltip('在岗状态'));
        await tester.pumpAndSettle();
        expect(find.byType(PopupMenuItem<PersonDutyStatus>), findsNWidgets(2));
        for (final choice in ['在岗', '离岗']) {
          expect(
            find.widgetWithText(PopupMenuItem<PersonDutyStatus>, choice),
            findsOneWidget,
          );
        }
        await tester.tap(
          find.widgetWithText(PopupMenuItem<PersonDutyStatus>, label),
        );
        await tester.pumpAndSettle();
      }

      expectBadge('P1', '在岗');
      expectBadge('P2', '离岗');
      expectBadge('P3', '待确认');
      await selectDuty('在岗');
      expect(find.text('张甲'), findsOneWidget);
      expect(find.text('共 1 条 · 第 1 页'), findsOneWidget);
      people.first['dutyStatus'] = 'OFF_DUTY';
      await refreshVisiblePage();
      expect(find.text('当前筛选条件下没有「在岗」人员'), findsOneWidget);
      await selectDuty('离岗');
      expect(find.text('共 2 条 · 第 1 页'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '乙');
      await refreshVisiblePage();
      expect(find.text('共 2 条 · 第 1 页'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('共 1 条 · 第 1 页'), findsOneWidget);
      await tester.tap(find.byTooltip('清除在岗状态筛选'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '乙',
      );
      await tester.tap(find.text('张乙'));
      await tester.pumpAndSettle();
      expect(find.text('在岗状态'), findsOneWidget);
      expect(find.text('离岗'), findsOneWidget);
      people[1]['dutyStatus'] = 'ON_DUTY';
      await refreshVisiblePage();
      expect(find.text('在岗'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expectBadge('P2', '在岗');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
