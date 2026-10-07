import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../core.dart';
import 'inspection.dart';

class InspectionGroupTasksPage extends StatefulWidget {
  const InspectionGroupTasksPage({
    super.key,
    required this.taskId,
    this.allTasks = true,
  });
  final String taskId;
  final bool allTasks;
  @override
  State<InspectionGroupTasksPage> createState() =>
      _InspectionGroupTasksPageState();
}

class _InspectionGroupTasksPageState extends State<InspectionGroupTasksPage> {
  InspectionController? _controller;
  JsonMap? _task;
  Object? _error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      _controller = InspectionController(WearScope.of(context), widget.taskId);
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final task = jsonMap(
        await _controller!.session.api.get(
          '/api/v1/work-tasks/${widget.taskId}',
        ),
      );
      if (mounted && _controller!.active) {
        setState(() {
          _task = task;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _task == null
      ? Scaffold(
          appBar: AppBar(title: Text(widget.allTasks ? '我的任务' : '巡检记录')),
          body: Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : WearEmpty(
                    title: '当前巡检组不可访问',
                    detail: '$_error',
                    onRetry: _load,
                  ),
          ),
        )
      : InspectionRecordsPage(
          controller: _controller!,
          task: _task!,
          allTasks: widget.allTasks,
        );
}

void inspectionFeedback(
  BuildContext context,
  InspectionController controller,
  bool ok,
  String message,
) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(ok ? message : '${controller.error ?? '操作未完成，请重试'}'),
    ),
  );
}

class InspectionActions extends StatelessWidget {
  const InspectionActions({
    super.key,
    required this.controller,
    required this.task,
    required this.onGuardian,
  });
  final InspectionController controller;
  final JsonMap task;
  final VoidCallback onGuardian;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final current = controller.current;
      final ended = task['status'] == 'ended';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.loading) const LinearProgressIndicator(),
          if (controller.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextButton.icon(
                onPressed: controller.busy ? null : controller.refresh,
                icon: const Icon(Icons.refresh),
                label: Text('同步未完成，点击重试：${controller.error}'),
              ),
            ),
          WearCard(
            child: InkWell(
              key: const ValueKey('inspection-records'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      InspectionRecordsPage(controller: controller, task: task),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.fact_check_outlined,
                    color: WearColors.brand,
                    size: 27,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '巡检记录',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          controller.accountProgress == null
                              ? '全部作业进度暂未获取'
                              : '我的全部作业 · 已完成 ${controller.accountCompleted} / ${controller.accountTotal}',
                          style: const TextStyle(color: WearColors.muted),
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: controller.accountTotal == 0
                              ? 0
                              : controller.accountCompleted /
                                    controller.accountTotal,
                          color: WearColors.brand,
                          backgroundColor: const Color(0xFFE5EEF7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          '点击查看本组巡检记录',
                          style: TextStyle(
                            fontSize: 12,
                            color: WearColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: WearColors.muted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (current != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '当前巡检：${textOf(current['title'])}',
                    style: const TextStyle(color: WearColors.muted),
                  ),
                ),
                TextButton(
                  onPressed: controller.busy
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => InspectionRecordsPage(
                              controller: controller,
                              task: task,
                            ),
                          ),
                        ),
                  child: const Text('选择任务'),
                ),
              ],
            ),
          if (controller.total > 0 && current == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '本组巡检已全部记录',
                style: TextStyle(color: WearColors.online),
              ),
            ),
          FilledButton.icon(
            key: const ValueKey('inspection-continue'),
            onPressed: controller.canWrite && current != null && !ended
                ? () async {
                    final ok = await controller.record(idOf(current['id']));
                    if (context.mounted) {
                      inspectionFeedback(
                        context,
                        controller,
                        ok,
                        '已记录巡检时间和巡检人',
                      );
                    }
                  }
                : null,
            icon: controller.busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(
              controller.busy
                  ? '记录中…'
                  : current == null && controller.data != null
                  ? '巡检已完成'
                  : '继续巡检',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '点击即记录当前项的时间与巡检人，并转至下一项',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: WearColors.muted),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onGuardian,
            icon: const Icon(Icons.call_outlined),
            label: const Text('联系监护人'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('inspection-report'),
            style: OutlinedButton.styleFrom(
              foregroundColor: WearColors.warning,
              side: const BorderSide(color: WearColors.warning),
            ),
            onPressed:
                controller.canWrite && controller.items.isNotEmpty && !ended
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => InspectionReportPage(
                        controller: controller,
                        task: task,
                      ),
                    ),
                  )
                : null,
            icon: const Icon(Icons.report_problem_outlined),
            label: const Text('上报异常'),
          ),
        ],
      );
    },
  );
}

