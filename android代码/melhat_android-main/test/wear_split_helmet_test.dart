import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:rolling_intelligence_headband/wear/api.dart';
import 'package:rolling_intelligence_headband/wear/communications/controller.dart';
import 'package:rolling_intelligence_headband/wear/communications/models.dart';
import 'package:rolling_intelligence_headband/wear/communications/rtc_engine.dart';
import 'package:rolling_intelligence_headband/wear/communications/zlm_rtc_engine.dart';
import 'package:rolling_intelligence_headband/wear/communications/media_preparation.dart';
import 'package:rolling_intelligence_headband/wear/communications/prepared_rtc_media.dart';
import 'package:rolling_intelligence_headband/wear/queries/split_helmet_live.dart';
import 'package:rolling_intelligence_headband/wear/queries/split_helmet_telemetry.dart';
import 'package:rolling_intelligence_headband/wear/core.dart'
    show WearSession, WearScope;
import 'package:rolling_intelligence_headband/wear/queries/helmet_media.dart';
import 'wear_session_test.dart' show MemoryCredentials;
import 'wear_comms_controller_test.dart'
    show FakeCommunicationsGateway, FakeRtcEngine;

Map<String, dynamic> credentialsJson(int count) => {
  'protocol': 'ZLM_WEBRTC',
  'channel': 'session-1',
  'video': true,
  'expiresAt': DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
  'heartbeatUrl': '/api/guardian/v1/split/sessions/session-1/heartbeat',
  'sessions': List.generate(
    count,
    (i) => {
      'deviceId': 'helmet-$i',
      'playUrl': '/api/guardian/v1/split/sessions/session-1/devices/SN$i/play',
      'talkUrl': '/api/guardian/v1/split/sessions/session-1/devices/SN$i/talk',
    },
  ),
};

CommunicationDevice helmet(int index, {String source = 'SPLIT_HELMET'}) =>
    CommunicationDevice(
      id: 'helmet-$index',
      sn: 'SN$index',
      personId: 'person-$index',
      typeCode: 'helmet',
      source: source,
      online: 'online',
      actions: const {'intercom', 'video'},
      equipmentContext: {
        'deviceId': 'helmet-$index',
        'personId': 'person-$index',
        'assignmentId': 'assignment-$index',
        'assignmentVersion': 1,
      },
      featureStates: const {
        'voice': {
          'supported': true,
          'verified': false,
          'integrationStatus': 'CONNECTED',
          'available': true,
        },
        'videoCall': {
          'supported': true,
          'verified': false,
          'integrationStatus': 'CONNECTED',
          'available': true,
        },
      },
    );

