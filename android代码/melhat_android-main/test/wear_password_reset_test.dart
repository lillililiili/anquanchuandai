import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/password_reset_page.dart';
import 'wear_session_test.dart' show MemoryCredentials, transport, reply;

void main() {
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'reset request validates and returns without sending or changing password at $scale',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetViewInsets();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final requests = <RequestOptions>[];
        final session = WearSession(
          credentials: MemoryCredentials(),
          dio: transport((r) {
            requests.add(r);
            return reply({'captchaEnabled': false}, raw: true);
          }),
        )..initialized = true;
        addTearDown(session.dispose);
        await tester.pumpWidget(
          WearApp(session: session, enableNotifications: false),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).at(0), 'operator');
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'retained-input',
        );
        Future<void> click(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        await click(find.text('忘记密码 / 申请重置  >'));
        expect(find.byType(WearPasswordResetPage), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.text('找回登录权限'), findsOneWidget);
        final account = find.byKey(const ValueKey('password-reset-account'));
        final code = find.byKey(const ValueKey('password-reset-code'));
        final submit = find.byKey(const ValueKey('password-reset-submit'));
        String challenge() => tester
            .widget<Text>(
              find.byKey(const ValueKey('password-reset-challenge')),
            )
            .data!;
        expect(
          tester.widget<TextFormField>(account).controller!.text,
          'operator',
        );
        await tester.enterText(account, '');
        await click(submit);
        expect(find.text('请输入工作账号'), findsOneWidget);
        await tester.enterText(account, 'operator');
        await tester.enterText(code, 'wrong');
        await click(submit);
        expect(find.text('验证码不正确，请重新输入'), findsOneWidget);
        final previous = challenge();
        await click(find.byKey(const ValueKey('password-reset-refresh')));
        expect(challenge(), isNot(previous));
        expect(tester.widget<TextFormField>(code).controller!.text, isEmpty);
        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        await tester.enterText(code, challenge().toLowerCase());
        await click(submit);
        expect(find.text('申请服务待接入'), findsOneWidget);
        expect(find.textContaining('申请尚未发送，密码未变更'), findsOneWidget);
        expect(requests.where((r) => r.method != 'GET'), isEmpty);
        await tester.tap(find.text('我知道了'));
        await tester.pumpAndSettle();
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await click(find.byTooltip('返回登录'));
        expect(find.byType(WearPasswordResetPage), findsNothing);
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(0))
              .controller!
              .text,
          'operator',
        );
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(1))
              .controller!
              .text,
          'retained-input',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
