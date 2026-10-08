import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rolling_intelligence_headband/config/backend_config.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';

// Read-only smoke for the persistent local acceptance accounts. No SOS,
// assignment, verification, password reset or device command is submitted.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const password = String.fromEnvironment('DEVICE_READY_USER_PASSWORD');
  var converted = false;
  testWidgets('real member and duty accounts navigate all four tabs', (
    t,
  ) async {
    expect(BackendConfig.mock, false);
    expect(BackendConfig.baseUrl, 'http://127.0.0.1:18084');
    expect(password.isNotEmpty, true);
    Future<void> settle() => t.pumpAndSettle(
      const Duration(milliseconds: 150),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 30),
    );
    Future<void> tap(Finder finder) async {
      await t.ensureVisible(finder);
      await settle();
      await t.tap(finder);
      await settle();
    }

    Future<void> shot(String name) async {
      if (!converted) {
        await binding.convertFlutterSurfaceToImage();
        converted = true;
      }
      await settle();
      await binding.takeScreenshot(name);
    }

    for (final account in ['wear_user', 'wear_duty']) {
      final session = WearSession(
        mock: false,
        credentials: MockCredentialStore(),
      );
      await session.initialize();
      await t.pumpWidget(WearApp(session: session, enableNotifications: false));
      await settle();
      await t.enterText(find.byType(TextFormField).at(0), account);
      await t.enterText(find.byType(TextFormField).at(1), password);
      await tap(find.widgetWithText(FilledButton, '登录'));
      expect(session.personId, account == 'wear_user' ? 'P3' : 'P1');
      expect(session.isAdmin, account == 'wear_duty');
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(session.canRequestSos, true);
      expect(find.text('发起值班交接'), findsNothing);
      final label = account == 'wear_user' ? 'member' : 'duty';
      await shot('$label-home');
      for (var index = 1; index <= 3; index++) {
        await tap(find.byType(NavigationDestination).at(index));
        expect(t.takeException(), isNull);
        await shot('$label-tab-$index');
      }
      expect(find.text('重试绑定'), findsNothing);
      if (account == 'wear_user') {
        await expectLater(
          session.api.get('/api/v1/people/P2'),
          throwsA(isA<WearApiException>().having((e) => e.code, 'code', 404)),
        );
        await expectLater(
          session.selectSite('site-2'),
          throwsA(isA<WearApiException>().having((e) => e.code, 'code', 403)),
        );
      }
      await tap(find.text('退出登录'));
      await tap(find.text('确认退出'));
      expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
      expect(session.token, isNull);
      await t.pumpWidget(const SizedBox.shrink());
      session.dispose();
    }
  });
}
