import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core.dart';
import 'query_utils.dart';
import 'query_widgets.dart';

class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({super.key});

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage> {
  final _peopleSearch = TextEditingController();
  WearSession? _session;
  JsonMap? _summary;
  bool _loading = true;
  Object? _error;
  int _request = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (!identical(session, _session)) {
      _session?.refreshTick.removeListener(_refresh);
      _session = session;
      session.refreshTick.addListener(_refresh);
      _load();
    }
  }

  @override
  void dispose() {
    _session?.refreshTick.removeListener(_refresh);
    _peopleSearch.dispose();
    super.dispose();
  }

  void _refresh() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    final session = _session;
    if (session == null) return;
    final request = ++_request;
    final scopeKey = session.scopeKey;
    if (!silent || _summary == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = jsonMap(await session.api.get('/api/v1/duty/summary'));
      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _summary = result;
        _loading = false;
        _error = null;
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
    final summary = _summary;
    return QueryPage(
      title: '值班工作台',
      subtitle: '先处理风险，再安排现场作业',
      actions: [
        IconButton(
          tooltip: '刷新工作台',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: QueryStateView(
        loading: _loading,
        error: _error,
        empty: summary == null,
        onRetry: _load,
        child: summary == null
            ? const SizedBox.shrink()
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    _dutyBanner(summary),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _peopleSearch,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _openPeopleSearch,
                      decoration: InputDecoration(
                        hintText: '按姓名查找现场人员',
                        prefixIcon: const Icon(Icons.person_search_outlined),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              _openPeopleSearch(_peopleSearch.text),
                          icon: const Icon(Icons.arrow_forward),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    WearCard(
                      padding: const EdgeInsets.all(4),
                      child: Column(
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final width =
                                  MediaQuery.textScalerOf(context).scale(14) >
                                      20
                                  ? constraints.maxWidth
                                  : (constraints.maxWidth - 10) / 2;
                              return Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  SizedBox(
                                    width: width,
                                    child: _metric(
                                      '待认领事件',
                                      intOf(summary['unclaimed']),
                                      Icons.notification_important_outlined,
                                      WearColors.danger,
                                      () => context.go('/events?status=open'),
                                    ),
                                  ),
                                  SizedBox(
                                    width: width,
                                    child: _metric(
                                      '我负责的事件',
                                      intOf(summary['mine']),
                                      Icons.assignment_ind_outlined,
                                      WearColors.primary,
                                      () => context.go(
                                        '/events?claimantUserId=${_session!.userId}',
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: width,
                                    child: _metric(
                                      '逾期事件',
                                      intOf(summary['overdue']),
                                      Icons.timer_off_outlined,
                                      WearColors.warning,
                                      () =>
                                          context.go('/events?escalated=true'),
                                    ),
                                  ),
                                  SizedBox(
                                    width: width,
                                    child: _metric(
                                      '失去监护',
                                      intOf(summary['lostSupervision']),
                                      Icons.person_off_outlined,
                                      WearColors.danger,
                                      () => context.push('/supervision'),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    QuerySection(
                      title: '近期未关闭事件',
                      trailing: TextButton(
                        onPressed: () => context.go('/events'),
                        child: const Text('事件中心'),
                      ),
                      children: jsonList(summary['recentEvents']).isEmpty
                          ? [
                              const WearCard(
                                child: Text(
                                  '暂无未关闭事件',
                                  style: TextStyle(color: WearColors.muted),
                                ),
                              ),
                            ]
                          : jsonList(summary['recentEvents'])
                                .map(
                                  (event) => QueryRow(
                                    title:
                                        '${eventTypeLabel(event['type'])} · ${textOf(event['personName'], '未关联人员')}',
                                    subtitle:
                                        '${formatTime(event['occurredAt'])} · ${eventStatusLabel(event['status'])}',
                                    onTap: () => context.go(
                                      '/events?eventId=${idOf(event['id'])}',
                                    ),
                                  ),
                                )
                                .toList(),
                    ),
                    const SizedBox(height: 20),
                    QuerySection(
                      title: '当前作业',
                      trailing: TextButton(
                        onPressed: () => context.push('/tasks'),
                        child: const Text('全部作业'),
                      ),
                      children: jsonList(summary['activeTasks']).isEmpty
                          ? [
                              const WearCard(
                                child: Text(
                                  '暂无进行中或待开始作业',
                                  style: TextStyle(color: WearColors.muted),
                                ),
                              ),
                            ]
                          : jsonList(summary['activeTasks'])
                                .map(
                                  (task) => QueryRow(
                                    title: textOf(task['title']),
                                    subtitle:
                                        '${taskStatusLabel(task['status'])} · ${textOf(task['spaceName'])}',
                                    trailing: WearBadge(
                                      text: taskStatusLabel(task['status']),
                                    ),
                                    onTap: () => context.push(
                                      '/tasks/${idOf(task['id'])}',
                                    ),
                                  ),
                                )
                                .toList(),
                    ),
                    const SizedBox(height: 20),
                    WearCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: _inventory(
                              '已领用人员',
                              intOf(summary['peopleCount']),
                              Icons.groups_outlined,
                              () => context.push('/people'),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 48,
                            color: WearColors.line,
                          ),
                          Expanded(
                            child: _inventory(
                              '在用装备',
                              intOf(summary['deviceCount']),
                              Icons.devices_other_outlined,
                              () => context.push('/devices'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    QuerySection(
                      title: '现场工具',
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final twoColumns =
                                constraints.maxWidth >= 330 &&
                                MediaQuery.textScalerOf(context).scale(15) <=
                                    20;
                            final width = twoColumns
                                ? (constraints.maxWidth - 10) / 2
                                : constraints.maxWidth;
                            return Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _shortcut(
                                  width,
                                  '人员档案',
                                  'assets/field-brand/cargo-v2/profile-card.png',
                                  () => context.push('/people'),
                                ),
                                _shortcut(
                                  width,
                                  '设备台账',
                                  'assets/field-brand/cargo-v2/device-card.png',
                                  () => context.push('/devices'),
                                ),
                                _shortcut(
                                  width,
                                  '轨迹回放',
                                  'assets/field-brand/cargo-v2/track-card.png',
                                  () => context.push('/tracks'),
                                ),
                                _shortcut(
                                  width,
                                  '电子围栏',
                                  'assets/field-brand/cargo-v2/fence-card.png',
                                  () => context.push('/fences'),
                                ),
                                _shortcut(
                                  width,
                                  '作业任务',
                                  'assets/field-brand/cargo-v2/workbench-card.png',
                                  () => context.push('/tasks'),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _metric(
    String label,
    int count,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 26,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      color: WearColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dutyBanner(JsonMap summary) {
    final hasUnclaimed = intOf(summary['unclaimed']) > 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: WearColors.line),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '现场值守',
                      style: TextStyle(color: WearColors.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasUnclaimed ? '待办优先，及时响应' : '查看现场，持续守护',
                      style: const TextStyle(
                        color: WearColors.ink,
                        fontSize: 22,
                        height: 1.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ClipOval(
                child: Image.asset(
                  'assets/field-brand/cargo-v2/device-card.png',
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: WearColors.accent,
              foregroundColor: WearColors.ink,
            ),
            onPressed: () =>
                context.go(hasUnclaimed ? '/events?status=open' : '/events'),
            icon: const Icon(Icons.arrow_forward, size: 19),
            label: Text(hasUnclaimed ? '查看待认领事件' : '打开事件中心'),
          ),
        ],
      ),
    );
  }

  void _openPeopleSearch(String raw) {
    final name = raw.trim();
    context.push(
      Uri(
        path: '/people',
        queryParameters: {if (name.isNotEmpty) 'name': name},
      ).toString(),
    );
  }

  Widget _shortcut(
    double width,
    String label,
    String asset,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: width,
      child: WearCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 9, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: WearColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Image.asset(
                  asset,
                  width: 54,
                  height: 54,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inventory(
    String label,
    int count,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            Icon(icon, color: WearColors.primary),
            const SizedBox(height: 4),
            Text(
              '$count',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            Text(label, style: const TextStyle(color: WearColors.muted)),
          ],
        ),
      ),
    );
  }
}
