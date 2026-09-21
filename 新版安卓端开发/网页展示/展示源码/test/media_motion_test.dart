import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/components/trajectory_player_controls.dart';
import 'package:rolling_intelligence_headband/controllers/trajectory_player_controller.dart';
import 'package:rolling_intelligence_headband/models/trajectory_point.dart';

void main() {
  testWidgets(
    'trajectory controls keep playback position through full screen and reduced motion',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TrajectoryPlayerController();
      addTearDown(controller.dispose);
      controller.setPoints(
        List.generate(
          3,
          (i) => TrajectoryPoint(
            latitude: 37.24,
            longitude: 118.81,
            timestamp: '2026-09-07 10:00:0$i',
            dateTime: DateTime(2026, 9, 7, 10, 0, i),
          ),
        ),
      );
      Future<void> show(bool fullScreen) => tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              disableAnimations: true,
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: TrajectoryPlayerControls(
                controller: controller,
                isFullScreen: fullScreen,
                onFullScreen: () {},
              ),
            ),
          ),
        ),
      );
      await show(false);
      await tester.tap(find.byTooltip('下一个轨迹点'));
      await tester.pump();
      expect(controller.currentIndex, 1);
      await show(true);
      expect(controller.currentIndex, 1);
      await tester.tap(find.byTooltip('上一个轨迹点'));
      await tester.pump();
      expect(controller.currentIndex, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
