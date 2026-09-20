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
      expect(find.text('定位正常'), findsOneWidget);
      expect(find.text('暂无进行中的作业'), findsOneWidget);
      expect(find.text('P-007'), findsOneWidget);
      expect(find.text('巡检一班'), findsOneWidget);
      expect(find.text('建设公司'), findsOneWidget);
      expect(find.text('2026-01-01 至 2026-12-31'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('联系该人员')).dy,
        lessThan(tester.getTopLeft(find.text('当前装备')).dy),
      );
      await tester.tap(find.text('联系该人员'));
      await tester.pumpAndSettle();
      expect(find.text('/communications?personId=7'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('查看轨迹'));
      await tester.tap(find.text('查看轨迹'));
      await tester.pumpAndSettle();
      expect(find.text('/tracks?personId=7'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('HELMET-42'));
      await tester.tap(find.text('HELMET-42'));
      await tester.pumpAndSettle();
      expect(find.text('/devices/42'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.textContaining('OLD-43'), 250);
      await tester.tap(find.textContaining('OLD-43'));
      await tester.pumpAndSettle();
      expect(find.text('/devices/43'), findsOneWidget);
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
    expect(find.text('定位正常'), findsNothing);
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
    expect(find.text('定位正常'), findsNothing);
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
      expect(find.text('定位正常'), findsNothing);
    },
  );

  testWidgets('invalid coordinates cannot be marked as a normal location', (
    tester,
  ) async {
    await _mount(tester, location: {..._location, 'lat': 1000});
    expect(find.text('未知'), findsOneWidget);
    expect(find.text('定位正常'), findsNothing);
  });

  testWidgets(
    'person detail remains readable and contact reachable on a phone',
    (tester) async {
      await _mount(tester, location: _location);
      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpAndSettle();
      expect(find.text('联系该人员').hitTestable(), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('OLD-43'), 250);
      expect(find.textContaining('OLD-43').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

const _location = <String, dynamic>{
  'personId': '7',
  'personCode': 'P-007',
  'personName': '张三',
  'deviceId': '42',
  'sn': 'HELMET-42',
  'lat': 31.2304,
  'lng': 121.4737,
  'occurredAt': '2026-09-18T10:20:00+08:00',
  'locationQuality': 'ok',
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
          case '/api/v1/people/7/assignments':
            data = [
              {
                'deviceId': '43',
                'typeCode': 'helmet',
                'sn': 'OLD-43',
                'issuedAt': '2026-01-01T10:00:00+08:00',
                'returnedAt': '2026-01-02T10:00:00+08:00',
              },
            ];
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
            ];
          case '/api/v1/locations/people/7':
            if (locationReady != null) await locationReady;
            data = location;
            code = locationCode;
          case '/api/v1/devices/42':
            data = {'id': '42', 'online': '1', 'connectionQuality': 'ok'};
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
  final session = WearSession(dio: dio, credentials: _MemoryCredentials())
    ..token = 'token'
    ..siteId = '1'
    ..me = {'userId': '99'};
  addTearDown(session.dispose);
  final router = GoRouter(
    initialLocation: '/people/7',
    routes: [
      GoRoute(
        path: '/people/:id',
        builder: (_, state) => PersonPage(id: state.pathParameters['id']!),
      ),
      for (final path in ['/communications', '/tracks', '/devices/:id'])
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
