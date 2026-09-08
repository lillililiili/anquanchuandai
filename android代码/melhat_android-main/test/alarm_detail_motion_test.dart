import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'field_alarm_workspace_test.dart' as harness;

void main() {
  testWidgets('reduced motion opens and resizes alarm details immediately', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await harness.mountWorkspace(
      tester,
      harness.FakeAlarmServer(),
      initialSelectedKey: 'device:1',
    );
    final controller = tester
        .widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet))
        .controller!;
    expect(controller.size, closeTo(.86, .001));
    await tester.tap(find.byTooltip('折叠详情'));
    expect(controller.size, closeTo(.2, .001));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('展开详情'));
    expect(controller.size, closeTo(1, .001));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
