import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/people.dart';

void main() {
  testWidgets(
    'person context uses a single-person location and preserves actions',
    (tester) async {
      final router = await _mount(tester, location: _location);
      expect(find.text('现场信息'), findsOneWidget);
      expect(find.text('31.230400, 121.473700'), findsOneWidget);
      expect(find.text('近期有效定位'), findsOneWidget);
      expect(find.text('暂无进行中的作业'), findsOneWidget);
      expect(find.text('P-007'), findsOneWidget);
      expect(find.text('巡检一班'), findsOneWidget);
      for (final text in ['承包商', '建设公司', '有效期', '2026-01-01 至 2026-12-31']) {
        expect(find.text(text), findsNothing);
      }
      expect(
        tester.getTopLeft(find.text('联系该人员')).dy,
        lessThan(tester.getTopLeft(find.text('当前装备')).dy),
      );
      await tester.tap(find.text('联系该人员'));
      await tester.pumpAndSettle();
      expect(find.text('/communications?personId=7'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('查看轨迹'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(EquipmentPanel),
          matching: find.byIcon(Icons.chevron_right),
        ),
        findsNothing,
      );
      for (final sn in ['HELMET-42', 'BELT-43']) {
        final serialNumber = find.text(sn);
        await tester.ensureVisible(serialNumber);
        await tester.pumpAndSettle();
        expect(
          tester.semantics.find(serialNumber),
          isSemantics(hasTapAction: false),
        );
        await tester.tap(serialNumber);
        await tester.pumpAndSettle();
        expect(find.byType(PersonPage), findsOneWidget);
        expect(find.text(sn), findsOneWidget);
      }
      expect(find.text('当前装备'), findsOneWidget);
      expect(find.textContaining('历史领用记录'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing location never invents position or a current job', (
    tester,
  ) async {
    await _mount(
      tester,
      location: {'personId': '7', 'locationQuality': 'unknown'},
    );
    expect(find.text('最近定位'), findsOneWidget);
    expect(find.text('未知'), findsWidgets);
    expect(find.text('当前作业'), findsOneWidget);
    expect(find.text('暂无进行中的作业'), findsOneWidget);
    expect(find.text('近期有效定位'), findsNothing);
  });

  testWidgets('stale and demo samples remain explicitly qualified', (
    tester,
  ) async {
    await _mount(
      tester,
      location: {..._location, 'locationQuality': 'stale', 'demo': true},
    );
    expect(find.text('定位已陈旧'), findsOneWidget);
    expect(find.text('示例数据'), findsOneWidget);
    expect(find.text('近期有效定位'), findsNothing);
  });

  testWidgets('optional location failure does not hide person or contact', (
    tester,
  ) async {
    await _mount(tester, locationCode: 403);
    expect(find.text('P-007'), findsOneWidget);
    expect(find.text('联系该人员'), findsOneWidget);
    expect(find.text('定位未获取'), findsOneWidget);
    expect(find.text('暂无访问权限'), findsNothing);
  });

  testWidgets('slow location does not block personnel details', (tester) async {
    final ready = Completer<void>();
    await _mount(tester, location: _location, locationReady: ready.future);
    expect(find.text('P-007'), findsOneWidget);
    expect(find.text('联系该人员'), findsOneWidget);
    expect(find.text('定位获取中'), findsOneWidget);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('31.230400, 121.473700'), findsOneWidget);
  });

  testWidgets(
    'another person location is never shown as this person location',
    (tester) async {
      await _mount(tester, location: {..._location, 'personId': '8'});
      expect(find.text('31.230400, 121.473700'), findsNothing);
      expect(find.text('未知'), findsOneWidget);
      expect(find.text('近期有效定位'), findsNothing);
    },
  );

  testWidgets('invalid coordinates cannot be marked as a normal location', (
    tester,
  ) async {
    await _mount(tester, location: {..._location, 'latitude': 1000});
    expect(find.text('未知'), findsOneWidget);
    expect(find.text('近期有效定位'), findsNothing);
  });

  testWidgets(
    'person detail remains readable and contact reachable on a phone',
    (tester) async {
      await _mount(tester, location: _location);
      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpAndSettle();
      expect(find.text('联系该人员').hitTestable(), findsOneWidget);
      await tester.scrollUntilVisible(find.text('HELMET-42'), 250);
      expect(find.text('HELMET-42').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

final _location = <String, dynamic>{
  'personId': '7',
  'personCode': 'P-007',
  'personName': '张三',
  'deviceId': '42',
  'sn': 'HELMET-42',
  'latitude': 31.2304,
  'longitude': 121.4737,
  'locationReportedAt': DateTime.now()
      .subtract(const Duration(seconds: 1))
      .toIso8601String(),
  'locationQuality': 'valid',
  'coordinateSystem': 'GCJ02',
  'locationFreshness': 'CURRENT',
  'connectionQuality': 'ok',
  'source': 'helmet',
  'floor': null,
  'floorSource': 'unknown',
  'demo': false,
};

Future<GoRouter> _mount(
  WidgetTester tester, {
  JsonMap? location,
  int locationCode = 200,
  Future<void>? locationReady,
}) async {
  tester.view.physicalSize = const Size(400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        Object? data;
        var code = 200;
        switch (options.path) {
          case '/api/v1/people/7':
            data = {
              'id': '7',
              'personCode': 'P-007',
              'name': '张三',
              'status': '0',
              'teamName': '巡检一班',
              'contractorName': '建设公司',
              'validFrom': '2026-01-01',
              'validTo': '2026-12-31',
            };
          case '/api/v1/people/7/equipment':
            data = [
              {
                'deviceId': '42',
                'typeCode': 'helmet',
                'sn': 'HELMET-42',
                'issuedAt': '2026-09-18T10:00:00+08:00',
                'connectionQuality': 'ok',
                'online': '1',
              },
              {
                'deviceId': '43',
                'typeCode': 'belt',
                'sn': 'BELT-43',
                'issuedAt': '2026-09-18T10:05:00+08:00',
              },
            ];
          case '/api/v1/locations/people/7':
            if (locationReady != null) await locationReady;
            data = location;
            code = locationCode;
          case '/api/v1/devices/42':
            data = {'id': '42', 'online': '1', 'connectionQuality': 'ok'};
          case '/api/v1/devices/43':
            data = {'id': '43', 'online': '0', 'connectionQuality': 'ok'};
          case '/api/v1/work-tasks':
            data = {'records': [], 'total': 0, 'current': 1, 'size': 100};
          default:
            fail(
              'Unexpected request: ${options.path}; never load factory-wide context',
            );
        }
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {'code': code, 'msg': 'fixture', 'data': data},
          ),
        );
      },
    ),
  );
  // This fixture implements the Android view API, not the shared Spring API.
  final session =
      WearSession(dio: dio, credentials: _MemoryCredentials(), mock: true)
        ..token = 'token'
        ..siteId = '1'
        ..me = {
          'userId': '99',
          'roles': ['wear_platform_admin'],
        };
  addTearDown(session.dispose);
  final router = GoRouter(
    initialLocation: '/people/7',
    routes: [
      GoRoute(
        path: '/people/:id',
        builder: (_, state) => PersonPage(id: state.pathParameters['id']!),
      ),
      for (final path in ['/communications', '/devices/:id'])
        GoRoute(
          path: path,
          builder: (_, state) => Scaffold(body: Text(state.uri.toString())),
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
  return router;
}

class _MemoryCredentials implements CredentialStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String? token) async {}
}
