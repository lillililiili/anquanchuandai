import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core.dart';
import '../device_report_time.dart';

abstract class DeviceMessageAudio extends ChangeNotifier {
  bool get playing;
  bool get failed;
  Duration get position;
  Duration get duration;
  Future<void> initialize();
  Future<void> play();
  Future<void> close();
}

class _VideoMessageAudio extends DeviceMessageAudio {
  _VideoMessageAudio(Uri uri)
    : _player = VideoPlayerController.networkUrl(uri) {
    _player.addListener(_changed);
  }
  final VideoPlayerController _player;
  bool _closed = false;
  void _changed() {
    if (!_closed) notifyListeners();
  }

  @override
  bool get playing => !_closed && _player.value.isPlaying;
  @override
  bool get failed => _player.value.hasError;
  @override
  Duration get position => _player.value.position;
  @override
  Duration get duration => _player.value.duration;
  @override
  Future<void> initialize() => _player.initialize();
  @override
  Future<void> play() async {
    if (!_closed) await _player.play();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _player.removeListener(_changed);
    await _player.dispose();
    super.dispose();
  }
}

DeviceMessageAudio _createAudio(Uri uri) => _VideoMessageAudio(uri);

bool _deviceVoice(JsonMap row) =>
    row['operationType'] == 'deviceVoiceMessage' &&
    row['direction'] == 'DEVICE_TO_PLATFORM' &&
    row['source'] == 'DIRECT_HELMET' &&
    row['reportAct'] == 'ca_sending_message' &&
    row['timeBasis'] == 'RECEIVED_AT';

Uri? deviceMessagePlaybackUri(JsonMap row, JsonMap playback, {DateTime? now}) {
  if (!_deviceVoice(row) ||
      row['status'] != 'READY' ||
      row['playable'] != true ||
      idOf(row['id']).isEmpty ||
      idOf(row['assetId']).isEmpty ||
      playback['id'] != row['id'] ||
      playback['assetId'] != row['assetId'] ||
      playback['mime'] != 'audio/mpeg') {
    return null;
  }
  final uri = Uri.tryParse(idOf(playback['url']));
  final expires = deviceReportInstant(playback['expiresAt']);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      uri.pathSegments.length != 3 ||
      uri.pathSegments[0] != 'helmet-media' ||
      uri.pathSegments[1] != 'files' ||
      uri.pathSegments[2] != idOf(row['assetId']) ||
      uri.queryParametersAll.keys.any(
        (key) => !['variant', 'token'].contains(key),
      ) ||
      uri.queryParametersAll['variant']?.length != 1 ||
      uri.queryParametersAll['token']?.length != 1 ||
      uri.queryParameters['variant'] != 'playback' ||
      idOf(uri.queryParameters['token']).isEmpty ||
      expires == null ||
      !expires.isAfter(now ?? DateTime.now())) {
    return null;
  }
  return uri;
}

/// Received device recordings are historical messages, never a call session.
/// All transport operations here are GET; only an explicit tap starts playback.
class DeviceVoiceMessages extends StatefulWidget {
  const DeviceVoiceMessages({
    super.key,
    this.createAudio = _createAudio,
    this.now,
  });
  final DeviceMessageAudio Function(Uri uri) createAudio;
  final DateTime Function()? now;

  @override
  State<DeviceVoiceMessages> createState() => _DeviceVoiceMessagesState();
}

