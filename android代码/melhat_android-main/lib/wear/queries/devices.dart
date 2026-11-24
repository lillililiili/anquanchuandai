import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core.dart';
import '../device_location.dart';
import '../device_features.dart';
import 'belt_telemetry.dart';
import 'device_local_operations.dart';
import 'split_helmet_telemetry.dart';
import 'query_utils.dart';
import 'query_widgets.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final _sn = TextEditingController();
  WearSession? _session;
  List<JsonMap> _records = const [];
  int _current = 1;
  int _total = 0;
  bool _hasMore = false;
  bool _loading = true;
  Object? _error;
  String? _typeCode;
  String? _relation;
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

  @override
  void dispose() {
    _sn.dispose();
    super.dispose();
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
        '/api/v1/devices',
        current: page,
        size: 20,
        query: {
          if (_sn.text.trim().isNotEmpty) 'sn': _sn.text.trim(),
          if (_typeCode != null) 'typeCode': _typeCode,
          if (_relation != null) 'relation': _relation,
        },
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
      title: '设备台账',
      subtitle: '领用状态来自当前领用记录。连接、电量和定位来自设备上报，未知或过期会标明。',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _sn,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(page: 1),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '按设备 SN 搜索',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip(
                          '全部类型',
                          _typeCode == null,
                          () => _setType(null),
                        ),
                        _filterChip(
                          '安全帽',
                          _typeCode == 'helmet',
                          () => _setType('helmet'),
                        ),
                        _filterChip(
                          '安全带',
                          _typeCode == 'belt',
                          () => _setType('belt'),
                        ),
                        if (_session?.simulatedWatchVisible != false)
                          _filterChip(
                            '模拟手表',
                            _typeCode == 'watch',
                            () => _setType('watch'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  tooltip: '领用状态',
                  initialValue: _relation,
                  onSelected: _setRelation,
                  itemBuilder: (_) => [
                    for (final status in deviceRelationLabels.entries)
                      PopupMenuItem(
                        value: status.key,
                        child: Text(status.value),
                      ),
                  ],
                  child: Chip(
                    label: Text(deviceRelationLabels[_relation] ?? '领用状态'),
                    onDeleted: _relation == null
                        ? null
                        : () => _setRelation(null),
                    deleteButtonTooltipMessage: '清除领用状态筛选',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: QueryStateView(
              loading: _loading,
              error: _error,
              empty: _records.isEmpty,
              onRetry: () => _load(page: _current),
              emptyTitle: _relation == null
                  ? '没有符合条件的设备'
                  : '当前筛选条件下没有「${deviceRelationLabels[_relation]}」设备',
              child: RefreshIndicator(
                onRefresh: () => _load(page: _current),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  itemCount: _records.length,
                  itemBuilder: (context, index) {
                    final device = _records[index];
                    final quality = connectionLabel(device);
                    final qualityColor = switch (device['connectionQuality']
                        ?.toString()) {
                      'ok' => WearColors.primary,
                      'stale' => WearColors.warning,
                      _ => WearColors.muted,
                    };
                    return QueryRow(
                      key: ValueKey('device-${idOf(device['id'])}'),
                      title: textOf(device['sn']),
                      subtitle:
                          '${deviceTypeLabel(device['typeCode'])} · ${textOf(device['modelName'])}\n${deviceRelationLabels[device['relation']] ?? '—'} · 电量 ${batteryLabel(device['battery'])}',
                      leading: Icon(
                        device['typeCode'] == 'belt'
                            ? Icons.safety_check
                            : Icons.engineering_outlined,
                      ),
                      trailing: WearBadge(text: quality, color: qualityColor),
                      onTap: () =>
                          context.push('/devices/${idOf(device['id'])}'),
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

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: FilterChip(
        label: Text(label),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }

  void _setType(String? value) {
    setState(() => _typeCode = value);
    _load(page: 1);
  }

  void _setRelation(String? value) {
    setState(() => _relation = value);
    _load(page: 1);
  }
}

class DevicePage extends StatefulWidget {
  const DevicePage({super.key, required this.id});

  final String id;

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  WearSession? _session;
  JsonMap? _device;
  List<JsonMap> _history = const [];
  bool _loading = true;
  Object? _error;
  int _request = 0;
  Timer? _telemetryTimer;
  @override
  void didUpdateWidget(covariant DevicePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _device = null;
      _history = const [];
      _load();
    }
  }

  @override
  void initState() {
    super.initState();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted &&
          !_loading &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused) {
        _load(quiet: true);
      }
    });
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (!identical(session, _session)) {
      _session = session;
      _load();
    }
  }

  Future<void> _load({bool quiet = false}) async {
    final session = _session;
    if (session == null) return;
    final request = ++_request;
    final scopeKey = session.scopeKey;
    setState(() {
      _loading = !quiet || _device == null;
      _error = null;
    });
    try {
      final responses = await Future.wait([
        session.api.get('/api/v1/devices/${widget.id}'),
        session.isAdmin
            ? session.api.get('/api/v1/devices/${widget.id}/assignments')
            : Future.value(<JsonMap>[]),
      ]);
      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _device = jsonMap(responses[0]);
        _history = jsonList(responses[1]);
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
    final device = _device;
    final location = deviceLocation(device ?? {});
    return QueryPage(
      title: device == null ? '设备详情' : textOf(device['sn']),
      body: QueryStateView(
        loading: _loading,
        error: _error,
        empty: device == null,
        onRetry: _load,
        child: device == null
            ? const SizedBox.shrink()
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    WearCard(
                      child: Column(
                        children: [
                          DetailField(
                            label: '设备类型',
                            value: deviceTypeLabel(device['typeCode']),
                          ),
                          DetailField(
                            label: '产品型号',
                            value: textOf(device['modelName']),
                          ),
                          DetailField(
                            label: '所在厂站',
                            value: textOf(device['siteName']),
                          ),
                          DetailField(
                            label: '领用状态',
                            value:
                                deviceRelationLabels[device['relation']] ?? '—',
                          ),
                          DetailField(
                            label: '连接状态',
                            value: connectionLabel(device),
                          ),
                          if (deviceFeature(device, 'battery').supported)
                            DetailField(
                              label: deviceFeatureLabel(device, 'battery'),
                              value: batteryLabel(device['battery']),
                            ),
                          DetailField(
                            label: '最后上报',
                            value: formatTime(device['lastReportedAt']),
                          ),
                          if (deviceFeature(device, 'location').supported) ...[
                            DetailField(
                              label: '设备上报位置',
                              value: location.position,
                            ),
                            DetailField(
                              label: '位置上报状态',
                              value: location.status,
                            ),
                            DetailField(
                              label: '位置上报时间',
                              value: location.reportedAt == null
                                  ? '未收到'
                                  : formatTime(location.reportedAt),
                            ),
                            const Text(
                              '位置上报时间是平台接收时间；重复上报的坐标不代表设备重新完成定位。',
                              style: TextStyle(color: WearColors.muted),
                            ),
                          ],
                          if (device['demo'] == true)
                            const DetailField(label: '数据标识', value: '演示数据'),
                        ],
                      ),
                    ),
                    if (device['source'] == 'DIRECT_BELT') ...[
                      const SizedBox(height: 18),
                      BeltTelemetryPanel(device: device),
                    ],
                    if (device['source'] == 'SPLIT_HELMET') ...[
                      const SizedBox(height: 18),
                      SplitHelmetTelemetryPanel(device: device),
                    ],
                    if (localDeviceProfile(device) != null) ...[
                      const SizedBox(height: 18),
                      DeviceLocalControlsHelp(device: device),
                    ],
                    if (_session!.isAdmin) ...[
                      const SizedBox(height: 18),
                      QuerySection(
                        title: '历史领用记录（${_history.length}）',
                        children: _history
                            .map(
                              (item) => QueryRow(
                                title: textOf(item['personName'], '未关联人员'),
                                subtitle:
                                    '${formatTime(item['issuedAt'])} 至 ${item['returnedAt'] == null ? '当前' : formatTime(item['returnedAt'])}',
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
