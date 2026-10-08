import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/mock_backend.dart';
import 'wear_session_test.dart' show reply;

class AcceptanceBackend extends MockBackend {
  AcceptanceBackend() : super(scoped: true);
  final writes = <RequestOptions>[];
  String? failSuffix;
  int? failCode;
  bool networkFailure = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method != 'GET') writes.add(options);
    if (failSuffix != null && options.path.endsWith(failSuffix!)) {
      if (networkFailure) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      return reply(null, code: failCode ?? 503, msg: '验收模拟：请求失败，请保留草稿');
    }
    return super.fetch(options, stream, cancelFuture);
  }
}

Future<WearSession> launchAcceptance(
  WidgetTester t,
  AcceptanceBackend backend, {
  String account = 'demo',
  double scale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  backend
    ..account = account
    ..siteId = '1';
  final s = WearSession(dio: Dio()..httpClientAdapter = backend)
    ..initialized = true
    ..token = 'local-test'
    ..siteId = '1'
    ..me = backend.identity;
  addTearDown(s.dispose);
  addTearDown(() async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
  await t.pumpWidget(WearApp(session: s, enableNotifications: false));
  await t.pumpAndSettle();
  return s;
}

Future<void> openAcceptance(WidgetTester t, String route) async {
  unawaited(GoRouter.of(t.element(find.byType(NavigationBar))).push(route));
  await t.pumpAndSettle();
}

Future<void> tapAcceptance(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<void> enterAcceptance(WidgetTester t, String key, String value) async {
  final finder = find.byKey(ValueKey(key));
  await t.ensureVisible(finder);
  await t.enterText(finder, value);
  await t.pumpAndSettle();
}

Future<void> fillVerification(WidgetTester t) async {
  await tapAcceptance(t, find.byKey(const ValueKey('verification-conclusion')));
  await tapAcceptance(t, find.text('需现场处理').last);
  await enterAcceptance(t, 'verification-situation', '已到现场，人员安全');
  await enterAcceptance(t, 'verification-measures', '安排人员陪同并检查装备');
}
