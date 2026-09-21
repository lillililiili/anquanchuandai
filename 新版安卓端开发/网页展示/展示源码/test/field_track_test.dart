import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/controllers/trajectory_player_controller.dart';
import 'package:rolling_intelligence_headband/components/skeleton_view.dart';
import 'package:rolling_intelligence_headband/hooks/use_skeleton.dart';
import 'package:rolling_intelligence_headband/models/playback_speed.dart';
import 'package:rolling_intelligence_headband/models/trajectory_point.dart';
import 'package:rolling_intelligence_headband/views/home_children/playback_of_trajectory.dart';

TrajectoryPoint _point(String timestamp) {
  return TrajectoryPoint(
    latitude: 37.24,
    longitude: 118.81,
    timestamp: timestamp,
    dateTime: DateTime.parse(timestamp.replaceFirst(' ', 'T')),
  );
}

void main() {
  test(
    'trajectory page keeps no-arg use and accepts initial query context',
    () {
      expect(const PlaybackOfTrajectoryPage(), isA<PlaybackOfTrajectoryPage>());
      final page = PlaybackOfTrajectoryPage(
        initialHatId: '12',
        initialHatNumber: 'MEL-0012',
        initialUserName: '张三',
        initialDate: DateTime(2026, 9, 5),
      );
      expect(page.initialHatId, '12');
      expect(page.initialHatNumber, 'MEL-0012');
      expect(page.initialUserName, '张三');
      expect(page.initialDate, DateTime(2026, 9, 5));
    },
  );

  group('TrajectoryPlayerController', () {
    test('replaces an old trajectory and clears it after an empty query', () {
      final controller = TrajectoryPlayerController();
      addTearDown(controller.dispose);

      controller.setPoints([
        _point('2026-09-06 08:00:00'),
        _point('2026-09-06 08:10:00'),
      ]);
      controller.seekTo(1);

      controller.setPoints([_point('2026-09-06 09:00:00')]);
      expect(controller.totalCount, 1);
      expect(controller.currentTimestamp, '2026-09-06 09:00:00');

      controller.setPoints(const []);
      expect(controller.totalCount, 0);
      expect(controller.currentIndex, -1);
      expect(controller.currentTimestamp, isNull);
    });

    test('locates the nearest trajectory point for a selected time', () {
      final controller = TrajectoryPlayerController();
      addTearDown(controller.dispose);
      controller.setPoints([
        _point('2026-09-06 08:00:00'),
        _point('2026-09-06 08:10:00'),
        _point('2026-09-06 08:20:00'),
      ]);

      controller.seekToTimestamp(DateTime(2026, 9, 6, 8, 13));

      expect(controller.currentIndex, 1);
      expect(controller.currentTimestamp, '2026-09-06 08:10:00');
    });

    test('keeps the original four playback speeds', () {
      expect(
        PlaybackSpeed.values.map((speed) => speed.label),
        orderedEquals([0.5, 1.0, 2.0, 5.0]),
      );
    });
  });

  test('query generation rejects results from an older condition', () {
    final generation = TrajectoryQueryGeneration();
    final firstQuery = generation.next();
    final secondQuery = generation.next();

    expect(generation.isCurrent(firstQuery), isFalse);
    expect(generation.isCurrent(secondQuery), isTrue);

    generation.invalidate();
    expect(generation.isCurrent(secondQuery), isFalse);
  });

  testWidgets('useSkeleton does not commit a late response from an old token', (
    tester,
  ) async {
    final first = Completer<List<int>>();
    final second = Completer<List<int>>();
    var generation = 1;
    var requestCount = 0;
    SkeletonBind<List<int>>? binding;

    await tester.pumpWidget(
      MaterialApp(
        home: HookBuilder(
          builder: (context) {
            binding = useSkeleton<List<int>>(
              immediate: false,
              commitToken: () => generation,
              request: () => requestCount++ == 0 ? first.future : second.future,
            );
            return Text('${binding!.data.value}');
          },
        ),
      ),
    );

    final firstExecution = binding!.execute();
    generation = 2;
    final secondExecution = binding!.execute();
    second.complete([2]);
    await secondExecution;
    await tester.pump();
    expect(find.text('[2]'), findsOneWidget);

    first.complete([1]);
    await firstExecution;
    await tester.pump();
    expect(find.text('[2]'), findsOneWidget);
  });
}
