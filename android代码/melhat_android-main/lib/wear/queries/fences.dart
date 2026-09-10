import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../core.dart';
import 'query_widgets.dart';

class FencesPage extends StatefulWidget {
  const FencesPage({super.key});

  @override
  State<FencesPage> createState() => _FencesPageState();
}

class _FencesPageState extends State<FencesPage> {
  WearSession? _session;
  List<JsonMap> _records = const [];
  int _current = 1;
  int _total = 0;
  bool _hasMore = false;
  bool _loading = true;
  Object? _error;
  int _request = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (!identical(session, _session)) {
      _session = session;
      _load(page: 1);
    }
  }

  Future<void> _load({required int page}) async {
    final session = _session;
    if (session == null) return;
    final request = ++_request;
    final scopeKey = session.scopeKey;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await session.api.page(
        '/api/v1/fences',
        current: page,
        size: 20,
      );
      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _records = result.records;
        _current = result.current;
        _total = result.total;
        _hasMore = result.hasMore;
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
      title: '电子围栏',
      subtitle: '只读查看平台围栏规则；禁用围栏仍保留历史事件。',
      body: Column(
        children: [
          Expanded(
            child: QueryStateView(
              loading: _loading,
              error: _error,
              empty: _records.isEmpty,
              onRetry: () => _load(page: _current),
              emptyTitle: '暂无电子围栏',
              child: RefreshIndicator(
                onRefresh: () => _load(page: _current),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _records.length,
                  itemBuilder: (context, index) {
                    final fence = _records[index];
                    final enabled = fence['enabled'] == true;
                    final people = fence['applyMode']?.toString() == 'persons'
                        ? '指定 ${jsonListIds(fence['personIds']).length} 人'
                        : '全厂站';
                    return QueryRow(
                      key: ValueKey('fence-${idOf(fence['id'])}'),
                      title: textOf(fence['name']),
                      subtitle:
                          '$people · 规则版本 ${textOf(fence['ruleVersion'])}',
                      trailing: WearBadge(
                        text: enabled ? '启用' : '停用',
                        color: enabled ? WearColors.primary : WearColors.muted,
                      ),
                      onTap: () => context.push('/fences/${idOf(fence['id'])}'),
                    );
                  },
                ),
              ),
            ),
          ),
          PagingFooter(
            current: _current,
            total: _total,
            hasMore: _hasMore,
            busy: _loading,
            onPrevious: () => _load(page: _current - 1),
            onNext: () => _load(page: _current + 1),
          ),
        ],
      ),
    );
  }
}

List<String> jsonListIds(Object? value) {
  if (value is! List) return const [];
  return value.map(idOf).where((id) => id.isNotEmpty).toList();
}

class FencePage extends StatefulWidget {
  const FencePage({super.key, required this.id});

  final String id;

  @override
  State<FencePage> createState() => _FencePageState();
}

class _FencePageState extends State<FencePage> {
  WearSession? _session;
  JsonMap? _fence;
  bool _loading = true;
  Object? _error;
  int _request = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (!identical(session, _session)) {
      _session = session;
      _load();
    }
  }

  Future<void> _load() async {
    final session = _session;
    if (session == null) return;
    final request = ++_request;
    final scopeKey = session.scopeKey;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = jsonMap(
        await session.api.get('/api/v1/fences/${widget.id}'),
      );
      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _fence = result;
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
    final fence = _fence;
    final points = fence == null
        ? const <LatLng>[]
        : _polygon(fence['polygon']);
    return QueryPage(
      title: fence == null ? '围栏详情' : textOf(fence['name']),
      body: QueryStateView(
        loading: _loading,
        error: _error,
        empty: fence == null,
        onRetry: _load,
        child: fence == null
            ? const SizedBox.shrink()
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SizedBox(
                      height: 260,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: points.length < 3
                            ? const WearEmpty(title: '围栏坐标不完整')
                            : FlutterMap(
                                options: MapOptions(
                                  initialCenter: points.first,
                                  initialZoom: 15,
                                  initialCameraFit: CameraFit.bounds(
                                    bounds: LatLngBounds.fromPoints(points),
                                    padding: const EdgeInsets.all(28),
                                  ),
                                  interactionOptions: const InteractionOptions(
                                    flags:
                                        InteractiveFlag.pinchZoom |
                                        InteractiveFlag.drag,
                                  ),
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName:
                                        'rolling_intelligence_headband',
                                  ),
                                  PolygonLayer(
                                    polygons: [
                                      Polygon(
                                        points: points,
                                        color: WearColors.primary.withValues(
                                          alpha: .18,
                                        ),
                                        borderColor: WearColors.primary,
                                        borderStrokeWidth: 3,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    WearCard(
                      child: Column(
                        children: [
                          DetailField(
                            label: '状态',
                            value: fence['enabled'] == true ? '启用' : '停用',
                          ),
                          DetailField(
                            label: '适用范围',
                            value: fence['applyMode'] == 'persons'
                                ? '指定人员'
                                : '全厂站',
                          ),
                          DetailField(label: '生效时段', value: _timeWindow(fence)),
                          DetailField(label: '触发方向', value: _direction(fence)),
                          DetailField(
                            label: '防抖时间',
                            value: '${intOf(fence['debounceSeconds'])} 秒',
                          ),
                          DetailField(
                            label: '规则版本',
                            value: textOf(fence['ruleVersion']),
                          ),
                          if (fence['demo'] == true)
                            const DetailField(label: '数据标识', value: '演示围栏'),
                        ],
                      ),
                    ),
                    if (fence['applyMode'] == 'persons') ...[
                      const SizedBox(height: 18),
                      QuerySection(
                        title: '适用人员',
                        children: jsonListIds(fence['personIds']).isEmpty
                            ? [
                                const WearCard(
                                  child: Text(
                                    '未配置人员',
                                    style: TextStyle(color: WearColors.muted),
                                  ),
                                ),
                              ]
                            : jsonListIds(fence['personIds'])
                                  .map(
                                    (id) => QueryRow(
                                      title: '人员 ID $id',
                                      onTap: () => context.push('/people/$id'),
                                    ),
                                  )
                                  .toList(),
                      ),
                    ],
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/events?type=geofence'),
                      icon: const Icon(Icons.history),
                      label: const Text('查看围栏事件'),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        '事件接口支持按围栏类型筛选；进入后可核对围栏名称与规则版本。',
                        style: TextStyle(color: WearColors.muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  List<LatLng> _polygon(Object? value) {
    return jsonList(value)
        .map((point) {
          final lat = double.tryParse(point['lat']?.toString() ?? '');
          final lng = double.tryParse(point['lng']?.toString() ?? '');
          return lat == null || lng == null ? null : LatLng(lat, lng);
        })
        .whereType<LatLng>()
        .toList();
  }

  String _timeWindow(JsonMap fence) {
    if (fence['timeStart'] == null && fence['timeEnd'] == null) return '全天';
    return '${textOf(fence['timeStart'], '00:00')}–${textOf(fence['timeEnd'], '24:00')}';
  }

  String _direction(JsonMap fence) {
    final values = <String>[];
    if (fence['enterEnabled'] == true) values.add('进入');
    if (fence['leaveEnabled'] == true) values.add('离开');
    return values.isEmpty ? '未启用' : values.join('、');
  }
}
