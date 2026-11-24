import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../api.dart';
import 'models.dart';
import 'prepared_rtc_media.dart';
import 'rtc_engine.dart';

/// A split helmet has independent receive and microphone peer connections.
/// This class never dials or retries device control; the server owns the lease.
class ZlmPeer {
  ZlmPeer({
    required this.api,
    required this.onStream,
    required this.onReady,
    required this.onFailure,
  });
  final WearApi api;
  final void Function(MediaStream?) onStream;
  final VoidCallback onReady;
  final void Function(String) onFailure;
  final List<RTCPeerConnection> _pcs = [];
  final Set<RTCPeerConnection> _connected = {};
  bool _closed = false, _track = false, _reported = false;
  bool _sendOnly = false;
  int _expected = 1;
  MediaStream? _remote;

  Future<void> open({
    required String playUrl,
    String? talkUrl,
    MediaStream? microphone,
    bool video = true,
    List<Map<String, dynamic>> iceServers = const [],
  }) async {
    _expected = microphone == null ? 1 : 2;
    await _connect(playUrl, false, microphone, video, iceServers);
    if (microphone != null) {
      if (talkUrl == null) throw const RtcJoinFailure('缺少对讲媒体地址');
      await _connect(talkUrl, true, microphone, false, iceServers);
    }
  }

  Future<void> _connect(
    String path,
    bool talk,
    MediaStream? mic,
    bool video,
    List<Map<String, dynamic>> iceServers,
  ) async {
    if (_closed) throw const RtcOperationCancelled();
    final pc = await createPeerConnection({
      'sdpSemantics': 'unified-plan',
      'iceServers': iceServers,
    });
    if (_closed) {
      await pc.close();
      throw const RtcOperationCancelled();
    }
    _pcs.add(pc);
    pc.onConnectionState = (state) {
      if (_closed) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _connected.add(pc);
        _checkReady();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _connected.remove(pc);
        onFailure('设备媒体连接已中断，请结束会话后重新发起');
      }
    };
    pc.onTrack = (event) {
      if (_closed || talk || event.streams.isEmpty) return;
      _remote = event.streams.first;
      _track = event.track.kind == 'audio' || event.track.kind == 'video';
      onStream(_remote);
      _checkReady();
    };
    if (talk) {
      for (final track in mic!.getAudioTracks()) {
        final transceiver = await pc.addTransceiver(
          track: track,
          init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.SendOnly,
            streams: [mic],
          ),
        );
        final codecs = (await getRtpSenderCapabilities('audio')).codecs;
        if (codecs != null && codecs.isNotEmpty) {
          int rank(RTCRtpCodecCapability c) =>
              switch (c.mimeType.toUpperCase()) {
                'AUDIO/PCMU' => 0,
                'AUDIO/PCMA' => 1,
                _ => 2,
              };
          final preferred = List<RTCRtpCodecCapability>.of(codecs)
            ..sort((a, b) => rank(a).compareTo(rank(b)));
          await transceiver.setCodecPreferences(preferred);
        }
      }
    } else {
      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      if (video) {
        await pc.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
      }
    }
    final iceDone = Completer<void>();
    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !iceDone.isCompleted) {
        iceDone.complete();
      }
    };
    await pc.setLocalDescription(await pc.createOffer());
    if (pc.iceGatheringState !=
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      await iceDone.future.timeout(const Duration(seconds: 12));
    }
    if (_closed) throw const RtcOperationCancelled();
    final offer = await pc.getLocalDescription();
    final answer = await api.postSdp(path, offer?.sdp ?? '');
    if (_closed) throw const RtcOperationCancelled();
    await pc.setRemoteDescription(RTCSessionDescription(answer, 'answer'));
  }

  Future<void> openMicrophone(String talkUrl, MediaStream microphone) {
    _sendOnly = true;
    return _connect(talkUrl, true, microphone, false, const []);
  }

  void _checkReady() {
    if (!_closed &&
        !_reported &&
        (_track || _sendOnly) &&
        _connected.length == _expected) {
      _reported = true;
      onReady();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final pc in _pcs) {
      try {
        await pc.close();
        await pc.dispose();
      } catch (_) {}
    }
    _pcs.clear();
    _connected.clear();
    final remote = _remote;
    _remote = null;
    if (remote != null) {
      try {
        await remote.dispose();
      } catch (_) {}
    }
    onStream(null);
  }
}

