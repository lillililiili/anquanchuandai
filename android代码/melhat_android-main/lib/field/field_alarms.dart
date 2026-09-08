import '../store/chat_store.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../components/field_motion.dart';
import '../components/field_brand.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../hooks/use_agent_page.dart';
import '../hooks/use_page_agent.dart';
import '../hooks/use_page_agent_get_data.dart';
import '../router/route_tree.dart';
import '../store/user_store.dart';
import '../api/alarm.dart';
import '../service/mcp_tool.dart';
import '../components/app_map.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'field_data.dart';
import 'field_session.dart';

class FieldAlarmWorkspace extends HookWidget {
  final VoidCallback onAdvanced;
  const FieldAlarmWorkspace({super.key, required this.onAdvanced});
  @override
  Widget build(BuildContext context) {
    final key = useMemoized(() => GlobalKey<_FieldAlarmBodyState>());
    final agent = useAgentPage(
      meta: RouteNode.alarmRecord,
      greetingMessage: '可按人员、作业分组和告警来源查询；处理结果由后台保存。',
    );
    usePageAgent(
      controller: agent,
      toolName: 'queryAlarmRecord',
      executeFn: (params) async {
        await key.currentState?.reload();
        return key.currentState?.querySummary(params) ?? <String, dynamic>{};
      },
    );
    usePageAgentGetData(
      agent,
      'AlarmRecordListSection',
      () => key.currentState?.summary ?? {},
    );
    return _FieldAlarmBody(
      key: key,
      onAdvanced: onAdvanced,
      onReady: () => agent.completeEmptyInit(),
      onResume: () => toolCallService.setCurrentController(agent),
    );
  }
}

class _FieldAlarmBody extends StatefulWidget {
  final VoidCallback onAdvanced, onReady, onResume;
  const _FieldAlarmBody({
    super.key,
    required this.onAdvanced,
    required this.onReady,
    required this.onResume,
  });
  @override
  State<_FieldAlarmBody> createState() => _FieldAlarmBodyState();
}

class _FieldAlarmBodyState extends State<_FieldAlarmBody> {
  final repo = FieldRepository(), session = FieldSession.instance;
  final scroll = ScrollController();
  final detailSheet = DraggableScrollableController();
  late final TextEditingController search;
  FieldSnapshot? snapshot;
  FieldEvent? selected;
  bool loading = true,
      detailLoading = false,
      submitting = false,
      needsVerification = false;
  String? message, error;
  int generation = 0, detailGeneration = 0, visibleLimit = 100;
  final seenEvents = <String>{};
  final highlightedEvents = <String>{};
  String? newestEventTime;
  Timer? highlightTimer;
  int filterRevision = 0;
  @override
  void initState() {
    super.initState();
    session.scope(UserStore.instance.userInfo?.userId ?? '');
    search = TextEditingController(text: session.search);
    reload();
  }

  @override
  void dispose() {
    highlightTimer?.cancel();
    generation++;
    detailGeneration++;
    search.dispose();
    scroll.dispose();
    detailSheet.dispose();
    super.dispose();
  }

  List<FieldEvent> get rows =>
      snapshot?.filter(
        group: session.group,
        search: session.search,
        source: session.source,
        status: session.status,
        type: session.type,
        start: session.start,
        end: session.end,
      ) ??
      [];
  Map<String, dynamic> querySummary(Map<String, dynamic>? params) {
    final page = fieldInt(params?['pageNum']).clamp(1, 100000);
    final size =
        (params?['pageSize'] == null ? 10 : fieldInt(params?['pageSize']))
            .clamp(1, 200);
    return {
      ...summary,
      'currentPage': page,
      'pageSize': size,
      'total': rows.length,
      'records': rows
          .skip((page - 1) * size)
          .take(size)
          .map((e) => {...e.raw, 'source': e.source, 'eventKey': e.key})
          .toList(),
    };
  }