void main() {
  testWidgets(
    'monitor opens only the microphone on its existing session and releases it independently',
    (tester) async {
      final api = _HeartbeatApi(), mic = _Media();
      final permissions = <bool>[];
      var allowed = false;
      _Peer? talk;
      const talkUrl =
          '/api/guardian/v1/split/sessions/monitor-1/devices/SN1/talk';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SplitMonitorMicrophone(
              api: api,
              talkUrl: talkUrl,
              preparation: RtcMediaPreparation<MediaStream>(
                requestPermission: (video) async {
                  permissions.add(video);
                  return allowed;
                },
                acquire: (_) async => mic,
                release: releaseWearMedia,
              ),
              peerFactory: (ready, failed) =>
                  talk = _Peer(api, (_) {}, ready, failed),
            ),
          ),
        ),
      );
      expect(permissions, isEmpty);
      await tester.tap(find.text('开启对讲'));
      await tester.pumpAndSettle();
      expect(talk, isNull);
      expect(find.textContaining('麦克风权限'), findsOneWidget);
      allowed = true;
      await tester.tap(find.text('开启对讲'));
      await tester.pumpAndSettle();
      expect(permissions, [false, false]);
      expect(talk!.talkUrl, talkUrl);
      expect(talk!.microphone, same(mic));
      expect(find.text('关闭麦克风'), findsNothing);
      talk!.onReady();
      await tester.pump();
      expect(find.text('麦克风已开启'), findsOneWidget);
      await tester.tap(find.text('关闭麦克风'));
      await tester.pumpAndSettle();
      expect(talk!.closed, isTrue);
      expect(mic.stops, 1);
      expect(mic.disposals, 1);
      expect(api.heartbeats, 0);
      await tester.tap(find.text('开启对讲'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(talk!.closed, isTrue);
      expect(mic.disposals, 2);
    },
  );
  testWidgets('split lease renews at sixty seconds and stops after release', (
    tester,
  ) async {
    final api = _HeartbeatApi();
    late _Peer peer;
    final engine = ZlmWearRtcEngine(
      api,
      (_) {},
      peerFactory: (a, s, r, f) {
        peer = _Peer(a, s, r, f);
        return peer;
      },
    )..usePreparedMedia(_Media());
    await engine.join(
      RtcCredentials.fromJson(credentialsJson(1)),
      RtcCallbacks(
        onLocalJoined: () {},
        onRemoteJoined: (_) {},
        onRemoteLeft: (_) {},
        onTokenExpiring: () {},
        onFailure: (_) {},
      ),
    );
    peer.onReady();
    await tester.pump(const Duration(seconds: 59));
    expect(api.heartbeats, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(api.heartbeats, 1);
    await engine.leave();
    await tester.pump(const Duration(seconds: 120));
    expect(api.heartbeats, 1);
  });
  testWidgets(
    'split recording submits duration, watermark and the exact stop task',
    (tester) async {
      final writes = <Map<String, dynamic>>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://backend.invalid'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            if (r.method == 'POST') {
              writes.add(Map<String, dynamic>.from(r.data));
            }
            h.resolve(
              Response(
                requestOptions: r,
                statusCode: 200,
                data: r.method == 'POST'
                    ? {
                        'id': 'task-1',
                        'status': 'sent',
                        'message': '已发送，设备结果待确认',
                      }
                    : {'status': 'ready', 'items': [], 'commands': []},
              ),
            );
          },
        ),
      );
      final session =
          WearSession(dio: dio, mock: false, credentials: MemoryCredentials())
            ..token = 'x'
            ..siteId = 's';
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearScope(
          session: session,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: HelmetMediaPanel(
                  deviceId: 'SN',
                  device: {
                    'source': 'SPLIT_HELMET',
                    'equipmentContext': {
                      'personId': 'P1',
                      'assignmentId': 'A1',
                      'assignmentVersion': 1,
                    },
                    'featureStates': {
                      'recording': {
                        'supported': true,
                        'integrationStatus': 'CONNECTED',
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
      await tester.enterText(find.byType(TextField).first, '0');
      await tester.tap(find.text('开始设备录像'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      await tester.enterText(find.byType(TextField).first, '60');
      await tester.enterText(find.byType(TextField).last, '现场');
      await tester.tap(find.text('开始设备录像'));
      await tester.pumpAndSettle();
      expect(writes.single['parameters'], {
        'durationSeconds': 60,
        'watermark': '现场',
      });
      expect(find.textContaining('设备结果待确认'), findsOneWidget);
      await tester.tap(find.text('停止设备录像'));
      await tester.pumpAndSettle();
      expect(writes.last['parameters']['commandId'], 'task-1');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('split credentials cap eight and bind every signal to the session', () {
    expect(RtcCredentials.fromJson(credentialsJson(8)).isUsable, isTrue);
    expect(RtcCredentials.fromJson(credentialsJson(9)).isUsable, isFalse);
    final foreign = credentialsJson(1);
    (foreign['sessions'] as List).first['talkUrl'] =
        'https://foreign.invalid/talk';
    expect(RtcCredentials.fromJson(foreign).isUsable, isFalse);
    final mixed = credentialsJson(1);
    (mixed['sessions'] as List).first['playUrl'] =
        '/api/guardian/v1/split/sessions/other/devices/SN0/play';
    expect(RtcCredentials.fromJson(mixed).isUsable, isFalse);
  });
  test(
    'SDP is raw and authenticated; redirects, foreign paths and stale replies fail',
    () async {
      var epoch = 1;
      final dio = Dio(BaseOptions(baseUrl: 'https://backend.invalid/wear-api'));
      var status = 200;
      var changeScope = false;
      var requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            requests++;
            expect(r.headers['X-Wearable-Token'], 'session-token');
            expect(r.contentType, 'application/sdp');
            expect(r.followRedirects, isFalse);
            expect(r.data, startsWith('v=0'));
            if (changeScope) epoch++;
            h.resolve(
              Response(
                requestOptions: r,
                statusCode: status,
                data: 'v=0\r\nanswer',
              ),
            );
          },
        ),
      );
      final api = WearApi(
        dio: dio,
        mock: false,
        token: () => 'session-token',
        siteId: () => 'site',
        epoch: () => epoch,
      );
      const path = '/api/guardian/v1/split/sessions/s/devices/SN/play';
      expect(await api.postSdp(path, 'v=0\r\noffer'), startsWith('v=0'));
      await expectLater(
        api.postSdp('https://foreign.invalid$path', 'v=0'),
        throwsA(isA<WearApiException>()),
      );
      expect(requests, 1);
      status = 302;
      await expectLater(
        api.postSdp(path, 'v=0'),
        throwsA(isA<WearApiException>()),
      );
      status = 200;
      changeScope = true;
      await expectLater(
        api.postSdp(path, 'v=0'),
        throwsA(isA<StaleSessionException>()),
      );
      final private = api.mediaResource(
        '/api/guardian/v1/split/devices/SN/files/asset',
      )!;
      expect(
        private.url,
        'https://backend.invalid/wear-api/api/guardian/v1/split/devices/SN/files/asset',
      );
      expect(private.headers['X-Wearable-Token'], 'session-token');
      expect(api.mediaResource('https://cdn.invalid/file')!.headers, isEmpty);
      expect(api.mediaResource('//foreign.invalid/file'), isNull);
    },
  );
  test(
    'TF zero remains a reported zero; missing values never become measurements',
    () {
      expect(splitTelemetryValue({}, 'pressure'), '未收到');
      expect(
        splitTelemetryValue({
          'storageUsed': 0,
          'storageUsedReportedAt': '2026-01-01',
          'storageUsedFreshness': 'STALE',
        }, 'storageUsed'),
        '0（历史上报）',
      );
      expect(splitTelemetryValue({'pressure': 0}, 'pressure'), '未收到');
    },
  );
  test(
    'group requires every selected helmet and never requests the phone camera',
    () async {
      final gateway = _BatchGateway(), rtc = _PreparedEngine();
      final controller = CommunicationsController(
        gateway: gateway,
        rtc: rtc,
        userId: '4',
        permissions: {'wear:call:start'},
      );
      controller.selectDevice(helmet(0));
      await controller.startCall(
        video: true,
        targets: List.generate(9, helmet),
        kind: 'group',
      );
      expect(gateway.batches, 0);
      expect(rtc.prepareCount, 0);
      await controller.startCall(
        targets: [
          helmet(0),
          helmet(1, source: 'DIRECT_HELMET'),
        ],
        kind: 'group',
      );
      expect(gateway.batches, 0);
      final joining = controller.startCall(
        video: true,
        targets: List.generate(2, helmet),
        kind: 'group',
      );
      await rtc.joinStarted.future;
      expect(rtc.cameraRequested, isFalse);
      expect(gateway.batches, 1);
      rtc.emitLocalJoined();
      rtc.emitRemoteJoined(1);
      await joining;
      await controller.terminate();
      controller.dispose();
    },
  );
  test(
    'group only reports connected after every peer and releases shared microphone once',
    () async {
      final api = WearApi(
        mock: false,
        token: () => 'x',
        siteId: () => 's',
        epoch: () => 1,
      );
      final peers = <_Peer>[];
      final mic = _Media();
      var local = 0, remote = 0;
      final engine = ZlmWearRtcEngine(
        api,
        (_) {},
        peerFactory: (a, s, ready, failed) {
          final peer = _Peer(a, s, ready, failed);
          peers.add(peer);
          return peer;
        },
      )..usePreparedMedia(mic);
      await engine.join(
        RtcCredentials.fromJson(credentialsJson(2)),
        RtcCallbacks(
          onLocalJoined: () => local++,
          onRemoteJoined: (_) => remote++,
          onRemoteLeft: (_) {},
          onTokenExpiring: () {},
          onFailure: (_) {},
        ),
      );
      expect(peers.length, 2);
      expect(peers.every((p) => identical(p.microphone, mic)), isTrue);
      peers.first.onReady();
      expect(local, 0);
      peers.last.onReady();
      expect(local, 1);
      expect(remote, 1);
      await engine.leave();
      await engine.dispose();
      expect(mic.stops, 1);
      expect(mic.disposals, 1);
      expect(peers.every((p) => p.closed), isTrue);
      peers.first.onReady();
      expect(local, 1);
    },
  );
}

class _BatchGateway extends FakeCommunicationsGateway
    implements BatchCommunicationsGateway {
  int batches = 0;
  @override
  Future<StartedCall> startBatchCall({
    required List<CommunicationDevice> devices,
    required String kind,
    required bool video,
    required String idempotencyKey,
    String? eventId,
  }) async {
    batches++;
    return StartedCall(
      call(status: 'offered'),
      RtcCredentials.fromJson(credentialsJson(devices.length)),
    );
  }
}

class _PreparedEngine extends FakeRtcEngine {
  bool? cameraRequested;
  @override
  Future<void> prepare({required bool video}) async {
    cameraRequested = video;
    await super.prepare(video: video);
  }
}

class _Peer extends ZlmPeer {
  _Peer(
    WearApi a,
    void Function(MediaStream?) s,
    void Function() r,
    void Function(String) f,
  ) : super(api: a, onStream: s, onReady: r, onFailure: f);
  MediaStream? microphone;
  String? talkUrl;
  bool closed = false;
  @override
  Future<void> openMicrophone(String path, MediaStream mic) async {
    talkUrl = path;
    microphone = mic;
  }

  @override
  Future<void> open({
    required String playUrl,
    String? talkUrl,
    MediaStream? microphone,
    bool video = true,
    List<Map<String, dynamic>> iceServers = const [],
  }) async {
    this.microphone = microphone;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class _Media extends Fake implements MediaStream {
  int stops = 0, disposals = 0;
  @override
  List<MediaStreamTrack> getAudioTracks() => getTracks();
  @override
  List<MediaStreamTrack> getTracks() => [_Track(() => stops++)];
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class _Track extends Fake implements MediaStreamTrack {
  _Track(this.onStop);
  final void Function() onStop;
  @override
  bool enabled = true;
  @override
  Future<void> stop() async {
    onStop();
  }
}

class _HeartbeatApi extends WearApi {
  _HeartbeatApi()
    : super(mock: false, token: () => 'x', siteId: () => 's', epoch: () => 1);
  int heartbeats = 0;
  @override
  Future<dynamic> post(String path, {Object? data}) async {
    heartbeats++;
    return <String, dynamic>{};
  }
}
