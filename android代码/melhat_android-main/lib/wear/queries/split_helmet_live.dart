import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../api.dart';
import '../communications/zlm_rtc_engine.dart';
import '../communications/media_preparation.dart';
import '../communications/prepared_rtc_media.dart';

class SplitHelmetLivePlayer extends StatefulWidget {
  const SplitHelmetLivePlayer({
    super.key,
    required this.api,
    required this.playUrl,
    required this.heartbeatUrl,
    this.talkUrl = '',
    required this.onFailure,
  });
  final WearApi api;
  final String playUrl, heartbeatUrl, talkUrl;
  final void Function(String) onFailure;
  @override
  State<SplitHelmetLivePlayer> createState() => _SplitHelmetLivePlayerState();
}

class _SplitHelmetLivePlayerState extends State<SplitHelmetLivePlayer> {
  ZlmPeer? _peer;
  MediaStream? _stream;
  Timer? _heartbeat, _deadline;
  bool _renewing = false, _failed = false;
  bool _ready = false;
  @override
  void initState() {
    super.initState();
    _open();
  }

  void _fail(String message) {
    if (!mounted || _failed) return;
    _failed = true;
    _heartbeat?.cancel();
    _deadline?.cancel();
    unawaited(_peer?.close());
    widget.onFailure(message);
  }

  Future<void> _open() async {
    final prefix = widget.playUrl.split('/devices/').first;
    if (!prefix.startsWith('/api/guardian/v1/split/sessions/') ||
        widget.heartbeatUrl != '$prefix/heartbeat') {
      _fail('实时画面授权不完整，请停止观看后重新发起');
      return;
    }
    final peer = ZlmPeer(
      api: widget.api,
      onStream: (stream) {
        if (mounted && !_failed) setState(() => _stream = stream);
      },
      onReady: () {
        _deadline?.cancel();
        if (mounted && !_failed) setState(() => _ready = true);
      },
      onFailure: _fail,
    );
    _peer = peer;
    _deadline = Timer(
      const Duration(seconds: 45),
      () => _fail('未收到设备实时画面，未自动重试'),
    );
    _heartbeat = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (_renewing || _failed) return;
      _renewing = true;
      try {
        await widget.api.post(widget.heartbeatUrl);
      } catch (_) {
        _fail('观看续期未确认，已停止本端播放');
      } finally {
        _renewing = false;
      }
    });
    try {
      await peer.open(playUrl: widget.playUrl);
    } catch (_) {
      _fail('设备画面连接失败，未自动重试');
    }
  }

  @override
  void dispose() {
    _failed = true;
    _heartbeat?.cancel();
    _deadline?.cancel();
    unawaited(_peer?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ZlmStreamView(stream: _stream),
      if (_ready &&
          !_failed &&
          widget.talkUrl.isNotEmpty &&
          widget.playUrl.endsWith('/play') &&
          widget.talkUrl ==
              '${widget.playUrl.substring(0, widget.playUrl.length - 4)}talk')
        SplitMonitorMicrophone(
          key: ValueKey(widget.talkUrl),
          api: widget.api,
          talkUrl: widget.talkUrl,
        ),
    ],
  );
}

class SplitMonitorMicrophone extends StatefulWidget {
  const SplitMonitorMicrophone({
    super.key,
    required this.api,
    required this.talkUrl,
    this.preparation,
    this.peerFactory,
  });
  final WearApi api;
  final String talkUrl;
  final RtcMediaPreparation<MediaStream>? preparation;
  final ZlmPeer Function(VoidCallback ready, void Function(String) failed)?
  peerFactory;
  @override
  State<SplitMonitorMicrophone> createState() => _SplitMonitorMicrophoneState();
}

enum _TalkPhase { off, preparing, connecting, talking, closing }

class _SplitMonitorMicrophoneState extends State<SplitMonitorMicrophone> {
  late final _preparation = widget.preparation ?? prepareWearMedia();
  _TalkPhase _phase = _TalkPhase.off;
  ZlmPeer? _talk;
  MediaStream? _mic;
  Timer? _deadline;
  int _operation = 0;
  String _error = '';

  Future<void> _release() async {
    ++_operation;
    _deadline?.cancel();
    final peer = _talk, mic = _mic;
    _talk = null;
    _mic = null;
    for (final track in mic?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = false;
    }
    await Future.wait([
      _preparation.cancel(),
      if (peer != null) peer.close(),
      if (mic != null) releaseWearMedia(mic),
    ]);
  }

  Future<void> _stop([String message = '']) async {
    if (_phase == _TalkPhase.off || _phase == _TalkPhase.closing) return;
    setState(() => _phase = _TalkPhase.closing);
    try {
      await _release();
    } catch (_) {
      message = '麦克风关闭状态待核实';
    }
    if (mounted) {
      setState(() {
        _phase = _TalkPhase.off;
        _error = message;
      });
    }
  }

  Future<void> _start() async {
    if (_phase != _TalkPhase.off) return;
    final op = ++_operation;
    bool current() => mounted && op == _operation;
    setState(() {
      _phase = _TalkPhase.preparing;
      _error = '';
    });
    try {
      await _preparation.prepare(video: false);
      if (!current()) return;
      final mic = _preparation.take(video: false);
      if (mic == null) throw StateError('未取得麦克风');
      _mic = mic;
      setState(() => _phase = _TalkPhase.connecting);
      void ready() {
        if (!current()) return;
        _deadline?.cancel();
        setState(() => _phase = _TalkPhase.talking);
      }

      void failed(String message) {
        if (current()) unawaited(_stop(message));
      }

      final peer =
          widget.peerFactory?.call(ready, failed) ??
          ZlmPeer(
            api: widget.api,
            onStream: (_) {},
            onReady: ready,
            onFailure: failed,
          );
      _talk = peer;
      _deadline = Timer(
        const Duration(seconds: 45),
        () => failed('对讲连接超时，可重新开启麦克风'),
      );
      await peer.openMicrophone(widget.talkUrl, mic);
    } catch (error) {
      if (current()) {
        await _stop(
          error is WearApiException ? error.message : '对讲未接通，请检查麦克风权限和设备连接',
        );
      }
    }
  }

  @override
  void dispose() {
    unawaited(_release().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (_error.isNotEmpty) Text(_error),
      if (_phase == _TalkPhase.talking) const Text('麦克风已开启'),
      OutlinedButton.icon(
        onPressed: _phase == _TalkPhase.off
            ? _start
            : _phase == _TalkPhase.closing
            ? null
            : _stop,
        icon: Icon(_phase == _TalkPhase.talking ? Icons.mic : Icons.mic_none),
        label: Text(switch (_phase) {
          _TalkPhase.off => '开启对讲',
          _TalkPhase.preparing => '取消麦克风授权',
          _TalkPhase.connecting => '取消对讲连接',
          _TalkPhase.talking => '关闭麦克风',
          _TalkPhase.closing => '正在关闭麦克风',
        }),
      ),
    ],
  );
}
