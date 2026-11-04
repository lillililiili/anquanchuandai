import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/api.dart';
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
        featureStates: {
          'voice': {'supported': true, 'verified': true, 'available': true},
          'video': {'supported': true, 'verified': true, 'available': true},
          'broadcast': {'supported': true, 'verified': true, 'available': true},
        },
      ),
    );
  });

  tearDown(() => controller.dispose());

  test(
    'late start after identity change cleans exact session with captured actor',
    () async {
      final reply = Completer<StartedCall>();
      gateway.startResult = reply.future;
      final started = controller.startCall();
      await Future<void>.delayed(Duration.zero);
      expect(gateway.startCount, 1);
      await controller.terminate();
      gateway.cleanupActor = 'new-account';
      reply.complete(
        StartedCall(gateway.call(status: 'offered'), gateway.credentials()),
      );
      await started;
      expect(gateway.endedIds, ['17']);
      expect(gateway.endedActors, ['original-account']);
      expect(rtc.joinCount, 0);
    },
  );

  test(
    'restored unknown is observable and explicit end only, without media',
    () async {
      gateway.ownedCalls = [gateway.call(status: 'unknown')];
      expect(await controller.recoverOwnedCalls(), isTrue);
      expect(controller.activeCall?.id, '17');
      expect(controller.isRecoveredSession, isTrue);
      expect(rtc.prepareCount, 0);
      expect(gateway.credentialsCount, 0);
      expect(gateway.endedIds, isEmpty);
      await controller.startCall();
      expect(gateway.startCount, 0);
      await controller.hangUp();
      expect(gateway.endedIds, ['17']);
    },
  );

  test(
    'leaving restored connected record never ends another client session',
    () async {
      gateway.ownedCalls = [gateway.call(status: 'connected')];
      await controller.recoverOwnedCalls();
      expect(controller.isConnected, isFalse);
      await controller.terminate();
      expect(gateway.endedIds, isEmpty);
      expect(rtc.prepareCount, 0);
    },
  );

  test(
    'public idempotent results do not request credentials, join, or auto end',
    () async {
      for (final status in [
        'unknown',
        'connected',
        'ending',
        'ended',
        'failed',
      ]) {
        final local = CommunicationsController(
          gateway: gateway,
          rtc: rtc,
          userId: '4',
          permissions: const {'wear:call:start'},
        );
        local.selectDevice(controller.selectedDevice);
        gateway.startResult = Future.value(
          StartedCall(gateway.call(status: status), null),
        );
        await local.startCall();
        expect(local.activeCall?.status.name, status);
        expect(local.isConnected, isFalse);
        await local.terminate();
      }
      expect(gateway.credentialsCount, 0);
      expect(gateway.endedIds, isEmpty);
      expect(rtc.joinCount, 0);
    },
  );

  test('known busy recovers record without retrying or joining', () async {
    gateway.startError = const WearApiException(
      409,
      '设备忙线',
      errorCode: 'CALL_BUSY',
    );
    gateway.onStart = () =>
        gateway.ownedCalls = [gateway.call(status: 'unknown')];
    await controller.startCall();
    expect(gateway.startCount, 1);
    expect(controller.activeCall?.id, '17');
    expect(controller.isRecoveredSession, isTrue);
    expect(controller.hasLocalSession, isFalse);
    expect(controller.statusMessage, isNot(contains('呼叫结果未确认')));
    expect(gateway.endedIds, isEmpty);
    expect(gateway.credentialsCount, 0);
    await controller.terminate();
    expect(gateway.endedIds, isEmpty);
  });

  test(
    'failed active-record read blocks dial before permission request',
    () async {
      gateway.ownedError = const WearApiException(503, '暂不可用');
      await controller.startCall();
      expect(gateway.startCount, 0);
      expect(rtc.prepareCount, 0);
      expect(controller.recoveryError, contains('未结束通话读取失败'));
    },
  );

  test(
    'late recovery cannot replace newer recovery or survive dispose',
    () async {
      final first = Completer<List<CallSession>>();
      final second = Completer<List<CallSession>>();
      gateway.ownedResult = first.future;
      final old = controller.recoverOwnedCalls();
      gateway.ownedResult = second.future;
      final latest = controller.recoverOwnedCalls();
      second.complete([gateway.call(status: 'answered')]);
      await latest;
      first.complete([gateway.call(status: 'unknown')]);
      await old;
      expect(controller.activeCall?.status, WearCallStatus.answered);
      await controller.terminate();
      expect(gateway.endedIds, isEmpty);
    },
  );

  test(
    'local voice SDK join does not show connected until server confirms it',
    () async {
      final serverConnected = Completer<CallSession>();
      gateway.joinResult = serverConnected.future;
      final start = controller.startCall();

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
    expect(controller.statusMessage, contains('请允许麦克风权限后重试'));
    expect(gateway.joinedUid, isNull);
    expect(gateway.endedIds, ['17']);
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
      expect(gateway.endedIds, ['17']);
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
      expect(gateway.endedIds, ['17']);
      expect(controller.activeCall!.status, WearCallStatus.ended);
    },
  );

  test(
    'microphone denial and timeout are resolved before any server dial',
    () async {
      rtc.prepareError = const RtcPermissionDenied(video: false);
      await controller.startCall();
      expect(gateway.startCount, 0);
      expect(gateway.endedIds, isEmpty);
      expect(controller.statusMessage, contains('麦克风权限'));
      rtc.prepareError = const RtcJoinFailure('麦克风准备超时，未发起呼叫');
      await controller.startCall();
      expect(gateway.startCount, 0);
      expect(controller.statusMessage, contains('准备超时'));
    },
  );

  test(
    'cancellation during microphone preparation prevents late dial',
    () async {
      final ready = Completer<void>();
      rtc.prepareResult = ready.future;
      final starting = controller.startCall();
      await Future<void>.delayed(Duration.zero);
      expect(controller.rtcPhase, WearRtcPhase.preparing);
      expect(gateway.startCount, 0);
      await controller.cancelPreparation();
      ready.complete();
      await starting;
      expect(gateway.startCount, 0);
      expect(controller.busy, isFalse);
      expect(controller.statusMessage, contains('未发起呼叫'));
    },
  );

  test(
    'lost dial response is unconfirmed and never guesses another session to end',
    () async {
      gateway.startError = StateError('response lost');
      await controller.startCall();
      expect(gateway.startCount, 1);
      expect(gateway.endedIds, isEmpty);
      expect(controller.statusMessage, contains('呼叫结果未确认'));
      expect(controller.activeCall, isNull);
      expect(rtc.leaveCount, 1);
    },
  );

  test(
    'failure ends only its created session; failed cleanup stays unconfirmed and retryable',
    () async {
      rtc.joinError = const RtcJoinFailure('媒体连接失败');
      gateway.endError = StateError('network unavailable');
      await controller.startCall();
      expect(gateway.endedIds, ['17']);
      expect(controller.statusMessage, contains('结束结果未确认'));
      expect(controller.activeCall!.isTerminal, isFalse);
      expect(controller.hasActiveOwnedSession, isTrue);
      gateway.endError = null;
      await controller.hangUp();
      expect(gateway.endedIds, ['17', '17']);
      expect(controller.activeCall!.isTerminal, isTrue);
    },
  );

  test(
    'termination and late RTC failure do not issue two end requests',
    () async {
      final starting = controller.startCall();
      await rtc.joinStarted.future;
      rtc.emitLocalJoined();
      await starting;
      rtc.emitFailure('网络中断');
      await controller.terminate();
      await Future<void>.delayed(Duration.zero);
      expect(gateway.endedIds, ['17']);
    },
  );

  test(
    'accepted ending remains pending and can be explicitly retried',
    () async {
      rtc.joinError = const RtcJoinFailure('媒体连接失败');
      gateway.endResult = gateway.call(status: 'ending');
      await controller.startCall();
      expect(controller.statusMessage, contains('正在确认设备挂断'));
      expect(controller.hasActiveOwnedSession, isTrue);
      gateway.endResult = gateway.call(status: 'ended');
      await controller.hangUp();
      expect(gateway.endedIds, ['17', '17']);
      expect(controller.activeCall!.isTerminal, isTrue);
    },
  );

  test(
    'local media release failure cannot prevent ending the owned cloud call',
    () async {
      final starting = controller.startCall();
      await rtc.joinStarted.future;
      rtc.emitLocalJoined();
      await starting;
      rtc.leaveError = StateError('driver release failed');
      await controller.hangUp();
      expect(gateway.endedIds, ['17']);
      expect(controller.activeCall!.isTerminal, isTrue);
    },
  );

  test(
    'SIP registration, answered, confirmation and media never substitute for server connected',
    () async {
      gateway.protocol = 'SIP';
      gateway.serverConnected = false;
      gateway.joinResult = Future.value(gateway.call(status: 'answered'));
      final starting = controller.startCall();
      await rtc.joinStarted.future;
      rtc.callbacks!.onRegistered!();
      expect(controller.sipRegistered, isTrue);
      expect(controller.isConnected, isFalse);
      rtc.emitRemoteJoined(1);
      expect(controller.isConnected, isFalse);
      rtc.emitLocalJoined();
      await starting;
      expect(controller.activeCall!.status, WearCallStatus.answered);
      expect(controller.isConnected, isFalse);
      expect(controller.activeStatusLabel, contains('等待双方接通'));
      gateway.detailResult = gateway.call(status: 'connected');
      await controller.refreshActiveCall();
      expect(controller.isConnected, isFalse);
      gateway.serverConnected = true;
      gateway.detailResult = gateway.call(status: 'connected');
      await controller.refreshActiveCall();
      expect(controller.isConnected, isTrue);
      expect(controller.activeStatusLabel, '语音连接已建立');
      expect(controller.statusMessage, contains('双向声音需现场确认'));
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

      expect(controller.ttsMessage, '已发送，等待设备回执');
      expect(gateway.ttsKeys[0], gateway.ttsKeys[1]);
      gateway.ttsResult = const [TtsCommand(id:'88',deviceId:'9',status:TtsCommandStatus.queued)];
      await controller.sendTts(eventId:'31');
      expect(gateway.ttsKeys[2],gateway.ttsKeys[0]);
      expect(controller.ttsMessage,contains('等待设备所在节点发送'));
      expect(controller.ttsText, '请立即撤离');
    },
  );
}

