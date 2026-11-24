import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core.dart';
import '../location_map.dart';
import '../person_duty_status.dart';
import 'location_history.dart';
import 'query_utils.dart';
import 'query_widgets.dart';

class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key, this.initialName});

  final String? initialName;

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  final _search = TextEditingController();
  WearSession? _session;
  List<JsonMap> _records = const [];
  int _current = 1;
  int _total = 0;
  bool _hasMore = false;
  bool _loading = true;
  Object? _error;
  PersonDutyStatus? _dutyStatus;
  String _appliedName = '';
  int _request = 0;
  bool _seededInitialName = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_seededInitialName) {
      _search.text = widget.initialName?.trim() ?? '';
      _seededInitialName = true;
    }
    final session = WearScope.of(context);
    if (!identical(session, _session)) {
      _session?.refreshTick.removeListener(_refreshVisible);
      _session = session;
      session.refreshTick.addListener(_refreshVisible);
      _load(page: 1);
    }
  }

  @override
  void didUpdateWidget(covariant PeoplePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialName != widget.initialName) {
      _search.text = widget.initialName?.trim() ?? '';
      _load(page: 1);
    }
  }

  @override
  void dispose() {
    _session?.refreshTick.removeListener(_refreshVisible);
    _search.dispose();
    super.dispose();
  }

  void _refreshVisible() {
    if (!_loading &&
        TickerMode.valuesOf(context).enabled &&
        ModalRoute.of(context)?.isCurrent == true) {
      unawaited(_load(page: _current, background: true));
    }
  }

  void _setDutyStatus(PersonDutyStatus? value) {
    setState(() => _dutyStatus = value);
    _load(page: 1);
  }

  Future<void> _load({required int page, bool background = false}) async {
    final session = _session;
    if (session == null) return;
    final request = ++_request;
    final scopeKey = session.scopeKey;
    if (!background) {
      _appliedName = _search.text.trim();
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await session.api.page(
        '/api/v1/people',
        current: page,
        size: 20,
        query: {
          if (_appliedName.isNotEmpty) 'name': _appliedName,
          if (_dutyStatus != null) 'dutyStatus': _dutyStatus!.code,
        },
      );
      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      if (page > 1 && result.records.isEmpty) {
        await _load(page: 1, background: background);
        return;
      }
      setState(() {
        _error = null;
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
      title: '人员档案',
      subtitle: '在岗状态由管理后台维护。姓名重复时请核对人员编号。',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _load(page: 1),
                    decoration: InputDecoration(
                      hintText: '按姓名搜索',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _search.clear();
                                _load(page: 1);
                              },
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<PersonDutyStatus>(
                  tooltip: '在岗状态',
                  initialValue: _dutyStatus,
                  onSelected: _setDutyStatus,
                  itemBuilder: (_) => [
                    for (final status in PersonDutyStatus.choices)
                      PopupMenuItem(value: status, child: Text(status.label)),
                  ],
                  child: Chip(
                    label: Text(_dutyStatus?.label ?? '在岗状态'),
                    onDeleted: _dutyStatus == null
                        ? null
                        : () => _setDutyStatus(null),
                    deleteButtonTooltipMessage: '清除在岗状态筛选',
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
              emptyTitle: _dutyStatus == null
                  ? '没有符合条件的人员'
                  : '当前筛选条件下没有「${_dutyStatus!.label}」人员',
              child: RefreshIndicator(
                onRefresh: () => _load(page: _current),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  itemCount: _records.length,
                  itemBuilder: (context, index) {
                    final person = _records[index];
                    final duty = PersonDutyStatus.from(person['dutyStatus']);
                    return QueryRow(
                      key: ValueKey('person-${idOf(person['id'])}'),
                      title: textOf(person['name']),
                      subtitle:
                          '${textOf(person['personCode'])} · ${textOf(person['teamName'], '未分组织')}',
                      leading: CircleAvatar(
                        child: Text(
                          textOf(person['name'], '?').characters.first,
                        ),
                      ),
                      trailing: WearBadge(
                        text: duty.label,
                        color: duty == PersonDutyStatus.onDuty
                            ? WearColors.primary
                            : WearColors.warning,
                      ),
                      onTap: () async {
                        await context.push('/people/${idOf(person['id'])}');
                        if (mounted) _load(page: _current);
                      },
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

class PersonPage extends StatefulWidget {
  const PersonPage({super.key, required this.id});

  final String id;

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  WearSession? _session;
  bool? _workMode;
  JsonMap? _person;
  JsonMap? _location;
  bool _locationLoading = true;
  bool _locationFailed = false;
  List<JsonMap> _activeTasks = const [];
  bool _tasksLoading = true;
  bool _tasksFailed = false;
  bool _loading = true;
  Object? _error;
  int _request = 0;
  Timer? _locationTimer;
  @override
  void initState() {
    super.initState();
    _locationTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final session = _session;
      if (mounted &&
          session != null &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused) {
        _loadLocation(session, _request, session.scopeKey);
      }
    });
  }

  @override
  void dispose() {
    _session?.refreshTick.removeListener(_refreshVisible);
    _locationTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (!identical(session, _session)) {
      _session?.refreshTick.removeListener(_refreshVisible);
      _session = session;
      session.refreshTick.addListener(_refreshVisible);
      _workMode = session.workBusinessEnabled;
      _load();
    } else if (_workMode != session.workBusinessEnabled) {
      _workMode = session.workBusinessEnabled;
      _activeTasks = [];
      _tasksFailed = false;
      _tasksLoading = session.workBusinessEnabled;
      if (session.workBusinessEnabled) {
        _loadActiveTasks(session, _request, session.scopeKey);
      }
    }
  }

  @override
  void didUpdateWidget(covariant PersonPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) _load();
  }

  void _refreshVisible() {
    if (!_loading &&
        TickerMode.valuesOf(context).enabled &&
        ModalRoute.of(context)?.isCurrent == true) {
      unawaited(_load(background: true));
    }
  }

  Future<void> _load({bool background = false}) async {
    final session = _session;
    if (session == null) return;
    final request = ++_request;
    final scopeKey = session.scopeKey;
    if (!background) {
      setState(() {
        _loading = true;
        _error = null;
        _location = null;
        _locationLoading = true;
        _locationFailed = false;
        _activeTasks = [];
        _tasksLoading = true;
        _tasksFailed = false;
      });
    }
    // Optional context must not block the personnel record or contact action.
    _loadLocation(session, request, scopeKey);
    _loadActiveTasks(session, request, scopeKey);
    try {
      final person = jsonMap(
        await session.api.get('/api/v1/people/${widget.id}'),
      );
      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _person = person;
        _error = null;
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

  Future<void> _loadActiveTasks(
    WearSession session,
    int request,
    String scopeKey,
  ) async {
    try {
      final tasks = await loadPersonActiveTasks(
        session.api,
        widget.id,
        allSite: session.isDutyAdmin,
      );
      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _activeTasks = tasks;
        _tasksLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _tasksFailed = true;
        _tasksLoading = false;
      });
    }
  }

  Future<void> _loadLocation(
    WearSession session,
    int request,
    String scopeKey,
  ) async {
    try {
      final location = jsonMap(
        await session.api.get('/api/v1/locations/people/${widget.id}'),
      );
      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _location = idOf(location['personId']) == widget.id ? location : null;
        _locationLoading = false;
      });
    } catch (error) {
      if (error is StaleSessionException) return;
      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _locationLoading = false;
        _locationFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = _person;
    return QueryPage(
      title: person == null ? '人员详情' : textOf(person['name']),
      body: QueryStateView(
        loading: _loading,
        error: _error,
        empty: person == null,
        onRetry: _load,
        child: person == null
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
                            label: '人员编号',
                            value: textOf(person['personCode']),
                          ),
                          DetailField(
                            label: '在岗状态',
                            value: PersonDutyStatus.from(
                              person['dutyStatus'],
                            ).label,
                          ),
                          DetailField(
                            label: '组织',
                            value: textOf(person['teamName']),
                          ),
                        ],
                      ),
                    ),
                    if (_session!.can('wear:assignment:issue')) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ActionChip(
                          label: const Text('装备分配 / 归还'),
                          onPressed: () async {
                            await context.push(
                              '/people-admin/equipment/${widget.id}',
                            );
                            if (mounted) _load();
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => context.push(
                        communicationUri(personId: widget.id).toString(),
                      ),
                      icon: const Icon(Icons.forum_outlined),
                      label: const Text('联系该人员'),
                    ),
                    const SizedBox(height: 18),
                    _PersonSiteContext(
                      personId: widget.id,
                      activeTasks: _activeTasks,
                      tasksLoading: _tasksLoading,
                      tasksFailed: _tasksFailed,
                      location: _location,
                      loading: _locationLoading,
                      failed: _locationFailed,
                    ),
                    const SizedBox(height: 18),
                    EquipmentPanel(
                      key: ValueKey('equipment-$_request'),
                      personId: widget.id,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _PersonSiteContext extends StatelessWidget {
  const _PersonSiteContext({
    required this.activeTasks,
    required this.tasksLoading,
    required this.tasksFailed,
    required this.personId,
    required this.location,
    required this.loading,
    required this.failed,
  });

  final String personId;
  final List<JsonMap> activeTasks;
  final bool tasksLoading, tasksFailed;
  final JsonMap? location;
  final bool loading;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final lat = double.tryParse(location?['latitude']?.toString() ?? '');
    final lng = double.tryParse(location?['longitude']?.toString() ?? '');
    final hasPosition =
        lat != null &&
        lng != null &&
        lat.isFinite &&
        lng.isFinite &&
        lat.abs() <= 90 &&
        lng.abs() <= 180;
    final quality = switch (location?['locationQuality']) {
      'valid' ||
      'ok' when hasPosition && isCurrentLocation(location ?? {}) => '近期有效定位',
      'stale' => '定位已陈旧',
      _ =>
        location?['coordinateSystem'] == 'UNKNOWN'
            ? '坐标系尚未确认，保留原始坐标'
            : '定位状态未知或已过期',
    };
    return WearCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, color: WearColors.brand),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '现场信息',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              if (location?['demo'] == true)
                const WearBadge(text: '示例数据', color: WearColors.warning),
            ],
          ),
          const SizedBox(height: 8),
          DetailField(
            label: '最近定位',
            value: hasPosition
                ? '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}'
                : '未知',
          ),
          Text(
            loading
                ? '定位获取中'
                : failed
                ? '定位未获取'
                : quality,
            style: const TextStyle(color: WearColors.muted, fontSize: 12),
          ),
          if (hasPosition)
            DetailField(
              label: location?['locationTimeBasis'] == 'DEVICE_COLLECTED_AT'
                  ? '设备采集时间'
                  : '位置接收时间',
              value: formatTime(location?['locationReportedAt']),
            ),
          if (!failed &&
              location != null &&
              isCurrentLocation(location ?? {}) &&
              verifiedLocation(location!) != null)
            VerifiedLocationMap(
              interactive: false,
              rows: [location!],
              system: idOf(location!['coordinateSystem']),
            ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LocationHistoryPage(personId: personId),
              ),
            ),
            icon: const Icon(Icons.route_outlined),
            label: const Text('查看历史轨迹'),
          ),
          if (WearScope.of(context).workBusinessEnabled)
            DetailField(
              label: '当前作业',
              value: tasksLoading
                  ? '获取中'
                  : tasksFailed
                  ? '未获取'
                  : activeTasks.isEmpty
                  ? '暂无进行中的作业'
                  : '${activeTasks.length} 项',
            ),
          for (final task
              in WearScope.of(context).workBusinessEnabled
                  ? activeTasks
                  : <JsonMap>[])
            TextButton.icon(
              onPressed: () => context.push('/tasks/${idOf(task['id'])}'),
              icon: const Icon(Icons.assignment_outlined, size: 18),
              label: Text(textOf(task['title'], '作业 ${idOf(task['id'])}')),
            ),
        ],
      ),
    );
  }
}

