import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'wear_media_scope_test.dart' show panel, history;
import 'wear_session_test.dart' show MemoryCredentials;

void main() {
  JsonMap photo() => {
    'id': 'authorized-asset',
    'name': '原授权照片',
    'kind': 'photo',
    'url': 'https://example.invalid/authorized-photo.jpg',
  };

  WearSession sessionFor(
    Future<Response<dynamic>> Function(RequestOptions) reply, {
    String user = 'u1',
    String site = 's1',
  }) {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) async {
          handler.resolve(await reply(request));
        },
      ),
    );
    final session =
        WearSession(dio: dio, mock: false, credentials: MemoryCredentials())
          ..token = 'isolated-test-token'
          ..siteId = site
          ..me = {'userId': user};
    addTearDown(session.dispose);
    return session;
  }

  Response<dynamic> response(
    RequestOptions request,
    Object data, {
    int code = 200,
  }) => Response(requestOptions: request, statusCode: code, data: data);

  Future<void> openPhoto(WidgetTester tester, WearSession session) async {
    await tester.pumpWidget(panel(session));
    await tester.pumpAndSettle();
    await tester.tap(find.text('原授权照片'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
  }

  testWidgets('revoked history also closes an already open photo preview', (
    tester,
  ) async {
    var allowed = true;
    final session = sessionFor(
      (request) async => response(
        request,
        allowed ? history([photo()]) : {'code': 403, 'message': '资料访问权限已撤销'},
        code: allowed ? 200 : 403,
      ),
    );
    await openPhoto(tester, session);
    allowed = false;
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('资料访问权限已撤销'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final changed in ['account', 'site']) {
    testWidgets('$changed change closes preview without replacing navigator', (
      tester,
    ) async {
      Future<Response<dynamic>> reply(RequestOptions request) async =>
          response(request, history([photo()]));
      final before = sessionFor(reply);
      final after = sessionFor(
        reply,
        user: changed == 'account' ? 'u2' : 'u1',
        site: changed == 'site' ? 's2' : 's1',
      );
      await openPhoto(tester, before);
      await tester.pumpWidget(panel(after));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.text('原授权照片'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('new issuance invalidates an old media preview', (tester) async {
    final session = sessionFor(
      (request) async => response(request, history([photo()])),
    );
    await openPhoto(tester, session);
    await tester.pumpWidget(panel(session, version: 2));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(Image), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a refreshed authorized list cannot retain a removed open asset',
    (tester) async {
      var included = true;
      final session = sessionFor(
        (request) async =>
            response(request, history(included ? [photo()] : [])),
      );
      await openPhoto(tester, session);
      included = false;
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.text('暂无已确认文件'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('ordinary history refresh keeps the same authorized preview', (
    tester,
  ) async {
    final session = sessionFor(
      (request) async => response(request, history([photo()])),
    );
    await openPhoto(tester, session);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.text('原授权照片'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('revocation removes only its preview and keeps a newer dialog', (
    tester,
  ) async {
    var allowed = true;
    final session = sessionFor(
      (request) async => response(
        request,
        allowed ? history([photo()]) : {'code': 403, 'message': '资料访问权限已撤销'},
        code: allowed ? 200 : 403,
      ),
    );
    await openPhoto(tester, session);
    showDialog<void>(
      context: tester.element(find.byType(Dialog)),
      builder: (_) => const AlertDialog(content: Text('其他业务提示')),
    );
    await tester.pumpAndSettle();
    allowed = false;
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('其他业务提示'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.text('关闭'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'media origin distinguishes platform recording and device files',
    (tester) async {
      final session = sessionFor(
        (request) async => response(
          request,
          history([
            {'id': 'p', 'kind': 'video', 'mediaOrigin': 'PLATFORM_RECORDING'},
            {'id': 'd', 'kind': 'video', 'mediaOrigin': 'DEVICE_RECORDING'},
            {'id': 'i', 'kind': 'photo', 'mediaOrigin': 'DEVICE_PHOTO'},
            {'id': 'u', 'kind': 'video'},
          ]),
        ),
      );
      await tester.pumpWidget(panel(session));
      await tester.pumpAndSettle();
      expect(find.textContaining('平台录制'), findsOneWidget);
      expect(find.textContaining('设备内录像'), findsOneWidget);
      expect(find.textContaining('设备照片'), findsOneWidget);
      expect(find.textContaining('来源未确认'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
