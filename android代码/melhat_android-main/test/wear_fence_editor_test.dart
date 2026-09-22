import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/fence_editor.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  testWidgets('map clicks form a polygon; edit preserves backend rule fields', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    JsonMap? saved;
    var tiles = 0;
    final session =
        WearSession(
            credentials: MemoryCredentials(),
            dio: transport((r) {
              if (r.path.contains('/map-tiles/')) {
                expect(r.path, startsWith('/api/v1/fences/map-tiles/'));
                expect(r.headers['X-Site-Id'], '1');
                tiles++;
                return reply(
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
                );
              }
              if (r.method == 'PUT') {
                saved = Map<String, dynamic>.from(r.data);
                return reply(saved);
              }
              if (r.path == '/api/v1/fences/9')
                return reply({
                  'name': '测试围栏',
                  'version': 7,
                  'enabled': false,
                  'applyMode': 'persons',
                  'personIds': ['2'],
                  'timeStart': '08:00',
                  'timeEnd': '17:00',
                  'enterEnabled': true,
                  'leaveEnabled': false,
                  'debounceSeconds': 90,
                  'polygon': [
                    {'lat': 31.0, 'lng': 121.0},
                    {'lat': 31.001, 'lng': 121.0},
                    {'lat': 31.001, 'lng': 121.001},
                  ],
                });
              return reply({
                'records': [
                  {'id': '2', 'name': '人员', 'personCode': 'P2'},
                ],
                'total': 1,
                'current': 1,
                'size': 100,
              });
            }),
          )
          ..initialized = true
          ..me = identity()
          ..siteId = '1';
    addTearDown(session.dispose);
    await tester.pumpWidget(
      WearScope(
        session: session,
        child: MaterialApp(home: const FenceEditorPage(id: '9')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('地图圈地 · 3 个顶点'), findsOneWidget);
    expect(tiles, greaterThan(0));
    final map = tester.getRect(find.byType(FlutterMap));
    await tester.tapAt(map.center + const Offset(50, 60));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('地图圈地 · 4 个顶点'), findsOneWidget);
    await tester.ensureVisible(find.text('撤销'));
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.text('地图圈地 · 3 个顶点'), findsOneWidget);
    final button = find.widgetWithText(FilledButton, '保存围栏');
    await tester.dragUntilVisible(
      button,
      find.byType(Scrollable).first,
      const Offset(0, -350),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(saved?['version'], 7);
    expect(saved?['enabled'], false);
    expect(saved?['personIds'], ['2']);
    expect(saved?['polygon'], hasLength(3));
    expect(saved?['debounceSeconds'], 90);
    expect(saved?['timeStart'], '08:00');
    expect(saved?['leaveEnabled'], false);
    expect(tester.takeException(), isNull);
  });
}
