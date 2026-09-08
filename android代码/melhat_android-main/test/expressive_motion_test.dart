import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/components/field_motion.dart';

void main() {
  testWidgets('spring interruption keeps position and editable child', (tester) async {
    var value = 0.0;
    Widget app(double target, {bool reduce = false, bool active = true}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: TickerMode(
          enabled: active,
          child: Scaffold(body: MotionSpringValue(
            value: target,
            builder: (_, current, child) {
              value = current;
              return child!;
            },
            child: const TextField(),
          )),
        ),
      ),
    );
    await tester.pumpWidget(app(0));
    await tester.enterText(find.byType(TextField), 'draft');
    final editable = tester.state(find.byType(EditableText));
    await tester.pumpWidget(app(3));
    await tester.pump(const Duration(milliseconds: 80));
    final interrupted = value;
    expect(interrupted, greaterThan(0));
    expect(interrupted, lessThan(3));
    await tester.pumpWidget(app(1));
    expect(value, closeTo(interrupted, .0001));
    await tester.pumpAndSettle();
    expect(value, closeTo(1, .0001));
    expect(tester.state(find.byType(EditableText)), same(editable));
    expect(find.text('draft'), findsOneWidget);
    await tester.pumpWidget(app(3));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(app(3, reduce: true));
    expect(value, 3);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(app(0, active: false));
    expect(value, 0);
    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();
    expect(value, 0);
    expect(tester.state(find.byType(EditableText)), same(editable));
    expect(tester.takeException(), isNull);
  });
}
