import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core.dart';
import 'query_utils.dart';
import 'management_widgets.dart';
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
  String? _status;
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
      _session = session;
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
    _search.dispose();
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
        '/api/v1/people',
        current: page,
        size: 20,
        query: {
          if (_search.text.trim().isNotEmpty) 'name': _search.text.trim(),
          if (_status != null) 'status': _status,
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
      title: '人员档案',
      subtitle: '人员档案独立于登录账号，姓名重复时请核对人员编号。',
      body: Column(
        children: [
          if (_session?.can('wear:person:edit') == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final action in const {
                    '新增人员': '/people-admin/new',
                    '班组 / 承包商': '/people-admin/organizations',
                    '导入 / 导出': '/people-admin/transfer',
                  }.entries)
                    ActionChip(
                      label: Text(action.key),
                      onPressed: () async {
                        await context.push(action.value);
                        if (mounted) _load(page: _current);
                      },
                    ),
                  if (_session!.isDutyAdmin)
                    ActionChip(
                      label: const Text('重置审批'),
                      onPressed: () => context.push('/people-admin/recovery'),
                    ),
                ],
              ),
            ),
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
                PopupMenuButton<String>(
                  tooltip: '人员状态',
                  initialValue: _status ?? '',
                  onSelected: (value) {
                    setState(() => _status = value.isEmpty ? null : value);
                    _load(page: 1);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: '', child: Text('全部状态')),
                    PopupMenuItem(value: '0', child: Text('在职')),
                    PopupMenuItem(value: '1', child: Text('停用')),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.filter_list),
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
              emptyTitle: '没有符合条件的人员',
              child: RefreshIndicator(
                onRefresh: () => _load(page: _current),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  itemCount: _records.length,
                  itemBuilder: (context, index) {
                    final person = _records[index];
                    return QueryRow(
                      key: ValueKey('person-${idOf(person['id'])}'),
                      title: textOf(person['name']),
                      subtitle:
                          '${textOf(person['personCode'])} · ${textOf(person['teamName'], '未分班组')}',
                      leading: CircleAvatar(
                        child: Text(
                          textOf(person['name'], '?').characters.first,
                        ),
                      ),
                      trailing: WearBadge(
                        text: personStatusLabel(person['status']),
                        color: person['status']?.toString() == '0'
                            ? WearColors.primary
                            : WearColors.muted,
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
  JsonMap? _person;
  JsonMap? _location;
  bool _locationLoading = true;
  bool _locationFailed = false;
  List<JsonMap> _activeTasks = const [];
  bool _tasksLoading = true;
  bool _tasksFailed = false;
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

  @override
  void didUpdateWidget(covariant PersonPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) _load();
  }

  Future<void> _load() async {
    final session = _session;
    if (session == null) return;
    final request = ++_request;
    final scopeKey = session.scopeKey;
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
    // Optional context must not block the personnel record or contact action.
    _loadLocation(session, request, scopeKey);
    _loadActiveTasks(session, request, scopeKey);
    try {
      final responses = await Future.wait([
        session.api.get('/api/v1/people/${widget.id}'),
        session.api.get('/api/v1/people/${widget.id}/assignments'),
      ]);
      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _person = jsonMap(responses[0]);
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

  Future<void> _loadActiveTasks(
    WearSession session,
    int request,
    String scopeKey,
  ) async {
    try {
      final tasks = await loadPersonActiveTasks(session.api, widget.id);
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
                            label: '状态',
                            value: personStatusLabel(person['status']),
                          ),
                          DetailField(
                            label: '班组',
                            value: textOf(person['teamName']),
                          ),
                          DetailField(
                            label: '承包商',
                            value: textOf(person['contractorName']),
                          ),
                          DetailField(
                            label: '有效期',
                            value:
                                '${textOf(person['validFrom'], '不限')} 至 ${textOf(person['validTo'], '不限')}',
                          ),
                        ],
                      ),
                    ),
                    if (_session!.can('wear:person:edit') ||
                        _session!.can('wear:assignment:issue')) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (_session!.can('wear:person:edit')) ...[
                            ActionChip(
                              label: const Text('编辑档案'),
                              onPressed: () async {
                                await context.push(
                                  '/people-admin/edit/${widget.id}',
                                );
                                if (mounted) _load();
                              },
                            ),
                            ActionChip(
                              label: Text(
                                person['status'] == '0' ? '停用人员' : '启用人员',
                              ),
                              onPressed: () async {
                                final active = person['status'] == '0';
                                if (!await confirmManagement(
                                  context,
                                  active ? '停用此人员？' : '启用此人员？',
                                  active
                                      ? '停用后不可再分配新装备。已有领用记录保留。'
                                      : '恢复人员档案为在职状态。',
                                )) {
                                  return;
                                }
                                if (!context.mounted) return;
                                try {
                                  await _session!.api.put(
                                    '/api/v1/people/${widget.id}/status',
                                    data: {
                                      'status': active ? '1' : '0',
                                      'version': person['version'],
                                    },
                                  );
                                  if (mounted) _load();
                                } catch (e) {
                                  if (context.mounted) {
                                    managementMessage(context, e);
                                  }
                                }
                              },
                            ),
                          ],
                          if (_session!.can('wear:assignment:issue'))
                            ActionChip(
                              label: const Text('装备分配 / 归还'),
                              onPressed: () async {
                                await context.push(
                                  '/people-admin/equipment/${widget.id}',
                                );
                                if (mounted) _load();
                              },
                            ),
                        ],
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
                    const SizedBox(height: 22),
                    QuerySection(
                      title: '历史领用记录（${_history.length}）',
                      children: _history
                          .map(
                            (item) => QueryRow(
                              title:
                                  '${deviceTypeLabel(item['typeCode'])} · ${textOf(item['sn'])}',
                              subtitle:
                                  '${formatTime(item['issuedAt'])} 至 ${item['returnedAt'] == null ? '当前' : formatTime(item['returnedAt'])}',
                              onTap: () => context.push(
                                '/devices/${idOf(item['deviceId'])}',
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
    final lat = double.tryParse(location?['lat']?.toString() ?? '');
    final lng = double.tryParse(location?['lng']?.toString() ?? '');
    final hasPosition =
        lat != null &&
        lng != null &&
        lat.isFinite &&
        lng.isFinite &&
        lat.abs() <= 90 &&
        lng.abs() <= 180;
    final quality = switch (location?['locationQuality']) {
      'ok' when hasPosition => '定位正常',
      'stale' => '定位已陈旧',
      _ => '定位状态未知',
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
              label: '定位时间',
              value: formatTime(location?['occurredAt']),
            ),
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
          for (final task in activeTasks)
            TextButton.icon(
              onPressed: () => context.push('/tasks/${idOf(task['id'])}'),
              icon: const Icon(Icons.assignment_outlined, size: 18),
              label: Text(textOf(task['title'], '作业 ${idOf(task['id'])}')),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.push(
                Uri(
                  path: '/tracks',
                  queryParameters: {'personId': personId},
                ).toString(),
              ),
              icon: const Icon(Icons.route_outlined),
              label: const Text('查看轨迹'),
            ),
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
    return QuerySection(
      title: widget.personId == null ? '我的装备' : '当前装备',
      children: [
        QueryStateView(
          loading: _loading,
          error: _error,
          empty: _items.isEmpty,
          onRetry: _load,
          emptyTitle: '暂无领用装备',
          emptyDetail: widget.personId == null ? '当前账号可能尚未关联人员档案' : null,
          child: Column(
            children: _items
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: WearCard(
                      padding: const EdgeInsets.all(12),
                      child: InkWell(
                        onTap: () =>
                            context.push('/devices/${idOf(item['deviceId'])}'),
                        child: Row(
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
                                    style: const TextStyle(
                                      color: WearColors.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  WearStatusDot(
                                    label: connectionLabel(item),
                                    color: connectionLabel(item) == '在线'
                                        ? WearColors.online
                                        : connectionLabel(item) == '数据陈旧'
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
                            const Icon(
                              Icons.chevron_right,
                              color: WearColors.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}
