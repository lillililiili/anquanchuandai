import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../core.dart';
import '../device_features.dart';
import '../shared_backend.dart';
import '../person_equipment_context.dart';
import 'query_widgets.dart';

/// Commands and files come from the same authenticated backend as the device.
class HelmetMediaPanel extends StatefulWidget {
  const HelmetMediaPanel({
    super.key,
    required this.deviceId,
    this.device = const {},
  });
  final String deviceId;
  final JsonMap device;
  @override
  State<HelmetMediaPanel> createState() => _HelmetMediaPanelState();
}

class _HelmetMediaPanelState extends State<HelmetMediaPanel> {
  WearSession? _session;
  JsonMap _data = {};
  JsonMap _live = {}, _viewContext = {}, _recordingContext = {};
  String? _viewerSessionId;
  String? _recordingSourceCommandId;
  bool _viewing = false;
  Object? _error;
  String _liveError = '';
  String _message = '';
  bool _loading = true, _writing = false, _reading = false;
  int _generation = 0;
  Timer? _timer;
  final Map<String, String> _pending = {};
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (!identical(session, _session)) {
      _releaseView();
      _session = session;
      _data = {};
      _pending.clear();
      ++_generation;
      _load();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
    }
  }

  @override
  void didUpdateWidget(covariant HelmetMediaPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId ||
        _viewerSessionId != null &&
            !sameEquipmentContext(
              _viewContext,
              jsonMap(widget.device['equipmentContext']),
            )) {
      _releaseView(oldWidget.deviceId);
      _live = {};
      ++_generation;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _releaseView();
    ++_generation;
    super.dispose();
  }

  Future<void> _load() async {
    if (_reading || _session == null) return;
    _reading = true;
    final session = _session!,
        scope = _session!.scopeKey,
        generation = _generation;
    try {
      final data = jsonMap(
        await session.api.get(
          '/api/guardian/v1/devices/${widget.deviceId}/media',
        ),
      );
      JsonMap live = {};
      String liveError = '';
      if (_viewing &&
          _viewerSessionId != null &&
          hasEquipmentContext(_viewContext)) {
        try {
          live = jsonMap(
            await session.api.get(
              '/api/guardian/v1/devices/${widget.deviceId}/live',
              query: {
                ...equipmentIdentity(_viewContext),
                'viewerSessionId': _viewerSessionId,
              },
            ),
          );
          if (live['live'] is Map) live = jsonMap(live['live']);
        } catch (e) {
          liveError = e is WearApiException ? e.message : '实时画面暂不可用';
          if (mounted &&
              scope == session.scopeKey &&
              generation == _generation &&
              e is WearApiException &&
              [403, 404, 409].contains(e.code)) {
            _releaseView();
          }
        }
      }
      if (!mounted || scope != session.scopeKey || generation != _generation) {
        return;
      }
      setState(() {
        _data = data;
        _live = live;
        _liveError = liveError;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || scope != session.scopeKey || generation != _generation) {
        return;
      }
      setState(() {
        _error = e;
        _live = {};
        _loading = false;
      });
    } finally {
      _reading = false;
    }
  }

  Future<void> _command(String action, [JsonMap parameters = const {}]) async {
    if (_writing) return;
    final session = _session!, scope = _session!.scopeKey;
    final recipient = action == 'stop_video'
        ? _viewContext
        : action == 'stop_recording'
        ? _recordingContext
        : jsonMap(widget.device['equipmentContext']);
    if (!hasEquipmentContext(recipient)) {
      setState(() => _message = '请先办理人员领用并刷新装备');
      return;
    }
    if (action == 'start_video') {
      _viewerSessionId ??= SharedBackend.requestId();
      _viewContext = Map<String, dynamic>.from(recipient);
    }
    if (action == 'start_recording') {
      _recordingContext = Map<String, dynamic>.from(recipient);
    }
    final intent =
        '$action:${jsonEncode(parameters)}:${jsonEncode(equipmentIdentity(recipient))}';
    final key = _pending.putIfAbsent(intent, SharedBackend.requestId);
    setState(() {
      _writing = true;
      _message = '正在提交…';
    });
    try {
      final result = jsonMap(
        await session.api.post(
          '/api/guardian/v1/devices/${widget.deviceId}/commands',
          data: {
            'action': action,
            'idempotencyKey': key,
            'parameters': parameters,
            ...equipmentIdentity(recipient),
            if (action == 'stop_recording')
              'sourceCommandId': _recordingSourceCommandId,
            if (action == 'start_video' || action == 'stop_video')
              'viewerSessionId': _viewerSessionId,
          },
        ),
      );
      if (!mounted || scope != session.scopeKey) return;
      _pending.remove(intent);
      if (action == 'start_video') _viewing = true;
      if (action == 'start_recording') {
        _recordingSourceCommandId = idOf(result['id']);
      }
      if (action == 'stop_video') {
        _viewing = false;
        _live = {};
        _viewerSessionId = null;
      }
      if (action == 'stop_recording') {
        _recordingContext = {};
        _recordingSourceCommandId = null;
      }
      setState(() => _message = textOf(result['message'], '已提交，等待设备确认'));
      await _load();
    } catch (e) {
      if (!mounted || scope != session.scopeKey) return;
      if (e is WearApiException && e.code >= 400 && e.code < 500) {
        _pending.remove(intent);
      }
      setState(
        () => _message = e is WearApiException
            ? e.message
            : '请求结果未确认，请刷新记录核实，勿重复提交',
      );
    } finally {
      if (mounted && scope == session.scopeKey) {
        setState(() => _writing = false);
      }
    }
  }

  bool _allowed(String action) {
    if (action == 'stop_video') {
      return !_writing &&
          _viewerSessionId != null &&
          hasEquipmentContext(_viewContext);
    }
    if (action == 'stop_recording') {
      return !_writing &&
          hasEquipmentContext(_recordingContext) &&
          (_recordingSourceCommandId?.isNotEmpty ?? false);
    }
    if (!actionFeature(_features, action).available ||
        !hasEquipmentContext(jsonMap(widget.device['equipmentContext'])) ||
        _writing ||
        _error != null ||
        (_data['status'] != 'ready' && action != 'stop_video')) {
      return false;
    }
    // /media is historical data and deliberately carries no live authority.
    // Current personnel/issuance feature state is checked above and rechecked
    // by the backend when accepting the command.
    // Other pages and viewers own independent subscriptions to the same stream.
    // Their pending start commands must not prevent this viewer from joining.
    if (action == 'start_video') return !_viewing;
    final identity = jsonEncode(
      equipmentIdentity(jsonMap(widget.device['equipmentContext'])),
    );
    if (_pending.keys.any(
      (key) => key.startsWith('$action:') && key.endsWith(':$identity'),
    )) {
      return true;
    }
    final last = jsonList(
      _data['commands'],
    ).where((c) => c['action'] == action).firstOrNull;
    return last == null ||
        !const [
          'requesting',
          'sent',
          'unknown',
          'waiting_media',
          'finalizing',
        ].contains(last['status']);
  }

  JsonMap get _features => {...widget.device};

  void _releaseView([String? deviceId]) {
    final session = _session, viewer = _viewerSessionId;
    if (session == null ||
        viewer == null ||
        !hasEquipmentContext(_viewContext)) {
      return;
    }
    final recipient = equipmentIdentity(_viewContext);
    _viewerSessionId = null;
    _viewing = false;
    unawaited(
      session.api
          .post(
            '/api/guardian/v1/devices/${deviceId ?? widget.deviceId}/commands',
            data: {
              'action': 'stop_video',
              'idempotencyKey': SharedBackend.requestId(),
              'parameters': <String, dynamic>{},
              ...recipient,
              'viewerSessionId': viewer,
            },
          )
          .catchError((Object _) => null),
    );
  }

  Future<void> _listLocal() async {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await _command('list_recordings', {
      'startTime': '$date 00:00:00',
      'endTime': '$date 23:59:59',
    });
  }

  @override
  Widget build(BuildContext context) {
    final files = jsonList(_data['items']), live = _live;
    final local = jsonList(
      _data['commands'],
    ).where((r) => r['action'] == 'list_recordings').firstOrNull;
    return QuerySection(
      title: '安全帽影像',
      children: [
        QueryStateView(
          loading: _loading,
          error: _data.isEmpty ? _error : null,
          empty: false,
          onRetry: _load,
          child: WearCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(switch (_data['status']) {
                  'ready' => '媒体服务可用，设备结果以回执与实际画面为准',
                  'unconfigured' => '媒体服务尚未配置',
                  _ => '媒体服务暂不可用',
                }),
                if (_error != null)
                  TextButton(
                    onPressed: _load,
                    child: const Text('刷新失败，当前信息已过期 · 重试'),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _button('拍照', Icons.photo_camera_outlined, 'take_photo'),
                    _button('实时观看', Icons.videocam_outlined, 'start_video'),
                    _button('停止观看', Icons.stop_circle_outlined, 'stop_video'),
                    _button(
                      '开始录像',
                      Icons.fiber_manual_record_outlined,
                      'start_recording',
                    ),
                    _button('停止录像', Icons.stop_outlined, 'stop_recording'),
                    if (actionFeature(_features, 'list_recordings').supported)
                      OutlinedButton.icon(
                        onPressed: _allowed('list_recordings')
                            ? _listLocal
                            : null,
                        icon: const Icon(Icons.video_library_outlined),
                        label: Text(
                          deviceFeatureLabel(_features, 'recording', '今日设备录像'),
                        ),
                      ),
                  ],
                ),
                if (_message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(_message),
                  ),
                if (_liveError.isNotEmpty)
                  Text(
                    _liveError,
                    style: const TextStyle(color: WearColors.muted),
                  ),
                if (deviceFeature(_features, 'video').supported &&
                    idOf(live['hlsUrl']).isNotEmpty &&
                    _error == null)
                  HelmetVideoPlayer(
                    key: ValueKey(
                      Uri.parse(
                        idOf(live['hlsUrl']),
                      ).replace(query: '').toString(),
                    ),
                    expiresAt: DateTime.tryParse(idOf(live['expiresAt'])),
                    url: idOf(live['hlsUrl']),
                    live: true,
                  ),
                if (deviceFeature(_features, 'video').supported &&
                    idOf(live['hlsUrl']).isEmpty)
                  const Text(
                    '收到真实视频流后显示画面；指令发送成功不代表设备已推流。',
                    style: TextStyle(color: WearColors.muted),
                  ),
                for (final command in jsonList(_data['commands']).take(8))
                  ListTile(
                    dense: true,
                    title: Text(
                      '${_actionLabel(idOf(command['action']))} · ${_statusLabel(idOf(command['status']), idOf(command['action']))}',
                    ),
                    subtitle: Text(
                      '${textOf(command['message'])}\n${formatTime(command['createdAt'])}',
                    ),
                  ),
                if (deviceFeature(_features, 'recording').supported &&
                    local?['result'] is List) ...[
                  const Divider(),
                  const Text('设备回报的本地录像'),
                  for (final raw in local!['result'] as List)
                    Builder(
                      builder: (context) {
                        final filename = raw is String
                            ? raw
                            : idOf(
                                jsonMap(raw)['fileName'] ??
                                    jsonMap(raw)['file_name'] ??
                                    jsonMap(raw)['name'],
                              );
                        return ListTile(
                          title: Text(
                            filename.isEmpty ? '录像信息缺少文件名' : filename,
                          ),
                          trailing: TextButton(
                            onPressed:
                                filename.isEmpty ||
                                    !_allowed('upload_recording')
                                ? null
                                : () => _command('upload_recording', {
                                    'files': [filename],
                                  }),
                            child: const Text('上传回放'),
                          ),
                        );
                      },
                    ),
                ],
                const Divider(),
                Text('已入库照片与录像（${files.length}）'),
                if (files.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('暂无已确认文件'),
                  ),
                for (final file in files) _asset(file),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _button(String label, IconData icon, String action) =>
      !actionFeature(_features, action).supported
      ? const SizedBox.shrink()
      : Tooltip(
          message: actionFeature(_features, action).reason,
          child: OutlinedButton.icon(
            onPressed: _allowed(action) ? () => _command(action) : null,
            icon: Icon(icon),
            label: Text(
              deviceFeatureLabel(
                _features,
                actionFeatures[action] ?? action,
                label,
              ),
            ),
          ),
        );
  Widget _asset(JsonMap row) {
    final url = idOf(row['url'] ?? row['playUrl'] ?? row['downloadUrl']);
    final valid = Uri.tryParse(url)?.scheme == 'https';
    return ListTile(
      leading: Icon(
        row['kind'] == 'photo' ? Icons.photo_outlined : Icons.movie_outlined,
      ),
      title: Text(
        textOf(row['name'], row['kind'] == 'photo' ? '设备照片' : '设备录像'),
      ),
      subtitle: Text(formatTime(row['createdAt'] ?? row['created'])),
      trailing: const Icon(Icons.chevron_right),
      onTap: !valid
          ? null
          : () => showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: row['kind'] == 'photo'
                            ? Image.network(
                                url,
                                fit: BoxFit.contain,
                                errorBuilder: (_, error, stack) =>
                                    const Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Text('照片加载失败或链接已过期，请刷新列表后重试'),
                                    ),
                              )
                            : HelmetVideoPlayer(url: url),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

String _actionLabel(String value) =>
    const {
      'take_photo': '拍照',
      'start_video': '实时观看',
      'stop_video': '停止观看',
      'start_recording': '平台录像',
      'stop_recording': '停止录像',
      'list_recordings': '查询本地录像',
      'upload_recording': '上传录像',
    }[value] ??
    value;
String _statusLabel(String value, String action) => value == 'completed'
    ? switch (action) {
        'stop_video' => '观看已结束',
        'start_video' => '观看会话已建立',
        'list_recordings' => '查询已完成',
        'take_photo' || 'stop_recording' || 'upload_recording' => '文件已入库',
        _ => '操作已完成',
      }
    : const {
            'sent': '等待回执',
            'acknowledged': '设备已确认',
            'recording': '正在录像',
            'waiting_media': '等待真实画面',
            'timeout': '回执超时',
            'unknown': '结果未确认',
            'rejected': '设备拒绝',
            'finalizing': '文件封装中',
            'requesting': '提交中',
          }[value] ??
          value;

class HelmetVideoPlayer extends StatefulWidget {
  const HelmetVideoPlayer({
    super.key,
    required this.url,
    this.live = false,
    this.expiresAt,
  });
  final String url;
  final bool live;
  final DateTime? expiresAt;
  @override
  State<HelmetVideoPlayer> createState() => _HelmetVideoPlayerState();
}

class _HelmetVideoPlayerState extends State<HelmetVideoPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;
  DateTime? _activeExpiry;
  int _generation = 0;
  @override
  void didUpdateWidget(covariant HelmetVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url &&
        (_failed ||
            _controller?.value.hasError == true ||
            _activeExpiry?.isBefore(
                  DateTime.now().add(const Duration(seconds: 30)),
                ) ==
                true)) {
      _controller?.dispose();
      _controller = null;
      _failed = false;
      _init();
    }
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final generation = ++_generation;
    _activeExpiry = widget.expiresAt;
    final uri = Uri.tryParse(widget.url);
    if (uri?.scheme != 'https') {
      setState(() => _failed = true);
      return;
    }
    final c = VideoPlayerController.networkUrl(uri!);
    _controller = c;
    try {
      await c.initialize();
      if (!mounted || generation != _generation) return;
      await c.play();
      if (mounted && generation == _generation) setState(() {});
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    ++_generation;
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (_failed || c?.value.hasError == true) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text('视频暂无法播放或链接已过期，请返回刷新后重试'),
      );
    }
    if (c == null || !c.value.isInitialized) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
        if (!widget.live) VideoProgressIndicator(c, allowScrubbing: true),
        TextButton.icon(
          onPressed: () async {
            if (c.value.isPlaying) {
              await c.pause();
            } else {
              await c.play();
            }
            if (mounted) setState(() {});
          },
          icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow),
          label: Text(c.value.isPlaying ? '暂停' : '播放'),
        ),
      ],
    );
  }
}
