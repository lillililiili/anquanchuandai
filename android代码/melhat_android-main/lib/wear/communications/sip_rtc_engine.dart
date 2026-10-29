import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sip_ua/sip_ua.dart';
import 'models.dart';
import 'rtc_engine.dart';

/// Protocol selection is explicit; SIP secrets never enter persistent settings.
class ProtocolWearRtcEngine implements WearRtcEngine, WearRtcAudioRoute {
  ProtocolWearRtcEngine({
    WearRtcEngine Function()? agoraFactory,
    WearRtcEngine Function(void Function(MediaStream?))? sipFactory,
  }) : _agoraFactory = agoraFactory ?? AgoraWearRtcEngine.new,
       _sipFactory = sipFactory ?? SipWearRtcEngine.new;
  final WearRtcEngine Function() _agoraFactory;
  final WearRtcEngine Function(void Function(MediaStream?)) _sipFactory;
  WearRtcEngine? _active;
  final remoteStream = ValueNotifier<MediaStream?>(null);
  bool _disposed = false;
  int _generation = 0;
  @override
  Future<void> join(RtcCredentials c, RtcCallbacks callbacks) async {
    if (_disposed) throw const RtcOperationCancelled();
    final generation = ++_generation;
    final old = _active;
    _active = null;
    remoteStream.value = null;
    await old?.dispose();
    if (_disposed || generation != _generation) {
      throw const RtcOperationCancelled();
    }
    final WearRtcEngine? next = c.protocol == 'SIP'
        ? _sipFactory((s) {
            if (!_disposed && generation == _generation) remoteStream.value = s;
          })
        : c.protocol == 'AGORA'
        ? _agoraFactory()
        : null;
    if (next == null) throw const RtcJoinFailure('设备通话协议暂不支持');
    _active = next;
    await next.join(c, callbacks);
    if (_disposed || generation != _generation) {
      await next.dispose();
      throw const RtcOperationCancelled();
    }
  }

  @override
  Future<void> renewToken(String token) async => _active?.renewToken(token);
  @override
  Future<void> setMicrophoneMuted(bool muted) async =>
      _active?.setMicrophoneMuted(muted);
  @override
  Future<void> setSpeakerphone(bool enabled) async {
    final active = _active;
    if (active is WearRtcAudioRoute) {
      await (active as WearRtcAudioRoute).setSpeakerphone(enabled);
    }
  }

  @override
  Future<void> leave() async {
    ++_generation;
    final old = _active;
    _active = null;
    if (!_disposed) remoteStream.value = null;
    await old?.dispose();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    final old = _active;
    _active = null;
    remoteStream.value = null;
    await old?.dispose();
    remoteStream.dispose();
  }
}

