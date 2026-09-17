import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core.dart';
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
  String? _assetStatus;
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
          if (_assetStatus != null) 'assetStatus': _assetStatus,
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
      title: '按设备查找',
      subtitle: '通过装备查找持有人，确认当前可用通讯能力。',
      body: Column(
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _filterChip('全部类型', _typeCode == null, () => _setType(null)),
                _filterChip(
                  '安全帽',
                  _typeCode == 'helmet',
                  () => _setType('helmet'),
                ),
                _filterChip('安全带', _typeCode == 'belt', () => _setType('belt')),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: '资产状态',
                  initialValue: _assetStatus ?? '',
                  onSelected: (value) {
                    setState(() => _assetStatus = value.isEmpty ? null : value);
                    _load(page: 1);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: '', child: Text('全部资产状态')),
                    PopupMenuItem(value: 'unassigned', child: Text('未分配')),
                    PopupMenuItem(value: 'in_stock', child: Text('在库')),
                    PopupMenuItem(value: 'maintenance', child: Text('维修中')),
                    PopupMenuItem(value: 'disabled', child: Text('已停用')),
                    PopupMenuItem(value: 'scrapped', child: Text('已报废')),
                  ],
                  child: Chip(
                    label: Text(
                      _assetStatus == null
                          ? '资产状态'
                          : assetStatusLabel(_assetStatus),
                    ),
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
              emptyTitle: '没有符合条件的设备',
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
                      _ => Theme.of(context).colorScheme.onSurfaceVariant,
                    };
                    return QueryRow(
                      key: ValueKey('device-${idOf(device['id'])}'),
                      title: textOf(device['sn']),
                      subtitle:
                          '${deviceTypeLabel(device['typeCode'])} · ${textOf(device['modelName'])}\n${assetStatusLabel(device['assetStatus'])} · 电量 ${batteryLabel(device['battery'])}',
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }

  void _setType(String? value) {
    setState(() => _typeCode = value);
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
      final responses = await Future.wait([
        session.api.get('/api/v1/devices/${widget.id}'),
        session.api.get('/api/v1/devices/${widget.id}/assignments'),
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
    final assignment = jsonMap(device?['currentAssignment']);
    final wearerId = idOf(assignment['personId']);
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            deviceTypeLabel(device['typeCode']),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '持有人  ${textOf(assignment['personName'], '未关联人员')}',
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              Text(connectionLabel(device)),
                              Text('电量 ${batteryLabel(device['battery'])}'),
                              if (device['demo'] == true) const Text('演示数据'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '上报 ${formatTime(device['lastReportedAt'])}',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (wearerId.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () => context.push(
                              communicationUri(personId: wearerId).toString(),
                            ),
                            icon: const Icon(Icons.person_outline),
                            label: const Text('联系持有人'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.push('/people/$wearerId'),
                            icon: const Icon(Icons.badge_outlined),
                            label: const Text('查看人员与其他装备'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    _actionPanel(context, device),
                    const SizedBox(height: 18),
                    WearCard(
                      padding: EdgeInsets.zero,
                      child: ExpansionTile(
                        title: const Text('更多资料'),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          12,
                        ),
                        children: [
                          DetailField(
                            label: '设备编号',
                            value: textOf(device['sn']),
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
                            label: '资产状态',
                            value: assetStatusLabel(device['assetStatus']),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    QuerySection(
                      title: '历史领用记录（${_history.length}）',
                      children: _history
                          .map(
                            (item) => QueryRow(
                              title: textOf(item['personName'], '未关联人员'),
                              subtitle:
                                  '${formatTime(item['issuedAt'])} 至 ${item['returnedAt'] == null ? '当前' : formatTime(item['returnedAt'])}',
                              onTap: item['personId'] == null
                                  ? null
                                  : () => context.push(
                                      '/people/${textOf(item['personId'])}',
                                    ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _actionPanel(BuildContext context, JsonMap device) {
    final actions = deviceActions(device);
    final assignment = jsonMap(device['currentAssignment']);
    final personId = assignment['personId']?.toString();
    final buttons = <Widget>[];
    if (actions.contains('tts')) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: () => _openCommunications(
            context,
            device,
            personId: personId,
            intent: 'tts',
          ),
          icon: Icon(Icons.campaign_outlined),
          label: Text('文字播报'),
        ),
      );
    }
    if (actions.contains('intercom')) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: () =>
              _openCommunications(context, device, personId: personId),
          icon: Icon(Icons.call_outlined),
          label: Text('语音通话'),
        ),
      );
    }
    if (actions.contains('video')) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: () => _openCommunications(
            context,
            device,
            personId: personId,
            video: true,
          ),
          icon: Icon(Icons.videocam_outlined),
          label: Text('视频'),
        ),
      );
    }
    return QuerySection(
      title: '设备能力',
      children: [
        if (buttons.isEmpty)
          WearCard(
            child: Text(
              '该装备未声明通讯能力，可通过已关联的持有人选择其他终端。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          Wrap(spacing: 8, runSpacing: 8, children: buttons),
        if (stringValues(
          jsonMap(device['capabilities'])['attributes'],
        ).isNotEmpty) ...[
          const SizedBox(height: 12),
          WearCard(
            child: Column(
              children: [
                for (final attribute in stringValues(
                  jsonMap(device['capabilities'])['attributes'],
                ))
                  DetailField(
                    label: _attributeLabel(attribute),
                    value: switch (attribute) {
                      'battery' => batteryLabel(device['battery']),
                      'online' => connectionLabel(device),
                      'location' ||
                      'gnss' => switch (device['locationQuality']) {
                        'ok' => '定位可信',
                        'stale' => '定位陈旧',
                        _ => '定位质量未知',
                      },
                      _ => '状态未知',
                    },
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _attributeLabel(String attribute) =>
      const {
        'battery': '电量能力',
        'location': '定位能力',
        'gnss': '卫星定位',
        'hook': '挂钩',
        'hookState': '挂钩',
        'buckle': '带扣',
        'buckleState': '带扣',
        'gas': '气体检测',
        'temperature': '温度',
        'online': '在线检测',
      }[attribute] ??
      attribute;

  void _openCommunications(
    BuildContext context,
    JsonMap device, {
    String? personId,
    bool video = false,
    String intent = 'voice',
  }) {
    final uri = Uri(
      path: '/communications',
      queryParameters: {
        'deviceId': widget.id,
        'intent': video ? 'video' : intent,
        if (personId != null && personId.isNotEmpty) 'personId': personId,
        if (video) 'video': '1',
      },
    );
    context.push(uri.toString());
  }
}
