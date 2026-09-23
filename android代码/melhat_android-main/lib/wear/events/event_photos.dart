import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../core.dart';
import 'event_video_preview.dart';

class EventPhotoCapture extends StatefulWidget {
  const EventPhotoCapture({
    super.key,
    required this.paths,
    required this.onChanged,
    required this.enabled,
  });
  final List<String> paths;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;
  @override
  State<EventPhotoCapture> createState() => _EventPhotoCaptureState();
}

class _EventPhotoCaptureState extends State<EventPhotoCapture> {
  bool capturing = false;
  bool isVideo(String path) =>
      RegExp(r'\.(mp4|webm|mov|m4v)$', caseSensitive: false).hasMatch(path);
  Future<void> capture() async {
    setState(() => capturing = true);
    try {
      if (kIsWeb) throw StateError('请使用安卓端添加现场附件');
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('现场拍照'),
                onTap: () => Navigator.pop(ctx, 'photo'),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('现场录像'),
                onTap: () => Navigator.pop(ctx, 'video'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从相册选择照片或视频'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
            ],
          ),
        ),
      );
      if (choice == null || !mounted) return;
      final picker = ImagePicker();
      final List<XFile> files;
      if (choice == 'gallery') {
        files = await picker.pickMultipleMedia(
          limit: 6 - widget.paths.length,
          imageQuality: 85,
          maxWidth: 1920,
          maxHeight: 1920,
        );
      } else {
        final file = choice == 'video'
            ? await picker.pickVideo(source: ImageSource.camera)
            : await picker.pickImage(
                source: ImageSource.camera,
                imageQuality: 85,
                maxWidth: 1920,
                maxHeight: 1920,
              );
        files = [?file];
      }
      if (files.isEmpty || !mounted) return;
      if (widget.paths.length + files.length > 6) throw StateError('最多添加6个附件');
      var total = 0;
      for (final path in widget.paths) {
        total += await XFile(path).length();
      }
      for (final file in files) {
        final size = await file.length();
        total += size;
        if (size == 0 || size > (isVideo(file.name) ? 50 : 10) * 1024 * 1024) {
          throw StateError('单张照片不超过10MB，单个视频不超过50MB');
        }
      }
      if (total > 100 * 1024 * 1024) throw StateError('附件合计不超过100MB');
      final folder = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/event-drafts',
      );
      await folder.create(recursive: true);
      final paths = <String>[];
      for (final file in files) {
        final extension = file.name.split('.').last.toLowerCase();
        if (![
          'jpg',
          'jpeg',
          'png',
          'mp4',
          'webm',
          'mov',
          'm4v',
        ].contains(extension)) {
          throw StateError('照片支持JPEG/PNG，视频支持MP4/WebM');
        }
        final path =
            '${folder.path}/${DateTime.now().microsecondsSinceEpoch}-${paths.length}.$extension';
        await file.saveTo(path);
        paths.add(path);
      }
      if (mounted) widget.onChanged([...widget.paths, ...paths]);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError ? error.message : '无法添加附件，请检查本机相机、相册及权限',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '现场照片 / 视频（选填）',
        style: TextStyle(fontWeight: FontWeight.w700, color: WearColors.ink),
      ),
      const SizedBox(height: 6),
      const Text(
        '最多6个；照片10MB、视频50MB，合计100MB，提交时上传',
        style: TextStyle(color: WearColors.muted, fontSize: 12),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final path in widget.paths)
            SizedBox(
              width: 88,
              height: 100,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: isVideo(path)
                        ? InkWell(
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (_) => EventVideoPreview(source: path),
                            ),
                            child: const ColoredBox(
                              color: Color(0xFFE8F1FF),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.play_circle_outline, size: 32),
                                  Text('视频', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          )
                        : FutureBuilder<Uint8List>(
                            future: XFile(path).readAsBytes(),
                            builder: (context, snapshot) => snapshot.hasData
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.memory(
                                      snapshot.data!,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Center(
                                    child: Text(
                                      '照片待读取',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                          ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton(
                      tooltip: '移除附件',
                      onPressed: widget.enabled && !capturing
                          ? () => widget.onChanged(
                              widget.paths.where((p) => p != path).toList(),
                            )
                          : null,
                      icon: const Icon(Icons.cancel, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          if (widget.paths.length < 6)
            SizedBox(
              width: 104,
              height: 100,
              child: OutlinedButton.icon(
                key: const ValueKey('event-capture-photo'),
                onPressed: widget.enabled && !capturing ? capture : null,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(capturing ? '添加中…' : '添加附件'),
              ),
            ),
        ],
      ),
    ],
  );
}

class EventSubmittedPhotos extends StatefulWidget {
  const EventSubmittedPhotos({
    super.key,
    required this.eventId,
    required this.version,
  });
  final String eventId;
  final int version;
  @override
  State<EventSubmittedPhotos> createState() => _EventSubmittedPhotosState();
}

class _EventSubmittedPhotosState extends State<EventSubmittedPhotos> {
  Future<Object?>? loading;
  String? scope;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (scope != session.scopeKey) {
      scope = session.scopeKey;
      loading = session.api.get('/api/v1/events/${widget.eventId}/media');
    }
  }

  @override
  void didUpdateWidget(covariant EventSubmittedPhotos old) {
    super.didUpdateWidget(old);
    if (old.version != widget.version) {
      loading = WearScope.of(
        context,
      ).api.get('/api/v1/events/${widget.eventId}/media');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = WearScope.of(context);
    return FutureBuilder<Object?>(
      future: loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TextButton(
            onPressed: () => setState(
              () => loading = session.api.get(
                '/api/v1/events/${widget.eventId}/media',
              ),
            ),
            child: const Text('现场附件加载失败，点击重试'),
          );
        }
        if (!snapshot.hasData) {
          return const LinearProgressIndicator(minHeight: 2);
        }
        final rows = jsonList(snapshot.data);
        if (rows.isEmpty) {
          return const Text(
            '暂无已提交附件',
            style: TextStyle(color: WearColors.muted),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '已提交现场附件',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: rows.map((row) {
                final url = Uri.parse(
                  session.api.dio.options.baseUrl,
                ).resolve(textOf(row['url'])).toString();
                final video = textOf(row['mediaType']).startsWith('video/');
                final headers = {
                  'Authorization': 'Bearer ${session.token}',
                  'X-Site-Id': session.siteId ?? '',
                };
                Widget photo() => Image.network(
                  url,
                  headers: {
                    'Authorization': 'Bearer ${session.token}',
                    'X-Site-Id': session.siteId ?? '',
                  },
                  fit: BoxFit.contain,
                  errorBuilder: (_, e, s) =>
                      const Icon(Icons.broken_image_outlined),
                );
                return InkWell(
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (ctx) => video
                        ? EventVideoPreview(source: url, headers: headers)
                        : Dialog(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(child: photo()),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('关闭'),
                                ),
                              ],
                            ),
                          ),
                  ),
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: video
                        ? const ColoredBox(
                            color: Color(0xFFE8F1FF),
                            child: Icon(Icons.play_circle_outline, size: 32),
                          )
                        : photo(),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}
