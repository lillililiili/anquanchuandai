import 'dart:async';
import 'package:dio/dio.dart';
import 'package:rolling_intelligence_headband/http/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/views/login_view.dart';
import 'package:rolling_intelligence_headband/theme/app_theme.dart';

void main() {
  testWidgets(
    'login supports large text, password visibility and empty validation',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(375, 812),
              textScaler: TextScaler.linear(2),
            ),
            child: const LoginView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('显示密码'));
      await tester.tap(find.byTooltip('显示密码'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField).last).obscureText,
        isFalse,
      );
      await tester.ensureVisible(find.text('登录并进入工作台'));
      await tester.tap(find.text('登录并进入工作台'));
      await tester.pump();
      expect(find.text('请输入用户名和密码'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'login disables repeated submits and recovers after network failure',
    (tester) async {
      final pending = Completer<void>();
      var requestCount = 0;
      final interceptor = InterceptorsWrapper(
        onRequest: (options, handler) async {
          requestCount++;
          await pending.future;
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              message: '网络连接失败，请重试',
            ),
          );
        },
      );
      http.dio.interceptors.insert(0, interceptor);
      addTearDown(() => http.dio.interceptors.remove(interceptor));
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const LoginView()),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'test-user');
      await tester.enterText(find.byType(TextField).last, 'test-password');
      await tester.ensureVisible(find.text('登录并进入工作台'));
      await tester.tap(find.text('登录并进入工作台'));
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).enabled,
        isFalse,
      );
      // Let the request reach the interceptor without touching a real server.
      await tester.pump(const Duration(milliseconds: 100));
      expect(requestCount, 1);
      pending.complete();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('网络连接失败，请重试'), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('CARGO login keeps form accessible with keyboard open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(375, 812),
            viewInsets: EdgeInsets.only(bottom: 300),
          ),
          child: LoginView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FieldLoginHero), findsNothing);
    await tester.ensureVisible(find.text('登录并进入工作台'));
    expect(find.text('登录并进入工作台').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
