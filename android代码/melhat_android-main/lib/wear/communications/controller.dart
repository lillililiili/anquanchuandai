import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'policy.dart';
import 'rtc_engine.dart';

abstract interface class CommunicationsGateway {
  Future<StartedCall> startCall({
    required String deviceId,
    required String kind,
    required bool video,
    required String idempotencyKey,
    String? eventId,
  });
  Future<CallSession> callDetails(String callId);
  Future<RtcCredentials> credentialsFor(String callId);
  Future<CallSession> markJoined(String callId, String uid);
  Future<CallSession> endCall(String callId);
  Future<List<TtsCommand>> sendTts({
    required List<String> deviceIds,
    required String text,
    required String idempotencyKey,
    String? eventId,
  });
}

enum WearRtcPhase { idle, joining, localJoined, demo, failed }

class CommunicationsController extends ChangeNotifier {
  CommunicationsController({
    required this.gateway,
    required this.rtc,
    required String userId,
    required Set<String> permissions,
  }) : policy = CommunicationsPolicy(userId: userId, permissions: permissions);

  final CommunicationsGateway gateway;
  final WearRtcEngine rtc;
  final CommunicationsPolicy policy;
  final Random _random = Random.secure();

  CommunicationDevice? selectedDevice;
  CallSession? activeCall;
  WearRtcPhase rtcPhase = WearRtcPhase.idle;
  String statusMessage = '';
  String ttsText = '';
  String ttsMessage = '';
  bool busy = false;
  bool ttsBusy = false;
  bool microphoneMuted = false;
  bool speakerphoneEnabled = true;
  bool _speakerBusy = false;
  bool remotePresent = false;
  int? remoteUid;

  bool _disposed = false;
  bool _foreground = true;
  bool _serverStateFresh = true;
  bool _rtcActive = false;
  bool _sessionOperationPending = false;
  bool _ending = false;
  int _operationGeneration = 0;
  int _callGeneration = 0;
  int _pollRequestGeneration = 0;
  Timer? _pollTimer;
  Future<void>? _pollInFlight;
  int? _pollInFlightCallGeneration;
  String? _pollInFlightCallId;
  Completer<void>? _joinOutcome;
  int? _joinOutcomeOperation;
  Future<void>? _termination;
  bool _notifierDisposed = false;

  bool get isConnected =>
      _foreground &&
      _serverStateFresh &&
      _rtcActive &&
      rtcPhase == WearRtcPhase.localJoined &&
      remotePresent &&
      activeCall?.isConnected == true;

  bool get hasActiveOwnedSession =>
      _sessionOperationPending ||
      (activeCall != null &&
          policy.owns(activeCall!) &&
          !activeCall!.isTerminal);

  void selectDevice(CommunicationDevice? device) {
    if (_disposed) return;
    selectedDevice = device;
    _notify();
  }

  Future<void> startCall({
    bool video = false,
    String? eventId,
    String kind = 'single',
  }) async {
    if (_sessionOperationPending || busy || hasActiveOwnedSession) {
      statusMessage = '请先结束当前通话';
      _notify();
      return;
    }
    final device = selectedDevice;
    if (device == null) {
      statusMessage = '请先选择人员装备';
      _notify();
      return;
    }
    if (video ? !policy.canStartVideo(device) : !policy.canStartVoice(device)) {
      statusMessage = video ? '该设备不支持视频通话或当前账号无权限' : '该设备不支持通话或当前账号无权限';
      _notify();
      return;
    }

    final operation = _beginSessionOperation('正在创建通话…');
    try {
      final started = await gateway.startCall(
        deviceId: device.id,
        eventId: eventId,
        kind: kind,
        video: video,
        idempotencyKey: _idempotencyKey('call'),
      );
      if (!_acceptsOperation(operation)) return;
      _replaceActiveCall(started.session, fresh: true);
      _schedulePolling();
      if (started.session.demo || started.credentials?.demo == true) {
        rtcPhase = WearRtcPhase.demo;
        statusMessage = '演示会话已建立，未连接真实设备';
        return;
      }
      if (!policy.canJoin(started.session)) {
        statusMessage = policy.owns(started.session)
            ? started.session.statusLabel
            : '仅发起人可以加入该通话';
        return;
      }
      var credentials = started.credentials;
      if (credentials == null) {
        credentials = await gateway.credentialsFor(started.session.id);
        if (!_acceptsCallOperation(operation, started.session.id)) return;
      }
      await _join(operation, started.session, credentials);
      if (!_acceptsCallOperation(operation, started.session.id)) return;
    } on RtcOperationCancelled {
      if (_acceptsOperation(operation)) {
        rtcPhase = WearRtcPhase.idle;
        statusMessage = '通话加入已取消';
      }
    } on RtcPermissionDenied catch (error) {
      if (!_acceptsOperation(operation)) return;
      rtcPhase = WearRtcPhase.failed;
      statusMessage = error.video ? '请允许麦克风和摄像头权限后重试' : '请允许麦克风权限后重试';
    } catch (error) {
      if (!_acceptsOperation(operation)) return;
      rtcPhase = WearRtcPhase.failed;
      statusMessage = _errorMessage(error, '通话建立失败');
    } finally {
      _finishSessionOperation(operation);
    }
  }

