import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core.dart';
import 'query_utils.dart';
import 'query_widgets.dart';
import 'work_reference.dart';
import 'my_equipment_page.dart';
import 'home_sos_banner.dart';

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
                          _currentWorkCard(summary),
                          const SizedBox(height: 12),
                          _equipmentCard(),
                          const SizedBox(height: 12),
                          _toolsCard(summary),
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

  Widget _currentWorkCard(JsonMap summary) {
    final tasks = jsonList(summary['activeTasks']);
    final task = tasks.isEmpty ? null : tasks.first;
    final title = textOf(task?['title'], '暂无当前作业');
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
                      onPressed: () => context.push('/tasks'),
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
                      task == null ? '未关联' : workOwnerLabel(task, _session!),
                    ),
                    const SizedBox(height: 5),
                    _metaLine(
                      Icons.person_outline,
                      '监护人',
                      task == null ? '未关联' : workGuardianLabel(task),
                    ),
                    const SizedBox(height: 5),
                    _metaLine(
                      Icons.description_outlined,
                      '',
                      task == null ? '暂无来源工作票' : _ticketLine(task),
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
                  onPressed: () => context.push(
                    task == null ? '/tasks' : '/tasks/${idOf(task['id'])}',
                  ),
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
            for (final item in _equipment.take(3))
              _equipmentRow({...item, 'displayStatus': connectionLabel(item)}),
        ],
      ),
    );
  }

  Widget _toolsCard(JsonMap summary) => WearCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WearSectionTitle('现场工具'),
        const SizedBox(height: 10),
        TextField(
          controller: _peopleSearch,
          textInputAction: TextInputAction.search,
          onSubmitted: _openPeopleSearch,
          decoration: InputDecoration(
            hintText: '按姓名查找现场人员',
            prefixIcon: const Icon(Icons.person_search_outlined),
            suffixIcon: IconButton(
              tooltip: '查找人员',
              onPressed: () => _openPeopleSearch(_peopleSearch.text),
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns =
                constraints.maxWidth >= 270 &&
                MediaQuery.textScalerOf(context).scale(14) <= 20;
            final width = twoColumns
                ? (constraints.maxWidth - 10) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _tool(width, 'people', '人员档案', Icons.badge_outlined, '/people'),
                _tool(
                  width,
                  'devices',
                  '全厂设备',
                  Icons.devices_other_outlined,
                  '/devices',
                ),
                _tool(width, 'tracks', '轨迹回放', Icons.route_outlined, '/tracks'),
                _tool(width, 'fences', '电子围栏', Icons.fence_outlined, '/fences'),
                _tool(
                  width,
                  'tasks',
                  '全部作业',
                  Icons.assignment_outlined,
                  '/tasks',
                ),
                _tool(
                  width,
                  'supervision',
                  '失去监护',
                  Icons.health_and_safety_outlined,
                  '/supervision',
                  count: intOf(summary['lostSupervision']),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );

  Widget _tool(
    double width,
    String key,
    String label,
    IconData icon,
    String route, {
    int count = 0,
  }) => SizedBox(
    width: width,
    child: Material(
      color: const Color(0xFFF0F7FF),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('home-tool-$key'),
        onTap: () => context.push(route),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: WearColors.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: WearColors.ink,
                  ),
                ),
              ),
              if (count > 0)
                Text(
                  '$count',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: WearColors.warning,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _equipmentRow(JsonMap item) {
    final status = textOf(item['displayStatus'], '状态未知');
    final online = status == '在线';
    return InkWell(
      onTap: () {
        final id = idOf(item['deviceId']);
        if (id.isEmpty) {
          _openMyEquipment();
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

  Widget _dutyActions(JsonMap summary) => Align(
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
  void _openPeopleSearch(String raw) {
    final name = raw.trim();
    context.push(
      Uri(
        path: '/people',
        queryParameters: {if (name.isNotEmpty) 'name': name},
      ).toString(),
    );
  }
}
