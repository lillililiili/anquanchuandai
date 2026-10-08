import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core.dart';
import 'query_utils.dart';
import 'query_widgets.dart';
import 'work_reference.dart';

String _workTypeLabel(Object? value) => switch (value?.toString()) {
  'patrol' => '巡检',
  'height' => '高处作业',
  'other' => '其他作业',
  _ => '类型未知',
};

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, this.groupId, this.allSite = false});
  final String? groupId;
  final bool allSite;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  WearSession? _session;
  List<JsonMap> _records = const [];
  int _current = 1;
  int _total = 0;
  bool _hasMore = false;
  bool _loading = true;
  Object? _error;
  String? _status;
  String? _workType;
  bool _mine = true;
  int _request = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (!identical(session, _session)) {
      _session = session;
      _mine = !widget.allSite || !session.isDutyAdmin;
      if (widget.groupId == null) _load(page: 1);
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
        _mine ? '/api/v1/work-tasks/mine' : '/api/v1/work-tasks',
        current: page,
        size: 20,
        query: {
          if (!_mine && _status != null) 'status': _status,
          if (!_mine && _workType != null) 'workType': _workType,
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
    if (widget.groupId != null) {
      return TaskPage(id: widget.groupId!);
    }
    final groups = <String, List<JsonMap>>{};
    for (final task in _records) {
      groups.putIfAbsent(taskGroup(task['status']), () => []).add(task);
    }
    const order = ['进行中', '有异常', '已完成', '待开始', '已结束', '状态未知'];
    return QueryPage(
      title: _session!.isDutyAdmin ? '作业任务' : '我的任务',
      onBack: _session!.isDutyAdmin
          ? () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/workbench');
              }
            }
          : null,
      subtitle: _mine ? '查看参与的作业、人员、装备及事件记录' : '当前厂站的授权作业 · 可按状态和类型筛选',
      body: Column(
        children: [
          if (_session!.isDutyAdmin)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('我的任务'),
                    selected: _mine,
                    onSelected: _loading
                        ? null
                        : (_) {
                            setState(() => _mine = true);
                            _load(page: 1);
                          },
                  ),
                  if (_session!.isDutyAdmin) const SizedBox(width: 8),
                  if (_session!.isDutyAdmin)
                    ChoiceChip(
                      label: const Text('全站作业'),
                      selected: !_mine,
                      onSelected: _loading
                          ? null
                          : (_) {
                              setState(() => _mine = false);
                              _load(page: 1);
                            },
                    ),
                  if (!_mine) ...[
                    const SizedBox(width: 8),
                    _menu(
                      label: _status == null
                          ? '全部状态'
                          : taskStatusLabel(_status),
                      value: _status ?? '',
                      values: const [
                        '',
                        'draft',
                        'ready',
                        'in_progress',
                        'paused',
                        'ended',
                      ],
                      labelOf: (value) =>
                          value.isEmpty ? '全部状态' : taskStatusLabel(value),
                      onSelected: (value) {
                        setState(() => _status = value.isEmpty ? null : value);
                        _load(page: 1);
                      },
                    ),
                    const SizedBox(width: 8),
                    _menu(
                      label: _workType == null
                          ? '全部类型'
                          : _workTypeLabel(_workType),
                      value: _workType ?? '',
                      values: const ['', 'patrol', 'height', 'other'],
                      labelOf: (value) =>
                          value.isEmpty ? '全部类型' : _workTypeLabel(value),
                      onSelected: (value) {
                        setState(
                          () => _workType = value.isEmpty ? null : value,
                        );
                        _load(page: 1);
                      },
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: QueryStateView(
              loading: _loading,
              error: _error,
              empty: _records.isEmpty,
              onRetry: () => _load(page: _current),
              emptyTitle: '没有符合条件的作业',
              child: RefreshIndicator(
                onRefresh: () => _load(page: _current),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  children: [
                    for (final group in order)
                      if (groups[group]?.isNotEmpty == true) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 12, 2, 9),
                          child: Text(
                            '$group（${groups[group]!.length}）',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        for (final task in groups[group]!)
                          QueryRow(
                            key: ValueKey('task-${idOf(task['id'])}'),
                            title: textOf(task['title']),
                            subtitle:
                                '${_workTypeLabel(task['workType'])} · ${textOf(task['spaceName'])}\n${formatTime(task['plannedStart'] ?? task['plannedStartAt'])} 至 ${formatTime(task['plannedEnd'] ?? task['plannedEndAt'])}',
                            trailing: WearBadge(
                              text: taskStatusLabel(task['status']),
                            ),
                            onTap: () async {
                              await context.push('/tasks/${idOf(task['id'])}');
                              if (mounted) await _load(page: _current);
                            },
                          ),
                      ],
                  ],
                ),
              ),
            ),
          ),
          if (!_loading && _error == null && _current == 1 && !_hasMore)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _total == 0 ? '共 0 条' : '共 $_total 条 · 已全部显示',
                  style: const TextStyle(color: WearColors.muted),
                ),
              ),
            )
          else
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

  Widget _menu({
    required String label,
    required String value,
    required List<String> values,
    required String Function(String) labelOf,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (_) => values
          .map((item) => PopupMenuItem(value: item, child: Text(labelOf(item))))
          .toList(),
      child: Chip(
        label: Text(label),
        avatar: const Icon(Icons.filter_list, size: 17),
      ),
    );
  }
}

