import '../components/field_home_actions.dart';
import '../components/tech_surface.dart';
import '../components/field_motion.dart';
import 'package:flutter/material.dart';
import '../components/field_assistant_action.dart';
import '../components/field_brand.dart';
import '../components/field_tools_section.dart';
import '../components/field_workbench_cards.dart';
import '../models/hat.dart';
import '../router/route_tree.dart';
import '../store/user_store.dart';
import 'field_data.dart';
import 'field_session.dart';

class FieldHomePage extends StatefulWidget {
  const FieldHomePage({super.key});
  @override
  State<FieldHomePage> createState() => _FieldHomePageState();
}

class _FieldHomePageState extends State<FieldHomePage> {
  final repo = FieldRepository(), session = FieldSession.instance;
  FieldSnapshot? data;
  bool loading = true;
  int requestId = 0;
  DateTime? updated;
  String todoSource = '';
  @override
  void initState() {
    super.initState();
    session.scope(UserStore.instance.userInfo?.userId ?? '');
    FieldRepository.revision.addListener(load);
    load();
  }

  @override
  void dispose() {
    requestId++;
    FieldRepository.revision.removeListener(load);
    super.dispose();
  }

  Future<void> load() async {
    final id = ++requestId;
    if (mounted) setState(() => loading = true);
    final next = await repo.load();
    if (!mounted || id != requestId) return;
    setState(() {
      data = next;
      if (next.complete && !next.groupNames.contains(session.group))
        session.group = '';
      loading = false;
      updated = DateTime.now();
    });
  }

  Future<void> alarms([FieldEvent? event]) async {
    session.search = '';
    session.source = todoSource;
    session.type = '';
    session.start = '';
    session.end = '';
    session.status = '0';
    session.selectedKey = event?.key ?? '';
    await context.goto(RouteNode.alarmRecord);
    if (mounted) await load();
  }

