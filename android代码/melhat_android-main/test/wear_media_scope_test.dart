import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/helmet_media.dart';
import 'wear_session_test.dart' show MemoryCredentials;

Widget panel(
  WearSession session, {
  String id = 'h',
  int version = 1,
  bool recording = false,
}) => WearScope(
  session: session,
  child: MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: HelmetMediaPanel(
          deviceId: id,
          device: {
            'equipmentContext': {
              'personId': 'P1',
              'assignmentId': 'A1',
              'assignmentVersion': version,
            },
            'featureStates': {
              recording ? 'recording' : 'video': {
                'supported': true,
                'verified': true,
                'available': true,
              },
            },
          },
        ),
      ),
    ),
  ),
);

JsonMap history([List<JsonMap> items = const []]) => {
  'status': 'ready',
  'items': items,
  'commands': [],
};

void main() {
  testWidgets('old live rejection cannot release a newly started viewer', (
    tester,
  ) async {
    final gate = Completer<void>();
    final requests = <RequestOptions>[];
    var liveCount = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, handler) async {
          requests.add(r);
          final oldPoll = r.path.endsWith('/live') && ++liveCount == 2;
          if (oldPoll) await gate.future;
          handler.resolve(
            Response(
              requestOptions: r,
              statusCode: oldPoll ? 403 : 200,
              data: oldPoll
                  ? {'code': 403, 'message': 'Old viewer ended'}
                  : r.method == 'POST'
                  ? {'status': 'sent'}
                  : r.path.endsWith('/live')
                  ? <String, dynamic>{}
                  : history(),
            ),
          );
        },
      ),
    );
    final session =
        WearSession(dio: dio, mock: false, credentials: MemoryCredentials())
          ..token = 'test-token'
          ..siteId = 's';
    addTearDown(session.dispose);
    await tester.pumpWidget(panel(session));
    await tester.pumpAndSettle();
    await tester.tap(find.text('实时观看'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(liveCount, 2);
    await tester.tap(find.text('停止观看'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('实时观看'));
    await tester.pumpAndSettle();
    final starts = requests
        .where((r) => r.method == 'POST' && r.data['action'] == 'start_video')
        .toList();
    expect(starts, hasLength(2));
    gate.complete();
    await tester.pumpAndSettle();
    expect(
      requests.where(
        (r) => r.method == 'POST' && r.data['action'] == 'stop_video',
      ),
      hasLength(1),
    );
    expect(find.text('Old viewer ended'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(
      requests
          .lastWhere((r) => r.path.endsWith('/live'))
          .queryParameters['viewerSessionId'],
      starts.last.data['viewerSessionId'],
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'late old viewer acknowledgement releases only its original viewer',
    (tester) async {
      final gate = Completer<void>();
      final requests = <RequestOptions>[];
      String? originalViewer;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, handler) async {
            requests.add(r);
            if (r.method == 'POST' &&
                r.data['action'] == 'start_video' &&
                originalViewer == null) {
              originalViewer = r.data['viewerSessionId'] as String;
              await gate.future;
            }
            handler.resolve(
              Response(
                requestOptions: r,
                statusCode: 200,
                data: r.method == 'POST'
                    ? {'status': 'sent'}
                    : r.path.endsWith('/live')
                    ? <String, dynamic>{}
                    : history(),
              ),
            );
          },
        ),
      );
      final session =
          WearSession(dio: dio, mock: false, credentials: MemoryCredentials())
            ..token = 'test-original-token'
            ..siteId = 's';
      addTearDown(session.dispose);
      await tester.pumpWidget(panel(session));
      await tester.pumpAndSettle();
      await tester.tap(find.text('实时观看'));
      await tester.pumpAndSettle();
      expect(originalViewer, isNotNull);
      session.token = 'test-new-token';
      await tester.pumpWidget(panel(session, version: 2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('实时观看'));
      await tester.pumpAndSettle();
      final newStart = requests.lastWhere(
        (r) => r.method == 'POST' && r.data['action'] == 'start_video',
      );
      expect(newStart.data['viewerSessionId'], isNot(originalViewer));
      gate.complete();
      await tester.pumpAndSettle();
      final releases = requests
          .where((r) => r.method == 'POST' && r.data['action'] == 'stop_video')
          .toList();
      expect(releases, hasLength(2));
      for (final release in releases) {
        expect(release.data['viewerSessionId'], originalViewer);
        expect(release.data['assignmentVersion'], 1);
        expect(release.headers['X-Wearable-Token'], 'test-original-token');
      }
      expect(
        releases[0].data['idempotencyKey'],
        isNot(releases[1].data['idempotencyKey']),
      );
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      final live = requests.lastWhere((r) => r.path.endsWith('/live'));
      expect(
        live.queryParameters['viewerSessionId'],
        newStart.data['viewerSessionId'],
      );
      expect(live.queryParameters['assignmentVersion'], 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('forbidden history clears cached file links', (tester) async {
    var allowed = true;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, handler) {
          handler.resolve(
            Response(
              requestOptions: r,
              statusCode: allowed ? 200 : 403,
              data: allowed
                  ? history([
                      {
                        'id': 'asset-1',
                        'name': '原授权资料',
                        'kind': 'photo',
                        'url': 'https://example.invalid/photo.jpg',
                      },
                    ])
                  : {'code': 403, 'message': '当前账号无资料访问权限'},
            ),
          );
        },
      ),
    );
    final session =
        WearSession(dio: dio, mock: false, credentials: MemoryCredentials())
          ..token = 'test-token'
          ..siteId = 's';
    addTearDown(session.dispose);
    await tester.pumpWidget(panel(session));
    await tester.pumpAndSettle();
    expect(find.text('原授权资料'), findsOneWidget);
    allowed = false;
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('原授权资料'), findsNothing);
    expect(find.textContaining('当前账号无资料访问权限'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'late recording reply cannot become another devices stop handle',
    (tester) async {
      final gate = Completer<void>();
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, handler) async {
            requests.add(r);
            if (r.method == 'POST') await gate.future;
            handler.resolve(
              Response(
                requestOptions: r,
                statusCode: 200,
                data: r.method == 'POST'
                    ? {'id': 'old-recording', 'status': 'sent'}
                    : history(),
              ),
            );
          },
        ),
      );
      final session =
          WearSession(dio: dio, mock: false, credentials: MemoryCredentials())
            ..token = 'test-token'
            ..siteId = 's';
      addTearDown(session.dispose);
      await tester.pumpWidget(panel(session, id: 'h1', recording: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始录像'));
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.method == 'POST'), hasLength(1));
      await tester.pumpWidget(panel(session, id: 'h2', recording: true));
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();
      final stop = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('停止录像'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(stop.onPressed, isNull);
      expect(requests.where((r) => r.method == 'POST'), hasLength(1));
      expect(
        requests.singleWhere((r) => r.method == 'POST').path,
        contains('/devices/h1/'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
