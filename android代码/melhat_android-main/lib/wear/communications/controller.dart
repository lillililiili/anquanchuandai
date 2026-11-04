import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../api.dart' show WearApiException;
import 'models.dart';
import 'policy.dart';
import 'rtc_engine.dart';

abstract interface class CommunicationsGateway {
  Future<List<CallSession>> ownedActiveCalls();
  Future<StartedCall> startCall({
    required String deviceId,
    required String kind,
    required bool video,
    required String idempotencyKey,
    Map<String, dynamic> recipient = const {},
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
    List<Map<String, dynamic>> recipients = const [],
    String? eventId,
  });
}

enum WearRtcPhase { idle, preparing, joining, localJoined, demo, failed }

abstract interface class CallCleanupGateway {
  Future<CallSession> Function() Function(String) captureCallCleanup();
}

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
  List<CallSession> recoveredCalls = const [];
  bool recoveringCalls = false;
  String recoveryError = '';
  int _recoveryGeneration = 0;
  final Set<String> _localSessionIds = {};
  final Map<String, Future<CallSession> Function()> _cleanupCalls = {};
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
  bool sipRegistered = false;
  String rtcProtocol = '';
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
  final Map<String, Future<CallSession>> _endRequests = {};
  bool _notifierDisposed = false;

  bool get isConnected =>
      _foreground &&
      _serverStateFresh &&
      _rtcActive &&
      rtcPhase == WearRtcPhase.localJoined &&
      remotePresent &&
      (!isSip || activeCall?.serverConnected == true) &&
      activeCall?.isConnected == true;

  String get activeStatusLabel {
    final call = activeCall;
    if (call == null) return statusMessage;
    if (isRecoveredSession) return call.statusLabel;
    if (call.demo || call.isTerminal || call.status == WearCallStatus.ending) {
      return call.statusLabel;
    }
    if (rtcPhase == WearRtcPhase.failed) return '本端连接失败';
    if (isConnected) return '语音连接已建立';
    if (call.status == WearCallStatus.answered ||
        call.status == WearCallStatus.connected) {
      return '设备已应答，等待双方接通';
    }
    return call.statusLabel;
  }

  bool get isSip => rtcProtocol == 'SIP' || activeCall?.protocol == 'SIP';
  bool get isRecoveredSession =>
      activeCall != null && !_localSessionIds.contains(activeCall!.id);
  bool get hasLocalSession =>
      _sessionOperationPending ||
      (activeCall != null && !isRecoveredSession && !activeCall!.isTerminal);

  bool get hasActiveOwnedSession =>
      _sessionOperationPending ||
      recoveredCalls.any(
        (call) =>
            call.id != activeCall?.id && policy.owns(call) && !call.isTerminal,
      ) ||
      (activeCall != null &&
          policy.owns(activeCall!) &&
          !activeCall!.isTerminal);

  void selectDevice(CommunicationDevice? device) {
    if (_disposed) return;
    selectedDevice = device;
    _notify();
  }

  /// Restore server records without acquiring media or taking over another end.
  Future<bool> recoverOwnedCalls() async {
    if (_disposed || !policy.canStartCalls) return true;
    final generation = ++_recoveryGeneration;
    final operation = _operationGeneration;
    recoveringCalls = true;
    recoveryError = '';
    _notify();
    try {
      final rows =
          (await gateway.ownedActiveCalls())
              .where((call) => policy.owns(call) && !call.isTerminal)
              .toList()
            ..sort(
              (a, b) => (b.startedAt ?? DateTime(1970)).compareTo(
                a.startedAt ?? DateTime(1970),
              ),
            );
      if (_disposed ||
          generation != _recoveryGeneration ||
          operation != _operationGeneration) {
        return false;
      }
      recoveredCalls = rows;
      final current = activeCall;
      if (!_sessionOperationPending &&
          (current == null || current.isTerminal || isRecoveredSession)) {
        final matching = rows.where((call) => call.id == current?.id);
        final target = rows.where(
          (call) => call.deviceId == selectedDevice?.id,
        );
        final next =
            matching.firstOrNull ?? target.firstOrNull ?? rows.firstOrNull;
        if (next != null) {
          observeCall(next);
        } else if (current != null && !current.isTerminal) {
          // Absence from a list is not proof of termination.
          await refreshActiveCall();
        }
      }
      return true;
    } catch (error) {
      if (!_disposed && generation == _recoveryGeneration) {
        recoveryError = _errorMessage(error, '未结束通话读取失败，请刷新后再呼叫');
      }
      return false;
    } finally {
      if (!_disposed && generation == _recoveryGeneration) {
        recoveringCalls = false;
        _notify();
      }
    }
  }

  void observeCall(CallSession call) {
    if (_disposed ||
        busy ||
        _sessionOperationPending ||
        !policy.owns(call) ||
        call.isTerminal ||
        (activeCall != null &&
            !activeCall!.isTerminal &&
            !isRecoveredSession)) {
      return;
    }
    _replaceActiveCall(call, fresh: true);
    rtcPhase = WearRtcPhase.idle;
    rtcProtocol = call.protocol;
    statusMessage = '已恢复未结束记录；本端未加入，请刷新状态或明确结束原通话';
    _schedulePolling();
    _notify();
  }

  Future<void> startCall({
    bool video = false,
    String? eventId,
    String kind = 'single',
  }) async {
    if (recoveringCalls) return;
    if (_sessionOperationPending || busy || hasActiveOwnedSession) {
      statusMessage = '请先结束当前通话';
      _notify();
      return;
    }

    if (!await recoverOwnedCalls() || _disposed) return;
    if (hasActiveOwnedSession) {
      statusMessage = '存在未结束通话，请先核实或明确结束原通话';
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
      statusMessage = !policy.canStartCalls
          ? '当前账号无通话权限'
          : device.feature(video ? 'video_call' : 'intercom').reason;
      _notify();
      return;
    }

    if (activeCall?.isTerminal == true) {
      activeCall = null;
      ++_callGeneration;
    }
    final operation = _beginSessionOperation('正在准备麦克风…');
    // Capture before awaiting the request: an expiry can precede a late reply.
    final captureCleanup = gateway is CallCleanupGateway
        ? (gateway as CallCleanupGateway).captureCallCleanup()
        : null;
    CallSession? created;
    bool dialRequested = false;
    try {
      rtcPhase = WearRtcPhase.preparing;
      final engine = rtc;
      if (engine is WearRtcPreparation) {
        await (engine as WearRtcPreparation).prepare(video: video);
      }
      if (!_acceptsOperation(operation)) return;
      rtcPhase = WearRtcPhase.idle;
      statusMessage = '麦克风已准备，正在创建通话…';
      _notify();
      dialRequested = true;
      final started = await gateway.startCall(
        deviceId: device.id,
        recipient: device.equipmentContext,
        eventId: eventId,
        kind: kind,
        video: video,
        idempotencyKey: _idempotencyKey('call'),
      );
      created = started.session;
      if (started.session.demo ||
          (started.credentials != null && policy.canJoin(started.session))) {
        _localSessionIds.add(created.id);
        if (captureCleanup != null) {
          _cleanupCalls[created.id] = captureCleanup(created.id);
        }
      }
      if (!_acceptsOperation(operation)) {
        await _endDetachedCall(started.session);
        return;
      }
      _replaceActiveCall(started.session, fresh: true);
      _schedulePolling();
      if (started.session.demo || started.credentials?.demo == true) {
        await rtc.leave();
        rtcPhase = WearRtcPhase.demo;
        statusMessage = '演示会话已建立，未连接真实设备';
        return;
      }
      if (!policy.canJoin(started.session) || started.credentials == null) {
        await _releaseRtc();
        rtcPhase = WearRtcPhase.idle;
        statusMessage = started.session.isTerminal
            ? '原请求${started.session.statusLabel}，未再次拨号'
            : '原请求${started.session.statusLabel}；未加入，请刷新状态或明确结束原通话';
        return;
      }
      final credentials = started.credentials!;
      await _join(operation, started.session, credentials);
      if (!_acceptsCallOperation(operation, started.session.id)) return;
    } on RtcOperationCancelled {
      if (_acceptsOperation(operation)) {
        await _failSession(operation, '通话加入已取消', call: created);
      }
    } on RtcPermissionDenied catch (error) {
      if (!_acceptsOperation(operation)) return;
      await _failSession(
        operation,
        error.video ? '请允许麦克风和摄像头权限后重试' : '请允许麦克风权限后重试',
        call: created,
      );
    } catch (error) {
      if (!_acceptsOperation(operation)) return;
      final known =
          error is WearApiException &&
          const {
            'CALL_BUSY',
            'DEVICE_OFFLINE',
            'SIP_NOT_REGISTERED',
            'MEDIA_SERVICE_UNAVAILABLE',
            'INVALID_CALL',
          }.contains(error.errorCode);
      await _failSession(
        operation,
        _errorMessage(
          error,
          known
              ? '未发起新通话'
              : dialRequested && created == null
              ? '呼叫结果未确认，请在通话记录中核实'
              : '通话建立失败',
        ),
        call: created,
      );
      if (created == null && dialRequested) await recoverOwnedCalls();
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
    final captureCleanup = gateway is CallCleanupGateway
        ? (gateway as CallCleanupGateway).captureCallCleanup()
        : null;
    _replaceActiveCall(session, fresh: true);
    _schedulePolling();
    try {
      rtcPhase = WearRtcPhase.preparing;
      statusMessage = '正在准备麦克风…';
      _notify();
      final engine = rtc;
      if (engine is WearRtcPreparation) {
        await (engine as WearRtcPreparation).prepare(video: session.video);
      }
      if (!_acceptsCallOperation(operation, session.id)) return;
      final credentials = await gateway.credentialsFor(session.id);
      if (!_acceptsCallOperation(operation, session.id)) return;
      _localSessionIds.add(session.id);
      if (captureCleanup != null) {
        _cleanupCalls[session.id] = captureCleanup(session.id);
      }
      await _join(operation, session, credentials);
      if (!_acceptsCallOperation(operation, session.id)) return;
    } on RtcOperationCancelled {
      if (_acceptsOperation(operation)) {
        await _failSession(operation, '通话加入已取消', call: session);
      }
    } on RtcPermissionDenied catch (error) {
      if (!_acceptsOperation(operation)) return;
      await _failSession(
        operation,
        error.video ? '请允许麦克风和摄像头权限后重试' : '请允许麦克风权限后重试',
        call: session,
      );
    } catch (error) {
      if (!_acceptsOperation(operation)) return;
      await _failSession(
        operation,
        _errorMessage(error, '加入通话失败'),
        call: session,
      );
    } finally {
      _finishSessionOperation(operation);
    }
  }

  int _beginSessionOperation(String message) {
    final operation = ++_operationGeneration;
    _sessionOperationPending = true;
    busy = true;
    _serverStateFresh = false;
    sipRegistered = false;
    rtcProtocol = '';
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
    rtcProtocol = credentials.protocol;
    statusMessage = isSip ? '正在注册语音服务…' : '正在加入 RTC 频道…';
    final outcome = Completer<void>();
    _joinOutcome = outcome;
    _joinOutcomeOperation = operation;
    _notify();
    await rtc.join(
      credentials,
      RtcCallbacks(
        onRegistered: () {
          if (!_acceptsCallOperation(operation, session.id)) return;
          sipRegistered = true;
          statusMessage = '语音服务已注册，等待本端会话确认…';
          _notify();
        },
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
    statusMessage = isSip ? '本端信令已确认，等待设备与媒体连接…' : '本端已加入，等待服务器确认…';
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
      await _failSession(
        operation,
        _errorMessage(error, '服务器未确认加入'),
        call: activeCall,
      );
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
    unawaited(_failSession(operation, message, call: activeCall));
  }

  Future<CallSession> _endOwnedCall(CallSession call) {
    if (!policy.owns(call)) throw const RtcJoinFailure('不能结束其他账号的通话');
    final existing = _endRequests[call.id];
    if (existing != null) return existing;
    late final Future<CallSession> request;
    request = (_cleanupCalls[call.id]?.call() ?? gateway.endCall(call.id)).then(
      (result) {
        if (result.isTerminal) _cleanupCalls.remove(call.id);
        if (!result.isTerminal && identical(_endRequests[call.id], request)) {
          _endRequests.remove(call.id);
        }
        return result;
      },
      onError: (Object error) {
        if (identical(_endRequests[call.id], request)) {
          _endRequests.remove(call.id);
        }
        throw error;
      },
    );
    _endRequests[call.id] = request;
    return request;
  }

  Future<void> _endDetachedCall(CallSession call) async {
    if (!policy.owns(call) ||
        call.isTerminal ||
        !_localSessionIds.contains(call.id)) {
      return;
    }
    try {
      await _endOwnedCall(call);
    } catch (_) {
      statusMessage = '本次通话结束结果未确认，请在通话记录中核实';
    } finally {
      if (_disposed) _cleanupCalls.remove(call.id);
    }
  }

  Future<void> _failSession(
    int operation,
    String message, {
    CallSession? call,
  }) async {
    if (!_acceptsOperation(operation)) return;
    final cleanupOperation = ++_operationGeneration;
    ++_callGeneration;
    ++_pollRequestGeneration;
    _pollTimer?.cancel();
    _completeAnyJoin();
    _sessionOperationPending = true;
    busy = true;
    rtcPhase = WearRtcPhase.failed;
    statusMessage = message;
    _notify();
    try {
      try {
        await _releaseRtc();
      } catch (_) {
        /* Still end this exact server session. */
      }
      if (call != null &&
          policy.owns(call) &&
          !call.isTerminal &&
          _localSessionIds.contains(call.id)) {
        try {
          final ended = await _endOwnedCall(call);
          if (!_acceptsOperation(cleanupOperation)) return;
          if (activeCall?.id == call.id) {
            activeCall = ended;
            _serverStateFresh = true;
          }
          statusMessage = ended.isTerminal
              ? '$message；本次通话已结束'
              : '$message；正在确认设备挂断';
        } catch (_) {
          if (!_acceptsOperation(cleanupOperation)) return;
          _serverStateFresh = false;
          statusMessage = '$message；结束结果未确认，请重试结束通话';
        }
      }
    } finally {
      if (_acceptsOperation(cleanupOperation)) {
        _sessionOperationPending = false;
        busy = false;
        _schedulePolling();
        _notify();
      }
    }
  }

  Future<void> cancelPreparation() async {
    if (_disposed || rtcPhase != WearRtcPhase.preparing) return;
    if (activeCall != null && !activeCall!.isTerminal) {
      await _failSession(_operationGeneration, '已取消加入', call: activeCall);
      return;
    }
    _cancelInteractiveOperation();
    rtcPhase = WearRtcPhase.idle;
    statusMessage = '已取消麦克风准备，未发起呼叫';
    await _releaseRtc();
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
      try {
        await _releaseRtc();
      } catch (_) {
        /* Server cleanup must still run. */
      }
      if (!_acceptsOperation(operation) || activeCall?.id != call.id) return;
      final ended = await _endOwnedCall(call);
      if (!_acceptsOperation(operation) || activeCall?.id != call.id) return;
      activeCall = ended;
      if (ended.isTerminal) {
        recoveredCalls = recoveredCalls.where((r) => r.id != ended.id).toList();
      }
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

  String? _ttsIntent, _ttsRequestKey;
  Future<void> sendTts({String? eventId}) async {
    final device = selectedDevice;
    final text = ttsText.trim();
    if (device == null || !policy.canSendTts(device)) {
      ttsMessage = device == null
          ? '请先选择人员装备'
          : !policy.canSubmitTts
          ? '当前账号无播报权限'
          : device.feature('tts').reason;
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
    final intent = '$text|${device.id}|${device.equipmentContext}|$eventId';
    if (_ttsIntent != intent) { _ttsIntent = intent; _ttsRequestKey = _idempotencyKey('tts'); }
    final operation = _operationGeneration;
    _notify();
    try {
      final commands = await gateway.sendTts(
        deviceIds: [device.id],
        recipients: [
          {...device.equipmentContext, 'deviceId': device.id},
        ],
        text: text,
        eventId: eventId,
        idempotencyKey: _ttsRequestKey!,
      );
      if (_disposed || operation != _operationGeneration) return;
      final failed = commands.any(
        (item) => item.status == TtsCommandStatus.failed,
      );
      ttsMessage = failed ? '指令提交失败，请查看设备结果' : commands.map((item) => item.status.label).toSet().join('；');
      if (commands.isNotEmpty && commands.every((item) => !item.status.unresolved)) { _ttsIntent = null; _ttsRequestKey = null; }
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
    if (next.isTerminal) {
      recoveredCalls = recoveredCalls.where((r) => r.id != next.id).toList();
    }
    return true;
  }

  int _statusRank(WearCallStatus status) => switch (status) {
    WearCallStatus.unknown => -1,
    WearCallStatus.requesting => 0,
    WearCallStatus.offered => 1,
    WearCallStatus.answered => 2,
    WearCallStatus.connected => 3,
    WearCallStatus.ending => 4,
    WearCallStatus.ended ||
    WearCallStatus.failed ||
    WearCallStatus.timedOut => 5,
  };

  void _syncConnectionMessage() {
    final call = activeCall;
    if (call == null) return;
    if (isRecoveredSession && !call.isTerminal) {
      statusMessage = '${call.statusLabel}；本端未加入，可刷新或明确结束原通话';
      return;
    }
    if (call.demo) {
      statusMessage = call.statusLabel;
    } else if (call.status == WearCallStatus.answered) {
      if (rtcPhase != WearRtcPhase.failed) statusMessage = '设备已应答，等待本端与双方媒体接通…';
    } else if (call.status == WearCallStatus.connected) {
      if (rtcPhase == WearRtcPhase.failed) return;
      statusMessage = isSip && !call.serverConnected
          ? '设备连接结果尚待服务端确认'
          : !_rtcActive || rtcPhase != WearRtcPhase.localJoined
          ? '服务器已确认，RTC 尚未就绪'
          : remotePresent
          ? isSip
                ? '语音连接已建立，双向声音需现场确认'
                : '已接通'
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
    sipRegistered = false;
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
    final call = activeCall;
    final future = () async {
      try {
        await rtc.dispose();
      } catch (_) {
        statusMessage = '本端媒体释放结果未确认';
      }
      if (call != null) await _endDetachedCall(call);
      _cleanupCalls.clear();
    }();
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