class TaskPage extends StatefulWidget {
  const TaskPage({super.key, required this.id});

  final String id;

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  WearSession? _session;
  JsonMap? _task;
  List<JsonMap> _equipment = const [];
  Map<String, List<JsonMap>?> _memberEquipment = const {};
  List<JsonMap> _events = const [];
  bool _loading = true;
  Object? _error;
  int _request = 0;
  bool _preview = false;
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
    if (widget.id == 'ui-preview') {
      await _showPreview();
      return;
    }
    final session = _session;
    if (session == null) return;
    final request = ++_request;
    final scopeKey = session.scopeKey;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        session.api.get('/api/v1/work-tasks/${widget.id}'),
        session.api.get('/api/v1/work-tasks/${widget.id}/equipment-check'),
        session.api.get('/api/v1/work-tasks/${widget.id}/events'),
      ]);
      final task = jsonMap(results[0]);
      final memberEquipment = <String, List<JsonMap>?>{};
      final people = jsonList(task['members'])
          .map((person) => idOf(person['personId']))
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      // Read ownership and telemetry from the business API, independently of
      // the work readiness check. A failed read must not imply no equipment.
      for (
        var start = 0;
        session.isAdmin && start < people.length;
        start += 6
      ) {
        await Future.wait(
          people.skip(start).take(6).map((id) async {
            try {
              memberEquipment[id] = await loadEquipmentWithTelemetry(
                session.api,
                '/api/v1/people/${Uri.encodeComponent(id)}/equipment',
              );
            } on StaleSessionException {
              rethrow;
            } catch (_) {
              memberEquipment[id] = null;
            }
          }),
        );
        if (!mounted || request != _request || scopeKey != session.scopeKey) {
          return;
        }
      }
      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _task = task;
        _equipment = jsonList(results[1]);
        _memberEquipment = memberEquipment;
        _events = jsonList(results[2]);
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

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/workbench');
    }
  }

  void _exampleAction() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('界面示例：未连接真实人员、事件或通话服务')));
  }

  Future<void> _showPreview() async {
    final task = await workReferencePreview();
    if (!mounted) return;
    setState(() {
      _preview = true;
      _task = task;
      _equipment = jsonList(task['equipmentCheck']);
      _events = jsonList(task['events']);
      _loading = false;
      _error = null;
    });
  }

  void _contactGuardian() {
    if (_preview) {
      _exampleAction();
      return;
    }
    final id = idOf(_task?['guardianPersonId']);
    if (id.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('尚未关联监护人，无法发起联系')));
      return;
    }
    context.push(communicationUri(personId: id).toString());
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    final unavailable =
        _error is WearApiException &&
        [404, 501].contains((_error as WearApiException).code);
    if (_loading || _error != null || task == null) {
      return QueryPage(
        title: '作业详情',
        body: Column(
          children: [
            Expanded(
              child: QueryStateView(
                loading: _loading,
                error: _error,
                empty: task == null,
                onRetry: _load,
                child: const SizedBox.shrink(),
              ),
            ),
            if (unavailable)
              TextButton(onPressed: _showPreview, child: const Text('查看界面示例')),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFEEF8FF),
      body: SafeArea(
        child: TaskReferenceView(
          task: task,
          equipment: _equipment,
          memberEquipment: _memberEquipment,
          events: _events,
          owner: workOwnerLabel(task, _session!),
          guardian: workGuardianLabel(task),
          preview: _preview,
          canViewPeople: _session!.isAdmin,
          onBack: _back,
          onRefresh: _preview ? _showPreview : _load,
          onPerson: (person) {
            if (_preview) {
              _exampleAction();
              return;
            }
            final id = idOf(person['personId']);
            if (id.isNotEmpty && _session!.isAdmin) context.push('/people/$id');
          },
          onEvent: (event) {
            if (_preview) {
              _exampleAction();
              return;
            }
            final id = idOf(event['id']);
            if (id.isNotEmpty) {
              context.push(
                Uri(
                  path: '/events',
                  queryParameters: {'eventId': id},
                ).toString(),
              );
            }
          },
          onGuardian: _contactGuardian,
          onEventRecords: () => context.push(
            '/events?taskId=${Uri.encodeComponent(widget.id)}&status=all',
          ),
          details: Column(
            children: [
              DetailField(label: '状态', value: taskStatusLabel(task['status'])),
              DetailField(
                label: '作业类型',
                value: _workTypeLabel(task['workType']),
              ),
              DetailField(label: '作业区域', value: textOf(task['spaceName'])),
              DetailField(
                label: '计划时间',
                value:
                    '${formatTime(task['plannedStart'] ?? task['plannedStartAt'])} 至 ${formatTime(task['plannedEnd'] ?? task['plannedEndAt'])}',
              ),
              DetailField(
                label: '实际时间',
                value:
                    '${formatTime(task['actualStart'])} 至 ${formatTime(task['actualEnd'])}',
              ),
              DetailField(label: '工作票', value: _ticketLabel(task)),
              if (task['demo'] == true)
                const DetailField(label: '数据标识', value: '演示作业，不作为生产依据'),
              for (final person in jsonList(task['members']))
                DetailField(
                  label: textOf(person['name']),
                  value: textOf(person['personCode']),
                ),
            ],
          ),
          equipmentDetails: Column(
            children: _equipment.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('该任务没有装备检查项'),
                    ),
                  ]
                : _equipment.map(_equipmentRow).toList(),
          ),
        ),
      ),
    );
  }

  Widget _equipmentRow(JsonMap item) {
    final result = item['result']?.toString();
    final color = switch (result) {
      'ok' => WearColors.primary,
      'missing' => WearColors.danger,
      _ => WearColors.warning,
    };
    return QueryRow(
      title:
          '${textOf(item['personName'])} · ${deviceTypeLabel(item['typeCode'])}',
      subtitle: item['sn'] == null ? '设备 SN 未知' : '设备 ${textOf(item['sn'])}',
      trailing: WearBadge(text: equipmentResultLabel(result), color: color),
    );
  }

  String _ticketLabel(JsonMap task) {
    if (task['ticketRequired'] != true) return '无需工作票';
    return switch (task['ticketStatus']?.toString()) {
      'provided' => textOf(task['ticketNo']),
      'unverified' => '待核实',
      _ => '状态未知',
    };
  }
}