class InspectionRecordsPage extends StatelessWidget {
  const InspectionRecordsPage({
    super.key,
    required this.controller,
    required this.task,
    this.allTasks = false,
  });
  final InspectionController controller;
  final JsonMap task;
  final bool allTasks;

  Future<void> _add(BuildContext context) async {
    final name = TextEditingController(),
        location = TextEditingController(),
        instruction = TextEditingController();
    final body = await showDialog<JsonMap>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增巡检项'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                maxLength: 128,
                decoration: const InputDecoration(labelText: '名称（必填）'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: location,
                maxLength: 200,
                decoration: const InputDecoration(labelText: '位置'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: instruction,
                maxLength: 500,
                decoration: const InputDecoration(labelText: '检查要求'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isNotEmpty) {
                Navigator.pop(ctx, {
                  'title': name.text.trim(),
                  'location': location.text.trim(),
                  'instruction': instruction.text.trim(),
                });
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // Dialog route completes its closing animation before releasing controllers.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    name.dispose();
    location.dispose();
    instruction.dispose();
    if (body != null && context.mounted) {
      final ok = await controller.mutate('items', body);
      if (context.mounted) {
        inspectionFeedback(context, controller, ok, '巡检项已加入当前组');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WearColors.background,
    appBar: AppBar(
      title: Text(allTasks ? '我的任务' : '巡检记录'),
      actions: [
        if (allTasks && controller.session.isDutyAdmin)
          TextButton(
            onPressed: () => context.go('/tasks?scope=all'),
            child: const Text('全站作业'),
          ),
        if (controller.session.isDutyAdmin && task['status'] != 'ended')
          IconButton(
            tooltip: '新增巡检项',
            onPressed: () => _add(context),
            icon: const Icon(Icons.add),
          ),
      ],
    ),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text(
              textOf(task['title']),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            const Text(
              '当前巡检组 · 组内成员共享进度和记录',
              style: TextStyle(fontSize: 12, color: WearColors.muted),
            ),
            const SizedBox(height: 14),
            WearCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '已完成 ${controller.completed} / ${controller.total}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: controller.total == 0
                        ? 0
                        : controller.completed / controller.total,
                    color: WearColors.brand,
                    backgroundColor: const Color(0xFFE5EEF7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ],
              ),
            ),
            if (controller.loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (controller.error != null)
              TextButton.icon(
                onPressed: controller.refresh,
                icon: const Icon(Icons.refresh),
                label: Text('同步失败，点击重试：${controller.error}'),
              ),
            for (final item in controller.items) ...[
              const SizedBox(height: 12),
              WearCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            textOf(item['title']),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        WearBadge(
                          text: inspectionStatus(item['status']),
                          color: inspectionColor(item['status']),
                        ),
                      ],
                    ),
                    if (textOf(item['location'], '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          textOf(item['location']),
                          style: const TextStyle(color: WearColors.muted),
                        ),
                      ),
                    if (textOf(item['instruction'], '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(textOf(item['instruction'])),
                      ),
                    const SizedBox(height: 8),
                    if (item['recordedAt'] != null)
                      Text(
                        '${formatTime(item['recordedAt'])} · ${textOf(item['inspector'])}',
                        style: const TextStyle(color: WearColors.muted),
                      )
                    else if (idOf(item['id']) ==
                        idOf(controller.current?['id']))
                      const Text(
                        '当前巡检项',
                        style: TextStyle(color: WearColors.brand),
                      )
                    else
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton(
                          key: ValueKey('inspection-select-${item['id']}'),
                          onPressed:
                              controller.canWrite && task['status'] != 'ended'
                              ? () async {
                                  final ok = await controller.mutate('select', {
                                    'itemId': idOf(item['id']),
                                  });
                                  if (context.mounted) {
                                    inspectionFeedback(
                                      context,
                                      controller,
                                      ok,
                                      '已设为当前巡检项，组内同步生效',
                                    );
                                  }
                                }
                              : null,
                          child: const Text('选择此项巡检'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (jsonList(controller.data?['reports']).isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '异常记录',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            for (final report in jsonList(controller.data?['reports']))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: WearCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        textOf(report['title']),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(textOf(report['description'])),
                      const SizedBox(height: 6),
                      Text(
                        '${textOf(report['location'])}\n${formatTime(report['reportedAt'])} · ${textOf(report['inspector'])}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: WearColors.muted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final media in jsonList(report['media']))
                            _mediaTile(context, media),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed:
                  controller.canWrite &&
                      controller.current != null &&
                      task['status'] != 'ended'
                  ? () async {
                      final ok = await controller.record(
                        idOf(controller.current?['id']),
                      );
                      if (context.mounted) {
                        inspectionFeedback(
                          context,
                          controller,
                          ok,
                          '已记录巡检时间和巡检人',
                        );
                      }
                    }
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(controller.busy ? '记录中…' : '继续巡检'),
            ),
            const SizedBox(height: 6),
            const Text(
              '直接记录当前项，不需要填写提交表单',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: WearColors.muted),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );

  Widget _mediaTile(BuildContext context, JsonMap media) {
    final video = textOf(media['mediaType']).startsWith('video/');
    final session = controller.session;
    final uri = Uri.parse(
      session.api.dio.options.baseUrl,
    ).resolve(textOf(media['url']));
    final headers = {
      'Authorization': 'Bearer ${session.token}',
      'X-Site-Id': session.siteId!,
    };
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              InspectionMediaPage(uri: uri, headers: headers, video: video),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 88,
          height: 78,
          child: video
              ? const ColoredBox(
                  color: Color(0xFFE8F1FF),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_circle, color: WearColors.brand),
                      Text('查看视频'),
                    ],
                  ),
                )
              : Image.network(
                  uri.toString(),
                  headers: headers,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined),
                ),
        ),
      ),
    );
  }
}

class InspectionReportPage extends StatefulWidget {
  const InspectionReportPage({
    super.key,
    required this.controller,
    required this.task,
  });
  final InspectionController controller;
  final JsonMap task;
  @override
  State<InspectionReportPage> createState() => _InspectionReportPageState();
}

class _InspectionReportPageState extends State<InspectionReportPage> {
  final _description = TextEditingController(),
      _location = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _files = [];
  final Map<String, Uint8List> _thumbnails = {};
  late String _itemId;
  String _request = inspectionRequestId();
  bool _sending = false, _picking = false;
  bool _video(XFile file) =>
      (file.mimeType ?? '').startsWith('video/') ||
      RegExp(
        r'\.(mp4|mov|webm|3gp|m4v)$',
        caseSensitive: false,
      ).hasMatch(file.name);
  @override
  void initState() {
    super.initState();
    final item = widget.controller.current ?? widget.controller.items.first;
    _itemId = idOf(item['id']);
    _location.text = textOf(
      item['location'],
      textOf(widget.task['spaceName'], ''),
    );
  }

