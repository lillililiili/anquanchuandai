import 'package:rolling_intelligence_headband/components/skeleton_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/components/field_motion.dart';

void main() {
  testWidgets('value transition retains editable child state and selection', (
    tester,
  ) async {
    final controller = TextEditingController(text: '保留草稿');
    addTearDown(controller.dispose);
    Widget app(String value) => MaterialApp(
      home: Scaffold(
        body: MotionSwap(
          value: value,
          child: TextField(controller: controller),
        ),
      ),
    );
    await tester.pumpWidget(app('a'));
    await tester.tap(find.byType(TextField));
    final original = tester.state(find.byType(EditableText));
    await tester.pumpWidget(app('b'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(EditableText)), same(original));
    expect(controller.text, '保留草稿');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'panel closes and reopens with same draft, including rapid toggles',
    (tester) async {
      Widget app(bool visible, double height) => MaterialApp(
        home: Scaffold(
          body: MotionPanel(
            visible: visible,
            height: height,
            child: const TextField(),
          ),
        ),
      );
      await tester.pumpWidget(app(true, 300));
      await tester.enterText(find.byType(TextField), 'draft');
      await tester.pumpWidget(app(false, 300));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpWidget(app(true, 420));
      await tester.pumpAndSettle();
      expect(find.text('draft'), findsOneWidget);
      await tester.pumpWidget(app(false, 420));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(app(true, 300));
      await tester.pumpAndSettle();
      expect(find.text('draft'), findsOneWidget);
    },
  );
  testWidgets('reduced motion is static and disabled presses do not shrink', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MotionActivity(
            child: MotionEntrance(
              child: MotionPress(
                enabled: false,
                child: SizedBox(width: 100, height: 100, child: Text('静态')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('静态')),
    );
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await gesture.up();
    expect(tester.takeException(), isNull);
  });
  testWidgets('changing reduce motion retains revealed text field state', (
    tester,
  ) async {
    Widget app(bool reduce) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: const Scaffold(body: MotionReveal(child: TextField())),
      ),
    );
    await tester.pumpWidget(app(false));
    await tester.enterText(find.byType(TextField), 'keep');
    final state = tester.state(find.byType(EditableText));
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(EditableText)), same(state));
    expect(find.text('keep'), findsOneWidget);
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(EditableText)), same(state));
  });
  testWidgets('refresh and failure retain content state with retry', (
    tester,
  ) async {
    Widget app(SkeletonStatus status) => MaterialApp(
      home: Scaffold(
        body: SkeletonView<int>(
          status: status,
          data: 1,
          builder: (_) => const TextField(),
          onRetry: () {},
        ),
      ),
    );
    await tester.pumpWidget(app(SkeletonStatus.success));
    await tester.enterText(find.byType(TextField), 'retained');
    final state = tester.state(find.byType(EditableText));
    await tester.pumpWidget(app(SkeletonStatus.loading));
    await tester.pump();
    expect(tester.state(find.byType(EditableText)), same(state));
    await tester.pumpWidget(app(SkeletonStatus.error));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(EditableText)), same(state));
    expect(find.text('retained'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}