class FakeCommunicationsGateway
    implements CommunicationsGateway, CallCleanupGateway {
  String cleanupActor = 'original-account';
  final List<String> endedActors = [];
  @override
  Future<CallSession> Function() Function(String) captureCallCleanup() {
    final actor = cleanupActor;
    return (id) => () {
      endedActors.add(actor);
      return endCall(id);
    };
  }

  List<CallSession> ownedCalls = [];
  Future<List<CallSession>>? ownedResult;
  Object? ownedError;
  @override
  Future<List<CallSession>> ownedActiveCalls() async {
    if (ownedError != null) throw ownedError!;
    return ownedResult == null ? ownedCalls : await ownedResult!;
  }

  bool demo = false;
  String protocol = 'AGORA';
  bool serverConnected = false;
  Object? endError;
  Object? startError;
  void Function()? onStart;
  final endedIds = <String>[];
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
  final ttsKeys = <String>[];
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
        'protocol': protocol,
        'serverConnected': serverConnected,
        'version': version,
      });

  RtcCredentials credentials() => RtcCredentials(
    appId: demo ? 'demo' : 'prod-app',
    channelName: 'wear-17',
    uid: 4007,
    token: demo ? 'demo-token' : 'initial-secret',
    demo: demo,
    video: false,
    protocol: protocol,
    server: 'wss://test.invalid',
    uri: 'sip:operator@test.invalid',
    target: 'sip:test@test.invalid',
    authorizationUsername: 'test',
    authorizationPassword: 'test',
    expiresAt: DateTime.now().add(const Duration(minutes: 10)),
  );

  @override
  Future<StartedCall> startCall({
    required String deviceId,
    required String kind,
    required bool video,
    required String idempotencyKey,
    Map<String, dynamic> recipient = const {},
    String? eventId,
  }) async {
    startCount++;
    onStart?.call();
    if (startError != null) throw startError!;
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
  Future<CallSession> endCall(String callId) async {
    endedIds.add(callId);
    if (endError != null) throw endError!;
    return endResult ?? call(status: 'ended');
  }

  @override
  Future<List<TtsCommand>> sendTts({
    required List<String> deviceIds,
    required String text,
    required String idempotencyKey,
    List<Map<String, dynamic>> recipients = const [],
    String? eventId,
  }) async {
    ttsKeys.add(idempotencyKey);
    lastTtsDeviceIds = deviceIds;
    lastTtsEventId = eventId;
    if (ttsError != null) throw ttsError!;
    return ttsResult;
  }
}

class FakeRtcEngine implements WearRtcEngine, WearRtcPreparation {
  final joinStarted = Completer<void>();
  RtcCallbacks? callbacks;
  Object? joinError;
  int joinCount = 0;
  int prepareCount = 0;
  int leaveCount = 0;
  int disposeCount = 0;
  String? renewedToken;
  Future<void>? prepareResult;
  Object? prepareError;
  Object? leaveError;
  @override
  Future<void> prepare({required bool video}) async {
    prepareCount++;
    if (prepareError != null) throw prepareError!;
    await prepareResult;
  }

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
  Future<void> leave() async {
    leaveCount++;
    if (leaveError != null) throw leaveError!;
  }

  @override
  Future<void> setMicrophoneMuted(bool muted) async {}

  @override
  Future<void> dispose() async => disposeCount++;
}
