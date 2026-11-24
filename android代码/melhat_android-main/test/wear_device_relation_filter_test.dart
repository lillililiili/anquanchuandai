import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/devices.dart';
import 'package:rolling_intelligence_headband/wear/shared_models.dart';

import 'wear_session_test.dart' show MemoryCredentials, reply, transport;

WearSession ledgerSession(List<JsonMap> devices, List<JsonMap> assignments) =>
    WearSession(
        mock: false,
        credentials: MemoryCredentials(),
        dio: transport((request) {
          expect(request.method, 'GET');
          expect(request.path, '/api/guardian/v1/mobile/context');
          expect(request.queryParameters['siteId'], 'site-1');
          return reply({
            'devices': devices,
            'assignments': assignments,
            'businessConfig': {'simulatedWatchVisible': false},
          }, raw: true);
        }),
      )
      ..token = 'test-token'
      ..siteId = 'site-1';

void main() {
  test(
    'missing assignment collection is distinct from confirmed empty inventory',
    () {
      final stock = <String, dynamic>{
        'id': 'H',
        'ledgerId': 'd',
        'lifecycle': 'STOCK',
      };
      expect(SharedModels({}).device(stock)['relation'], isNull);
      expect(
        SharedModels({'assignments': []}).device(stock)['relation'],
        'UNASSIGNED',
      );
    },
  );
  testWidgets(
    'ledger offers only issued and unissued with an independent clear action',
    (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = ledgerSession(
        [
          {
            'id': 'h',
            'ledgerId': 'device-h',
            'sn': 'H-100',
            'type': 'H',
            'source': 'DIRECT_HELMET',
            'lifecycle': 'IN_USE',
          },
          {
            'id': 'b',
            'ledgerId': 'device-b',
            'sn': 'B-200',
            'type': 'B',
            'source': 'DIRECT_BELT',
            'lifecycle': 'IN_USE',
          },
          {
            'id': 's',
            'ledgerId': 'device-s',
            'sn': 'S-300',
            'type': 'H',
            'source': 'SPLIT_HELMET',
            'lifecycle': 'STOCK',
          },
        ],
        [
          {
            'id': 'a-h',
            'deviceId': 'device-h',
            'personId': 'p1',
            'active': true,
          },
          {
            'id': 'a-b',
            'deviceId': 'device-b',
            'personId': 'p2',
            'active': true,
          },
          {
            'id': 'a-old',
            'deviceId': 'device-s',
            'personId': 'p1',
            'active': false,
          },
        ],
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: WearScope(session: session, child: const DevicesPage()),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> selectStatus(String label) async {
        final menu = find.byTooltip('领用状态');
        expect(menu.hitTestable(), findsOneWidget);
        final type = find.widgetWithText(FilterChip, '安全带');
        expect(
          tester.getCenter(menu).dy,
          closeTo(tester.getCenter(type).dy, 1),
        );
        expect(tester.getRect(menu).right, lessThanOrEqualTo(360));
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.byType(PopupMenuItem<String>), findsNWidgets(2));
        expect(
          find.widgetWithText(PopupMenuItem<String>, '已领用'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(PopupMenuItem<String>, '未领用'),
          findsOneWidget,
        );
        final option = find.widgetWithText(PopupMenuItem<String>, label);
        await tester.ensureVisible(option);
        await tester.tap(option);
        await tester.pumpAndSettle();
      }

      expect(find.text('共 3 条 · 第 1 页'), findsOneWidget);
      await selectStatus('已领用');
      expect(find.text('H-100'), findsOneWidget);
      expect(find.text('B-200'), findsOneWidget);
      expect(find.text('S-300'), findsNothing);
      expect(find.text('共 2 条 · 第 1 页'), findsOneWidget);
      await selectStatus('未领用');
      expect(find.text('S-300'), findsOneWidget);
      expect(find.textContaining('未领用 · 电量'), findsOneWidget);
      expect(find.text('共 1 条 · 第 1 页'), findsOneWidget);

      final beltType = find.widgetWithText(FilterChip, '安全带');
      await tester.tap(beltType);
      await tester.pumpAndSettle();
      expect(find.text('当前筛选条件下没有「未领用」设备'), findsOneWidget);
      await tester.tap(find.byTooltip('清除领用状态筛选'));
      await tester.pumpAndSettle();
      expect(find.text('B-200'), findsOneWidget);
      expect(find.text('H-100'), findsNothing);
      expect(find.text('共 1 条 · 第 1 页'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'H-100');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('共 0 条 · 第 1 页'), findsOneWidget);
    },
  );

  test(
    'current assignments, returns and reissues are visible in list and detail',
    () async {
      final device = <String, dynamic>{
        'id': 'h',
        'ledgerId': 'd',
        'type': 'H',
        'source': 'SPLIT_HELMET',
        'lifecycle': 'STOCK',
      };
      final assignments = <JsonMap>[];
      final session = ledgerSession([device], assignments);
      addTearDown(session.dispose);
      Future<void> expectRelation(String expected) async {
        for (final relation in ['ASSIGNED', 'UNASSIGNED']) {
          final result = await session.api.page(
            '/api/v1/devices',
            query: {'relation': relation},
          );
          expect(
            result.records.map((d) => d['id']),
            relation == expected ? ['h'] : isEmpty,
          );
        }
        expect(
          jsonMap(await session.api.get('/api/v1/devices/h'))['relation'],
          expected,
        );
      }

      await expectRelation('UNASSIGNED');
      device['lifecycle'] = 'IN_USE';
      assignments.add({
        'id': 'first',
        'deviceId': 'd',
        'personId': 'p1',
        'active': true,
      });
      await expectRelation('ASSIGNED');
      assignments.single['active'] = false;
      device['lifecycle'] = 'STOCK';
      await expectRelation('UNASSIGNED');
      assignments.add({
        'id': 'second',
        'deviceId': 'd',
        'personId': 'p2',
        'active': true,
      });
      device['lifecycle'] = 'IN_USE';
      await expectRelation('ASSIGNED');
    },
  );

  test(
    'incomplete or conflicting ownership does not match either choice',
    () async {
      final session = ledgerSession(
        [
          for (final id in ['hidden', 'duplicate', 'conflict'])
            {
              'id': id,
              'ledgerId': id,
              'type': 'H',
              'lifecycle': 'IN_USE',
              if (id == 'conflict') 'relation': 'CONFLICT',
            },
          {'id': 'missing', 'type': 'B'},
        ],
        [
          {
            'id': 'one',
            'deviceId': 'duplicate',
            'personId': 'p1',
            'active': true,
          },
          {
            'id': 'two',
            'deviceId': 'duplicate',
            'personId': 'p2',
            'active': true,
          },
          {'id': 'broken', 'personId': 'p3', 'active': true},
        ],
      );
      addTearDown(session.dispose);
      expect((await session.api.page('/api/v1/devices')).total, 4);
      for (final relation in ['ASSIGNED', 'UNASSIGNED']) {
        expect(
          (await session.api.page(
            '/api/v1/devices',
            query: {'relation': relation},
          )).records,
          isEmpty,
        );
      }
    },
  );

  test(
    'inventory filtering for allocating equipment stays independent',
    () async {
      const lifecycleByFilter = {
        'issued': 'IN_USE',
        'in_stock': 'STOCK',
        'maintenance': 'MAINTENANCE',
        'disabled': 'DISABLED',
        'scrapped': 'SCRAPPED',
      };
      final session = ledgerSession([
        for (final lifecycle in lifecycleByFilter.values)
          {
            'id': lifecycle,
            'type': 'H',
            'source': 'SPLIT_HELMET',
            'lifecycle': lifecycle,
            'ledgerId': lifecycle,
          },
      ], []);
      addTearDown(session.dispose);
      for (final entry in lifecycleByFilter.entries) {
        final result = await session.api.page(
          '/api/v1/devices',
          query: {'assetStatus': entry.key},
        );
        expect(result.total, 1);
        expect(result.records.single['id'], entry.value);
      }
      final unissued = await session.api.page(
        '/api/v1/devices',
        query: {'relation': 'UNASSIGNED'},
      );
      expect(
        unissued.records.map((row) => row['id']),
        unorderedEquals(['STOCK', 'MAINTENANCE', 'DISABLED', 'SCRAPPED']),
      );
    },
  );
}
