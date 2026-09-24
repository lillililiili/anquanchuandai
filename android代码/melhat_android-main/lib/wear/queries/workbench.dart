import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core.dart';
import 'query_utils.dart';
import 'query_widgets.dart';
import 'work_reference.dart';
import 'my_equipment_page.dart';
import 'home_sos_banner.dart';
import 'inspection_pages.dart';
import 'current_work.dart';
import '../events/manual_sos_page.dart';

class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({super.key});

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage> {
  WearSession? _session;
  JsonMap? _summary;
  JsonMap? _currentTask;
  bool _taskUnavailable = false;
  List<JsonMap> _equipment = const [];
  bool _equipmentUnavailable = false;
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
      JsonMap? currentTask;
      var taskUnavailable = false;
      try {
        currentTask = await loadCurrentWork(session);
      } on StaleSessionException {
        rethrow;
      } catch (_) {
        taskUnavailable = true;
      }
      List<JsonMap> equipment = const [];
      var equipmentUnavailable = false;
      try {
        equipment = await loadEquipmentWithTelemetry(
          session.api,
          '/api/v1/me/equipment',
        );
      } catch (_) {
        equipmentUnavailable = true;
      }
      if (!mounted || request != _request || scopeKey != session.scopeKey) {
        return;
      }
      setState(() {
        _summary = result;
        _currentTask = currentTask;
        _taskUnavailable = taskUnavailable;
        _equipment = equipment;
        _equipmentUnavailable = equipmentUnavailable;
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
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    Container(
                      height: WearHeaderLayout.height(context),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: const BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage(
                            'assets/field-brand/preview/work_reference_header.png',
                          ),
                          fit: BoxFit.cover,
                          opacity: .70,
                          alignment: Alignment.bottomRight,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _pageHeader(),
                          const SizedBox(height: 12),
                          _greeting(),
                          const SizedBox(height: 4),
                          _dutyActions(summary),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          HomeSosBanner(refreshVersion: _request),
                          _currentWorkCard(),
                          const SizedBox(height: 12),
                          _manualSosEntry(),
                          const SizedBox(height: 12),
                          _equipmentCard(),
                          const SizedBox(height: 12),
                          if (_session!.isAdmin)
                            _toolsCard()
                          else
                            _inspectionTools(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _pageHeader() => const Padding(
    padding: EdgeInsets.only(top: 10),
    child: Row(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: WearRollingWordmark(height: 22),
        ),
        Spacer(),
        WearSiteSwitcher(),
      ],
    ),
  );
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

  Widget _currentWorkCard() {
    final task = _currentTask;
    if (_taskUnavailable || task == null) return _currentWorkPlaceholder();
    final title = textOf(task['title']);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final height = 228.0 + (textScale - 1).clamp(0, 2) * 130;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                bottom: 40,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/field-brand/preview/work_reference_scene.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                  ),
                ),
              ),
              Positioned(
                top: 1,
                left: 4,
                right: 2,
                child: Row(
                  children: [
                    Container(
                      width: 5,
                      height: 25,
                      decoration: BoxDecoration(
                        color: const Color(0xFF008BFF),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      '当前作业',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF101F43),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _openGroupTasks(task),
                      child: const Text('全部作业', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 5,
                top: 43,
                right: 118,
                bottom: 50,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF101F43),
                          ),
                        ),
                      ),
                    ),
                    _metaLine(
                      Icons.person_outline,
                      '负责人',
                      workOwnerLabel(task, _session!),
                    ),
                    const SizedBox(height: 5),
                    _metaLine(
                      Icons.person_outline,
                      '监护人',
                      workGuardianLabel(task),
                    ),
                    const SizedBox(height: 5),
                    _metaLine(
                      Icons.description_outlined,
                      '',
                      _ticketLine(task),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: FilledButton(
                  key: const ValueKey('view-current-work'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF008BFF),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  onPressed: () => _openCurrentWork(task),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '查看作业',
                        style: TextStyle(
                          fontSize: 17,
                          decoration: TextDecoration.none,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.chevron_right, size: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCurrentWork(JsonMap task) async {
    await context.push('/tasks/${idOf(task['id'])}');
    if (mounted) await _load(silent: true);
  }

  Widget _currentWorkPlaceholder() => WearCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WearSectionTitle('当前作业'),
        const SizedBox(height: 18),
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Color(0xFFE8F1FF),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _taskUnavailable
                  ? Icons.cloud_off_outlined
                  : Icons.task_alt_rounded,
              size: 30,
              color: WearColors.brand,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _taskUnavailable ? '当前任务加载失败' : '当前无任务',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: WearColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _taskUnavailable ? '暂时无法确认任务状态，请重试' : '暂无待完成作业，可查看任务列表与完成记录',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: WearColors.muted,
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _taskUnavailable
              ? () => _load(silent: true)
              : () => context.push('/tasks'),
          icon: Icon(
            _taskUnavailable ? Icons.refresh : Icons.assignment_outlined,
            size: 18,
          ),
          label: Text(_taskUnavailable ? '重新加载' : '查看任务列表'),
        ),
      ],
    ),
  );

  Widget _metaLine(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: WearColors.muted),
          const SizedBox(width: 6),
          if (label.isNotEmpty)
            Text(
              '$label  ',
              style: const TextStyle(color: WearColors.muted, fontSize: 12),
            ),
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
      return textOf(task['ticketNo'], '无需工作票');
    }
    return switch (task['ticketStatus']?.toString()) {
      'provided' => '${textOf(task['ticketNo'])} · 来源工作票',
      'unverified' => '待核实',
      _ => textOf(task['ticketNo'], '来源工作票'),
    };
  }

  void _openMyEquipment() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const MyEquipmentPage(backLabel: '返回现场'),
      ),
    );
  }

  Widget _equipmentCard() {
    return WearCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WearSectionTitle(
            '我的装备',
            trailing: TextButton(
              key: const ValueKey('home-my-equipment'),
              onPressed: _openMyEquipment,
              child: const Text('查看全部 >'),
            ),
          ),
          if (_equipment.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: 32,
                    color: WearColors.muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _equipmentUnavailable ? '装备信息暂未获取' : '暂无已绑定装备',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: WearColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _equipmentUnavailable ? '下拉刷新后重试' : '查看全部可进入个人装备页面',
                          style: const TextStyle(
                            fontSize: 12,
                            color: WearColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            for (final item in _equipment.take(3)) _equipmentRow(item),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('home-equipment-status'),
              onPressed: _openMyEquipment,
              style: TextButton.styleFrom(
                foregroundColor: WearColors.brand,
                backgroundColor: const Color(0xFFF0F7FF),
                minimumSize: const Size(48, 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.battery_charging_full_rounded, size: 18),
              label: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('设备状态'),
                  SizedBox(width: 6),
                  Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _manualSosEntry() => Material(
    color: const Color(0xFFFFF1F0),
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      key: const ValueKey('home-manual-sos'),
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final id = await Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => const ManualSosPage()),
        );
        if (!mounted || id == null) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('SOS 报警已提交，等待管理员审批')));
        context.push('/events?eventId=${Uri.encodeComponent(id)}');
      },
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.sos, color: Color(0xFFD92D20), size: 30),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '手动 SOS 报警',
                    style: TextStyle(
                      color: Color(0xFFB42318),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '填写现场情况，提交管理员处理',
                    style: TextStyle(color: WearColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Color(0xFFB42318)),
          ],
        ),
      ),
    ),
  );

  Widget _inspectionTools() => WearCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WearSectionTitle('巡检工具'),
        const SizedBox(height: 10),
        _inspectionToolRow(
          icon: Icons.assignment_outlined,
          title: '我的任务',
          subtitle: '查看任务与填写巡检结果',
          highlighted: true,
          onTap: () => context.push('/tasks'),
        ),
        _inspectionToolRow(
          icon: Icons.fact_check_outlined,
          title: '巡检记录',
          subtitle: _recordTask == null ? '当前暂无作业' : '查看当前作业巡检进度与异常记录',
          onTap: _recordTask == null ? null : _openInspectionRecords,
        ),
      ],
    ),
  );

  void _openInspectionRecords() {
    final task = _recordTask;
    if (task == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            InspectionGroupTasksPage(taskId: idOf(task['id']), allTasks: false),
      ),
    );
  }

  JsonMap? get _recordTask =>
      _currentTask ?? jsonList(_summary?['activeTasks']).firstOrNull;

  Widget _inspectionToolRow({
    Key? key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool highlighted = false,
    int count = 0,
  }) => Material(
    color: highlighted ? const Color(0xFFF5F5F5) : Colors.white,
    child: InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: WearColors.brand),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: WearColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: WearColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (count > 0) ...[
              Text(
                '$count',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: WearColors.warning,
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.chevron_right, size: 20, color: WearColors.muted),
          ],
        ),
      ),
    ),
  );

  Widget _toolsCard() => WearCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WearSectionTitle('现场管理'),
        const SizedBox(height: 10),
        _tool('people', '人员档案', '查看现场人员与档案信息', Icons.badge_outlined, '/people'),
        _tool(
          'devices',
          '全厂设备',
          '查看设备状态与绑定信息',
          Icons.devices_other_outlined,
          '/devices',
        ),
        _tool(
          'tasks',
          '全部作业',
          '查看作业安排与执行进度',
          Icons.assignment_outlined,
          '/tasks',
        ),
      ],
    ),
  );

  Widget _tool(
    String key,
    String label,
    String subtitle,
    IconData icon,
    String route, {
    int count = 0,
  }) => _inspectionToolRow(
    key: ValueKey('home-tool-$key'),
    icon: icon,
    title: label,
    subtitle: subtitle,
    count: count,
    onTap: () =>
        route == '/tasks' ? _openGroupTasks(_currentTask) : context.push(route),
  );

  Widget _equipmentRow(JsonMap item) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        final id = idOf(item['deviceId']);
        if (id.isEmpty) {
          _openMyEquipment();
          return;
        }
        if (_session!.isAdmin) {
          context.push('/devices/$id');
        } else {
          _openMyEquipment();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 290 ||
                MediaQuery.textScalerOf(context).scale(12) > 16;
            return Row(
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
                        textOf(
                          item['displayName'],
                          deviceTypeLabel(item['typeCode']),
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: WearColors.ink,
                        ),
                      ),
                      Text(
                        textOf(item['sn']),
                        style: const TextStyle(
                          fontSize: 12,
                          color: WearColors.muted,
                        ),
                      ),
                      if (stacked) ...[
                        const SizedBox(height: 6),
                        _equipmentBatteryBadge(item),
                      ],
                    ],
                  ),
                ),
                if (!stacked) ...[
                  const SizedBox(width: 8),
                  _equipmentBatteryBadge(item),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  void _openGroupTasks(JsonMap? task) {
    final groupId = idOf(task?['id']);
    context.push(
      task?['workType'] == 'patrol' && groupId.isNotEmpty
          ? '/tasks?groupId=${Uri.encodeComponent(groupId)}'
          : '/tasks',
    );
  }

  Widget _equipmentBatteryBadge(JsonMap item) {
    final status = connectionLabel(item);
    final raw = num.tryParse(item['battery']?.toString() ?? '');
    // Device telemetry is a percentage; 1 means 1%, never a full battery.
    final percent =
        item['telemetryUnavailable'] != true &&
            raw != null &&
            raw.isFinite &&
            raw >= 0 &&
            raw <= 100
        ? raw.round()
        : null;
    final current = status == '在线' && percent != null;
    final color = !current
        ? WearColors.muted
        : percent <= 20
        ? const Color(0xFFBF3434)
        : percent <= 50
        ? const Color(0xFFA65B00)
        : const Color(0xFF168447);
    final background = !current
        ? const Color(0xFFF0F3F7)
        : percent <= 20
        ? const Color(0xFFFFEEEE)
        : percent <= 50
        ? const Color(0xFFFFF5E5)
        : const Color(0xFFEAF8EF);
    final battery = percent == null ? '电量未知' : '$percent%';
    final label = status == '在线'
        ? '$status $battery'
        : '$status\n${percent == null ? battery : '上次 $battery'}';
    return Semantics(
      label:
          '$status，${percent == null ? '电量未知' : '${current ? '电量' : '上次电量'}百分之$percent'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _dutyActions(JsonMap summary) => !_session!.isAdmin
      ? const SizedBox(height: 32)
      : Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const ValueKey('home-start-handover'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF008BFF),
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(48, 32),
              padding: const EdgeInsets.symmetric(horizontal: 5),
            ),
            onPressed: () => context.push('/handovers'),
            child: const Text('发起值班交接', style: TextStyle(fontSize: 11)),
          ),
        );
}
