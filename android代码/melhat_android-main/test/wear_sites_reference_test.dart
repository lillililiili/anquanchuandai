import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/sites_page.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'authorized search and explicit site confirmation at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        var switches = 0;
        var fail = true;
        final session =
            WearSession(
                credentials: MemoryCredentials(),
                dio: transport((r) {
                  if (r.path == '/api/v1/me/current-site') {
                    switches++;
                    expect(r.method, 'PUT');
                    expect(r.data, {'siteId': '2'});
                    return fail
                        ? reply(null, code: 500, msg: '厂站切换失败')
                        : reply({'currentSiteId': '2'});
                  }
                  return reply({'records': [], 'total': 0});
                }),
              )
              ..initialized = true
              ..me = identity()
              ..siteId = '1'
              ..token = 'test';
        (session.me!['authorizedSites'] as List).add({
          'id': '3',
          'name': '停用厂站',
          'status': '1',
        });
        addTearDown(session.dispose);
        await tester.pumpWidget(
          WearApp(session: session, enableNotifications: false),
        );
        await tester.pumpAndSettle();
        GoRouter.of(tester.element(find.byType(NavigationBar))).go('/sites');
        await tester.pumpAndSettle();
        expect(find.text('停用厂站'), findsNothing);
        expect(find.text('已选择'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('sites-search')),
          '不存在',
        );
        await tester.pumpAndSettle();
        expect(find.text('未找到匹配厂站，请尝试其他名称或编码。'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('sites-search')),
          '厂站二',
        );
        await tester.pumpAndSettle();
        final row = find.byKey(const ValueKey('site-2'));
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(session.siteId, '1');
        expect(switches, 0);
        final enter = find.byKey(const ValueKey('sites-enter'));
        await tester.ensureVisible(enter);
        await tester.tap(enter);
        await tester.pumpAndSettle();
        expect(session.siteId, '1');
        expect(find.byType(WearSitesPage), findsOneWidget);
        expect(find.textContaining('厂站切换失败'), findsWidgets);
        fail = false;
        await tester.ensureVisible(enter);
        await tester.tap(enter);
        await tester.pumpAndSettle();
        expect(session.siteId, '2');
        expect(switches, 2);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('no authorization disables entry and preserves logout', (
    tester,
  ) async {
    final credentials = MemoryCredentials('test');
    final session =
        WearSession(
            credentials: credentials,
            dio: transport(
              (r) => r.path == '/captchaImage'
                  ? reply({'captchaEnabled': false}, raw: true)
                  : reply(null),
            ),
          )
          ..initialized = true
          ..me = (identity(site: null)..['authorizedSites'] = [])
          ..token = 'test';
    addTearDown(session.dispose);
    await tester.pumpWidget(
      WearApp(session: session, enableNotifications: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无可访问的厂站'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('sites-enter')))
          .onPressed,
      isNull,
    );
    final logout = find.byKey(const ValueKey('sites-logout'));
    await tester.ensureVisible(logout);
    await tester.tap(logout);
    await tester.pumpAndSettle();
    expect(session.me, isNull);
    expect(credentials.value, isNull);
    expect(find.text('欢迎登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
