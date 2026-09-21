import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import 'package:rolling_intelligence_headband/http/index.dart';
import 'package:rolling_intelligence_headband/views/home_children/playback_of_trajectory.dart';

class _FakeTrackServer {
  _FakeTrackServer({
    this.failFirstTrajectory = false,
    this.heldTrajectory,
    this.trajectoryRecords = const [],
  });

  final List<Map<String, dynamic>> trajectoryRecords;

  final bool failFirstTrajectory;
  final Completer<void>? heldTrajectory;
  final trajectoryRequests = <RequestOptions>[];
  final videoRequests = <RequestOptions>[];

  late final Interceptor interceptor = InterceptorsWrapper(
    onRequest: (options, handler) async {
      if (options.path == '/hat/location/record/query') {
        trajectoryRequests.add(options);
        if (trajectoryRequests.length == 1 && failFirstTrajectory) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              message: 'forced trajectory failure',
            ),
          );
          return;
        }
        if (heldTrajectory != null) await heldTrajectory!.future;
        handler.resolve(_ok(options, trajectoryRecords));
        return;
      }

      if (options.path == '/hat/location/record/relatedFiles') {
        videoRequests.add(options);
        handler.resolve(_ok(options, <dynamic>[]));
        return;
      }

      handler.reject(
        DioException(
          requestOptions: options,
          message: 'Unexpected request: ${options.method} ${options.path}',
        ),
      );
    },
  );

  Response<Map<String, dynamic>> _ok(RequestOptions options, dynamic data) {
    return Response(
      requestOptions: options,
      statusCode: 200,
      data: {'code': 200, 'msg': 'ok', 'data': data},
    );
  }
}

Future<GoRouter> _mountTrackPage(
  WidgetTester tester,
  _FakeTrackServer server,
) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  http.dio.interceptors.insert(0, server.interceptor);
  addTearDown(() => http.dio.interceptors.remove(server.interceptor));

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: TextButton(
            onPressed: () => context.push('/track'),
            child: const Text('打开轨迹'),
          ),
        ),
      ),
      GoRoute(
        path: '/track',
        builder: (context, state) => PlaybackOfTrajectoryPage(
          initialHatId: '12',
          initialHatNumber: 'MEL-0012',
          initialUserName: '张三',
          initialDate: DateTime(2026, 9, 5),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.text('打开轨迹'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return router;
}

void main() {
  testWidgets(
    'quick day changes clear old results and query the full chosen day',
    (tester) async {
      final server = _FakeTrackServer();
      await _mountTrackPage(tester, server);
      await tester.tap(find.text('查询'));
      await tester.pumpAndSettle();
      expect(server.trajectoryRequests, hasLength(1));
      await tester.tap(find.text('今天全天'));
      await tester.pumpAndSettle();
      expect(find.text('该查询范围内暂无轨迹数据'), findsNothing);
      expect(server.trajectoryRequests, hasLength(1));
      await tester.tap(find.text('查询'));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      final day =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final payload = server.trajectoryRequests.last.data as Map;
      expect(payload['startTime'], '$day 00:00');
      expect(payload['endTime'], '$day 23:59:59');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'query and repeat query keep the same tile layer and bounded camera',
    (tester) async {
      final server = _FakeTrackServer(
        trajectoryRecords: [
          {
            'lat': '37.24087',
            'lng': '118.81377',
            'timestamp': '2026-09-05 00:40:53',
          },
          {
            'lat': '37.24088',
            'lng': '118.81378',
            'timestamp': '2026-09-05 00:45:53',
          },
        ],
      );
      await _mountTrackPage(tester, server);
      final mapState = tester.state(find.byType(FlutterMap));
      final tileState = tester.state(find.byType(TileLayer));
      final provider = tester
          .widget<TileLayer>(find.byType(TileLayer))
          .tileProvider;
      for (var query = 0; query < 2; query++) {
        await tester.tap(find.text('查询'));
        await tester.pumpAndSettle();
        expect(
          identical(tester.state(find.byType(FlutterMap)), mapState),
          isTrue,
        );
        expect(
          identical(tester.state(find.byType(TileLayer)), tileState),
          isTrue,
        );
        expect(
          identical(
            tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider,
            provider,
          ),
          isTrue,
        );
        final camera = MapCamera.of(tester.element(find.byType(TileLayer)));
        expect(camera.zoom.isFinite, isTrue);
        expect(camera.zoom, lessThanOrEqualTo(15));
      }
      expect(server.trajectoryRequests, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing calendar dates preserves an all-day time range', (
    tester,
  ) async {
    final server = _FakeTrackServer();
    await _mountTrackPage(tester, server);
    await tester.tap(find.text('09-05 00:00 - 09-05 23:59:59'));
    await tester.pumpAndSettle();
    final picker = tester.widget<SfDateRangePicker>(
      find.byType(SfDateRangePicker),
    );
    picker.onSubmit!(
      PickerDateRange(DateTime(2026, 9, 4), DateTime(2026, 9, 5)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('查询'));
    await tester.pumpAndSettle();
    final payload = server.trajectoryRequests.single.data as Map;
    expect(payload['startTime'], '2026-09-04 00:00');
    expect(payload['endTime'], '2026-09-05 23:59:59');
  });

  testWidgets(
    'error-card retry runs trajectory and related-video queries with one snapshot',
    (tester) async {
      final server = _FakeTrackServer(failFirstTrajectory: true);
      await _mountTrackPage(tester, server);

      await tester.tap(find.text('查询'));
      await tester.pumpAndSettle();
      expect(find.text('重试'), findsOneWidget);
      expect(server.trajectoryRequests, hasLength(1));
      expect(server.videoRequests, isEmpty);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(server.trajectoryRequests, hasLength(2));
      expect(server.videoRequests, hasLength(1));
      final trajectoryData = server.trajectoryRequests.last.data as Map;
      final videoQuery = server.videoRequests.single.queryParameters;
      expect(trajectoryData['hatIds'], ['12']);
      expect(trajectoryData['startTime'], '2026-09-05 00:00');
      expect(trajectoryData['endTime'], '2026-09-05 23:59:59');
      expect(videoQuery['hatNumber'], 'MEL-0012');
      expect(videoQuery['startTime'], trajectoryData['startTime']);
      expect(videoQuery['endTime'], trajectoryData['endTime']);
      expect(find.text('暂无轨迹数据'), findsOneWidget);
      expect(find.text('该查询范围内暂无轨迹数据'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'leaving while trajectory is pending ignores completion and skips video',
    (tester) async {
      final heldTrajectory = Completer<void>();
      final server = _FakeTrackServer(heldTrajectory: heldTrajectory);
      final router = await _mountTrackPage(tester, server);

      await tester.tap(find.text('查询'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(server.trajectoryRequests, hasLength(1));

      router.pop();
      await tester.pumpAndSettle();
      heldTrajectory.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('打开轨迹'), findsOneWidget);
      expect(server.videoRequests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