  Future<void> devices({
    String status = '',
    bool low = false,
    bool focusSearch = false,
  }) async {
    final hats =
        data?.hats
            .where((h) => session.group.isEmpty || h.bindGroup == session.group)
            .toList() ??
        [];
    final chosen = await showModalBottomSheet<Hat>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => FieldDeviceSheet(
        hats: hats,
        focusSearch: focusSearch,
        status: status,
        low: low,
        complete: data?.devices.complete ?? false,
        group: session.group,
      ),
    );
    if (chosen == null || !mounted) return;
    await context.goto(
      RouteNode.playbackOfTrajectory,
      extra: {
        'hatId': chosen.id,
        'hatNumber': chosen.hatNumber,
        'userName': chosen.bindUserName,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hats =
        data?.hats
            .where((h) => session.group.isEmpty || h.bindGroup == session.group)
            .toList() ??
        [];
    final allPending = data?.filter(group: session.group, status: '0') ?? [];
    final pending = allPending
        .where((event) => todoSource.isEmpty || event.source == todoSource)
        .toList();
    final online = hats.where((h) => h.status == '1').length;
    final low = hats
        .where((h) => h.electricityUsage != null && h.electricityUsage! <= 20)
        .length;
    final groups = <String>{'', ...data?.groupNames ?? []};
    final partial = data != null && !data!.complete;
    final waiting = loading && data == null;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
            children: [
              Row(
                children: [
                  const FieldBrandMark(size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '现场安全工作台',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            letterSpacing: -.3,
                          ),
                        ),
                        Text(
                          '你好，${UserStore.instance.userInfo?.nickName ?? '现场管理员'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const FieldAssistantAction(),
                  IconButton(
                    tooltip: '刷新工作台',
                    onPressed: loading ? null : load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FieldHomeActions(
                groups: groups,
                group: groups.contains(session.group) ? session.group : '',
                enabled: !loading,
                onGroupChanged: (value) =>
                    setState(() => session.group = value),
                onSearch: () => devices(focusSearch: true),
              ),
              const SizedBox(height: 12),
              if (loading) const LinearProgressIndicator(),
              if (partial)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    '${data!.warnings.join('；')}。数量仅统计已加载数据，下拉重试。',
                    style: const TextStyle(
                      color: Colors.deepOrange,
                      height: 1.5,
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '优先待办',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => alarms(),
                    child: Text('查看全部 (${pending.length})'),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final entry in {
                    '': '全部',
                    'device': '设备',
                    'fence': '围栏',
                  }.entries)
                    ChoiceChip(
                      label: Text(
                        '${entry.value} ${waiting ? '—' : allPending.where((event) => entry.key.isEmpty || event.source == entry.key).length}',
                      ),
                      selected: todoSource == entry.key,
                      onSelected: waiting
                          ? null
                          : (_) => setState(() => todoSource = entry.key),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (pending.isEmpty && !loading)
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          partial ? '已加载数据中暂无待办，请先完成同步。' : '当前作业组与来源下暂无待处理告警。',
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: partial ? load : () => devices(),
                          icon: Icon(
                            partial
                                ? Icons.refresh
                                : Icons.construction_outlined,
                          ),
                          label: Text(partial ? '重新同步' : '查看设备状态'),
                        ),
                      ],
                    ),
                  ),
                ),
              for (final event in pending.take(4))
                FieldEventCard(event: event, onTap: () => alarms(event)),
              const SizedBox(height: 12),
              MotionEntrance(
                child: FieldDeviceOverview(
                  online: online,
                  total: hats.length,
                  offline: hats.where((h) => h.status == '0').length,
                  low: low,
                  waiting: waiting,
                  onOnline: () => devices(status: '1'),
                  onOffline: () => devices(status: '0'),
                  onLow: () => devices(low: true),
                ),
              ),
              const SizedBox(height: 10),
              FieldToolsSection(
                onTrack: () => context.goto(RouteNode.playbackOfTrajectory),
                onDevices: () => devices(),
                onFence: () => context.goto(RouteNode.geoFence),
                onMyHelmet: () => context.goto(RouteNode.mySafetyHat),
                onCheckIn: () => context.goto(RouteNode.checkIn),
                onAiConfig: () => context.goto(RouteNode.aiConfig),
              ),
              if (updated != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    '后台数据 · 最近读取 ${updated!.hour.toString().padLeft(2, '0')}:${updated!.minute.toString().padLeft(2, '0')}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class FieldDeviceSheet extends StatefulWidget {
  final List<Hat> hats;
  final String status, group;
  final bool low, complete, focusSearch;
  const FieldDeviceSheet({
    super.key,
    required this.hats,
    this.status = '',
    this.group = '',
    this.low = false,
    this.focusSearch = false,
    required this.complete,
  });
  @override
  State<FieldDeviceSheet> createState() => _FieldDeviceSheetState();
}

class _FieldDeviceSheetState extends State<FieldDeviceSheet> {
  final search = TextEditingController();
  final scroll = ScrollController();
  late String status = widget.status;
  late bool low = widget.low;
  @override
  void dispose() {
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  void clearFilters() => setState(() {
    search.clear();
    status = '';
    low = false;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final term = search.text.trim().toLowerCase();
    final rows = widget.hats
        .where(
          (h) =>
              (status.isEmpty || h.status == status) &&
              (!low ||
                  (h.electricityUsage != null && h.electricityUsage! <= 20)) &&
              [
                h.hatNumber,
                h.bindUserName,
                h.bindGroup,
              ].join(' ').toLowerCase().contains(term),
        )
        .toList();
    final filtered = status.isNotEmpty || low || term.isNotEmpty;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .82,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: CustomScrollView(
          key: const PageStorageKey('field-device-results'),
          controller: scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const FieldSceneAccent(scene: 'device-card', size: 40),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '设备状态',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭设备列表',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: search,
                      autofocus: widget.focusSearch,
                      decoration: InputDecoration(
                        hintText: '搜索姓名、设备或作业组',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清除设备搜索',
                                onPressed: () => setState(search.clear),
                                icon: const Icon(Icons.close),
                              ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final entry in {
                          '': '全部状态',
                          '1': '在线',
                          '0': '离线',
                        }.entries)
                          ChoiceChip(
                            label: Text(entry.value),
                            selected: status == entry.key,
                            onSelected: (_) =>
                                setState(() => status = entry.key),
                          ),
                        FilterChip(
                          label: const Text('低电量 ≤20%'),
                          selected: low,
                          onSelected: (v) => setState(() => low = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        MotionSwap(
                          value: '$status:$low:$term',
                          child: Text(
                            '${widget.group.isEmpty ? '全部作业组' : widget.group} · ${widget.complete ? '' : '已加载 '}${rows.length} 台',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        if (filtered)
                          TextButton(
                            onPressed: clearFilters,
                            child: const Text('清除条件'),
                          ),
                      ],
                    ),
                    if (!widget.complete) const Text('数据未完整，关闭后可下拉刷新工作台。'),
                  ],
                ),
              ),
            ),
            if (rows.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Text('没有符合当前条件的设备'),
                      if (filtered)
                        TextButton(
                          onPressed: clearFilters,
                          child: const Text('显示当前作业组全部设备'),
                        ),
                    ],
                  ),
                ),
              ),
            SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final h = rows[index];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: MotionSwap(
                    value: '$status:$low:$term',
                    child: MotionPress(
                      enabled: h.id != null,
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: TechSurface(
                          radius: 16,
                          child: ListTile(
                            title: Text(
                              h.bindUserName?.isNotEmpty == true
                                  ? h.bindUserName!
                                  : '未绑定人员',
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${h.hatNumber ?? '—'} · ${h.bindGroup ?? '未分组'}',
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    _deviceBadge(
                                      h.status == '1'
                                          ? '在线'
                                          : h.status == '0'
                                          ? '离线'
                                          : '状态未知',
                                      h.status == '1'
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurfaceVariant,
                                      h.status == '1'
                                          ? Icons.wifi
                                          : Icons.wifi_off,
                                    ),
                                    _deviceBadge(
                                      h.electricityUsage == null
                                          ? '电量未提供'
                                          : '${h.electricityUsage!.toStringAsFixed(0)}% 电量',
                                      h.electricityUsage != null &&
                                              h.electricityUsage! <= 20
                                          ? Colors.deepOrange
                                          : theme.colorScheme.onSurfaceVariant,
                                      Icons.battery_std,
                                    ),
                                  ],
                                ),
                                if (h.id == null) const Text('缺少设备编号，无法查看轨迹'),
                              ],
                            ),
                            trailing: h.id == null
                                ? null
                                : const Icon(
                                    Icons.route_outlined,
                                    semanticLabel: '查看人员轨迹',
                                  ),
                            onTap: h.id == null
                                ? null
                                : () => Navigator.pop(context, h),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 16 + MediaQuery.viewPaddingOf(context).bottom,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceBadge(String text, Color color, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(icon, size: 14, color: color),
          ),
          TextSpan(text: ' $text'),
        ],
      ),
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}
