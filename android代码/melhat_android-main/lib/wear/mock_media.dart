import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'data.dart';

/// Uploaded demo attachments stay in memory; preview never resolves an API URL.
class MockMediaTile extends StatelessWidget {
  const MockMediaTile({
    super.key,
    required this.media,
    this.width = 96,
    this.height = 96,
  });
  final JsonMap media;
  final double width, height;
  @override
  Widget build(BuildContext context) {
    final video = textOf(media['mediaType']).startsWith('video/');
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => _MockMediaPage(media: media)),
      ),
      child: SizedBox(
        width: width,
        height: height,
        child: video
            ? const Icon(Icons.play_circle_outline, size: 32)
            : _photo(media),
      ),
    );
  }
}

Widget _photo(JsonMap media) {
  final data = textOf(media['localData'], '');
  if (data.isEmpty) return const Center(child: Text('本地模拟附件'));
  return Image.memory(
    base64Decode(data),
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
  );
}

class _MockMediaPage extends StatefulWidget {
  const _MockMediaPage({required this.media});
  final JsonMap media;
  @override
  State<_MockMediaPage> createState() => _MockMediaPageState();
}

class _MockMediaPageState extends State<_MockMediaPage> {
  VideoPlayerController? _controller;
  Directory? _temporary;
  String? _error;
  bool get _video => textOf(widget.media['mediaType']).startsWith('video/');
  @override
  void initState() {
    super.initState();
    if (_video) unawaited(_open());
  }

  Future<void> _open() async {
    if (kIsWeb) {
      _error = '本地视频已保存；请在安卓端预览';
      return;
    }
    Directory? directory;
    VideoPlayerController? controller;
    try {
      directory = await Directory.systemTemp.createTemp('wear-mock-media-');
      final file = File('${directory.path}/preview.mp4');
      await file.writeAsBytes(
        base64Decode(textOf(widget.media['localData'], '')),
      );
      controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        await directory.delete(recursive: true);
        return;
      }
      setState(() {
        _controller = controller;
        _temporary = directory;
      });
    } catch (_) {
      await controller?.dispose();
      if (directory != null) await directory.delete(recursive: true);
      if (mounted) setState(() => _error = '本地视频无法播放');
    }
  }

  Future<void> _close() async {
    await _controller?.dispose();
    if (_temporary != null) await _temporary!.delete(recursive: true);
  }

  @override
  void dispose() {
    unawaited(_close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_video ? '本地模拟视频' : '本地模拟照片')),
    body: Center(
      child: !_video
          ? InteractiveViewer(child: _photo(widget.media))
          : _error != null
          ? Text(_error!)
          : _controller == null
          ? const CircularProgressIndicator()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
                VideoProgressIndicator(_controller!, allowScrubbing: true),
                IconButton(
                  tooltip: '播放或暂停',
                  icon: Icon(
                    _controller!.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                  onPressed: () => setState(() {
                    _controller!.value.isPlaying
                        ? _controller!.pause()
                        : _controller!.play();
                  }),
                ),
              ],
            ),
    ),
  );
}