class ZlmWearRtcEngine
    implements WearRtcEngine, WearRtcAudioRoute, WearPreparedRtcMedia {
  ZlmWearRtcEngine(this.api, this.onStreams, {this.peerFactory});
  final ZlmPeer Function(
    WearApi,
    void Function(MediaStream?),
    VoidCallback,
    void Function(String),
  )?
  peerFactory;
  final WearApi api;
  final void Function(Map<String, MediaStream?>) onStreams;
  final List<ZlmPeer> _peers = [];
  final Map<String, MediaStream?> _streams = {};
  final Set<String> _ready = {};
  MediaStream? _mic;
  Timer? _heartbeat, _deadline;
  bool _closed = false,
      _heartbeatBusy = false,
      _failed = false,
      _joined = false;
  @override
  void usePreparedMedia(MediaStream stream) => _mic = stream;
  @override
  Future<void> join(RtcCredentials c, RtcCallbacks callbacks) async {
    if (_closed || c.demo || !c.isUsable || c.isExpired || _mic == null) {
      throw const RtcJoinFailure('分体式安全帽媒体授权无效或麦克风未准备');
    }
    void fail(String message) {
      if (_closed || _failed) return;
      _failed = true;
      callbacks.onFailure(message);
    }

    _deadline = Timer(
      const Duration(seconds: 45),
      () => fail('设备媒体连接超时，未自动重试'),
    );
    _heartbeat = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (_closed || _heartbeatBusy) return;
      _heartbeatBusy = true;
      try {
        await api.post(c.heartbeatUrl);
      } catch (_) {
        fail('通话续期未确认，连接已停止，请核实后重新发起');
      } finally {
        _heartbeatBusy = false;
      }
    });
    for (final target in c.sessions) {
      _streams[target.deviceId] = null;
    }
    onStreams(Map.of(_streams));
    try {
      await Future.wait(
        c.sessions.map((target) async {
          void onStream(MediaStream? stream) {
            if (!_closed) {
              _streams[target.deviceId] = stream;
              onStreams(Map.of(_streams));
            }
          }

          void onReady() {
            if (_closed || _failed || _joined) return;
            _ready.add(target.deviceId);
            if (_ready.length == c.sessions.length) {
              _joined = true;
              _deadline?.cancel();
              callbacks.onLocalJoined();
              callbacks.onRemoteJoined(1);
            }
          }

          final peer =
              peerFactory?.call(api, onStream, onReady, fail) ??
              ZlmPeer(
                api: api,
                onStream: onStream,
                onReady: onReady,
                onFailure: fail,
              );
          _peers.add(peer);
          await peer.open(
            playUrl: target.playUrl,
            talkUrl: target.talkUrl,
            microphone: _mic,
            video: c.video,
            iceServers: c.iceServers,
          );
        }),
      );
    } catch (_) {
      await leave();
      rethrow;
    }
  }

  @override
  Future<void> renewToken(String token) async {}
  @override
  Future<void> setMicrophoneMuted(bool muted) async {
    for (final track in _mic?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> setSpeakerphone(bool enabled) =>
      Helper.setSpeakerphoneOn(enabled);
  @override
  Future<void> leave() async {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    _deadline?.cancel();
    await Future.wait(_peers.map((p) => p.close()));
    _peers.clear();
    final mic = _mic;
    _mic = null;
    if (mic != null) {
      for (final track in mic.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await mic.dispose();
      } catch (_) {}
    }
    _streams.clear();
    onStreams({});
  }

  @override
  Future<void> dispose() => leave();
}

class ZlmStreamView extends StatefulWidget {
  const ZlmStreamView({super.key, required this.stream, this.label = ''});
  final MediaStream? stream;
  final String label;
  @override
  State<ZlmStreamView> createState() => _ZlmStreamViewState();
}

class _ZlmStreamViewState extends State<ZlmStreamView> {
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
    setState(() {
      _ready = true;
      _renderer.srcObject = widget.stream;
    });
  }

  @override
  void didUpdateWidget(covariant ZlmStreamView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ready) _renderer.srcObject = widget.stream;
  }

  @override
  void dispose() {
    if (_ready) _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (widget.label.isNotEmpty) Text(widget.label),
      AspectRatio(
        aspectRatio: 4 / 3,
        child: _ready && widget.stream != null
            ? RTCVideoView(_renderer)
            : const Center(child: Text('等待设备媒体连接…')),
      ),
    ],
  );
}
