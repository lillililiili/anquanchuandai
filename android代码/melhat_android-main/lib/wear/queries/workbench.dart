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
  List<JsonMap> _equipment = const [];
  int? _inboxCount;
  bool _loading = true;
  Object? _error;
  int _request = 0;
  bool _handoverBusy = false;

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
      List<JsonMap> equipment = const [];
      int? inboxCount;
      try {
        equipment = jsonList(await session.api.get('/api/v1/me/equipment'));
      } catch (_) {}
      try {
        inboxCount = intOf(
          jsonMap(await session.api.get('/api/v1/events/inbox/count'))['count'],
        );
      } catch (_) {}
      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _summary = result;
        _equipment = equipment;
        _inboxCount = inboxCount;
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
    return Scaffold(
      backgroundColor: WearColors.background,
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _pageHeader(),
                    const SizedBox(height: 12),
                    _greeting(),
                    const SizedBox(height: 12),
                    _dutyActions(summary),
                    const SizedBox(height: 12),
                    _currentWorkCard(summary),
                    const SizedBox(height: 12),
                    _equipmentCard(),
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

  Widget _pageHeader() {
    final session = _session;
    final count = intOf(_summary?['unclaimed']);
    return Row(
      children: [
        const FittedBox(
          fit: BoxFit.scaleDown,
          child: WearRollingWordmark(height: 24),
        ),
        const SizedBox(width: 8),
        Container(width: 1, height: 20, color: WearColors.line),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: session == null || session.busy || session.callActive.value
                ? null
                : () => context.go('/sites'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '现场',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: WearColors.ink,
                    height: 1.1,
                  ),
                ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        session?.siteName ?? '临江示范电厂',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: WearColors.muted,
                        ),
                      ),
                    ),
                    const Icon(Icons.expand_more, size: 16, color: WearColors.muted),
                  ],
                ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: '消息',
          onPressed: () => context.go('/events'),
          icon: Badge(
            isLabelVisible: count > 0,
            child: const Icon(Icons.notifications_none, color: WearColors.ink),
          ),
        ),
      ],
    );
  }

  Widget _greeting() {
    final me = _session?.me;
    final name = textOf(me?['nickName'], textOf(me?['userName'], '值班员'));
    final hour = DateTime.now().hour;
    final hello = hour < 12
        ? '上午好'
        : hour < 18
        ? '下午好'
        : '晚上好';
    final now = DateTime.now();
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return Row(
      children: [
        const WearAssetImage(
          WearArt.characterAvatar,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          borderRadius: BorderRadius.all(Radius.circular(22)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$name，$hello',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: WearColors.ink,
                ),
              ),
              const Text(
                '平安作业，安全为先',
                style: TextStyle(fontSize: 12, color: WearColors.muted),
              ),
            ],
          ),
        ),
        Flexible(
          child: Text(
            '${now.year}年${now.month.toString().padLeft(2, '0')}月${now.day.toString().padLeft(2, '0')}日\n${weekdays[now.weekday - 1]}',
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              height: 1.35,
              color: WearColors.muted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _currentWorkCard(JsonMap summary) {
    final tasks = jsonList(summary['activeTasks']);
    final task = tasks.isEmpty ? null : tasks.first;
    final title = textOf(task?['title'], '锅炉平台检修');
    final space = textOf(task?['spaceName'], 'B12');
    final ticket = task == null
        ? 'GL-20260915-018 · 来源工作票'
        : _ticketLine(task);
    void open() {
      if (task != null) {
        context.push('/tasks/${idOf(task['id'])}');
      } else {
        context.push('/tasks');
      }
    }
    return WearCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WearSectionTitle('当前作业'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: WearColors.ink,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3C4),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            space,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF8A6A00),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _metaLine(Icons.person_outline, '负责人', '李志远'),
                    _metaLine(Icons.person_outline, '监护人', '周明'),
                    _metaLine(Icons.description_outlined, '', ticket),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const WearAssetImage(
                WearArt.workScene,
                width: 92,
                height: 108,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: open,
            child: const Text('查看作业  >'),
          ),
        ],
      ),
    );
  }

  Widget _metaLine(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: WearColors.muted),
          const SizedBox(width: 6),
          if (label.isNotEmpty)
            Text('$label  ', style: const TextStyle(color: WearColors.muted, fontSize: 12)),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: WearColors.ink),
            ),
          ),
        ],
      ),
    );
  }

  String _ticketLine(JsonMap task) {
    if (task['ticketRequired'] != true) {
      return textOf(task['ticketNo'], 'GL-20260915-018 · 来源工作票');
    }
    return switch (task['ticketStatus']?.toString()) {
      'provided' => '${textOf(task['ticketNo'])} · 来源工作票',
      'unverified' => '待核实',
      _ => textOf(task['ticketNo'], '来源工作票'),
    };
  }

  List<JsonMap> _displayEquipment() {
    JsonMap? live(String type) {
      for (final item in _equipment) {
        if (item['typeCode']?.toString() == type) return item;
      }
      return null;
    }

    JsonMap row(String type, String name, String sn, String status, bool online) {
      final item = live(type);
      if (item != null) {
        return {
          ...item,
          'displayName': name,
          'displayStatus': connectionLabel(item),
        };
      }
      return {
        'typeCode': type,
        'sn': sn,
        'displayName': name,
        'displayStatus': status,
        'online': online,
        'showcase': true,
      };
    }

    return [
      row('helmet', '安全帽', 'RL-H001', '在线', true),
      row('belt', '安全带', 'RL-B001', '连接中断', false),
      row('watch', '手表', 'RL-W001', '在线', true),
    ];
  }

  Widget _equipmentCard() {
    final rows = _displayEquipment();
    return WearCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WearSectionTitle(
            '我的装备',
            trailing: TextButton(
              onPressed: () => context.push('/devices'),
              child: const Text('查看全部 >'),
            ),
          ),
          for (final item in rows) _equipmentRow(item),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6E8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const WearAssetImage(
                  WearArt.warningTriangle,
                  width: 28,
                  height: 28,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '安全带连接中断',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFC2410C),
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '待现场核验 · 连接中断不直接判定违规',
                        style: TextStyle(fontSize: 11, color: WearColors.muted),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: () => context.go('/events'),
                  child: const Text('去核验'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => context.go('/me'),
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('查看我的装备  >'),
          ),
        ],
      ),
    );
  }

  Widget _equipmentRow(JsonMap item) {
    final status = textOf(item['displayStatus'], '状态未知');
    final online = status == '在线';
    return InkWell(
      onTap: () {
        final id = idOf(item['deviceId']);
        if (id.isEmpty) {
          context.push('/devices');
          return;
        }
        context.push('/devices/$id');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            WearAssetImage(
              WearArt.equipment(item['typeCode']),
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    textOf(item['displayName'], deviceTypeLabel(item['typeCode'])),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: WearColors.ink,
                    ),
                  ),
                  Text(
                    textOf(item['sn']),
                    style: const TextStyle(fontSize: 12, color: WearColors.muted),
                  ),
                ],
              ),
            ),
            WearStatusDot(
              label: status,
              color: online
                  ? WearColors.online
                  : status.contains('断')
                  ? WearColors.warning
                  : WearColors.muted,
            ),
            const Icon(Icons.chevron_right, color: WearColors.muted),
          ],
        ),
      ),
    );
  }

  Widget _dutyActions(JsonMap summary) {
    final hasUnclaimed = intOf(summary['unclaimed']) > 0;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () =>
                context.go(hasUnclaimed ? '/events?status=open' : '/events'),
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: Text(hasUnclaimed ? '查看待认领事件' : '打开事件中心'),
          ),
        ),
        if (_session?.isDuty == true) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _handoverBusy ? null : _startHandover,
              icon: _handoverBusy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.swap_horiz_rounded, size: 20),
              label: const Text('发起值班交接'),
            ),
          ),
        ],
      ],
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

  Future<void> _startHandover() async {
    final session = _session;
    if (session == null || !session.isDuty || _handoverBusy) return;
    FocusScope.of(context).unfocus();
    setState(() => _handoverBusy = true);
    List<JsonMap> operators = const [];
    try {
      operators = jsonList(
        await session.api.get('/api/v1/duty/operators'),
      ).where((item) => idOf(item['userId']) != session.userId).toList();
    } catch (error) {
      if (error is StaleSessionException || !mounted) return;
      final message = error is WearApiException ? error.message : '交接未提交，请稍后重试';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    } finally {
      if (mounted) setState(() => _handoverBusy = false);
    }
    if (!mounted || session != _session) return;
    TextEditingController? comment;
    try {
      if (operators.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前厂站没有可接班的其他值班人员')),
        );
        return;
      }

      final formKey = GlobalKey<FormState>();
      comment = TextEditingController();
      String? toUserId;
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '发起值班交接',
                  style: TextStyle(
                    color: WearColors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '当前负责的事件与任务将由服务端自动生成交接快照。',
                  style: TextStyle(color: WearColors.muted, height: 1.5),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: toUserId,
                  decoration: const InputDecoration(labelText: '接班人'),
                  items: operators
                      .map(
                        (item) => DropdownMenuItem(
                          value: idOf(item['userId']),
                          child: Text(
                            textOf(item['nickName']).isNotEmpty
                                ? textOf(item['nickName'])
                                : textOf(item['userName'], '未命名值班员'),
                          ),
                        ),
                      )
                      .toList(),
                  validator: (value) => value == null ? '请选择接班人' : null,
                  onChanged: (value) => toUserId = value,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: comment,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: '交接备注（选填）',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() != true) return;
                    Navigator.pop(sheetContext, true);
                  },
                  child: const Text('提交交接'),
                ),
              ],
            ),
          ),
          ),
        ),
      );
      final note = comment.text.trim();
      if (confirmed != true || toUserId == null || !mounted) return;
      await session.api.post(
        '/api/v1/duty/handovers',
        data: {
          'toUserId': toUserId,
          if (note.isNotEmpty) 'comment': note,
        },
      );
      if (!mounted || session != _session) return;
      session.requestRefresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('交接已发起，等待接班人确认')),
      );
    } catch (error) {
      if (error is StaleSessionException || !mounted) return;
      final message = error is WearApiException ? error.message : '交接未提交，请稍后重试';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      if (error is WearApiException && error.code == 409) {
        session.requestRefresh();
      }
    } finally {
      final toDispose = comment;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        toDispose?.dispose();
      });
      if (mounted && _handoverBusy) {
        setState(() => _handoverBusy = false);
      }
    }
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
