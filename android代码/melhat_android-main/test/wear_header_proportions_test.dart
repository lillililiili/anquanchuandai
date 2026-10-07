import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'four page headers share height and full-width edges at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final session =
            WearSession(
                credentials: MemoryCredentials(),
                dio: transport((r) {
                  if (r.path.endsWith('/summary')) {
                    return reply({'activeTasks': [], 'unclaimed': 2});
                  }
                  if (r.path.endsWith('/inbox/count')) {
                    return reply({'count': 2});
                  }
                  if (r.path.endsWith('/equipment')) return reply([]);
                  return reply({
                    'records': [],
                    'total': 0,
                    'current': 1,
                    'size': 20,
                  });
                }),
              )
              ..initialized = true
              ..token = 'test'
              ..siteId = '1'
              ..me = identity(user: 'header-$scale');
        addTearDown(session.dispose);
        await tester.pumpWidget(
          WearApp(session: session, enableNotifications: false),
        );
        await tester.pumpAndSettle();
        final home = find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              ((w.decoration as BoxDecoration).image?.image is AssetImage) &&
              ((w.decoration as BoxDecoration).image!.image as AssetImage)
                  .assetName
                  .endsWith('work_reference_header.png'),
        );
        final rect = tester.getRect(home);
        debugPrint('HOME HEADER scale=$scale bounds=$rect');
        expect(rect.left, 0);
        expect(rect.top, 0);
        expect(rect.width, 360);
        for (final index in [1, 2, 3]) {
          await tester.tap(find.byType(NavigationDestination).at(index));
          await tester.pumpAndSettle();
          final hero = find.byKey(
            ValueKey(
              'wear-page-hero-${['home', 'comms', 'events', 'mine'][index]}',
            ),
          );
          expect(tester.getSize(hero).height, closeTo(rect.height, 1));
          expect(tester.getRect(hero).left, 0);
          expect(tester.getSize(hero).width, 360);
          expect(tester.getSize(find.byType(NavigationBar)).height, 60);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'login banner and scrollable form fit short screens at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final session = WearSession(
          credentials: MemoryCredentials(),
          dio: transport((_) => reply({})),
        )..initialized = true;
        addTearDown(session.dispose);
        await tester.pumpWidget(
          WearApp(session: session, enableNotifications: false),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .getSize(find.byKey(const ValueKey('wear-page-hero-login')))
              .height,
          scale == 1 ? 148 : 230,
        );
        expect(find.text('欢迎登录'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
