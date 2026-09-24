import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Uses the same authenticated media URL as photo evidence; no public copy.
class EventVideoPreview extends StatefulWidget {
  const EventVideoPreview({super.key, required this.source, this.headers});
  final String source;
  final Map<String, String>? headers;
  @override
  State<EventVideoPreview> createState() => _EventVideoPreviewState();
}

class _EventVideoPreviewState extends State<EventVideoPreview> {
  late final VideoPlayerController _player = VideoPlayerController.networkUrl(
    Uri.parse(widget.source),
    httpHeaders: widget.headers ?? const {},
  );
  late final Future<void> _ready = _player.initialize();
  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: FutureBuilder<void>(
              future: _ready,
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Text('视频加载失败，请关闭后重试');
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 160,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AspectRatio(
                        aspectRatio: _player.value.aspectRatio,
                        child: VideoPlayer(_player),
                      ),
                      VideoProgressIndicator(_player, allowScrubbing: true),
                      ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: _player,
                        builder: (_, value, _) => IconButton(
                          tooltip: value.isPlaying ? '暂停视频' : '播放视频',
                          onPressed: () => value.isPlaying
                              ? _player.pause()
                              : _player.play(),
                          icon: Icon(
                            value.isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    ),
  );
}
