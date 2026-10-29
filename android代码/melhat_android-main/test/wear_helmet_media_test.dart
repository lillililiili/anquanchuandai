import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/helmet_media.dart';
import 'wear_session_test.dart' show MemoryCredentials;

void main() {
  testWidgets(
    'stop recording retains the start command and original issuance after reassignment',
    (tester) async {
      final writes = <Map<String, dynamic>>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/wear-api'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            if (r.method == 'POST')
              writes.add(Map<String, dynamic>.from(r.data));
            h.resolve(
              Response(
                requestOptions: r,
                statusCode: 200,
                data: r.method == 'POST'
                    ? {'id': 'record-command-1', 'status': 'sent'}
                    : {
                        'status': 'ready',
                        'actions': ['start_recording', 'stop_recording'],
                        'items': [],
                        'commands': [],
                      },
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
      Widget panel(int version) => WearScope(
        session: session,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HelmetMediaPanel(
                deviceId: 'h',
                device: {
                  'equipmentContext': {
                    'personId': 'P1',
                    'assignmentId': 'A1',
                    'assignmentVersion': version,
                  },
                  'featureStates': {
                    'recording': {
                      'supported': true,
                      'verified': true,
                      'available': version == 1,
                    },
                  },
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(panel(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始录像'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(panel(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('停止录像'));
      await tester.pumpAndSettle();
      expect(writes.last['action'], 'stop_recording');
      expect(writes.last['sourceCommandId'], 'record-command-1');
      expect(writes.last['assignmentVersion'], 1);
      expect(writes.last['personId'], 'P1');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'history reads do not start live playback and reassignment releases the original viewer',
    (tester) async {
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/wear-api'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, handler) {
            requests.add(r);
            handler.resolve(
              Response(
                requestOptions: r,
                statusCode: 200,
                data: r.method == 'POST'
                    ? {'status': 'sent'}
                    : r.path.endsWith('/live')
                    ? <String, dynamic>{}
                    : {
                        'status': 'ready',
                        'actions': [],
                        'items': [],
                        'commands': [
                          {
                            'action': 'start_video',
                            'status': 'waiting_media',
                            'viewerSessionId': 'another-page-viewer',
                          },
                          {'action': 'stop_video', 'status': 'completed'},
                        ],
                      },
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
      Widget panel(int version) => WearScope(
        session: session,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HelmetMediaPanel(
                deviceId: 'h',
                device: {
                  'equipmentContext': {
                    'personId': 'P1',
                    'assignmentId': 'A1',
                    'assignmentVersion': version,
                  },
                  'featureStates': {
                    'video': {
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
      await tester.pumpWidget(panel(1));
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.path.endsWith('/live')), isEmpty);
      expect(find.text('停止观看 · 观看已结束'), findsOneWidget);
      expect(find.textContaining('文件已入库'), findsNothing);
      await tester.tap(find.text('实时观看'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.ancestor(
                of: find.text('实时观看'),
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNull,
      );
      final start = requests.firstWhere((r) => r.method == 'POST');
      expect(start.data['assignmentVersion'], 1);
      expect(start.data['personId'], 'P1');
      final live = requests.firstWhere((r) => r.path.endsWith('/live'));
      expect(
        live.queryParameters['viewerSessionId'],
        start.data['viewerSessionId'],
      );
      await tester.pumpWidget(panel(2));
      await tester.pumpAndSettle();
      final stop = requests.lastWhere((r) => r.method == 'POST');
      expect(stop.data['action'], 'stop_video');
      expect(stop.data['assignmentVersion'], 1);
      expect(stop.data['viewerSessionId'], start.data['viewerSessionId']);
      final count = requests.where((r) => r.path.endsWith('/live')).length;
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.path.endsWith('/live')).length, count);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'ambiguous media requests retain their key and only confirmed responses release it',
    (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ids = <String>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/wear-api'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(
              options.uri.path,
              startsWith('/wear-api/api/guardian/v1/devices/h/'),
            );
            expect(options.headers['X-Wearable-Token'], 'test-token');
            if (options.method == 'POST') {
              ids.add((options.data as Map)['idempotencyKey'] as String);
              if (ids.length == 1) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.receiveTimeout,
                  ),
                );
                return;
              }
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'status': 'completed', 'message': '文件已保存'},
                ),
              );
            } else {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'status': 'ready',
                    'actions': ['take_photo'],
                    'featureStates': {
                      'photo': {
                        'supported': true,
                        'verified': true,
                        'available': true,
                      },
                    },
                    'items': [],
                    'commands': [],
                  },
                ),
              );
            }
          },
        ),
      );
      final session =
          WearSession(dio: dio, mock: false, credentials: MemoryCredentials())
            ..token = 'test-token'
            ..siteId = 's';
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearScope(
          session: session,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: HelmetMediaPanel(
                  deviceId: 'h',
                  device: const {
                    'equipmentContext': {
                      'personId': 'P1',
                      'assignmentId': 'A1',
                      'assignmentVersion': 2,
                    },
                    'featureStates': {
                      'photo': {
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
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('拍照'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('拍照'));
      await tester.pumpAndSettle();
      expect(ids.length, 2);
      expect(ids[0], ids[1]);
      await tester.tap(find.text('拍照'));
      await tester.pumpAndSettle();
      expect(ids[2], isNot(ids[1]));
      expect(find.textContaining('已接通'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
