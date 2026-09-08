import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rolling_intelligence_headband/field/field_home.dart';
import 'package:rolling_intelligence_headband/field/field_session.dart';
import 'package:rolling_intelligence_headband/http/index.dart';
import 'package:rolling_intelligence_headband/models/hat.dart';
import 'package:rolling_intelligence_headband/theme/app_theme.dart';
import 'package:rolling_intelligence_headband/views/home_view.dart';

final _hats = [
  {
    'id': '1',
    'hatNumber': 'H1',
    'bindUserName': '张三',
    'bindGroup': '作业A',
    'status': '1',
    'electricityUsage': 10,
  },
  {
    'id': '2',
    'hatNumber': 'H2',
    'bindUserName': '李四',
    'bindGroup': '作业B',
    'status': '0',
    'electricityUsage': 85,
  },
];

void main() {
  testWidgets(
    'workbench source counts follow group and keep priority tasks ahead of tools',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      FieldSession.instance.clear();
      final interceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          final rows = switch (options.path) {
            '/hat/safety/info/page' => _hats,
            '/hat/alarm/page' => [
              {
                'id': 'd1',
                'hatId': '1',
                'hatNumber': 'H1',
                'userName': '张三',
                'alarmType': 'fall',
                'isHandled': 0,
              },
            ],
            '/hat/fence/alarm/page' => [
              {
                'id': 'f1',
                'hatId': '2',
                'hatNumber': 'H2',
                'userName': '李四',
                'alarmType': '1',
                'isHandled': 0,
              },
            ],
            '/hat/group/info' => [
              {'id': 'g1', 'groupName': '作业A'},
              {'id': 'g2', 'groupName': '作业B'},
            ],
            _ => <Map<String, Object>>[],
          };
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'code': 200,
                'msg': 'ok',
                'data': {'records': rows, 'total': rows.length},
              },
            ),
          );
        },
      );
      http.dio.interceptors.insert(0, interceptor);
      addTearDown(() {
        http.dio.interceptors.remove(interceptor);
        FieldSession.instance.clear();
      });
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const FieldHomePage()),
      );
      await tester.pumpAndSettle();
      expect(find.text('查看全部 (2)'), findsOneWidget);
      expect(find.text('设备 1'), findsOneWidget);
      expect(find.text('围栏 1'), findsOneWidget);
      await tester.tap(find.text('围栏 1'));
      await tester.pumpAndSettle();
      expect(find.text('查看全部 (1)'), findsOneWidget);
      expect(find.text('跌倒告警 · 张三'), findsNothing);
      await tester.tap(find.text('全部分组'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('作业A'));
      await tester.pumpAndSettle();
      expect(find.text('设备 1'), findsOneWidget);
      expect(find.text('围栏 0'), findsOneWidget);
      expect(find.text('查看全部 (0)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'device sheet filters and clears at 320dp with large text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 812),
              textScaler: TextScaler.linear(2),
              viewInsets: EdgeInsets.only(bottom: 220),
            ),
            child: Scaffold(
              body: FieldDeviceSheet(
                hats: _hats.map(Hat.fromJson).toList(),
                complete: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('低电量 ≤20%'));
      await tester.tap(find.text('低电量 ≤20%'));
      await tester.pumpAndSettle();
      expect(find.text('全部作业组 · 1 台'), findsOneWidget);
      await tester.ensureVisible(find.text('清除条件'));
      await tester.tap(find.text('清除条件'));
      await tester.pumpAndSettle();
      expect(find.text('全部作业组 · 2 台'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('all four navigation labels and actions fit 260dp with 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/home/tab1',
      routes: [
        for (var i = 1; i <= 4; i++)
          GoRoute(
            path: '/home/tab$i',
            builder: (_, state) => HomeView(child: Text('页面${state.uri.path}')),
          ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['首页', '对讲', '监控', '我的']) {
      expect(find.text(label), findsOneWidget);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(router.routeInformationProvider.value.uri.path, '/home/tab4');
  });
}
