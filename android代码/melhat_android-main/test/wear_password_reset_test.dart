import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/password_reset_page.dart';
import 'wear_session_test.dart' show transport, reply;

void main() {
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'recovery submits to backend and retains input on failure at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        var submitted = 0;
        final api = WearApi(
          token: () => null,
          siteId: () => null,
          epoch: () => 0,
          dio: transport((r) {
            if (r.path == '/captchaImage')
              return reply({'code': 200, 'captchaEnabled': false}, raw: true);
            expect(r.path, '/api/v1/account-recovery/requests');
            expect(r.data['identifier'], 'P-001');
            expect(r.data['realName'], '测试人员');
            expect(r.headers.containsKey('Authorization'), isFalse);
            submitted++;
            return submitted == 1
                ? reply(null, code: 503, msg: '暂不可用')
                : reply({'id': 'receipt', 'status': 'pending'});
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: WearPasswordResetPage(api: api, initialAccount: 'P-001'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).at(1), '测试人员');
        await tester.enterText(find.byType(TextFormField).at(2), '13800000000');
        await tester.enterText(find.byType(TextFormField).at(3), '忘记账号');
        final button = find.widgetWithText(FilledButton, '提交申请');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(submitted, 1);
        expect(find.text('申请已提交'), findsNothing);
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(1))
              .controller!
              .text,
          '测试人员',
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.text('申请已提交'), findsOneWidget);
        expect(find.textContaining('receipt'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
