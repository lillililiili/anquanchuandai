import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../core.dart';
import 'query_widgets.dart';

/// Only a server-selected primary location is shown for each person.
class PersonLocationPanel extends StatefulWidget {
  const PersonLocationPanel({
    super.key,
    required this.personId,
    this.expanded = false,
  });
  final String personId;
  final bool expanded;

  @override
  State<PersonLocationPanel> createState() => _PersonLocationPanelState();
}

class _PersonLocationPanelState extends State<PersonLocationPanel> {
  WearSession? _session;
  JsonMap? _location;
  bool _loading = true;
  Object? _error;
  int _request = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (_session != session) {
      _session = session;
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant PersonLocationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.personId != widget.personId) _load();
  }

  Future<void> _load() async {
    final session = _session!;
    final scope = session.scopeKey;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = jsonMap(
        await session.api.get('/api/v1/locations/people/${widget.personId}'),
      );
      if (!mounted || request != _request || scope != session.scopeKey) return;
      setState(() {
        _location = value;
        _loading = false;
      });
    } catch (error) {
      if (!mounted ||
          error is StaleSessionException ||
          request != _request ||
          scope != session.scopeKey) {
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
    final location = _location ?? const <String, dynamic>{};
    final lat = double.tryParse(location['lat']?.toString() ?? '');
    final lng = double.tryParse(location['lng']?.toString() ?? '');
    final hasCoordinates =
        lat != null &&
        lng != null &&
        lat.isFinite &&
        lng.isFinite &&
        lat.abs() <= 90 &&
        lng.abs() <= 180;
    final quality = switch (location['locationQuality']) {
      'ok' => '定位可信',
      'stale' => '位置数据陈旧',
      _ => '位置质量未知',
    };
    final source = switch (location['source']) {
      'helmet' => '安全帽 GNSS',
      'none' || null => '暂无定位来源',
      final value => textOf(value),
    };
    final floor = textOf(location['floor'], '');
    return QuerySection(
      title: '人员位置',
      children: [
        QueryStateView(
          loading: _loading,
          error: _error,
          empty: false,
          onRetry: _load,
          child: WearCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (location['demo'] == true)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('演示位置 · 非生产依据'),
                  ),
                Text(quality, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                DetailField(
                  label: '区域',
                  value: textOf(location['regionName'], '区域未知'),
                ),
                DetailField(
                  label: '楼层',
                  value: floor.isEmpty || floor == 'unknown' ? '楼层未知' : floor,
                ),
                DetailField(label: '位置来源', value: source),
                DetailField(
                  label: '更新时间',
                  value: formatTime(location['occurredAt']),
                ),
                if (widget.expanded) ...[
                  DetailField(
                    label: '定位装备',
                    value: textOf(location['sn'], '未知'),
                  ),
                  DetailField(
                    label: '楼层来源',
                    value: location['floorSource'] == 'unknown'
                        ? '未知'
                        : textOf(location['floorSource'], '未知'),
                  ),
                  DetailField(
                    label: '精度',
                    value: textOf(location['accuracy'], '精度未知'),
                  ),
                  const SizedBox(height: 16),
                  if (hasCoordinates) ...[
                    SizedBox(
                      height: 250,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: FlutterMap(
                          options: MapOptions(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            initialCenter: LatLng(lat, lng),
                            initialZoom: 16,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName:
                                  'rolling_intelligence_headband',
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: LatLng(lat, lng),
                                  child: Icon(
                                    Icons.location_on,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    size: 40,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '经纬度 $lat, $lng · WGS84\n© OpenStreetMap contributors',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ] else
                    const WearEmpty(
                      title: '暂无有效位置坐标',
                      detail: '等待可用位置上报，区域与楼层未知。',
                    ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => context.push(
                      '/tracks?personId=${Uri.encodeComponent(widget.personId)}',
                    ),
                    icon: const Icon(Icons.route_outlined),
                    label: const Text('查看人员轨迹'),
                  ),
                  TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新位置'),
                  ),
                ] else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  PersonLocationPage(personId: widget.personId),
                            ),
                          ),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('查看位置与轨迹'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class PersonLocationPage extends StatelessWidget {
  const PersonLocationPage({super.key, required this.personId});
  final String personId;
  @override
  Widget build(BuildContext context) => QueryPage(
    title: '人员位置',
    subtitle: '查看该人员的最近位置和历史轨迹。',
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [PersonLocationPanel(personId: personId, expanded: true)],
    ),
  );
}
