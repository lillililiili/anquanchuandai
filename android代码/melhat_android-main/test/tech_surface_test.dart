import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/components/tech_surface.dart';

void main() {
  testWidgets(
    'decorative surface does not intercept controls or replace state',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TechSurface(
              animated: true,
              child: SizedBox(
                width: 300,
                height: 160,
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('操作'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('操作'));
      expect(taps, 1);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('reduced motion and hidden decorations schedule no frames', (
    tester,
  ) async {
    Widget app(bool reduced, bool visible) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: TickerMode(
          enabled: visible,
          child: const SizedBox(
            width: 100,
            height: 100,
            child: TechAura(orb: true),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(true, true));
    await tester.pump(const Duration(seconds: 8));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(app(false, true));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(app(false, false));
    await tester.pump(const Duration(seconds: 8));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