  Map<String, dynamic> get summary => {
    'loadedCount': rows.length,
    'complete': snapshot?.complete ?? false,
    'pending': rows.where((e) => !e.handled).length,
    'records': rows
        .take(10)
        .map(
          (e) => {
            'id': e.id,
            'source': e.source,
            'person': e.userName,
            'type': e.title,
            'handled': e.handled,
          },
        )
        .toList(),
  };
  Future<void> reload() async {
    final request = ++generation;
    if (mounted) setState(() => loading = true);
    final data = await repo.load();
    if (!mounted || request != generation) return;
    highlightTimer?.cancel();
    setState(() {
      highlightedEvents.clear();
      // Establish a complete baseline first; late-loaded historical rows are
      // never presented as newly received alarms.
      if (data.complete) {
        final previousTime = newestEventTime;
        if (previousTime != null) {
          highlightedEvents.addAll(
            data.events
                .where(
                  (event) =>
                      !seenEvents.contains(event.key) &&
                      event.time.compareTo(previousTime) > 0 &&
                      !event.handled,
                )
                .map((event) => event.key),
          );
        }
        seenEvents.addAll(data.events.map((event) => event.key));
        for (final event in data.events) {
          if (newestEventTime == null ||
              event.time.compareTo(newestEventTime!) > 0) {
            newestEventTime = event.time;
          }
        }
        newestEventTime ??= '';
      }
      snapshot = data;
      if (data.complete && !data.groupNames.contains(session.group)) {
        session.group = '';
      }
      loading = false;
    });
    if (highlightedEvents.isNotEmpty) {
      highlightTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(highlightedEvents.clear);
      });
    }
    widget.onReady();
    if (session.selectedKey.isNotEmpty) {
      final matches = data.events.where((e) => e.key == session.selectedKey);
      final event = matches.firstOrNull ?? selected;
      if (event != null) {
        await choose(event, scrollTo: selected == null);
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前已加载记录中没有该告警，请刷新后重试。')));
      }
    }
  }

  Future<void> choose(FieldEvent event, {bool scrollTo = true}) async {
    if (submitting) return;
    final request = ++detailGeneration;
    setState(() {
      selected = event;
      session.selectedKey = event.key;
      detailLoading = true;
      error = null;
      message = null;
      needsVerification = false;
    });
    try {
      final current = await repo.detail(event);
      if (!mounted || request != detailGeneration) return;
      setState(() {
        selected = current;
        snapshot = snapshot?.replace(current);
        detailLoading = false;
      });
      if (current.handled) session.drafts.remove(current.key);
    } catch (e) {
      if (!mounted || request != detailGeneration) return;
      setState(() {
        detailLoading = false;
        error = '详情未加载成功，请重试后再处理。';
        needsVerification = true;
      });
    }
    if (scrollTo && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && detailSheet.isAttached) {
          moveDetail(.86);
        }
      });
    }
  }

  void moveDetail(double extent) {
    if (!mounted || !detailSheet.isAttached) return;
    if (MotionPolicy.reduced(context)) {
      detailSheet.jumpTo(extent);
    } else {
      detailSheet.animateTo(
        extent,
        duration: const Duration(milliseconds: MotionPolicy.panelMs),
        curve: MotionPolicy.panelCurve,
      );
    }
  }

  Future<void> verify() async {
    final event = selected;
    if (event == null || submitting) return;
    final request = ++detailGeneration;
    setState(() => detailLoading = true);
    try {
      final fresh = await repo.detail(event);
      if (!mounted || request != detailGeneration) return;
      setState(() {
        selected = fresh;
        snapshot = snapshot?.replace(fresh);
        needsVerification = false;
        error = null;
        message = fresh.handled ? '后台已确认处理完成。' : '后台显示尚未处理，可继续填写或重试。';
      });
      if (fresh.handled) {
        session.drafts.remove(fresh.key);
        FieldRepository.revision.value++;
      }
    } catch (e) {
      if (mounted && request == detailGeneration)
        setState(() => error = '暂时无法核对后台结果，请重试。草稿已保留。');
    } finally {
      if (mounted && request == detailGeneration)
        setState(() => detailLoading = false);
    }
  }

  Future<void> submit() async {
    final event = selected;
    if (event == null ||
        event.handled ||
        detailLoading ||
        submitting ||
        needsVerification)
      return;
    final draft = session.draft(event.key);
    if (!draft.complete) {
      setState(() => error = '请填写核查情况、处置措施和处理结果。');
      return;
    }
    setState(() {
      submitting = true;
      message = null;
      error = null;
    });
    final request = ++detailGeneration;
    generation++; // Discard a refresh that started before this submission.
    loading = false;
    var sent = false;
    try {
      final fresh = await repo.detail(event);
      if (!mounted || request != detailGeneration) return;
      if (fresh.handled) {
        if (mounted)
          setState(() {
            selected = fresh;
            snapshot = snapshot?.replace(fresh);
            message = '该告警已被处理，已同步后台结果。';
          });
        session.drafts.remove(event.key);
        FieldRepository.revision.value++;
        return;
      }
      sent = true;
      await repo.handle(event, draft.description);
      if (!mounted || request != detailGeneration) return;
      final confirmed = await repo.detail(event);
      if (!mounted || request != detailGeneration) return;
      if (!confirmed.handled) throw StateError('后台尚未确认');
      session.drafts.remove(event.key);
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() {
        selected = confirmed;
        snapshot = snapshot?.replace(confirmed);
        message = '处理已保存到后台，待办数量已更新。';
      });
      FieldRepository.revision.value++;
    } catch (e) {
      if (mounted)
        setState(() {
          needsVerification = sent;
          error = sent
              ? '尚未确认保存结果。草稿已保留，请先核对后台结果，再决定是否重试。'
              : '未能读取最新告警，请重试。草稿已保留。';
        });
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> openTrack(FieldEvent event) async {
    if (submitting) return;
    await context.goto(
      RouteNode.playbackOfTrajectory,
      extra: {
        'hatId': event.hatId,
        'hatNumber': event.hatNumber,
        'userName': event.userName,
        'date': event.time,
      },
    );
    if (mounted) widget.onResume();
  }

  void closeDetail() {
    if (submitting) return;
    FocusScope.of(context).unfocus();
    setState(() {
      selected = null;
      session.selectedKey = '';
      detailGeneration++;
    });
  }

  void filter(void Function() change) {
    if (submitting) return;
    setState(() {
      filterRevision++;
      highlightedEvents.clear();
      change();
      selected = null;
      session.selectedKey = '';
      detailGeneration++;
      visibleLimit = 100;
    });
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  Map<String, String> typesFor(String source) => {
    '': '全部类型',
    if (source != 'fence') ...{
      'sos': 'SOS 求助',
      'removal': '脱帽',
      'fall': '跌倒',
      'silent': '静默',
      'proximity': '近电',
    },
    if (source != 'device') ...{'1': '围栏禁入', '2': '围栏禁出'},
  };

  Future<void> showFilters() async {
    if (submitting) return;
    FocusScope.of(context).unfocus();
    var group = session.group, source = session.source, type = session.type;
    var start = session.start, end = session.end;
    final options = <String, String>{
      '': '全部作业组',
      for (final n in snapshot?.groupNames ?? <String>[]) n: n,
      if (group.isNotEmpty) group: group,
    };
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) {
          final preview = snapshot?.filter(
            group: group,
            source: source,
            type: type,
            start: start,
            end: end,
            search: session.search,
            status: session.status,
          );
          Future<void> pickDate(bool isStart) async {
            final raw = isStart ? start : end;
            final date = await showDatePicker(
              context: context,
              initialDate: DateTime.tryParse(raw) ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 1)),
            );
            if (date == null || !context.mounted) return;
            final value = date.toIso8601String().substring(0, 10);
            update(() {
              if (isStart) {
                start = value;
              } else {
                end = value;
              }
              if (start.isNotEmpty &&
                  end.isNotEmpty &&
                  start.compareTo(end) > 0) {
                if (isStart) {
                  end = value;
                } else {
                  start = value;
                }
              }
            });
          }

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16 +
                  MediaQuery.viewInsetsOf(context).bottom +
                  MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '筛选告警',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '取消筛选',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                drop(
                  '告警来源',
                  source,
                  {'': '设备与围栏', 'device': '设备', 'fence': '围栏'},
                  (v) => update(() {
                    source = v;
                    if (!typesFor(source).containsKey(type)) type = '';
                  }),
                ),
                const SizedBox(height: 16),
                drop('作业分组', group, options, (v) => update(() => group = v)),
                const SizedBox(height: 16),
                drop(
                  '告警类型',
                  type,
                  typesFor(source),
                  (v) => update(() => type = v),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => pickDate(true),
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Text(start.isEmpty ? '开始日期' : start),
                    ),
                    TextButton.icon(
                      onPressed: () => pickDate(false),
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: Text(end.isEmpty ? '结束日期' : end),
                    ),
                    if (start.isNotEmpty || end.isNotEmpty)
                      TextButton(
                        onPressed: () => update(() {
                          start = '';
                          end = '';
                        }),
                        child: const Text('清空日期'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '${snapshot?.complete == true ? '符合条件' : '已加载数据中符合'} ${preview?.length ?? 0} 条 · 应用后更新列表',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () => update(() {
                        group = '';
                        source = '';
                        type = '';
                        start = '';
                        end = '';
                      }),
                      child: const Text('重置'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        child: const Text('应用筛选'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    if (applied != true || !mounted) return;
    filter(() {
      session.group = group;
      session.source = source;
      session.type = type;
      session.start = start;
      session.end = end;
    });
  }

  Widget drop(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> changed,
  ) => DropdownButtonFormField<String>(
    initialValue: options.containsKey(value) ? value : '',
    key: ValueKey('$label:$value'),
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: options.entries
        .map(
          (e) => DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: (v) => changed(v ?? ''),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), current = selected;
    final matches = rows;
    final filtered =
        session.group.isNotEmpty ||
        session.source.isNotEmpty ||
        session.type.isNotEmpty ||
        session.start.isNotEmpty ||
        session.end.isNotEmpty;
    final next = matches
        .where((e) => !e.handled && e.key != current?.key)
        .firstOrNull;
    return PopScope(
      canPop: !submitting && current == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !submitting && selected != null) closeDetail();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '告警工作台',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          actions: [
            IconButton(
              tooltip: '打开 AI 助手',
              onPressed: () => ChatStore.instance.setChatPanelOpen(true),
              icon: const Icon(Icons.smart_toy_outlined),
            ),
            IconButton(
              tooltip: '刷新后台数据',
              onPressed: loading || submitting ? null : reload,
              icon: const Icon(Icons.refresh),
            ),
            PopupMenuButton<String>(
              tooltip: '更多查询方式',
              enabled: !submitting,
              onSelected: (_) => widget.onAdvanced(),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'advanced', child: Text('设备告警分页查询')),
              ],
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: search,
                        enabled: !submitting,
                        decoration: InputDecoration(
                          hintText: '搜索姓名、设备编号或围栏',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: session.search.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清除搜索',
                                  onPressed: submitting
                                      ? null
                                      : () => filter(() {
                                          session.search = '';
                                          search.clear();
                                        }),
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                        onChanged: (v) => filter(() => session.search = v),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final e in {
                                    '0': '待处理',
                                    '1': '已处理',
                                    '': '全部',
                                  }.entries)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: ChoiceChip(
                                        label: Text(e.value),
                                        selected: session.status == e.key,
                                        onSelected: submitting
                                            ? null
                                            : (_) => filter(
                                                () => session.status = e.key,
                                              ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton.icon(
                            onPressed: submitting ? null : showFilters,
                            icon: const Icon(Icons.tune, size: 18),
                            label: Text(filtered ? '已筛选' : '筛选'),
                          ),
                        ],
                      ),
                      if (filtered)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              if (session.group.isNotEmpty)
                                filterChip(
                                  session.group,
                                  () => session.group = '',
                                ),
                              if (session.source.isNotEmpty)
                                filterChip(
                                  session.source == 'fence' ? '围栏告警' : '设备告警',
                                  () => session.source = '',
                                ),
                              if (session.type.isNotEmpty)
                                filterChip(
                                  typesFor('')[session.type] ?? session.type,
                                  () => session.type = '',
                                ),
                              if (session.start.isNotEmpty ||
                                  session.end.isNotEmpty)
                                filterChip(
                                  '${session.start.isEmpty ? '不限' : session.start} 至 ${session.end.isEmpty ? '不限' : session.end}',
                                  () {
                                    session.start = '';
                                    session.end = '';
                                  },
                                ),
                              TextButton(
                                onPressed: submitting
                                    ? null
                                    : () => filter(() {
                                        session.clearFilters();
                                        search.clear();
                                      }),
                                child: const Text('清除筛选'),
                              ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          '${snapshot?.complete == true ? '符合条件' : '已加载'} ${matches.length} 条 · ${matches.where((e) => !e.handled).length} 条待处理',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (loading) const LinearProgressIndicator(),
                Expanded(
                  child: MotionSwap(
                    value: '$filterRevision',
                    child: RefreshIndicator(
                      onRefresh: submitting ? () async {} : reload,
                      child: ListView(
                        key: const ValueKey('alarm-results'),
                        controller: scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          current == null ? 100 : 180,
                        ),
                        children: [
                          if (snapshot != null && !snapshot!.complete)
                            _notice(
                              '${snapshot!.warnings.join('；')}。当前数量仅代表已加载记录，请刷新重试；分页查询仅包含设备告警。',
                              warning: true,
                            ),
                          if (!loading && matches.isEmpty) ...[
                            _notice('没有符合条件的告警，可调整或清除筛选。'),
                            OutlinedButton(
                              onPressed: submitting
                                  ? null
                                  : () => filter(() {
                                      session.clearFilters();
                                      search.clear();
                                    }),
                              child: const Text('显示全部告警'),
                            ),
                          ],
                          for (final event in matches.take(visibleLimit))
                            Card(
                              key: ValueKey(event.key),
                              color:
                                  highlightedEvents.contains(event.key) &&
                                      !MotionPolicy.reduced(context)
                                  ? Colors.deepOrange.withValues(alpha: .10)
                                  : theme.colorScheme.surface,
                              margin: const EdgeInsets.only(bottom: 8),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                selected: event.key == current?.key,
                                selectedColor: theme.colorScheme.onSurface,
                                selectedTileColor: theme.colorScheme.primary
                                    .withValues(alpha: .12),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                leading: Icon(
                                  event.isFence
                                      ? Icons.shield_outlined
                                      : Icons.notifications_active_outlined,
                                  color: event.handled
                                      ? const Color(0xFF24845B)
                                      : event.type == 'sos'
                                      ? theme.colorScheme.error
                                      : Colors.deepOrange,
                                ),
                                title: Text(
                                  '${event.title} · ${event.userName.isEmpty ? '未关联人员' : event.userName}',
                                  maxLines: 2,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${event.hatNumber} · ${event.time}',
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          _eventBadge(
                                            event.handled ? '已处理' : '待处理',
                                            event.handled
                                                ? theme.colorScheme.primary
                                                : Colors.deepOrange,
                                          ),
                                          if (!event.handled &&
                                              event.type == 'sos')
                                            _eventBadge(
                                              'SOS 求助',
                                              theme.colorScheme.error,
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: submitting ? null : () => choose(event),
                              ),
                            ),
                          if (matches.length > visibleLimit)
                            TextButton(
                              onPressed: () =>
                                  setState(() => visibleLimit += 100),
                              child: Text(
                                '继续加载（还剩 ${matches.length - visibleLimit} 条）',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (current != null)
              DraggableScrollableSheet(
                controller: detailSheet,
                initialChildSize: .86,
                minChildSize: .2,
                maxChildSize: 1,
                snap: true,
                snapSizes: const [.2, .86, 1],
                builder: (context, controller) => Material(
                  color: theme.scaffoldBackgroundColor,
                  elevation: 12,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '告警详情',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '展开详情',
                              onPressed: () => moveDetail(1),
                              icon: const Icon(Icons.keyboard_arrow_up),
                            ),
                            IconButton(
                              tooltip: '折叠详情',
                              onPressed: () {
                                FocusScope.of(context).unfocus();
                                moveDetail(.2);
                              },
                              icon: const Icon(Icons.keyboard_arrow_down),
                            ),
                            IconButton(
                              tooltip: '收起详情',
                              onPressed: submitting ? null : closeDetail,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: SingleChildScrollView(
                          key: ValueKey('alarm-detail-content:${current.key}'),
                          controller: controller,
                          padding: EdgeInsets.fromLTRB(
                            16,
                            12,
                            16,
                            24 + MediaQuery.viewPaddingOf(context).bottom,
                          ),
                          child: buildDetail(current, next),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget filterChip(String label, VoidCallback clear) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: InputChip(
      label: Text(label),
      onDeleted: submitting ? null : () => filter(clear),
    ),
  );

  Widget buildDetail(FieldEvent current, FieldEvent? next) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MotionEntrance(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primaryContainer,
                  theme.colorScheme.surface,
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: .16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '告警概况',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    MotionSwap(
                      key: ValueKey('status:${current.key}'),
                      value: '${current.handled}',
                      child: Semantics(
                        liveRegion: true,
                        child: _eventBadge(
                          current.handled ? '已处理' : '待处理',
                          current.handled
                              ? const Color(0xFF24845B)
                              : Colors.deepOrange,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        current.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ExcludeSemantics(
                      child: FieldSceneAccent(
                        scene: current.isFence ? 'fence-card' : 'device-card',
                        size: 64,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _detailLine(Icons.schedule_rounded, '发生时间', current.time),
                if (current.description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    current.description,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: .5),
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '人员与位置',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _detailLine(
                Icons.person_outline_rounded,
                '关联人员',
                '${current.userName} · ${current.hatNumber}',
              ),
              if (current.fenceName.isNotEmpty)
                _detailLine(Icons.fence_rounded, '围栏', current.fenceName),
              _detailLine(
                Icons.location_on_outlined,
                '位置',
                current.positionLabel,
              ),
              const Divider(height: 24),
              _detailLine(
                Icons.sensors_rounded,
                '来源',
                '${current.isFence ? '电子围栏' : '设备告警'} · 编号：${current.id}',
              ),
              _detailLine(Icons.shield_outlined, '告警级别', current.levelLabel),
              _detailLine(
                Icons.event_available_outlined,
                '结束时间',
                fieldText(current.raw['alarmEndTime']).isEmpty
                    ? '后台未提供'
                    : fieldText(current.raw['alarmEndTime']),
              ),
            ],
          ),
        ),
        if (current.position != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: ClipRRect(
              key: ValueKey('map:${current.key}:${current.positionLabel}'),
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 200,
                child: AppMap(
                  initialCenter: LatLng(
                    current.position!.lat,
                    current.position!.lng,
                  ),
                  initialZoom: 15,
                  children: [
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(
                            current.position!.lat,
                            current.position!.lng,
                          ),
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 36,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              onPressed: submitting || current.hatId.isEmpty
                  ? null
                  : () => openTrack(current),
              icon: const Icon(Icons.route, size: 18),
              label: const Text('查看人员轨迹'),
            ),
            if (!current.isFence)
              OutlinedButton(
                onPressed: submitting
                    ? null
                    : () async {
                        await context.goto(
                          RouteNode.alarmDetail,
                          params: {'alarmId': current.id},
                        );
                        if (mounted) widget.onResume();
                        if (mounted) await choose(current, scrollTo: false);
                      },
                child: const Text('完整详情与位置'),
              ),
            if (!current.isFence && !current.handled)
              OutlinedButton(
                onPressed: submitting || detailLoading
                    ? null
                    : () async {
                        setState(() => submitting = true);
                        try {
                          await AlarmApi.answer(current.id);
                          if (mounted)
                            setState(() => message = '后台已接受接听请求；这不代表设备通话已接通。');
                        } catch (e) {
                          if (mounted) setState(() => error = '接听请求失败，请重试。');
                        } finally {
                          if (mounted) setState(() => submitting = false);
                        }
                      },
                child: const Text('接听请求'),
              ),
          ],
        ),
        if (detailLoading) const LinearProgressIndicator(),
        if (error != null) _notice(error!, warning: true),
        if (message != null) _notice(message!),
        if (needsVerification)
          OutlinedButton.icon(
            onPressed: submitting || detailLoading ? null : verify,
            icon: const Icon(Icons.sync),
            label: const Text('核对后台结果'),
          ),
        if (current.handled) ...[
          const SizedBox(height: 10),
          Text(
            '已处理 · ${current.handleTime.isEmpty ? '后台未提供时间' : current.handleTime}',
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: next == null ? null : () => choose(next),
            icon: const Icon(Icons.arrow_forward),
            label: Text(next == null ? '当前筛选下没有下一条' : '处理下一条'),
          ),
        ] else
          _FieldDraftForm(
            key: ValueKey(current.key),
            draft: session.draft(current.key),
            enabled: !detailLoading && !submitting && !needsVerification,
            onSubmit: submit,
            busy: submitting,
          ),
      ],
    );
  }

  Widget _detailLine(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _eventBadge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );

  Widget _notice(String text, {bool warning = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(
      text,
      style: TextStyle(
        color: warning
            ? Colors.deepOrange
            : Theme.of(context).colorScheme.onSurface,
        fontSize: 13,
        height: 1.5,
      ),
    ),
  );
}

class _FieldDraftForm extends StatefulWidget {
  final FieldDraft draft;
  final bool enabled, busy;
  final VoidCallback onSubmit;
  const _FieldDraftForm({
    super.key,
    required this.draft,
    required this.enabled,
    required this.onSubmit,
    required this.busy,
  });
  @override
  State<_FieldDraftForm> createState() => _FieldDraftFormState();
}

class _FieldDraftFormState extends State<_FieldDraftForm> {
  final form = GlobalKey<FormState>();
  bool expanded = true;
  late final inquiry = TextEditingController(text: widget.draft.inquiry);
  late final measure = TextEditingController(text: widget.draft.measure);
  late final result = TextEditingController(text: widget.draft.result);
  @override
  void dispose() {
    inquiry.dispose();
    measure.dispose();
    result.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: .5),
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: widget.busy
              ? null
              : () {
                  if (expanded) FocusScope.of(context).unfocus();
                  setState(() => expanded = !expanded);
                },
          icon: AnimatedRotation(
            turns: expanded ? .5 : 0,
            duration: MotionPolicy.duration(context, MotionPolicy.contentMs),
            curve: MotionPolicy.panelCurve,
            child: const Icon(Icons.expand_more),
          ),
          label: Text(expanded ? '收起核查与处置' : '展开核查与处置'),
        ),
        MotionReveal(
          child: Visibility(
            visible: expanded,
            maintainState: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Text(
                  '切换告警或查看轨迹时保留草稿。退出登录或重启后清除。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '已填写 ${[inquiry, measure, result].where((field) => field.text.trim().isNotEmpty).length}/3 项${[inquiry, measure, result].any((field) => field.text.isNotEmpty) ? ' · 草稿已暂存' : ''}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                TweenAnimationBuilder<double>(
                  tween: Tween(
                    end:
                        [inquiry, measure, result]
                            .where((field) => field.text.trim().isNotEmpty)
                            .length /
                        3,
                  ),
                  duration: MotionPolicy.duration(
                    context,
                    MotionPolicy.contentMs,
                  ),
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(4),
                    semanticsLabel: '处置草稿填写进度',
                  ),
                ),
                const SizedBox(height: 12),
                Form(
                  key: form,
                  child: Column(
                    children: [
                      field('核查情况', inquiry, (v) => widget.draft.inquiry = v),
                      field('处置措施', measure, (v) => widget.draft.measure = v),
                      field('处理结果', result, (v) => widget.draft.result = v),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: widget.enabled
                      ? () {
                          if (form.currentState!.validate()) widget.onSubmit();
                        }
                      : null,
                  icon: widget.busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(widget.busy ? '正在提交并核对…' : '确认完成处理'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  Widget field(
    String label,
    TextEditingController controller,
    ValueChanged<String> changed,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: controller,
      enabled: widget.enabled,
      minLines: 2,
      maxLines: 5,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: true,
        prefixIcon: Icon(
          label == '核查情况'
              ? Icons.fact_check_outlined
              : label == '处置措施'
              ? Icons.build_outlined
              : Icons.task_alt_rounded,
          size: 20,
        ),
      ),
      onChanged: (value) => setState(() => changed(value)),
      validator: (v) => v == null || v.trim().isEmpty ? '请填写$label' : null,
    ),
  );
}
