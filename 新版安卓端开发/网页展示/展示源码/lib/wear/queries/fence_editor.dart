import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core.dart';
import 'backend_tiles.dart';
import 'management_widgets.dart';
import 'query_widgets.dart';

class FenceEditorPage extends StatefulWidget {
  const FenceEditorPage({super.key, this.id});
  final String? id;
  @override
  State<FenceEditorPage> createState() => _FenceEditorPageState();
}

class _FenceEditorPageState extends State<FenceEditorPage> {
  final _map = MapController();
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _debounce = TextEditingController(text: '60');
  final _lat = TextEditingController(),
      _lng = TextEditingController(),
      _search = TextEditingController();
  WearSession? _session;
  List<LatLng> _points = [];
  List<JsonMap> _people = [];
  Set<String> _personIds = {};
  bool _loading = true,
      _busy = false,
      _enabled = true,
      _enter = true,
      _leave = true,
      _persons = false;
  bool _failedTiles = false, _drawing = true;
  int? _selected;
  int _version = 1, _retry = 0;
  String? _start, _end;
  Object? _error;
  LatLng _center = const LatLng(31.2304, 121.4737);
  bool _hasKnownCenter = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session == null) {
      _session = WearScope.of(context);
      _load();
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _debounce, _lat, _lng, _search]) {
      c.dispose();
    }
    _map.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = _session!.api;
      final fence = widget.id == null
          ? <String, dynamic>{}
          : jsonMap(await api.get('/api/v1/fences/${widget.id}'));
      final people = <JsonMap>[];
      for (var page = 1; ; page++) {
        final result = await api.page(
          '/api/v1/people',
          size: 100,
          current: page,
        );
        people.addAll(result.records);
        if (!result.hasMore) break;
      }
      if (!mounted) return;
      _people = people;
      _name.text = fence['name']?.toString() ?? '';
      _points = jsonList(fence['polygon'])
          .map(
            (p) => LatLng(
              (p['lat'] as num).toDouble(),
              (p['lng'] as num).toDouble(),
            ),
          )
          .toList();
      if (_points.isNotEmpty) {
        _center = _points.first;
        _hasKnownCenter = true;
      }
      _lat.text = _center.latitude.toStringAsFixed(6);
      _lng.text = _center.longitude.toStringAsFixed(6);
      _personIds = (fence['personIds'] as List? ?? []).map(idOf).toSet();
      _persons = fence['applyMode'] == 'persons';
      _enabled = fence['enabled'] != false;
      _enter = fence['enterEnabled'] != false;
      _leave = fence['leaveEnabled'] != false;
      _start = fence['timeStart']?.toString();
      _end = fence['timeEnd']?.toString();
      _version = intOf(fence['version'], 1);
      _debounce.text = '${intOf(fence['debounceSeconds'], 60)}';
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_points.length < 3 ||
        !_enter && !_leave ||
        _persons && _personIds.isEmpty ||
        (_start == null) != (_end == null)) {
      managementMessage(context, '请圈选至少三个点，选择触发方向，并完整填写适用人员和时段');
      return;
    }
    final debounce = int.tryParse(_debounce.text);
    if (debounce == null || debounce < 0 || debounce > 86400) {
      managementMessage(context, '防抖时间请输入 0–86400 秒');
      return;
    }
    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{
        'name': _name.text.trim(),
        'polygon': [
          for (final p in _points) {'lat': p.latitude, 'lng': p.longitude},
        ],
        'enabled': _enabled,
        'applyMode': _persons ? 'persons' : 'all_site',
        'personIds': _persons ? _personIds.toList() : [],
        'timeStart': _start,
        'timeEnd': _end,
        'enterEnabled': _enter,
        'leaveEnabled': _leave,
        'debounceSeconds': debounce,
        'version': _version,
      };
      if (widget.id == null) {
        await _session!.api.post('/api/v1/fences', data: body);
      } else {
        await _session!.api.put('/api/v1/fences/${widget.id}', data: body);
      }
      if (mounted) {
        managementMessage(context, '围栏已保存到主系统');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) managementMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _point(LatLng point) {
    if (!_drawing || _busy) return;
    setState(() {
      if (_selected != null) {
        _points[_selected!] = point;
        _selected = null;
      } else {
        _points.add(point);
      }
    });
  }

  Future<void> _time(bool start) async {
    final result = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        final value =
            '${result.hour.toString().padLeft(2, '0')}:${result.minute.toString().padLeft(2, '0')}';
        if (start) {
          _start = value;
        } else {
          _end = value;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => QueryPage(
    title: widget.id == null ? '新增围栏' : '编辑围栏',
    body: QueryStateView(
      loading: _loading,
      error: _error,
      empty: false,
      onRetry: _load,
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ManagementSection(
              title: '地图圈地 · ${_points.length} 个顶点',
              children: [
                Text(
                  _selected == null
                      ? '点地图添加顶点；点编号后再点地图可移动该顶点。双指缩放，拖动平移。'
                      : '正在调整第 ${_selected! + 1} 个顶点，请点击新的位置。',
                  style: const TextStyle(color: WearColors.muted, fontSize: 12),
                ),
                if (!_hasKnownCenter)
                  const Text(
                    '尚无围栏定位，底图为浏览起点。请移动地图或输入现场坐标后圈地。',
                    style: TextStyle(color: WearColors.warning, fontSize: 12),
                  ),
                SizedBox(
                  height: 260,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: FlutterMap(
                      mapController: _map,
                      options: MapOptions(
                        initialCenter: _center,
                        initialZoom: 16,
                        minZoom: 3,
                        maxZoom: 19,
                        initialCameraFit: _points.length >= 3
                            ? CameraFit.bounds(
                                bounds: LatLngBounds.fromPoints(_points),
                                padding: const EdgeInsets.all(35),
                              )
                            : null,
                        onTap: (_, p) => _point(p),
                        interactionOptions: const InteractionOptions(
                          flags:
                              InteractiveFlag.drag |
                              InteractiveFlag.pinchZoom |
                              InteractiveFlag.doubleTapZoom,
                        ),
                      ),
                      children: [
                        TileLayer(
                          key: ValueKey(_retry),
                          urlTemplate: '/api/v1/fences/map-tiles/{z}/{x}/{y}',
                          tileProvider: BackendTileProvider(
                            _session!.api,
                            '${_session!.scopeKey}:$_retry',
                          ),
                          errorTileCallback: (_, _, _) {
                            if (!_failedTiles && mounted) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  setState(() => _failedTiles = true);
                                }
                              });
                            }
                          },
                        ),
                        if (_points.length >= 3)
                          PolygonLayer(
                            polygons: [
                              Polygon(
                                points: _points,
                                color: WearColors.brand.withValues(alpha: .18),
                                borderColor: WearColors.brand,
                                borderStrokeWidth: 2,
                              ),
                            ],
                          ),
                        if (_points.length == 2)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: _points,
                                color: WearColors.brand,
                                strokeWidth: 2,
                              ),
                            ],
                          ),
                        MarkerLayer(
                          markers: [
                            for (var i = 0; i < _points.length; i++)
                              Marker(
                                point: _points[i],
                                width: 34,
                                height: 34,
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _selected = _selected == i ? null : i;
                                    _drawing = true;
                                  }),
                                  child: CircleAvatar(
                                    backgroundColor: _selected == i
                                        ? WearColors.warning
                                        : WearColors.brand,
                                    child: Text(
                                      '${i + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const Align(
                          alignment: Alignment.bottomRight,
                          child: ColoredBox(
                            color: Colors.white,
                            child: Text(
                              '© OpenStreetMap contributors',
                              style: TextStyle(fontSize: 9),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_failedTiles)
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '底图加载失败，请重试',
                          style: TextStyle(color: WearColors.warning),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _failedTiles = false;
                          _retry++;
                        }),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('点选'),
                      selected: _drawing,
                      onSelected: (v) => setState(() => _drawing = v),
                    ),
                    ActionChip(
                      label: Text(_selected == null ? '撤销' : '删除顶点'),
                      onPressed: _points.isEmpty
                          ? null
                          : () => setState(() {
                              _points.removeAt(_selected ?? _points.length - 1);
                              _selected = null;
                            }),
                    ),
                    ActionChip(
                      label: const Text('清空'),
                      onPressed: _points.isEmpty
                          ? null
                          : () async {
                              if (await confirmManagement(
                                    context,
                                    '清空顶点？',
                                    '已保存的围栏在再次保存前不会改变。',
                                  ) &&
                                  mounted) {
                                setState(() {
                                  _points.clear();
                                  _selected = null;
                                });
                              }
                            },
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: ManagementField(
                        controller: _lng,
                        label: '经度',
                        keyboard: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ManagementField(
                        controller: _lat,
                        label: '纬度',
                        keyboard: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                      ),
                    ),
                  ],
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    final lat = double.tryParse(_lat.text),
                        lng = double.tryParse(_lng.text);
                    if (lat == null ||
                        lng == null ||
                        !lat.isFinite ||
                        !lng.isFinite ||
                        lat.abs() > 85 ||
                        lng.abs() > 180) {
                      managementMessage(context, '请输入有效坐标（纬度 ±85，经度 ±180）');
                      return;
                    }
                    _map.move(LatLng(lat, lng), 17);
                    setState(() => _hasKnownCenter = true);
                  },
                  icon: const Icon(Icons.my_location),
                  label: const Text('定位到输入坐标'),
                ),
              ],
            ),
            ManagementSection(
              title: '围栏规则',
              children: [
                ManagementField(
                  controller: _name,
                  label: '围栏名称',
                  required: true,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用围栏'),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('进入触发'),
                      selected: _enter,
                      onSelected: (v) => setState(() => _enter = v),
                    ),
                    FilterChip(
                      label: const Text('离开触发'),
                      selected: _leave,
                      onSelected: (v) => setState(() => _leave = v),
                    ),
                  ],
                ),
                ManagementField(
                  controller: _debounce,
                  label: '防抖时间（秒）',
                  keyboard: TextInputType.number,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => _time(true),
                      child: Text('开始 ${_start ?? '不限'}'),
                    ),
                    OutlinedButton(
                      onPressed: () => _time(false),
                      child: Text('结束 ${_end ?? '不限'}'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _start = null;
                        _end = null;
                      }),
                      child: const Text('设为全天'),
                    ),
                  ],
                ),
              ],
            ),
            ManagementSection(
              title: '适用人员',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _persons ? '指定人员 · 已选 ${_personIds.length} 人' : '全厂站人员',
                  ),
                  value: _persons,
                  onChanged: (v) => setState(() => _persons = v),
                ),
                if (_persons) ...[
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: '搜索姓名或人员编号',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  SizedBox(
                    height: 220,
                    child: ListView(
                      children: [
                        for (final p in _people.where(
                          (p) => '${p['name']} ${p['personCode']}'.contains(
                            _search.text.trim(),
                          ),
                        ))
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(textOf(p['name'])),
                            subtitle: Text(textOf(p['personCode'])),
                            value: _personIds.contains(idOf(p['id'])),
                            onChanged: (v) => setState(() {
                              v!
                                  ? _personIds.add(idOf(p['id']))
                                  : _personIds.remove(idOf(p['id']));
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(_busy ? '保存中…' : '保存围栏'),
            ),
          ],
        ),
      ),
    ),
  );
}