  @override
  void dispose() {
    _description.dispose();
    _location.dispose();
    super.dispose();
  }

  void _changed() => _request = inspectionRequestId();
  Future<void> _pick(String mode) async {
    if (_sending || _picking) return;
    setState(() => _picking = true);
    try {
      List<XFile> result;
      if (mode == 'gallery') {
        result = await _picker.pickMultipleMedia();
      } else {
        final file = mode == 'photo'
            ? await _picker.pickImage(
                source: ImageSource.camera,
                imageQuality: 85,
                maxWidth: 2400,
              )
            : await _picker.pickVideo(
                source: ImageSource.camera,
                maxDuration: const Duration(minutes: 2),
              );
        result = file == null ? [] : [file];
      }
      if (!mounted) return;
      for (final file in result) {
        if (_files.length >= 6) throw const FormatException('最多添加6个附件');
        final size = await file.length();
        if (size > (_video(file) ? 50 : 10) * 1024 * 1024) {
          throw const FormatException('照片不超过10MB，视频不超过50MB');
        }
        if (!_video(file)) _thumbnails[file.path] = await file.readAsBytes();
        if (!mounted) return;
        setState(() {
          _files.add(file);
          _changed();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('附件未添加：$e')));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {
    if (_sending || _picking) return;
    if (_description.text.trim().isEmpty || _location.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写异常位置和异常描述')));
      return;
    }
    setState(() => _sending = true);
    try {
      final form = FormData.fromMap({
        'itemId': _itemId,
        'requestId': _request,
        'description': _description.text.trim(),
        'location': _location.text.trim(),
      });
      var total = 0;
      for (final file in _files) {
        final bytes = await file.readAsBytes();
        total += bytes.length;
        if (total > 100 * 1024 * 1024) {
          throw const FormatException('附件合计不超过100MB');
        }
        form.files.add(
          MapEntry(
            'files',
            MultipartFile.fromBytes(bytes, filename: file.name),
          ),
        );
      }
      final ok = await widget.controller.mutate('reports', form);
      if (!mounted) return;
      inspectionFeedback(context, widget.controller, ok, '异常已提交，组内成员可查看');
      if (ok) {
        setState(() => _sending = false);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('提交未完成：$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sending,
    child: Scaffold(
      backgroundColor: WearColors.background,
      appBar: AppBar(title: const Text('上报异常')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          WearCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('关联作业', style: TextStyle(color: WearColors.muted)),
                const SizedBox(height: 6),
                Text(
                  textOf(widget.task['title']),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _itemId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '巡检项'),
                  items: widget.controller.items
                      .map(
                        (i) => DropdownMenuItem(
                          value: idOf(i['id']),
                          child: Text(
                            textOf(i['title']),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _sending
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _itemId = value;
                              _changed();
                            });
                          }
                        },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _location,
                  enabled: !_sending,
                  maxLength: 200,
                  onChanged: (_) => _changed(),
                  decoration: const InputDecoration(labelText: '异常位置 *'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          WearCard(
            child: TextField(
              controller: _description,
              enabled: !_sending,
              minLines: 4,
              maxLines: 7,
              maxLength: 1000,
              onChanged: (_) => _changed(),
              decoration: const InputDecoration(
                labelText: '异常描述 *',
                hintText: '请描述现场异常情况',
              ),
            ),
          ),
          const SizedBox(height: 14),
          WearCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '照片 / 视频',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  '可拍摄或从相册选择，最多6个附件',
                  style: TextStyle(color: WearColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final file in _files)
                      SizedBox(
                        width: 88,
                        height: 92,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: _video(file)
                                    ? const ColoredBox(
                                        color: Color(0xFFE8F1FF),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.play_circle_outline,
                                              color: WearColors.brand,
                                            ),
                                            Text('视频'),
                                          ],
                                        ),
                                      )
                                    : Image.memory(
                                        _thumbnails[file.path]!,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: IconButton(
                                tooltip: '移除附件',
                                onPressed: _sending
                                    ? null
                                    : () => setState(() {
                                        _files.remove(file);
                                        _thumbnails.remove(file.path);
                                        _changed();
                                      }),
                                icon: const Icon(
                                  Icons.cancel,
                                  color: WearColors.ink,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_files.length < 6)
                      SizedBox(
                        width: 88,
                        height: 92,
                        child: OutlinedButton(
                          onPressed: _sending || _picking
                              ? null
                              : () => _pick('gallery'),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add),
                              Text('添加附件', textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _sending || _picking
                            ? null
                            : () => _pick('photo'),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('拍照'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _sending || _picking
                            ? null
                            : () => _pick('video'),
                        icon: const Icon(Icons.videocam_outlined),
                        label: const Text('录视频'),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _sending || _picking
                      ? null
                      : () => _pick('gallery'),
                  child: Text(_picking ? '正在选择附件…' : '从相册选择'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _sending || _picking ? null : _submit,
            child: Text(_sending ? '正在上传并提交…' : '提交异常'),
          ),
          const SizedBox(height: 20),
        ],
      ),
    ),
  );
}

class InspectionMediaPage extends StatefulWidget {
  const InspectionMediaPage({
    super.key,
    required this.uri,
    required this.headers,
    required this.video,
  });
  final Uri uri;
  final Map<String, String> headers;
  final bool video;
  @override
  State<InspectionMediaPage> createState() => _InspectionMediaPageState();
}

class _InspectionMediaPageState extends State<InspectionMediaPage> {
  VideoPlayerController? _video;
  Object? _error;
  @override
  void initState() {
    super.initState();
    if (widget.video) _load();
  }

  Future<void> _load() async {
    _video = VideoPlayerController.networkUrl(
      widget.uri,
      httpHeaders: widget.headers,
    );
    try {
      await _video!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.video ? '异常视频' : '异常照片')),
    body: Center(
      child: !widget.video
          ? InteractiveViewer(
              child: Image.network(
                widget.uri.toString(),
                headers: widget.headers,
                errorBuilder: (_, _, _) => const Text('照片加载失败，请返回后重试'),
              ),
            )
          : _error != null
          ? const Text('视频加载失败，请返回后重试')
          : _video?.value.isInitialized != true
          ? const CircularProgressIndicator()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: _video!.value.aspectRatio,
                  child: VideoPlayer(_video!),
                ),
                VideoProgressIndicator(_video!, allowScrubbing: true),
                IconButton(
                  tooltip: '播放或暂停',
                  onPressed: () {
                    setState(() {
                      _video!.value.isPlaying
                          ? _video!.pause()
                          : _video!.play();
                    });
                  },
                  icon: Icon(
                    _video!.value.isPlaying
                        ? Icons.pause_circle
                        : Icons.play_circle,
                  ),
                ),
              ],
            ),
    ),
  );
}
