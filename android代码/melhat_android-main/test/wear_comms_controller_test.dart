import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/communications/controller.dart';
import 'package:rolling_intelligence_headband/wear/communications/models.dart';
import 'package:rolling_intelligence_headband/wear/communications/rtc_engine.dart';

void main() {
  late FakeCommunicationsGateway gateway;
  late FakeRtcEngine rtc;
  late CommunicationsController controller;

  setUp(() {
    gateway = FakeCommunicationsGateway();
    rtc = FakeRtcEngine();
    controller = CommunicationsController(
      gateway: gateway,
      rtc: rtc,
      userId: '4',
      permissions: const {'wear:call:start', 'wear:command:tts'},
    );
    controller.selectDevice(
      const CommunicationDevice(
        id: '9',
        sn: 'MH-009',
        personId: '21',
        personName: '张三',
        actions: {'tts', 'intercom', 'video'},
      ),
    );
  });

  tearDown(() => controller.dispose());

  test(
    'local SDK join does not show connected until server confirms it',
    () async {
      final serverConnected = Completer<CallSession>();
      gateway.joinResult = serverConnected.future;
      final start = controller.startCall(video: true);

      await rtc.joinStarted.future;
      rtc.emitLocalJoined();
      await Future<void>.delayed(Duration.zero);

      expect(controller.rtcPhase, WearRtcPhase.localJoined);
      expect(controller.activeCall!.status, WearCallStatus.offered);
      expect(controller.isConnected, isFalse);
      expect(gateway.joinedUid, '4007');

      serverConnected.complete(gateway.call(status: 'connected'));
      await start;

      expect(controller.activeCall!.status, WearCallStatus.connected);
      expect(controller.isConnected, isFalse);
      rtc.emitRemoteJoined(91);
      expect(controller.isConnected, isTrue);
    },
  );

  test(
    'demo credentials never initialize Agora and remain visibly demo',
    () async {
      gateway.demo = true;

      await controller.startCall();

      expect(rtc.joinCount, 0);
      expect(gateway.joinedUid, isNull);
      expect(controller.rtcPhase, WearRtcPhase.demo);
      expect(controller.isConnected, isFalse);
      expect(controller.statusMessage, contains('演示'));
    },
  );

  test('an owned nonterminal session blocks a second explicit call', () async {
    gateway.demo = true;
    await controller.startCall();
    expect(controller.hasActiveOwnedSession, isTrue);

    await controller.startCall();

    expect(gateway.startCount, 1);
    expect(controller.statusMessage, '请先结束当前通话');
  });

  test('permission failure is shown and does not mark server joined', () async {
    rtc.joinError = const RtcPermissionDenied(video: false);

    await controller.startCall();

    expect(controller.rtcPhase, WearRtcPhase.failed);
    expect(controller.statusMessage, '请允许麦克风权限后重试');
    expect(gateway.joinedUid, isNull);
  });

  test('server timeout wins over SDK state and releases the engine', () async {
    gateway.joinResult = Future.value(gateway.call(status: 'connected'));
    final start = controller.startCall();
    await rtc.joinStarted.future;
    rtc.emitLocalJoined();
    await start;
    gateway.detailResult = gateway.call(status: 'timed_out');

    await controller.refreshActiveCall();

    expect(controller.activeCall!.status, WearCallStatus.timedOut);
    expect(controller.isConnected, isFalse);
    expect(rtc.leaveCount, 1);
  });

  test(
    'server timeout also unblocks a pending local join confirmation',
    () async {
      gateway.joinResult = Completer<CallSession>().future;
      final start = controller.startCall();
      await rtc.joinStarted.future;
      rtc.emitLocalJoined();
      await Future<void>.delayed(Duration.zero);
      gateway.detailResult = gateway.call(status: 'timed_out');

      await controller.refreshActiveCall();

      await expectLater(
        start.timeout(const Duration(milliseconds: 100)),
        completes,
      );
      expect(controller.busy, isFalse);
    },
  );

  test(
    'expiring token is refreshed in memory and renewed in the engine',
    () async {
      gateway.joinResult = Future.value(gateway.call(status: 'connected'));
      final start = controller.startCall();
      await rtc.joinStarted.future;
      rtc.emitLocalJoined();
      await start;
      gateway.refreshedCredentials = const RtcCredentials(
        appId: 'prod-app',
        channelName: 'wear-17',
        uid: 4007,
        token: 'renewed-secret',
        video: false,
      );

      rtc.emitTokenExpiring();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(rtc.renewedToken, 'renewed-secret');
      expect(controller.rtcPhase, WearRtcPhase.localJoined);
    },
  );

  test(
    'background and resume calibration do not present stale connected state',
    () async {
      gateway.joinResult = Future.value(gateway.call(status: 'connected'));
      final start = controller.startCall();
      await rtc.joinStarted.future;
      rtc.emitLocalJoined();
      await start;
      rtc.emitRemoteJoined(91);
      expect(controller.isConnected, isTrue);

      controller.setForeground(false);
      expect(controller.isConnected, isFalse);

      controller.setForeground(true);
      expect(controller.isConnected, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(controller.isConnected, isTrue);
    },
  );

  test(
    'pending start blocks scope changes and cannot open RTC after dispose',
    () async {
      final delayedStart = Completer<StartedCall>();
      gateway.startResult = delayedStart.future;

      final start = controller.startCall();
      await Future<void>.delayed(Duration.zero);
      expect(controller.hasActiveOwnedSession, isTrue);

      controller.dispose();
      delayedStart.complete(
        StartedCall(gateway.call(status: 'offered'), gateway.credentials()),
      );
      await start;

      expect(rtc.joinCount, 0);
      expect(rtc.disposeCount, 1);
    },
  );

  test(
    'resume blocks duplicate credentials and replacement attempts',
    () async {
      final credentials = Completer<RtcCredentials>();
      gateway.credentialsResult = credentials.future;
      final offered = gateway.call(status: 'offered');

      final first = controller.resumeCall(offered);
      await Future<void>.delayed(Duration.zero);
      final second = controller.resumeCall(offered);
      await second;

      expect(controller.hasActiveOwnedSession, isTrue);
      expect(gateway.credentialsCount, 1);
      expect(controller.statusMessage, '请先结束当前通话');

      controller.dispose();
      credentials.complete(gateway.credentials());
      await first;
      expect(rtc.joinCount, 0);
    },
  );

  test('late poll cannot regress an ended call after hangup', () async {
    gateway.joinResult = Future.value(
      gateway.call(status: 'connected', version: 2),
    );
    final start = controller.startCall();
    await rtc.joinStarted.future;
    rtc.emitLocalJoined();
    await start;
    rtc.emitRemoteJoined(91);

    final oldPoll = Completer<CallSession>();
    gateway.detailFuture = oldPoll.future;
    final refresh = controller.refreshActiveCall();
    gateway.endResult = gateway.call(status: 'ended', version: 3);
    await controller.hangUp();
    oldPoll.complete(gateway.call(status: 'offered', version: 1));
    await refresh;

    expect(controller.activeCall!.status, WearCallStatus.ended);
    expect(controller.activeCall!.version, 3);
  });

  test('slow poll is single flight and eventually accepts ended', () async {
    gateway.demo = true;
    await controller.startCall();
    final slow = Completer<CallSession>();
    gateway.detailFuture = slow.future;

    final first = controller.refreshActiveCall();
    final repeatedTick = controller.refreshActiveCall();
    await Future<void>.delayed(Duration.zero);

    expect(gateway.detailCount, 1);
    slow.complete(gateway.call(status: 'ended', version: 2));
    await Future.wait([first, repeatedTick]);

    expect(controller.activeCall!.status, WearCallStatus.ended);
    expect(controller.hasActiveOwnedSession, isFalse);
  });

  test(
    'HTTP refresh failure invalidates freshness and transport failure is retained',
    () async {
      gateway.joinResult = Future.value(gateway.call(status: 'connected'));
      final start = controller.startCall();
      await rtc.joinStarted.future;
      rtc.emitLocalJoined();
      await start;
      rtc.emitRemoteJoined(91);
      expect(controller.isConnected, isTrue);

      gateway.detailError = StateError('poll failed');
      await controller.refreshActiveCall();
      expect(controller.isConnected, isFalse);

      gateway.detailError = null;
      rtc.emitFailure('RTC 传输已断开');
      await Future<void>.delayed(Duration.zero);
      await controller.refreshActiveCall();
      expect(controller.isConnected, isFalse);
      expect(controller.statusMessage, 'RTC 传输已断开');
    },
  );

  test(
    'TTS uses exact body semantics, retains text on failure, and never claims heard',
    () async {
      controller.ttsText = '请立即撤离';
      gateway.ttsError = StateError('network down');

      await controller.sendTts(eventId: '31');

      expect(controller.ttsText, '请立即撤离');
      expect(gateway.lastTtsDeviceIds, ['9']);
      expect(gateway.lastTtsEventId, '31');
      expect(controller.ttsMessage, contains('提交失败'));

      gateway.ttsError = null;
      gateway.ttsResult = const [
        TtsCommand(id: '88', deviceId: '9', status: TtsCommandStatus.sent),
      ];
      await controller.sendTts(eventId: '31');

      expect(controller.ttsMessage, '指令已提交（不代表现场已听到）');
      expect(controller.ttsText, '请立即撤离');
    },
  );
}

class FakeCommunicationsGateway implements CommunicationsGateway {
  bool demo = false;
  int startCount = 0;
  int credentialsCount = 0;
  int detailCount = 0;
  Future<StartedCall>? startResult;
  Future<CallSession>? joinResult;
  Future<RtcCredentials>? credentialsResult;
  Future<CallSession>? detailFuture;
  CallSession? detailResult;
  CallSession? endResult;
  Object? detailError;
  RtcCredentials? refreshedCredentials;
  String? joinedUid;
  Object? ttsError;
  List<TtsCommand> ttsResult = const [];
  List<String>? lastTtsDeviceIds;
  String? lastTtsEventId;

  CallSession call({required String status, int version = 1}) =>
      CallSession.fromJson({
        'id': '17',
        'kind': 'single',
        'status': status,
        'deviceId': '9',
        'personId': '21',
        'requesterUserId': '4',
        'video': false,
        'demo': demo,
        'version': version,
      });

  RtcCredentials credentials() => RtcCredentials(
    appId: demo ? 'demo' : 'prod-app',
    channelName: 'wear-17',
    uid: 4007,
    token: demo ? 'demo-token' : 'initial-secret',
    demo: demo,
    video: false,
  );

  @override
  Future<StartedCall> startCall({
    required String deviceId,
    required String kind,
    required bool video,
    required String idempotencyKey,
    String? eventId,
  }) async {
    startCount++;
    if (startResult != null) return await startResult!;
    return StartedCall(call(status: 'offered'), credentials());
  }

  @override
  Future<CallSession> markJoined(String callId, String uid) {
    joinedUid = uid;
    return joinResult ?? Future.value(call(status: 'connected'));
  }

  @override
  Future<CallSession> callDetails(String callId) async {
    detailCount++;
    if (detailError != null) throw detailError!;
    if (detailFuture != null) return await detailFuture!;
    return detailResult ?? call(status: 'connected');
  }

  @override
  Future<RtcCredentials> credentialsFor(String callId) async {
    credentialsCount++;
    if (credentialsResult != null) return await credentialsResult!;
    return refreshedCredentials ?? credentials();
  }

  @override
  Future<CallSession> endCall(String callId) async =>
      endResult ?? call(status: 'ended');

  @override
  Future<List<TtsCommand>> sendTts({
    required List<String> deviceIds,
    required String text,
    required String idempotencyKey,
    String? eventId,
  }) async {
    lastTtsDeviceIds = deviceIds;
    lastTtsEventId = eventId;
    if (ttsError != null) throw ttsError!;
    return ttsResult;
  }
}

class FakeRtcEngine implements WearRtcEngine {
  final joinStarted = Completer<void>();
  RtcCallbacks? callbacks;
  Object? joinError;
  int joinCount = 0;
  int leaveCount = 0;
  int disposeCount = 0;
  String? renewedToken;

  @override
  Future<void> join(RtcCredentials credentials, RtcCallbacks callbacks) async {
    joinCount++;
    this.callbacks = callbacks;
    if (!joinStarted.isCompleted) joinStarted.complete();
    if (joinError != null) throw joinError!;
  }

  void emitLocalJoined() => callbacks!.onLocalJoined();
  void emitRemoteJoined(int uid) => callbacks!.onRemoteJoined(uid);
  void emitTokenExpiring() => callbacks!.onTokenExpiring();
  void emitFailure(String message) => callbacks!.onFailure(message);

  @override
  Future<void> renewToken(String token) async => renewedToken = token;

  @override
  Future<void> leave() async => leaveCount++;

  @override
  Future<void> setMicrophoneMuted(bool muted) async {}

  @override
  Future<void> dispose() async => disposeCount++;
}
