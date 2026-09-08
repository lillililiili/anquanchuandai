import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rolling_intelligence_headband/components/map_fence.dart';
import 'package:rolling_intelligence_headband/components/map_trajectory_player.dart';
import 'package:rolling_intelligence_headband/components/pagination_list_view.dart';
import 'package:rolling_intelligence_headband/components/pagination_view.dart'
    as inline;
import 'package:rolling_intelligence_headband/components/trajectory_player_view.dart';
import 'package:rolling_intelligence_headband/controllers/trajectory_player_controller.dart';
import 'package:rolling_intelligence_headband/hooks/use_pagination.dart';
import 'package:rolling_intelligence_headband/http/response/page.dart';
import 'package:rolling_intelligence_headband/models/trajectory_point.dart';

void main() {
  testWidgets('successful empty search keeps header and supports a new query', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HookBuilder(
            builder: (context) {
              final term = useState('missing');
              final page = usePaginationTable<String>(
                apiFun: (_) async => DataPage(
                  records: term.value == 'missing' ? [] : ['张三'],
                  total: term.value == 'missing' ? 0 : 1,
                ),
              );
              return PaginationListView<String>(
                bind: page,
                header: TextButton(
                  onPressed: () {
                    term.value = '';
                    page.reload();
                  },
                  child: const Text('清空搜索'),
                ),
                itemBuilder: (_, item, index) => Text(item),
                emptyMsg: '没有匹配人员',
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('没有匹配人员'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    await tester.tap(find.text('清空搜索'));
    await tester.pumpAndSettle();
    expect(find.text('张三'), findsOneWidget);
  });

  testWidgets('scroll uses the loaded total to request the next page', (
    tester,
  ) async {
    final requestedPages = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HookBuilder(
            builder: (context) {
              final page = usePaginationTable<int>(
                apiFun: (params) async {
                  final current = params['pageNum'] as int;
                  requestedPages.add(current);
                  return DataPage(
                    records: List.generate(
                      20,
                      (index) => (current - 1) * 20 + index,
                    ),
                    total: 40,
                  );
                },
              );
              return PaginationListView<int>(
                bind: page,
                itemBuilder: (_, item, index) =>
                    SizedBox(height: 80, child: Text('人员$item')),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1400));
    await tester.pumpAndSettle();
    expect(requestedPages, [1, 2]);
  });

  testWidgets(
    'inline pagination reflects external selection without data changes',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HookBuilder(
              builder: (context) {
                final selected = useState(false);
                final page = usePaginationTable<String>(
                  apiFun: (_) async => DataPage(records: ['张三'], total: 1),
                );
                final scroll = useScrollController();
                return SingleChildScrollView(
                  controller: scroll,
                  child: inline.PaginationView<String>(
                    bind: page,
                    scrollController: scroll,
                    slot: (data, status) => TextButton(
                      onPressed: () => selected.value = !selected.value,
                      child: Text(selected.value ? '已选张三' : '选择张三'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择张三'));
      await tester.pump();
      expect(find.text('已选张三'), findsOneWidget);
    },
  );

  test('region rejects missing, repeated, invalid and collinear points', () {
    expect(isValidFenceArea([]), isFalse);
    expect(
      isValidFenceArea([
        const LatLng(1, 1),
        const LatLng(1, 1),
        const LatLng(2, 2),
      ]),
      isFalse,
    );
    expect(
      isValidFenceArea([
        const LatLng(1, 1),
        const LatLng(2, 2),
        const LatLng(3, 3),
      ]),
      isFalse,
    );
    expect(
      isValidFenceArea([
        const LatLng(1, 1),
        const LatLng(1, 2),
        const LatLng(2, 2),
      ]),
      isTrue,
    );
  });

  testWidgets('external trajectory controller survives map rebuild', (
    tester,
  ) async {
    final controller = TrajectoryPlayerController();
    addTearDown(controller.dispose);
    // Empty map avoids tiles; the externally managed controller still owns a real trajectory.
    controller.setPoints(
      List.generate(
        3,
        (i) => TrajectoryPoint(
          latitude: 37,
          longitude: 118,
          timestamp: '2026-09-06 08:0$i:00',
          dateTime: DateTime(2026, 9, 6, 8, i),
        ),
      ),
    );
    controller.seekTo(1);
    controller.toggleSpeed();
    final speed = controller.speed;
    await tester.pumpWidget(
      MaterialApp(
        home: TrajectoryPlayerView(points: [], controller: controller),
      ),
    );
    await tester.pump();
    expect(controller.currentIndex, 1);
    expect(controller.speed, speed);
    expect(controller.points, hasLength(3));
  });

  testWidgets(
    'fullscreen system back closes overlay and disposal restores portrait',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              final visible = useState(true);
              return Stack(
                children: [
                  const Scaffold(body: Text('轨迹父页')),
                  MapTrajectoryPlayer(
                    visible: visible.value,
                    onClose: () => visible.value = false,
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('轨迹父页'), findsOneWidget);
      expect(
        tester
            .widget<MapTrajectoryPlayer>(find.byType(MapTrajectoryPlayer))
            .visible,
        isFalse,
      );
      expect(
        calls
            .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
            .last
            .arguments,
        ['DeviceOrientation.portraitUp', 'DeviceOrientation.portraitDown'],
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