class _DeviceVoiceMessagesState extends State<DeviceVoiceMessages>
    with WidgetsBindingObserver {
  WearSession? _session;
  String? _identity;
  List<JsonMap> _rows = [];
  int _page = 1, _total = 0, _readGeneration = 0, _playGeneration = 0;
  bool _expanded = false, _visible = true, _foreground = true;
  bool _loading = false, _reading = false;
  String? _error, _playError, _busyId, _playingId;
  String? _targetAssetId;
  DeviceMessageAudio? _audio;
  Timer? _poll;
  static const _root = '/api/guardian/v1/voice-messages';
  static const _size = 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  String _identityOf(WearSession session) {
    final permissions = session.permissions.toList()..sort();
    final roles = session.roles.toList()..sort();
    return '${session.scopeKey}|$permissions|$roles';
  }

  bool get _active => _expanded && _visible && _foreground;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    final identity = _identityOf(session);
    final visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    final changed = !identical(_session, session) || _identity != identity;
    final becameVisible = !_visible && visible;
    _visible = visible;
    if (changed) {
      _stop();
      ++_readGeneration;
      _reading = false;
      _session = session;
      _identity = identity;
      _rows = [];
      _page = 1;
      _total = 0;
      _error = null;
      _playError = null;
    }
    if (!_active || session.callActive.value) _stop();
    _schedulePoll();
    if (_active && (changed || becameVisible)) unawaited(_load());
  }

  void _schedulePoll() {
    _poll?.cancel();
    _poll = _active
        ? Timer.periodic(
            const Duration(seconds: 10),
            (_) => _load(background: true),
          )
        : null;
  }

  bool _same(WearSession session, String identity) =>
      mounted &&
      _active &&
      identical(_session, session) &&
      _identity == identity &&
      _identityOf(session) == identity;

  void _stop() {
    ++_playGeneration;
    final audio = _audio;
    _audio = null;
    _busyId = null;
    _playingId = null;
    _targetAssetId = null;
    audio?.removeListener(_audioChanged);
    if (audio != null) unawaited(audio.close());
  }

  Future<void> _load({bool background = false}) async {
    final session = _session, identity = _identity;
    if (session == null || identity == null || !_active || _reading) return;
    _reading = true;
    final generation = ++_readGeneration;
    setState(() {
      if (!background) _loading = true;
    });
    try {
      final result = jsonMap(
        await session.api.get(
          _root,
          query: {
            'siteId': session.siteId,
            'pageNum': _page,
            'pageSize': _size,
          },
        ),
      );
      if (!_same(session, identity) || generation != _readGeneration) return;
      final rows = jsonList(result['rows']);
      final target = _playingId ?? _busyId;
      if (target != null &&
          !rows.any(
            (row) =>
                row['id'] == target &&
                row['assetId'] == _targetAssetId &&
                _deviceVoice(row) &&
                row['playable'] == true &&
                row['status'] == 'READY',
          )) {
        _stop();
      }
      setState(() {
        _rows = rows;
        _total = intOf(result['total']);
        _page = intOf(result['pageNum'], _page);
        _error = null;
      });
    } catch (error) {
      if (!_same(session, identity) || generation != _readGeneration) return;
      if (error is WearApiException && [401, 403, 404].contains(error.code)) {
        _stop();
        _rows = [];
        _total = 0;
      }
      setState(
        () => _error = error is WearApiException && error.code == 403
            ? '暂无设备语音消息访问权限'
            : '设备语音消息读取失败，请重试',
      );
    } finally {
      if (mounted && generation == _readGeneration) {
        setState(() {
          _reading = false;
          _loading = false;
        });
      }
    }
  }

  Future<void> _play(JsonMap row) async {
    final session = _session, identity = _identity;
    if (session == null ||
        identity == null ||
        !_active ||
        session.callActive.value) {
      return;
    }
    _stop();
    final generation = _playGeneration, id = idOf(row['id']);
    setState(() {
      _busyId = id;
      _targetAssetId = idOf(row['assetId']);
      _playError = null;
    });
    try {
      final result = jsonMap(
        await session.api.get('$_root/${Uri.encodeComponent(id)}/playback'),
      );
      if (!_same(session, identity) || generation != _playGeneration) return;
      final uri = deviceMessagePlaybackUri(
        row,
        result,
        now: widget.now?.call(),
      );
      if (uri == null) throw const WearApiException(502, '录音播放信息不完整');
      final audio = widget.createAudio(uri);
      _audio = audio;
      _playingId = id;
      audio.addListener(_audioChanged);
      await audio.initialize();
      if (!_same(session, identity) || generation != _playGeneration) {
        await audio.close();
        return;
      }
      if (deviceMessagePlaybackUri(row, result, now: widget.now?.call()) ==
          null) {
        throw const WearApiException(410, '录音播放授权已过期');
      }
      await audio.play();
      if (mounted && generation == _playGeneration) {
        setState(() => _busyId = null);
      }
    } catch (error) {
      if (!_same(session, identity) || generation != _playGeneration) return;
      _stop();
      if (error is WearApiException && [401, 403, 404].contains(error.code)) {
        ++_readGeneration;
        _reading = false;
        _loading = false;
        _rows.removeWhere((item) => item['id'] == id);
        _total = (_total - 1).clamp(0, _total);
      }
      setState(
        () => _playError =
            error is WearApiException && [403, 404].contains(error.code)
            ? '该语音消息已不可访问'
            : '录音暂不可播放，请重新点击播放重试',
      );
    }
  }

  void _audioChanged() {
    if (!mounted) return;
    if (_audio?.failed == true) {
      _stop();
      _playError = '录音播放失败，请重试';
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _stop();
    _schedulePoll();
    if (mounted) setState(() {});
    if (_active) unawaited(_load(background: true));
  }

  @override
  void dispose() {
    ++_readGeneration;
    _poll?.cancel();
    _stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WearCard(
    padding: EdgeInsets.zero,
    child: ExpansionTile(
      title: const Text('设备语音消息（非实时通话）'),
      subtitle: const Text('设备主动发送的录音 · 点击播放'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      onExpansionChanged: (value) {
        setState(() {
          _expanded = value;
          if (!value) {
            _stop();
            ++_readGeneration;
            _reading = false;
            _loading = false;
          }
        });
        _schedulePoll();
        if (value) unawaited(_load());
      },
      children: [
        if (_session?.callActive.value == true) const Text('通话期间不能播放设备语音消息。'),
        if (_error != null) Text(_error!),
        if (_playError != null) Text(_playError!),
        if (_loading && _rows.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (_rows.isEmpty && _error == null)
          const Text('暂无设备语音消息'),
        for (final row in _rows) _message(row),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _reading ? null : () => _load(),
              child: const Text('刷新消息'),
            ),
            Text('第 $_page 页 · 共 $_total 条'),
            TextButton(
              onPressed: _reading || _page <= 1
                  ? null
                  : () => _changePage(_page - 1),
              child: const Text('上一页'),
            ),
            TextButton(
              onPressed: _reading || _page * _size >= _total
                  ? null
                  : () => _changePage(_page + 1),
              child: const Text('下一页'),
            ),
          ],
        ),
      ],
    ),
  );

  void _changePage(int page) {
    _stop();
    setState(() {
      _page = page;
      _rows = [];
    });
    unawaited(_load());
  }

  Widget _message(JsonMap row) {
    final id = idOf(row['id']);
    final recognized = _deviceVoice(row);
    final playable =
        recognized &&
        row['status'] == 'READY' &&
        row['playable'] == true &&
        id.isNotEmpty &&
        idOf(row['assetId']).isNotEmpty;
    final active = _playingId == id, busy = _busyId == id;
    final audio = active ? _audio : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '来源设备：${textOf(row['deviceId'])}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '上报时人员：${!recognized ? '来源未确认' : textOf(row['personName'], idOf(row['personId']).isEmpty ? '未关联人员' : '${row['personId']}（历史姓名未提供）')}',
          ),
          Text(
            '平台接收时间：${recognized ? deviceReportTimeLabel(row['receivedAt']) : '来源未确认'}',
          ),
          if (!playable)
            Text(
              !recognized
                  ? '来源未确认，不能播放'
                  : row['status'] == 'REJECTED'
                  ? '音频未接收'
                  : '录音暂不可播放',
            ),
          if (active && audio != null && audio.duration.inMilliseconds > 0) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value:
                  (audio.position.inMilliseconds /
                          audio.duration.inMilliseconds)
                      .clamp(0, 1),
            ),
            Text('${_duration(audio.position)} / ${_duration(audio.duration)}'),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey('voice-message-play-$id'),
              onPressed: active || busy
                  ? () => setState(_stop)
                  : !playable || _session?.callActive.value == true
                  ? null
                  : () => _play(row),
              icon: Icon(
                active || busy ? Icons.stop_circle_outlined : Icons.play_arrow,
              ),
              label: Text(
                busy
                    ? '正在加载 · 停止'
                    : active
                    ? '停止播放'
                    : '播放录音',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _duration(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