  Future<void> resumeCall(CallSession session) async {
    if (_sessionOperationPending || busy || hasActiveOwnedSession) {
      statusMessage = '请先结束当前通话';
      _notify();
      return;
    }
    if (!policy.canJoin(session)) {
      statusMessage = session.demo ? '演示会话不连接真实 RTC' : '仅发起人可加入待接通会话';
      _notify();
      return;
    }

    final operation = _beginSessionOperation('正在读取通话凭证…');
    _replaceActiveCall(session, fresh: true);
    _schedulePolling();
    try {
      final credentials = await gateway.credentialsFor(session.id);
      if (!_acceptsCallOperation(operation, session.id)) return;
      await _join(operation, session, credentials);
      if (!_acceptsCallOperation(operation, session.id)) return;
    } on RtcOperationCancelled {
      if (_acceptsOperation(operation)) {
        rtcPhase = WearRtcPhase.idle;
        statusMessage = '通话加入已取消';
      }
    } on RtcPermissionDenied catch (error) {
      if (!_acceptsOperation(operation)) return;
      rtcPhase = WearRtcPhase.failed;
      statusMessage = error.video ? '请允许麦克风和摄像头权限后重试' : '请允许麦克风权限后重试';
    } catch (error) {
      if (!_acceptsOperation(operation)) return;
      rtcPhase = WearRtcPhase.failed;
      statusMessage = _errorMessage(error, '加入通话失败');
    } finally {
      _finishSessionOperation(operation);
    }
  }

  int _beginSessionOperation(String message) {
    final operation = ++_operationGeneration;
    _sessionOperationPending = true;
    busy = true;
    _serverStateFresh = false;
    statusMessage = message;
    _notify();
    return operation;
  }

  void _finishSessionOperation(int operation) {
    if (!_acceptsOperation(operation)) return;
    _sessionOperationPending = false;
    busy = false;
    _notify();
  }

  Future<void> _join(
    int operation,
    CallSession session,
    RtcCredentials credentials,
  ) async {
    if (credentials.demo) {
      rtcPhase = WearRtcPhase.demo;
      statusMessage = '演示会话已建立，未连接真实设备';
      return;
    }
    if (!credentials.isUsable || credentials.isExpired) {
      throw const RtcJoinFailure('通话凭证无效或已过期');
    }
    if (!_acceptsCallOperation(operation, session.id)) {
      throw const RtcOperationCancelled();
    }

    rtcPhase = WearRtcPhase.joining;
    statusMessage = '正在加入 RTC 频道…';
    final outcome = Completer<void>();
    _joinOutcome = outcome;
    _joinOutcomeOperation = operation;
    _notify();
    await rtc.join(
      credentials,
      RtcCallbacks(
        onLocalJoined: () =>
            unawaited(_markLocalJoined(operation, session.id, credentials.uid)),
        onRemoteJoined: (uid) => _onRemoteJoined(operation, session.id, uid),
        onRemoteLeft: (uid) => _onRemoteLeft(operation, session.id, uid),
        onTokenExpiring: () => unawaited(_refreshToken(operation, session.id)),
        onFailure: (message) =>
            _handleRtcFailure(operation, session.id, message),
      ),
    );
    if (!_acceptsCallOperation(operation, session.id)) {
      await rtc.leave();
      throw const RtcOperationCancelled();
    }
    _rtcActive = true;
    await outcome.future;
    if (!_acceptsCallOperation(operation, session.id)) {
      throw const RtcOperationCancelled();
    }
  }

