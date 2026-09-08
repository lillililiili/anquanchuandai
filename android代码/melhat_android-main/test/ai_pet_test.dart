import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/components/ai_pet.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets(
    'pet keeps a small touch area, drags to edge, hides and restores',
    (tester) async {
      final settings = AiPetSettings.instance;
      await settings.load();
      await settings.update(hide: false, side: true, interval: 0);
      int opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiPetDock(
              visible: true,
              onOpen: () => opens++,
              onSettings: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.getSize(find.byType(AiPetAvatar)), const Size(48, 48));
      final target = find.byType(GestureDetector);
      expect(tester.getSize(target), const Size(56, 56));
      await tester.tap(target);
      expect(opens, 1);
      await tester.drag(target, const Offset(-600, 30));
      await tester.pumpAndSettle();
      expect(settings.right, false);
      expect(opens, 1);
      await settings.update(hide: true);
      await tester.pump();
      expect(find.byType(AiPetAvatar), findsNothing);
      await settings.update(hide: false);
      await tester.pump();
      expect(find.byType(AiPetAvatar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('idle waits after completion, rebuild keeps timer, taps do not queue', (tester) async {
    int tap = 0;
    bool busy = false;
    Widget scene() => MaterialApp(home: Center(child: AiPetAvatar(
      idleSeconds: 20, tapSerial: tap, busy: busy)));
    dynamic painter() => tester.widget<CustomPaint>(find.descendant(
      of: find.byType(AiPetAvatar), matching: find.byType(CustomPaint))).painter;
    await tester.pumpWidget(scene());
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(scene());
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    final first = painter().action;
    expect(first, isNot(AiPetAction.rest));
    await tester.pump(const Duration(milliseconds: 2700));
    await tester.pump();
    expect(painter().action, AiPetAction.rest);
    await tester.pump(const Duration(seconds: 19));
    expect(painter().action, AiPetAction.rest);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(painter().action, isNot(first));
    tap++;
    await tester.pumpWidget(scene());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(painter().action, AiPetAction.twist);
    tap++;
    await tester.pumpWidget(scene());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    expect(painter().action, AiPetAction.rest);
    tap++;
    await tester.pumpWidget(scene());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(painter().action, AiPetAction.wave);
    busy = true;
    await tester.pumpWidget(scene());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(painter().action, AiPetAction.typing);
    tap++;
    await tester.pumpWidget(scene());
    await tester.pump();
    expect(painter().action, AiPetAction.typing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion suppresses busy and idle animations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: AiPetAvatar(busy: true, idleSeconds: 30),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 35));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('idle is finite and background stops animation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: AiPetAvatar(idleSeconds: 30))),
    );
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 35));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}