class SipWearRtcEngine
    implements WearRtcEngine, WearRtcAudioRoute, SipUaHelperListener {
  SipWearRtcEngine(this.onStream);
  final void Function(MediaStream?) onStream;
  // SIP messages contain authentication material. Disable library logging even in debug builds.
  final SIPUAHelper _helper = SIPUAHelper(
    customLogger: Logger(level: Level.off),
  );
  RtcCallbacks? _callbacks;
  Completer<void>? _registered;
  Call? _call;
  MediaStream? _local;
  bool _closed = false, _joined = false, _remote = false;
  Timer? _deadline, _expiry;

  @override
  Future<void> join(RtcCredentials c, RtcCallbacks callbacks) async {
    if (_closed || c.demo || !c.isUsable || c.isExpired) {
      throw const RtcJoinFailure('SIP 通话凭据无效或已过期');
    }
    final permissions = await [
      Permission.microphone,
      if (c.video) Permission.camera,
    ].request();
    if (_closed) throw const RtcOperationCancelled();
    if (permissions.values.any((p) => !p.isGranted)) {
      throw RtcPermissionDenied(video: c.video);
    }
    _callbacks = callbacks;
    _registered = Completer<void>();
    _helper.addSipUaHelperListener(this);
    final ice = <Map<String, String>>[];
    for (final row in c.iceServers) {
      final urls = row['urls'] is List ? row['urls'] as List : [row['urls']];
      for (final url in urls) {
        if (url is String && url.isNotEmpty) {
          ice.add({
            'urls': url,
            if (row['username'] is String) 'username': row['username'],
            if (row['credential'] is String) 'credential': row['credential'],
          });
        }
      }
    }
    final settings = UaSettings()
      ..transportType = TransportType.WS
      ..webSocketUrl = c.server
      ..uri = c.uri
      ..authorizationUser = c.authorizationUsername
      ..password = c.authorizationPassword
      ..displayName = '智能穿戴移动端'
      ..iceServers = ice
      ..register = true;
    try {
      await _helper.start(settings);
      await _registered!.future.timeout(const Duration(seconds: 25));
      if (_closed) throw const RtcOperationCancelled();
      if (c.isExpired) throw const RtcJoinFailure('通话授权已到期');
      // Camera is acquired only for an explicitly requested video call.
      final local = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': c.video,
      });
      if (_closed) {
        for (final track in local.getTracks()) {
          await track.stop();
        }
        await local.dispose();
        throw const RtcOperationCancelled();
      }
      _local = local;
      if (!await _helper.call(
        c.target,
        voiceOnly: !c.video,
        mediaStream: local,
      )) {
        throw const RtcJoinFailure('SIP 呼叫未建立');
      }
      _deadline = Timer(const Duration(seconds: 45), () {
        if (!_joined) _fail('设备未在限定时间内接听，请结束会话后重试');
      });
      _expiry = Timer(
        c.expiresAt!.difference(DateTime.now()),
        () => _fail('通话授权已到期，请重新发起'),
      );
    } on RtcOperationCancelled {
      rethrow;
    } on RtcPermissionDenied {
      rethrow;
    } catch (_) {
      await leave();
      throw const RtcJoinFailure('SIP 注册或媒体连接失败，请检查网络与服务状态');
    }
  }

  void _fail(String message) {
    if (!_closed) _callbacks?.onFailure(message);
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    final pending = _registered;
    if (_closed || pending == null || pending.isCompleted) return;
    if (state.state == RegistrationStateEnum.REGISTERED) pending.complete();
    if (state.state == RegistrationStateEnum.REGISTRATION_FAILED) {
      pending.completeError(const RtcJoinFailure('SIP 注册失败'));
    }
  }

  @override
  void transportStateChanged(TransportState state) {
    if (state.state == TransportStateEnum.DISCONNECTED) _fail('通话网络已断开');
  }

  @override
  void callStateChanged(Call call, CallState state) {
    if (_closed) return;
    if (_call != null && _call!.id != call.id) {
      call.hangup();
      return;
    }
    _call = call;
    if (state.state == CallStateEnum.CONFIRMED && !_joined) {
      _joined = true;
      _deadline?.cancel();
      _callbacks?.onLocalJoined();
    }
    if (state.state == CallStateEnum.STREAM &&
        state.originator == Originator.remote &&
        state.stream != null) {
      onStream(state.stream);
      if (!_remote) {
        _remote = true;
        _callbacks?.onRemoteJoined(1);
      }
    }
    if (state.state == CallStateEnum.ENDED ||
        state.state == CallStateEnum.FAILED) {
      if (_remote) _callbacks?.onRemoteLeft(1);
      _fail(state.state == CallStateEnum.FAILED ? '设备通话未接通或媒体协商失败' : '通话已结束');
    }
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {}
  @override
  void onNewNotify(Notify ntf) {}
  @override
  void onNewReinvite(ReInvite event) {
    event.reject?.call({});
  }

  @override
  Future<void> renewToken(String token) async =>
      throw const RtcJoinFailure('SIP 授权到期后请重新发起通话');
  @override
  Future<void> setMicrophoneMuted(bool muted) async {
    if (muted) {
      _call?.mute(true, false);
    } else {
      _call?.unmute(true, false);
    }
  }

  @override
  Future<void> setSpeakerphone(bool enabled) =>
      Helper.setSpeakerphoneOn(enabled);
  @override
  Future<void> leave() async {
    if (_closed) return;
    _closed = true;
    _deadline?.cancel();
    _expiry?.cancel();
    _helper.removeSipUaHelperListener(this);
    final pending = _registered;
    if (pending != null && !pending.isCompleted) pending.complete();
    _callbacks = null;
    try {
      _call?.hangup();
    } catch (_) {}
    _call = null;
    _helper.stop();
    for (final track in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _local?.dispose();
    _local = null;
    onStream(null);
  }

  @override
  Future<void> dispose() => leave();
}

class SipRemoteVideo extends StatefulWidget {
  const SipRemoteVideo({super.key, required this.engine});
  final ProtocolWearRtcEngine engine;
  @override
  State<SipRemoteVideo> createState() => _SipRemoteVideoState();
}

class _SipRemoteVideoState extends State<SipRemoteVideo> {
  final _renderer = RTCVideoRenderer();
  bool _ready = false;
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _renderer.initialize();
    if (!mounted) {
      await _renderer.dispose();
      return;
    }
    widget.engine.remoteStream.addListener(_sync);
    _ready = true;
    _sync();
  }

  void _sync() {
    if (mounted && _ready) {
      setState(() => _renderer.srcObject = widget.engine.remoteStream.value);
    }
  }

  @override
  void dispose() {
    widget.engine.remoteStream.removeListener(_sync);
    if (_ready) _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 4 / 3,
    child: _ready && _renderer.srcObject != null
        ? RTCVideoView(_renderer)
        : const Center(child: Text('等待设备视频画面…')),
  );
}
