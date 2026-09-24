import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rolling_intelligence_headband/wear/queries/people.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/person_management.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('binary export preserves auth scope and rejects JSON errors', () async {
    var denied = false;
    final api = WearApi(
      token: () => 'test',
      siteId: () => '2',
      epoch: () => 1,
      dio: transport((r) {
        expect(r.headers['X-Site-Id'], '2');
        expect(r.headers['Authorization'], 'Bearer test');
        return denied
            ? reply(null, code: 403, msg: '无权限')
            : ResponseBody.fromBytes(
                Uint8List.fromList([80, 75, 3, 4, 1, 2]),
                200,
              );
      }),
    );
    expect(await api.request('POST', '/api/v1/people/export', binary: true), [
      80,
      75,
      3,
      4,
      1,
      2,
    ]);
    denied = true;
    await expectLater(
      api.request('POST', '/api/v1/people/export', binary: true),
      throwsA(isA<WearApiException>().having((e) => e.code, 'code', 403)),
    );
  });
  testWidgets(
    'admin personnel is read-only while equipment issue and return remain usable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var assigned = false;
      final writes = <RequestOptions>[];
      final person = {
        'id': '8',
        'name': '张三',
        'personCode': 'P-008',
        'status': '0',
      };
      final device = {
        'id': '42',
        'deviceId': '42',
        'typeCode': 'helmet',
        'sn': 'H-042',
      };
      Object page(List<Object> rows) => {
        'records': rows,
        'total': rows.length,
        'current': 1,
        'size': 20,
      };
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) {
                if (r.method != 'GET') {
                  writes.add(r);
                  if (r.path == '/api/v1/assignments') {
                    expect(r.data['personId'], '8');
                    expect(r.data['deviceId'], '42');
                    assigned = true;
                  } else {
                    expect(r.path, '/api/v1/assignments/501/return');
                    assigned = false;
                  }
                  expect(r.data['idempotencyKey'], isNotEmpty);
                  return reply({});
                }
                if (r.path == '/api/v1/people') return reply(page([person]));
                if (r.path == '/api/v1/people/8') return reply(person);
                if (r.path == '/api/v1/people/8/equipment') {
                  return reply(
                    assigned
                        ? [
                            {...device, 'id': '501'},
                          ]
                        : [],
                  );
                }
                if (r.path == '/api/v1/devices') {
                  return reply(page(assigned ? [] : [device]));
                }
                if (r.path == '/api/v1/work-tasks') return reply(page([]));
                if (r.path == '/api/v1/locations/people/8') {
                  return reply({'personId': '8'});
                }
                if (r.path == '/api/v1/people/8/assignments') return reply([]);
                throw StateError('Unexpected request: ${r.path}');
              }),
            )
            ..initialized = true
            ..me = {
              ...identity(roles: ['admin']),
              'permissions': ['*:*:*'],
            }
            ..siteId = '1';
      addTearDown(session.dispose);
      expect(session.can('wear:person:edit'), isFalse);
      expect(session.can('wear:person:query'), isTrue);
      expect(session.can('wear:assignment:issue'), isTrue);
      final router = GoRouter(
        initialLocation: '/people',
        routes: [
          GoRoute(path: '/people', builder: (_, _) => const PeoplePage()),
          GoRoute(
            path: '/people/:id',
            builder: (_, s) => PersonPage(id: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/people-admin/equipment/:id',
            builder: (_, s) => PersonEquipmentPage(id: s.pathParameters['id']!),
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
      for (final label in ['新增人员', '班组 / 承包商', '导入 / 导出']) {
        expect(find.text(label), findsNothing);
      }
      await tester.tap(find.text('张三'));
      await tester.pumpAndSettle();
      for (final label in ['编辑档案', '停用人员', '启用人员']) {
        expect(find.text(label), findsNothing);
      }
      final equipment = find.text('装备分配 / 归还');
      await tester.ensureVisible(equipment);
      await tester.tap(equipment);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('分配'));
      await tester.tap(find.text('分配'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await tester.pumpAndSettle();
      expect(assigned, isTrue);
      await tester.ensureVisible(find.text('归还'));
      await tester.tap(find.text('归还'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await tester.pumpAndSettle();
      expect(assigned, isFalse);
      expect(writes.length, 2);
      router.pop();
      await tester.pumpAndSettle();
      expect(equipment, findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('人员档案'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
