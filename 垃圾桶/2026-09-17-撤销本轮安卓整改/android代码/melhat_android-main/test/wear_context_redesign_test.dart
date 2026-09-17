import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/mine_page.dart';
import 'package:rolling_intelligence_headband/wear/notifications.dart';
import 'package:rolling_intelligence_headband/wear/queries/devices.dart';
import 'package:rolling_intelligence_headband/wear/queries/person_location.dart';
import 'package:rolling_intelligence_headband/wear/queries/tracks.dart';

void main() {
  testWidgets(
    'my equipment stays personal and handovers load only on their page',
    (tester) async {
      final requested = <String>[];
      final session = _session((path) {
        requested.add(path);
        return <dynamic>[];
      });
      final notifications = WearNotifications(
        session: session,
        openEvent: (_) async {},
      );
      addTearDown(notifications.dispose);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearScope(
          session: session,
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(body: WearMinePage(notifications: notifications)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requested, isEmpty);
      expect(find.text('我的装备'), findsOneWidget);
      expect(find.text('查看全部'), findsNothing);
      await tester.tap(find.text('我的装备'));
      await tester.pumpAndSettle();
      expect(requested, ['/api/v1/me/equipment']);
      expect(find.text('暂无领用装备'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('TTS intent and wearer contact retain different target scopes', (
    tester,
  ) async {
    final session = _session(
      (path) => path.endsWith('/assignments')
          ? []
          : {
              'id': '42',
              'sn': 'BELT-42',
              'typeCode': 'belt',
              'currentAssignment': {'personId': '7', 'personName': '值班人员'},
              'capabilities': {
                'actions': ['tts'],
              },
            },
    );
    addTearDown(session.dispose);
    Uri? destination;
    final router = GoRouter(
      initialLocation: '/devices/42',
      routes: [
        GoRoute(
          path: '/devices/:id',
          builder: (_, state) => DevicePage(id: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/communications',
          builder: (_, state) {
            destination = state.uri;
            return Scaffold(body: Text(state.uri.toString()));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      WearScope(
        session: session,
        child: MaterialApp.router(
          theme: ThemeData.dark(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('文字播报'));
    await tester.tap(find.text('文字播报'));
    await tester.pumpAndSettle();
    expect(destination!.queryParameters['intent'], 'tts');
    expect(destination!.queryParameters['deviceId'], '42');
    router.pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('联系持有人'));
    await tester.tap(find.text('联系持有人'));
    await tester.pumpAndSettle();
    expect(destination!.queryParameters, {'personId': '7'});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unknown floor remains unknown across theme changes without refetch',
    (tester) async {
      var requests = 0;
      final session = _session((path) {
        expect(path, '/api/v1/locations/people/7');
        requests++;
        return {
          'personId': '7',
          'source': 'none',
          'floor': null,
          'floorSource': 'unknown',
          'locationQuality': 'unknown',
        };
      });
      addTearDown(session.dispose);
      final brightness = ValueNotifier(Brightness.dark);
      addTearDown(brightness.dispose);
      await tester.pumpWidget(
        WearScope(
          session: session,
          child: ValueListenableBuilder(
            valueListenable: brightness,
            builder: (context, value, _) => MaterialApp(
              theme: ThemeData(brightness: value),
              home: const Scaffold(
                body: SingleChildScrollView(
                  child: PersonLocationPanel(personId: '7'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('楼层未知'), findsOneWidget);
      expect(find.text('区域未知'), findsOneWidget);
      brightness.value = Brightness.light;
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('楼层未知'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'person track loading and empty results do not index a missing point',
    (tester) async {
      final session = _session((path) {
        if (path == '/api/v1/people/7') {
          return {'id': '7', 'name': '值班人员', 'personCode': 'P7'};
        }
        expect(path, '/api/v1/locations/people/7/tracks');
        return {'records': [], 'total': 0, 'current': 1, 'size': 100};
      });
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearScope(
          session: session,
          child: MaterialApp(home: const TracksPage(personId: '7')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('该时段没有轨迹点'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

WearSession _session(Object? Function(String) data) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {'code': 200, 'data': data(options.path)},
          ),
        );
      },
    ),
  );
  return WearSession(dio: dio, credentials: _MemoryCredentials())
    ..token = 'token'
    ..siteId = '1'
    ..me = {
      'userId': '7',
      'userName': '值班人员',
      'authorizedSites': [
        {'id': '1', 'name': '一号厂站'},
      ],
    };
}

class _MemoryCredentials implements CredentialStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String? token) async {}
}