class EquipmentPanel extends StatefulWidget {
  const EquipmentPanel({super.key, this.personId});

  final String? personId;

  @override
  State<EquipmentPanel> createState() => _EquipmentPanelState();
}

class _EquipmentPanelState extends State<EquipmentPanel> {
  WearSession? _session;
  List<JsonMap> _items = const [];
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

  @override
  void didUpdateWidget(covariant EquipmentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.personId != widget.personId) _load();
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
      final path = widget.personId == null
          ? '/api/v1/me/equipment'
          : '/api/v1/people/${widget.personId}/equipment';
      final result = await loadEquipmentWithTelemetry(session.api, path);
      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _items = result;
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
    final isMyEquipment = widget.personId == null;
    return QuerySection(
      title: isMyEquipment ? '我的装备' : '当前装备',
      children: [
        QueryStateView(
          loading: _loading,
          error: _error,
          empty: _items.isEmpty,
          onRetry: _load,
          emptyTitle: '暂无领用装备',
          emptyDetail: isMyEquipment ? '当前账号可能尚未关联人员档案' : null,
          child: Column(
            children: _items.map((item) {
              final status = connectionLabel(item);
              final details = Row(
                children: [
                  WearAssetImage(
                    WearArt.equipment(item['typeCode']),
                    width: 88,
                    height: 88,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deviceTypeLabel(item['typeCode']),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: WearColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          textOf(item['sn']),
                          style: const TextStyle(color: WearColors.muted),
                        ),
                        const SizedBox(height: 8),
                        WearStatusDot(
                          label: status,
                          color: status == '在线'
                              ? WearColors.online
                              : status == '数据陈旧'
                              ? WearColors.warning
                              : WearColors.muted,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '领用时间 ${formatTime(item['issuedAt'])}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: WearColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isMyEquipment)
                    const Icon(Icons.chevron_right, color: WearColors.muted),
                ],
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: WearCard(
                  padding: const EdgeInsets.all(12),
                  child: isMyEquipment
                      ? InkWell(
                          onTap: () => context.push(
                            '/devices/${idOf(item['deviceId'])}',
                          ),
                          child: details,
                        )
                      : MergeSemantics(child: details),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