  Future<void> _markLocalJoined(int operation, String callId, int uid) async {
    if (!_acceptsCallOperation(operation, callId)) return;
    _rtcActive = true;
    rtcPhase = WearRtcPhase.localJoined;
    statusMessage = '本端已加入，等待服务器确认…';
    _notify();
    try {
      final server = await gateway.markJoined(callId, uid.toString());
      if (!_acceptsCallOperation(operation, callId)) return;
      _applyServerUpdate(server);
      _serverStateFresh = true;
      _syncConnectionMessage();
      _completeJoin(operation);
      _schedulePolling();
    } catch (error) {
      if (!_acceptsCallOperation(operation, callId)) return;
      rtcPhase = WearRtcPhase.failed;
      statusMessage = _errorMessage(error, '服务器未确认加入');
      _completeJoin(operation, error: error);
      await _releaseRtc();
      if (!_acceptsOperation(operation)) return;
    }
    _notify();
  }

  void _onRemoteJoined(int operation, String callId, int uid) {
    if (!_acceptsCallOperation(operation, callId)) return;
    remoteUid = uid;
    remotePresent = true;
    _syncConnectionMessage();
    _notify();
  }

  void _onRemoteLeft(int operation, String callId, int uid) {
    if (!_acceptsCallOperation(operation, callId)) return;
    if (remoteUid == uid) remoteUid = null;
    remotePresent = false;
    statusMessage = '设备已离开 RTC 频道';
    _notify();
  }

  Future<void> _refreshToken(int operation, String callId) async {
    final call = activeCall;
    if (!_acceptsCallOperation(operation, callId) ||
        call == null ||
        !policy.canReadCredentials(call)) {
      return;
    }
    try {
      final credentials = await gateway.credentialsFor(callId);
      if (!_acceptsCallOperation(operation, callId)) return;
      if (credentials.demo ||
          credentials.isExpired ||
          credentials.token.isEmpty) {
        throw const RtcJoinFailure('通话凭证已过期');
      }
      await rtc.renewToken(credentials.token);
      if (!_acceptsCallOperation(operation, callId)) return;
    } catch (error) {
      if (!_acceptsCallOperation(operation, callId)) return;
      rtcPhase = WearRtcPhase.failed;
      statusMessage = _errorMessage(error, '通话凭证更新失败');
      await _releaseRtc();
      if (!_acceptsOperation(operation)) return;
    }
    _notify();
  }

  void _handleRtcFailure(int operation, String callId, String message) {
    if (!_acceptsCallOperation(operation, callId)) return;
    rtcPhase = WearRtcPhase.failed;
    _rtcActive = false;
    remotePresent = false;
    remoteUid = null;
    statusMessage = message;
    _completeJoin(operation, error: RtcJoinFailure(message));
    unawaited(_releaseRtc());
    _notify();
  }

  Future<void> refreshActiveCall() {
    final current = activeCall;
    if (_disposed || current == null || current.id.isEmpty) {
      return Future<void>.value();
    }
    final callGeneration = _callGeneration;
    final existing = _pollInFlight;
    if (existing != null &&
        _pollInFlightCallGeneration == callGeneration &&
        _pollInFlightCallId == current.id) {
      return existing;
    }
    final request = ++_pollRequestGeneration;
    late final Future<void> poll;
    poll = _refreshActiveCallOnce(current, callGeneration, request)
        .whenComplete(() {
          if (identical(_pollInFlight, poll)) {
            _pollInFlight = null;
            _pollInFlightCallGeneration = null;
            _pollInFlightCallId = null;
          }
        });
    _pollInFlight = poll;
    _pollInFlightCallGeneration = callGeneration;
    _pollInFlightCallId = current.id;
    return poll;
  }

  Future<void> _refreshActiveCallOnce(
    CallSession current,
    int callGeneration,
    int request,
  ) async {
    try {
      final server = await gateway.callDetails(current.id);
      if (!_acceptsPoll(callGeneration, request, current.id)) return;
      if (!_applyServerUpdate(server)) return;
      _serverStateFresh = true;
      _syncConnectionMessage();
      if (server.isTerminal) {
        _pollTimer?.cancel();
        _cancelInteractiveOperation();
        await _releaseRtc();
        if (_disposed || activeCall?.id != current.id) return;
      }
    } catch (error) {
      if (!_acceptsPoll(callGeneration, request, current.id)) return;
      _serverStateFresh = false;
      if (rtcPhase != WearRtcPhase.failed) {
        statusMessage = _errorMessage(error, '通话状态刷新失败');
      }
    }
    _notify();
  }

