import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core.dart';
import 'query_utils.dart';
import 'query_widgets.dart';

class TracksPage extends StatefulWidget {
  const TracksPage({super.key, this.personId});

  final String? personId;

  @override
  State<TracksPage> createState() => _TracksPageState();
}

class _TracksPageState extends State<TracksPage> {
  final _search = TextEditingController();
  WearSession? _session;
  JsonMap? _person;
  List<JsonMap> _people = const [];
  List<JsonMap> _points = const [];
  DateTime _from = _startOfDay(DateTime.now());
  DateTime _to = _endOfDay(DateTime.now());
  int _index = 0;
  double _speed = 1;
  bool _playing = false;
  bool _loading = false;
  bool _searching = false;
  Object? _error;
  Object? _searchError;
  Timer? _timer;
  int _request = 0;
  int _searchRequest = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (!identical(session, _session)) {
      _session = session;
      if (widget.personId != null && widget.personId!.isNotEmpty) {
        _selectById(widget.personId!);
      } else {
        _findPeople();
      }
    }
  }

  @override
  void didUpdateWidget(covariant TracksPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.personId != widget.personId && widget.personId != null) {
      _selectById(widget.personId!);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _selectById(String id) async {
    final session = _session;
    if (session == null) return;
    final request = ++_searchRequest;
    final scopeKey = session.scopeKey;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final person = jsonMap(await session.api.get('/api/v1/people/$id'));
      if (!mounted ||
          request != _searchRequest ||
          scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _person = person;
        _people = const [];
        _search.text = textOf(person['name'], '');
        _searching = false;
      });
      await _loadTracks();
    } catch (error) {
      if (error is StaleSessionException) return;
      if (!mounted ||
          request != _searchRequest ||
          scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _searchError = error;
        _searching = false;
      });
    }
  }

  Future<void> _findPeople() async {
    final session = _session;
    if (session == null) return;
    final request = ++_searchRequest;
    final scopeKey = session.scopeKey;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final page = await session.api.page(
        '/api/v1/people',
        current: 1,
        size: 100,
        query: {
          if (_search.text.trim().isNotEmpty) 'name': _search.text.trim(),
        },
      );
      if (!mounted ||
          request != _searchRequest ||
          scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _people = page.records;
        _searching = false;
      });
    } catch (error) {
      if (error is StaleSessionException) return;
      if (!mounted ||
          request != _searchRequest ||
          scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _searchError = error;
        _searching = false;
      });
    }
  }

  Future<void> _loadTracks() async {
    final session = _session;
    final person = _person;
    if (session == null || person == null) return;
    _stop();
    final request = ++_request;
    final scopeKey = session.scopeKey;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loaded = <JsonMap>[];
      var pageNumber = 1;
      var expectedTotal = 0;
      while (loaded.length < 500) {
        final page = await session.api.page(
          '/api/v1/locations/people/${idOf(person['id'])}/tracks',
          current: pageNumber,
          size: 100,
          query: {
            'from': _from.toUtc().toIso8601String(),
            'to': _to.toUtc().toIso8601String(),
          },
        );
        if (!mounted || request != _request || scopeKey != session.scopeKey) {
          return;
        }
        expectedTotal = page.total.clamp(0, 500);
        loaded.addAll(page.records.take(500 - loaded.length));
        if (!page.hasMore ||
            loaded.length >= expectedTotal ||
            page.records.isEmpty) {
          break;
        }
        pageNumber++;
      }
      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _points = loaded;
        _index = 0;
        _loading = false;
      });
    } catch (error) {
      if (error is StaleSessionException) return;
      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return QueryPage(
      title: '轨迹回放',
      subtitle: '安全帽 GNSS 轨迹 · WGS84 · 服务端最多抽稀为 500 点',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _findPeople(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.person_search_outlined),
                hintText: '按姓名搜索人员（含历史有效人员）',
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        onPressed: _findPeople,
                        icon: const Icon(Icons.search),
                      ),
              ),
            ),
          ),
          if (_searchError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: WearEmpty(
                title: '人员加载失败',
                detail: _searchError is WearApiException
                    ? (_searchError as WearApiException).message
                    : null,
                onRetry: _findPeople,
              ),
            ),
          if (_people.isNotEmpty &&
              (_person == null ||
                  _search.text.trim() != textOf(_person!['name'], '')))
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _people.length,
                itemBuilder: (context, index) {
                  final person = _people[index];
                  return QueryRow(
                    title: textOf(person['name']),
                    subtitle:
                        '${textOf(person['personCode'])} · ${person['status'] == '0' ? '在职' : '历史人员'}',
                    onTap: () {
                      setState(() {
                        _person = person;
                        _people = const [];
                        _search.text = textOf(person['name'], '');
                      });
                      _loadTracks();
                    },
                  );
                },
              ),
            ),
          if (_person != null) _filters(context),
          Expanded(
            child: _person == null
                ? const WearEmpty(
                    title: '请先选择人员',
                    detail: '轨迹按人员稳定 ID 查询，与登录账号无关。',
                  )
                : QueryStateView(
                    loading: _loading,
                    error: _error,
                    empty: _points.isEmpty,
                    onRetry: _loadTracks,
                    emptyTitle: '该时段没有轨迹点',
                    emptyDetail: '人员没有有效安全帽领用或该时段没有 GNSS 样本。',
                    child: _trackBody(context),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filters(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 10),
      child: WearCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () => _pickDate(from: true),
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(_day(_from)),
              ),
            ),
            const Text('至', style: TextStyle(color: WearColors.muted)),
            Expanded(
              child: TextButton.icon(
                onPressed: () => _pickDate(from: false),
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(_day(_to)),
              ),
            ),
            IconButton(
              onPressed: _loading ? null : _loadTracks,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trackBody(BuildContext context) {
    final latLngs = _validPoints(_points);
    final current = _points[_index.clamp(0, _points.length - 1)];
    final currentLat = double.tryParse(current['lat']?.toString() ?? '');
    final currentLng = double.tryParse(current['lng']?.toString() ?? '');
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: latLngs.isEmpty
                  ? const WearEmpty(title: '轨迹坐标无效', detail: '服务返回的轨迹点缺少有效经纬度。')
                  : FlutterMap(
                      key: ValueKey(
                        '${idOf(_person?['id'])}-${_points.length}-${_from.millisecondsSinceEpoch}-${_to.millisecondsSinceEpoch}',
                      ),
                      options: MapOptions(
                        initialCenter: latLngs.first,
                        initialZoom: 16,
                        initialCameraFit: latLngs.length > 1
                            ? CameraFit.bounds(
                                bounds: LatLngBounds.fromPoints(latLngs),
                                padding: const EdgeInsets.all(34),
                              )
                            : null,
                        interactionOptions: const InteractionOptions(
                          flags:
                              InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'rolling_intelligence_headband',
                        ),
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: latLngs,
                              color: WearColors.primary,
                              strokeWidth: 4,
                            ),
                          ],
                        ),
                        if (currentLat != null && currentLng != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: LatLng(currentLat, currentLng),
                                width: 44,
                                height: 44,
                                child: const Icon(
                                  Icons.location_on,
                                  size: 42,
                                  color: WearColors.danger,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: WearCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: _togglePlayback,
                      icon: Icon(
                        _playing
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                        size: 36,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: _index.toDouble(),
                        min: 0,
                        max: (_points.length - 1).toDouble(),
                        divisions: _points.length > 1
                            ? _points.length - 1
                            : null,
                        onChanged: (value) {
                          _stop();
                          setState(() => _index = value.round());
                        },
                      ),
                    ),
                    Text('${_index + 1}/${_points.length}'),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${formatTime(current['occurredAt'])} · ${_qualityLabel(current['locationQuality'])}',
                        style: const TextStyle(
                          color: WearColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _seekTime,
                      icon: const Icon(Icons.schedule, size: 17),
                      label: const Text('定位时间'),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final speed in const [0.5, 1.0, 2.0, 5.0])
                      ChoiceChip(
                        label: Text(
                          '${speed == speed.roundToDouble() ? speed.toInt() : speed}x',
                        ),
                        selected: _speed == speed,
                        onSelected: (_) {
                          setState(() => _speed = speed);
                          if (_playing) _startTimer();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate({required bool from}) async {
    final initial = from ? _from : _to;
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (value == null || !mounted) return;
    final nextFrom = from ? _startOfDay(value) : _from;
    final nextTo = from ? _to : _endOfDay(value);
    if (nextTo.isBefore(nextFrom)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('结束日期不能早于开始日期')));
      return;
    }
    setState(() {
      _from = nextFrom;
      _to = nextTo;
    });
    _loadTracks();
  }

  Future<void> _seekTime() async {
    final current =
        DateTime.tryParse(
          _points[_index]['occurredAt']?.toString() ?? '',
        )?.toLocal() ??
        _from;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: _from,
      lastDate: _to,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    final target = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final index = nearestPointIndex(_points, target);
    if (index >= 0) {
      _stop();
      setState(() => _index = index);
    }
  }

  void _togglePlayback() {
    if (_playing) {
      _stop();
      return;
    }
    if (_index >= _points.length - 1) setState(() => _index = 0);
    setState(() => _playing = true);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: (850 / _speed).round()), (
      _,
    ) {
      if (!mounted || _index >= _points.length - 1) {
        _stop();
        return;
      }
      setState(() => _index++);
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (mounted && _playing) setState(() => _playing = false);
  }

  static DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  static DateTime _endOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day, 23, 59, 59, 999);

  String _day(DateTime value) =>
      '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  List<LatLng> _validPoints(List<JsonMap> points) {
    return points
        .map((point) {
          final lat = double.tryParse(point['lat']?.toString() ?? '');
          final lng = double.tryParse(point['lng']?.toString() ?? '');
          return lat == null || lng == null ? null : LatLng(lat, lng);
        })
        .whereType<LatLng>()
        .toList();
  }

  String _qualityLabel(Object? value) => switch (value?.toString()) {
    'ok' => '定位可信',
    'stale' => '定位陈旧',
    _ => '定位质量未知',
  };
}
