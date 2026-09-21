import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rolling_intelligence_headband/http/index.dart';
import 'package:rolling_intelligence_headband/views/home_children/geo_fence_edit.dart';

Future<List<RequestOptions>> mountFence(
  WidgetTester tester, {
  bool editing = false,
}) async {
  tester.view.physicalSize = const Size(420, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final writes = <RequestOptions>[];
  final interceptor = InterceptorsWrapper(
    onRequest: (options, handler) {
      dynamic data;
      if (options.path == '/system/dict/data/type/elec_fence_type') {
        data = [
          {'dictLabel': '禁止进入', 'dictValue': '1'},
        ];
      } else if (options.path == '/hat/electronic/fence/9') {
        data = {
          'id': '9',
          'fenceName': '旧围栏',
          'fenceType': '禁止进入',
          'status': 0,
          'fenceShape': 'polygon',
          'coordinates': [
            {'latitude': 37.0, 'longitude': 118.0},
            {'latitude': 37.0, 'longitude': 118.1},
            {'latitude': 37.1, 'longitude': 118.1},
          ],
        };
      } else if (options.path == '/hat/electronic/fence' &&
          (options.method == 'PUT' || options.method == 'POST')) {
        writes.add(options);
        data = true;
      } else {
        handler.reject(
          DioException(requestOptions: options, message: 'Unexpected request'),
        );
        return;
      }
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {'code': 200, 'msg': 'ok', 'data': data},
        ),
      );
    },
  );
  http.dio.interceptors.insert(0, interceptor);
  addTearDown(() => http.dio.interceptors.remove(interceptor));
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: TextButton(
            onPressed: () => context.push('/fence-edit'),
            child: const Text('打开围栏'),
          ),
        ),
      ),
      GoRoute(
        path: '/fence-edit',
        builder: (context, state) =>
            GeoFenceEditPage(fenceId: editing ? '9' : null),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.text('打开围栏'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return writes;
}

void main() {
  testWidgets('editing an inactive fence preserves status and trims the name', (
    tester,
  ) async {
    final writes = await mountFence(tester, editing: true);
    await tester.enterText(find.byType(TextField), '  更名围栏  ');
    await tester.ensureVisible(find.text('保存围栏'));
    await tester.tap(find.text('保存围栏'));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    final payload = writes.single.data as Map;
    expect(writes.single.method, 'PUT');
    expect(payload['fence']['status'], 0);
    expect(payload['fence']['fenceName'], '更名围栏');
    expect(payload['coordinates'], hasLength(3));
  });

  testWidgets('blank name and missing type cannot issue a fence save', (
    tester,
  ) async {
    final writes = await mountFence(tester);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.ensureVisible(find.text('保存围栏'));
    await tester.tap(find.text('保存围栏'));
    await tester.pump();
    expect(writes, isEmpty);
    expect(find.text('请输入围栏名称'), findsWidgets);
    await tester.enterText(find.byType(TextField), '有效名称');
    await tester.ensureVisible(find.text('保存围栏'));
    await tester.tap(find.text('保存围栏'));
    await tester.pump();
    expect(writes, isEmpty);
    expect(find.text('请选择围栏类型'), findsWidgets);
    await tester.ensureVisible(find.byType(DropdownButton<String>));
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('禁止进入').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存围栏'));
    await tester.tap(find.text('保存围栏'));
    await tester.pump();
    expect(writes, isEmpty);
    expect(find.textContaining('至少需要3个不同且不共线的点'), findsOneWidget);
  });
}