  void setForeground(bool foreground) {
    if (_disposed) return;
    _foreground = foreground;
    _serverStateFresh = false;
    if (foreground) {
      statusMessage = '正在校准通话状态…';
      _schedulePolling();
      unawaited(refreshActiveCall());
    } else {
      _pollTimer?.cancel();
      if (activeCall != null && !activeCall!.isTerminal) {
        statusMessage = '应用位于后台，音视频状态待返回前台确认';
      }
    }
    _notify();
  }

  void _schedulePolling() {
    _pollTimer?.cancel();
    if (_disposed ||
        !_foreground ||
        activeCall == null ||
        activeCall!.isTerminal) {
      return;
    }
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(refreshActiveCall()),
    );
  }

  Future<void> hangUp() async {
    final call = activeCall;
    if (_disposed || _ending || call == null || !policy.canEnd(call)) return;
    _ending = true;
    busy = true;
    _sessionOperationPending = true;
    final operation = ++_operationGeneration;
    ++_callGeneration;
    ++_pollRequestGeneration;
    _pollTimer?.cancel();
    _completeAnyJoin();
    statusMessage = '正在结束通话…';
    _notify();
    try {
      await _releaseRtc();
      if (!_acceptsOperation(operation) || activeCall?.id != call.id) return;
      final ended = await gateway.endCall(call.id);
      if (!_acceptsOperation(operation) || activeCall?.id != call.id) return;
      activeCall = ended;
      _serverStateFresh = true;
      statusMessage = ended.statusLabel;
    } catch (error) {
      if (!_acceptsOperation(operation)) return;
      _serverStateFresh = false;
      statusMessage = _errorMessage(error, '结束通话失败');
      _schedulePolling();
    } finally {
      if (_acceptsOperation(operation)) {
        _sessionOperationPending = false;
        _ending = false;
        busy = false;
        _notify();
      }
    }
  }

  Future<void> toggleMicrophone() async {
    final operation = _operationGeneration;
    final callId = activeCall?.id;
    if (!_rtcActive || callId == null) return;
    final muted = !microphoneMuted;
    try {
      await rtc.setMicrophoneMuted(muted);
      if (!_acceptsCallOperation(operation, callId)) return;
      microphoneMuted = muted;
    } catch (error) {
      if (!_acceptsCallOperation(operation, callId)) return;
      statusMessage = _errorMessage(error, '麦克风切换失败');
    }
    _notify();
  }

  Future<void> toggleSpeakerphone() async {
    final operation = _operationGeneration;
    final callId = activeCall?.id;
    if (!isConnected || callId == null || _speakerBusy) return;
    final route = rtc;
    if (route is! WearRtcAudioRoute) {
      statusMessage = '当前音频引擎不支持扬声器切换';
      _notify();
      return;
    }
    final enabled = !speakerphoneEnabled;
    _speakerBusy = true;
    try {
      await (route as WearRtcAudioRoute).setSpeakerphone(enabled);
      if (!_acceptsCallOperation(operation, callId)) return;
      speakerphoneEnabled = enabled;
    } catch (error) {
      if (!_acceptsCallOperation(operation, callId)) return;
      statusMessage = _errorMessage(error, '扬声器切换失败');
    } finally {
      _speakerBusy = false;
    }
    _notify();
  }

  Future<void> sendTts({String? eventId}) async {
    final device = selectedDevice;
    final text = ttsText.trim();
    if (device == null || !policy.canSendTts(device)) {
      ttsMessage = '该设备不支持播报或当前账号无权限';
      _notify();
      return;
    }
    if (text.isEmpty) {
      ttsMessage = '请输入播报内容';
      _notify();
      return;
    }
    if (ttsBusy) return;
    ttsBusy = true;
    ttsMessage = '正在提交…';
    final operation = _operationGeneration;
    _notify();
    try {
      final commands = await gateway.sendTts(
        deviceIds: [device.id],
        text: text,
        eventId: eventId,
        idempotencyKey: _idempotencyKey('tts'),
      );
      if (_disposed || operation != _operationGeneration) return;
      final failed = commands.any(
        (item) => item.status == TtsCommandStatus.failed,
      );
      ttsMessage = failed ? '指令提交失败，请查看设备结果' : '指令已提交（不代表现场已听到）';
    } catch (error) {
      if (_disposed || operation != _operationGeneration) return;
      ttsMessage = _errorMessage(error, '指令提交失败');
    } finally {
      if (!_disposed && operation == _operationGeneration) {
        ttsBusy = false;
        _notify();
      }
    }
  }

  void _replaceActiveCall(CallSession call, {required bool fresh}) {
    activeCall = call;
    _serverStateFresh = fresh;
    ++_callGeneration;
    ++_pollRequestGeneration;
  }

  bool _applyServerUpdate(CallSession next) {
    final current = activeCall;
    if (current == null || current.id != next.id) return false;
    if (current.isTerminal && current.status != next.status) return false;
    if (current.version > 0 &&
        next.version > 0 &&
        next.version < current.version) {
      return false;
    }
    if (_statusRank(next.status) < _statusRank(current.status)) return false;
    activeCall = next;
    return true;
  }

  int _statusRank(WearCallStatus status) => switch (status) {
    WearCallStatus.unknown => -1,
    WearCallStatus.requesting => 0,
    WearCallStatus.offered => 1,
    WearCallStatus.connected => 2,
    WearCallStatus.ended ||
    WearCallStatus.failed ||
    WearCallStatus.timedOut => 3,
  };

  void _syncConnectionMessage() {
    final call = activeCall;
    if (call == null) return;
    if (call.demo) {
      statusMessage = call.statusLabel;
    } else if (call.status == WearCallStatus.connected) {
      if (rtcPhase == WearRtcPhase.failed) return;
      statusMessage = !_rtcActive || rtcPhase != WearRtcPhase.localJoined
          ? '服务器已确认，RTC 尚未就绪'
          : remotePresent
          ? '已接通'
          : '服务器已确认，等待设备加入…';
    } else {
      statusMessage = call.failReason.isNotEmpty
          ? '${call.statusLabel}：${call.failReason}'
          : call.statusLabel;
    }
  }

  bool _acceptsOperation(int operation) =>
      !_disposed && operation == _operationGeneration;

  bool _acceptsCallOperation(int operation, String callId) =>
      _acceptsOperation(operation) && activeCall?.id == callId;

  bool _acceptsPoll(int callGeneration, int request, String callId) =>
      !_disposed &&
      callGeneration == _callGeneration &&
      request == _pollRequestGeneration &&
      activeCall?.id == callId;

  void _completeJoin(int operation, {Object? error}) {
    if (_joinOutcomeOperation != operation) return;
    final outcome = _joinOutcome;
    _joinOutcome = null;
    _joinOutcomeOperation = null;
    if (outcome == null || outcome.isCompleted) return;
    if (error == null) {
      outcome.complete();
    } else {
      outcome.completeError(error);
    }
  }

  void _completeAnyJoin() {
    final outcome = _joinOutcome;
    _joinOutcome = null;
    _joinOutcomeOperation = null;
    if (outcome != null && !outcome.isCompleted) outcome.complete();
  }

  void _cancelInteractiveOperation() {
    ++_operationGeneration;
    _sessionOperationPending = false;
    busy = false;
    _completeAnyJoin();
  }

  Future<void> _releaseRtc() async {
    _rtcActive = false;
    remotePresent = false;
    remoteUid = null;
    microphoneMuted = false;
    speakerphoneEnabled = true;
    await rtc.leave();
  }

  String _idempotencyKey(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  String _errorMessage(Object error, String fallback) {
    final dynamic value = error;
    try {
      final message = value.message?.toString().trim();
      if (message != null && message.isNotEmpty) return '$fallback：$message';
    } catch (_) {}
    final text = error
        .toString()
        .replaceFirst(RegExp(r'^[A-Za-z]+(?:Exception|Error):\s*'), '')
        .trim();
    return text.isEmpty ? fallback : '$fallback：$text';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> terminate() {
    final existing = _termination;
    if (existing != null) return existing;
    _disposed = true;
    ++_operationGeneration;
    ++_callGeneration;
    ++_pollRequestGeneration;
    _pollTimer?.cancel();
    _completeAnyJoin();
    final future = rtc.dispose();
    _termination = future;
    return future;
  }

  @override
  void dispose() {
    if (_notifierDisposed) return;
    _notifierDisposed = true;
    unawaited(terminate());
    super.dispose();
  }
}
