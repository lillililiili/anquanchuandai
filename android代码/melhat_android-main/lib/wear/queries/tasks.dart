import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core.dart';
import 'query_utils.dart';
import 'query_widgets.dart';

String _workTypeLabel(Object? value) => switch (value?.toString()) {
  'patrol' => '巡检',
  'height' => '高处作业',
  'other' => '其他作业',
  _ => '类型未知',
};

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

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
    final groups = <String, List<JsonMap>>{};
    for (final task in _records) {
      groups.putIfAbsent(taskGroup(task['status']), () => []).add(task);
    }
    const order = ['进行中', '待开始', '已结束', '状态未知'];
    return QueryPage(
      title: '作业任务',
      subtitle: _mine ? '我负责或参与的作业 · 按服务端结果分页' : '当前厂站的授权作业 · 可按状态和类型筛选',
      body: Column(
        children: [
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
                const SizedBox(width: 8),
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
                    label: _status == null ? '全部状态' : taskStatusLabel(_status),
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
                      setState(() => _workType = value.isEmpty ? null : value);
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
                                '${_workTypeLabel(task['workType'])} · ${textOf(task['spaceName'])}\n${formatTime(task['plannedStart'])} 至 ${formatTime(task['plannedEnd'])}',
                            trailing: WearBadge(
                              text: taskStatusLabel(task['status']),
                            ),
                            onTap: () =>
                                context.push('/tasks/${idOf(task['id'])}'),
                          ),
                      ],
                  ],
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
  List<JsonMap> _events = const [];
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
      final results = await Future.wait([
        session.api.get('/api/v1/work-tasks/${widget.id}'),
        session.api.get('/api/v1/work-tasks/${widget.id}/equipment-check'),
        session.api.get('/api/v1/work-tasks/${widget.id}/events'),
      ]);
      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _task = jsonMap(results[0]);
        _equipment = jsonList(results[1]);
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

  @override
  Widget build(BuildContext context) {
    final task = _task;
    return QueryPage(
      title: task == null ? '作业详情' : textOf(task['title']),
      body: QueryStateView(
        loading: _loading,
        error: _error,
        empty: task == null,
        onRetry: _load,
        child: task == null
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
                            label: '状态',
                            value: taskStatusLabel(task['status']),
                          ),
                          DetailField(
                            label: '作业类型',
                            value: _workTypeLabel(task['workType']),
                          ),
                          DetailField(
                            label: '作业区域',
                            value: textOf(task['spaceName']),
                          ),
                          DetailField(
                            label: '计划时间',
                            value:
                                '${formatTime(task['plannedStart'])} 至 ${formatTime(task['plannedEnd'])}',
                          ),
                          DetailField(
                            label: '实际时间',
                            value:
                                '${formatTime(task['actualStart'])} 至 ${formatTime(task['actualEnd'])}',
                          ),
                          DetailField(label: '工作票', value: _ticketLabel(task)),
                          if (task['demo'] == true)
                            const DetailField(
                              label: '数据标识',
                              value: '演示作业，不作为生产依据',
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    QuerySection(
                      title: '作业成员（${jsonList(task['members']).length}）',
                      children: jsonList(task['members'])
                          .map(
                            (person) => QueryRow(
                              title: textOf(person['name']),
                              subtitle: textOf(person['personCode']),
                              onTap: () => context.push(
                                '/people/${idOf(person['personId'])}',
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 14),
                    QuerySection(
                      title: '装备检查（${_equipment.length}）',
                      children: _equipment.isEmpty
                          ? [
                              const WearCard(
                                child: Text(
                                  '该任务没有装备检查项',
                                  style: TextStyle(color: WearColors.muted),
                                ),
                              ),
                            ]
                          : _equipment.map(_equipmentRow).toList(),
                    ),
                    const SizedBox(height: 14),
                    QuerySection(
                      title: '关联事件（${_events.length}）',
                      children: _events.isEmpty
                          ? [
                              const WearCard(
                                child: Text(
                                  '暂无关联事件',
                                  style: TextStyle(color: WearColors.muted),
                                ),
                              ),
                            ]
                          : _events.map((event) {
                              final pending =
                                  event['taskMatch']?.toString() == 'pending';
                              return QueryRow(
                                title:
                                    '${eventTypeLabel(event['type'])} · ${textOf(event['personName'], '未关联人员')}',
                                subtitle: pending
                                    ? '存在多个候选任务，需人工确认关联'
                                    : '${formatTime(event['occurredAt'])} · ${eventStatusLabel(event['status'])}',
                                trailing: WearBadge(
                                  text: pending
                                      ? '待确认关联'
                                      : textOf(event['severity'], '风险未知'),
                                  color: pending ? WearColors.warning : null,
                                ),
                                onTap: () => context.push(
                                  '/events?eventId=${idOf(event['id'])}',
                                ),
                              );
                            }).toList(),
                    ),
                  ],
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
