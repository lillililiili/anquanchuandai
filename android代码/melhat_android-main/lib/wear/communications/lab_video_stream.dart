import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../core.dart';

/// Media always goes through the authenticated main platform. Adapter-returned
/// streamUrl values are deliberately not used (including absolute URLs).
Uri labVideoUri(WearApi api, String callId, String deviceId) =>
    Uri.parse(api.dio.options.baseUrl)
        .resolve(
          '/api/v1/lab/calls/${Uri.encodeComponent(callId)}/video/stream',
        )
        .replace(queryParameters: {'deviceId': deviceId});

class LabVideoStream extends StatefulWidget {
  const LabVideoStream({
    super.key,
    required this.session,
    required this.callId,
    required this.deviceId,
    required this.active,
  });
  final WearSession session;
  final String callId, deviceId;
  final bool active;
  @override
  State<LabVideoStream> createState() => _LabVideoStreamState();
}

class _LabVideoStreamState extends State<LabVideoStream>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  String? _failure;
  int _generation = 0;
  String? _scope;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  @override
  void didUpdateWidget(LabVideoStream oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.callId != widget.callId ||
        oldWidget.deviceId != widget.deviceId ||
        oldWidget.active != widget.active ||
        _scope != widget.session.scopeKey) {
      _open();
    }
  }

  Future<void> _open() async {
    final generation = ++_generation;
    final old = _controller;
    _controller = null;
    _failure = null;
    _scope = widget.session.scopeKey;
    if (old != null) {
      old.removeListener(_changed);
      unawaited(old.dispose());
    }
    if (!widget.active) return;
    final api = widget.session.api;
    final token = api.token(), site = api.siteId();
    if (token == null || site == null) {
      _failure = '请登录后查看画面';
      return;
    }
    final controller = VideoPlayerController.networkUrl(
      labVideoUri(api, widget.callId, widget.deviceId),
      httpHeaders: {'Authorization': 'Bearer $token', 'X-Site-Id': site},
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    controller.addListener(_changed);
    try {
      await controller.initialize();
      if (!mounted || generation != _generation) return;
      // Video is helmet -> dispatcher only. Do not duplicate call audio from
      // the test clip or acquire/publish the phone camera/microphone.
      await controller.setVolume(0);
      await controller.setLooping(true);
      if (!mounted || generation != _generation) return;
      if (_foreground) await controller.play();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _failure = '画面暂不可用，请重试');
      }
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (_controller?.value.hasError == true) _failure = '画面连接中断，请重试';
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed && widget.active) {
      unawaited(_controller?.play());
    } else {
      unawaited(_controller?.pause());
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_changed);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ColoredBox(
      color: const Color(0xFF173954),
      child: Center(
        child: !widget.active
            ? const Text('等待设备接通', style: TextStyle(color: Colors.white70))
            : _failure != null
            ? TextButton.icon(
                onPressed: () {
                  setState(() {});
                  _open();
                },
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: Text(
                  _failure!,
                  style: const TextStyle(color: Colors.white),
                ),
              )
            : controller?.value.isInitialized == true
            ? AspectRatio(
                aspectRatio: controller!.value.aspectRatio,
                child: VideoPlayer(controller),
              )
            : const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
