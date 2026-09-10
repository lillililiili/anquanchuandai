import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core.dart';
import 'query_widgets.dart';

List<JsonMap> aggregateLostSupervision(
  List<JsonMap> tasks,
  Map<String, List<JsonMap>> checksByTask,
) {
  final people = <String, JsonMap>{};
  for (final task in tasks) {
    final taskId = idOf(task['id']);
    for (final check in checksByTask[taskId] ?? const <JsonMap>[]) {
      if (check['typeCode']?.toString() != 'helmet' ||
          check['result']?.toString() == 'ok') {
        continue;
      }
      final personId = idOf(check['personId']);
      if (personId.isEmpty) continue;
      final person = people.putIfAbsent(
        personId,
        () => <String, dynamic>{
          'personId': personId,
          'personName': textOf(check['personName'], '未知人员'),
          'tasks': <JsonMap>[],
        },
      );
      (person['tasks'] as List<JsonMap>).add({
        'taskId': taskId,
        'taskTitle': textOf(task['title']),
        'result': check['result'],
        'needsConfirm': check['needsConfirm'] == true,
      });
    }
  }
  return people.values.toList();
}

class SupervisionPage extends StatefulWidget {
  const SupervisionPage({super.key});

  @override
  State<SupervisionPage> createState() => _SupervisionPageState();
}

class _SupervisionPageState extends State<SupervisionPage> {
  WearSession? _session;
  List<JsonMap> _people = const [];
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
      final tasks = <JsonMap>[];
      var current = 1;
      while (true) {
        final page = await session.api.page(
          '/api/v1/work-tasks',
          current: current,
          size: 100,
          query: const {'status': 'in_progress'},
        );
        if (!mounted || request != _request || scopeKey != session.scopeKey) {
          return;
        }
        tasks.addAll(page.records);
        if (!page.hasMore || page.records.isEmpty) break;
        current++;
      }

      final checks = <String, List<JsonMap>>{};
      const batchSize = 8;
      for (var offset = 0; offset < tasks.length; offset += batchSize) {
        final end = (offset + batchSize).clamp(0, tasks.length);
        final batch = tasks.sublist(offset, end);
        final responses = await Future.wait(
          batch.map(
            (task) => session.api.get(
              '/api/v1/work-tasks/${idOf(task['id'])}/equipment-check',
            ),
          ),
        );
        if (!mounted || request != _request || scopeKey != session.scopeKey) {
          return;
        }
        for (var index = 0; index < batch.length; index++) {
          checks[idOf(batch[index]['id'])] = jsonList(responses[index]);
        }
      }

      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _people = aggregateLostSupervision(tasks, checks);
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
      title: '失去监护人员',
      subtitle: '汇总全部进行中作业，安全帽缺失或状态未知的人员按稳定 ID 去重。',
      body: QueryStateView(
        loading: _loading,
        error: _error,
        empty: _people.isEmpty,
        onRetry: _load,
        emptyTitle: '当前没有失去监护人员',
        emptyDetail: '仅安全帽检查结果为“缺少”或“未知”时列入。',
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _people.length,
            itemBuilder: (context, index) {
              final person = _people[index];
              final tasks = jsonList(person['tasks']);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: WearCard(
                  padding: const EdgeInsets.fromLTRB(14, 14, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Color(0xFFFFF2E1),
                            child: Icon(
                              Icons.person_off_outlined,
                              color: WearColors.warning,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  textOf(person['personName']),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '人员 ID ${idOf(person['personId'])}',
                                  style: const TextStyle(
                                    color: WearColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          WearBadge(
                            text: '${tasks.length} 项作业',
                            color: WearColors.warning,
                          ),
                        ],
                      ),
                      const Divider(height: 22),
                      for (final task in tasks)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(textOf(task['taskTitle'])),
                          subtitle: Text(_reason(task)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              context.push('/tasks/${idOf(task['taskId'])}'),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _reason(JsonMap task) {
    final reason = task['result']?.toString() == 'missing'
        ? '缺少安全帽'
        : '安全帽设备或遥测状态未知';
    return task['needsConfirm'] == true ? '$reason · 需人工确认' : reason;
  }
}
