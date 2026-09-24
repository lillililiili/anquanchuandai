import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core.dart';
import '../scroll_to_top.dart';
import '../inline_filters.dart';
import 'event_controller.dart';
import 'event_models.dart';
import 'event_repository.dart';
import 'event_state_store.dart';
import 'event_reference_view.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({
    super.key,
    this.eventId,
    this.personId,
    this.taskId,
    this.initialClaimantUserId,
    this.initialEscalated,
    this.initialStatus,
    this.initialType,
  });

  final String? eventId;
  final String? personId;
  final String? taskId;
  final String? initialClaimantUserId;
  final bool? initialEscalated;
  final String? initialStatus;
  final String? initialType;

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  final ScrollController _scroll = ScrollController();
  final Map<String, TextEditingController> _handleEditors = {};
  EventController? _controller;
  WearSession? _session;
  String? _scopeKey;
  Timer? _scrollSave;
  int _routeGeneration = 0;
  JsonMap? _dutySummary;
  String? _summaryScope;
  int _summaryRequest = 0;
  bool _openingFilters = false;
  List<JsonMap> _filterOptions = [];
  String? _filterOptionsScope;
  String? _filterOptionsError;

  @override
  void didUpdateWidget(covariant EventsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (controller == null) return;
    var next = controller.filters;
    var filtersChanged = false;
    if (oldWidget.personId != widget.personId) {
      next = next.copyWith(personId: widget.personId ?? '');
      filtersChanged = true;
    }
    if (oldWidget.taskId != widget.taskId) {
      next = next.copyWith(taskId: widget.taskId ?? '');
      filtersChanged = true;
    }
    if (oldWidget.initialClaimantUserId != widget.initialClaimantUserId) {
      next = next.copyWith(claimantUserId: widget.initialClaimantUserId ?? '');
      filtersChanged = true;
    }
    if (oldWidget.initialEscalated != widget.initialEscalated) {
      next = next.copyWith(escalated: widget.initialEscalated ?? false);
      filtersChanged = true;
    }
    if (oldWidget.initialStatus != widget.initialStatus) {
      next = next.copyWith(status: widget.initialStatus ?? 'active');
      filtersChanged = true;
    }
    if (oldWidget.initialType != widget.initialType) {
      next = next.copyWith(type: widget.initialType ?? '');
      filtersChanged = true;
    }
    final eventChanged = oldWidget.eventId != widget.eventId;
    if (!filtersChanged && !eventChanged) return;
    final routeRequest = ++_routeGeneration;
    unawaited(() async {
      if (filtersChanged) await controller.setFilters(next);
      if (!mounted ||
          !identical(controller, _controller) ||
          routeRequest != _routeGeneration ||
          !eventChanged) {
        return;
      }
      if (widget.eventId case final eventId? when eventId.isNotEmpty) {
        await controller.select(eventId);
      } else {
        await controller.closeDetail();
      }
    }());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (_controller == null) {
      _session = session;
      _scopeKey = session.scopeKey;
      _controller = _buildController(session)..addListener(_changed);
      session.refreshTick.addListener(_serverSignaled);
      unawaited(_initializeAndRestoreScroll());
    } else if (!identical(_session, session)) {
      _session?.refreshTick.removeListener(_serverSignaled);
      _controller?.removeListener(_changed);
      _controller?.dispose();
      _session = session;
      _scopeKey = session.scopeKey;
      _controller = _buildController(session)..addListener(_changed);
      session.refreshTick.addListener(_serverSignaled);
      unawaited(_initializeAndRestoreScroll());
    } else if (_scopeKey != session.scopeKey) {
      _session?.refreshTick.removeListener(_serverSignaled);
      _session = session;
      _scopeKey = session.scopeKey;
      session.refreshTick.addListener(_serverSignaled);
      unawaited(
        _controller!
            .replaceScope(
              scopeKey: session.scopeKey,
              actor: _actor(session),
              store: _store(session),
            )
            .then((_) => _restoreScroll()),
      );
    }
    if (_summaryScope != session.scopeKey) {
      _dutySummary = null;
      unawaited(_loadDutySummary());
    }
  }

  Future<void> _loadDutySummary() async {
    final session = _session;
    if (session == null || widget.eventId?.isNotEmpty == true) return;
    final scope = session.scopeKey;
    _summaryScope = scope;
    final request = ++_summaryRequest;
    try {
      final data = jsonMap(await session.api.get('/api/v1/duty/summary'));
      if (!mounted ||
          request != _summaryRequest ||
          session != _session ||
          scope != session.scopeKey) {
        return;
      }
      setState(() => _dutySummary = data);
    } catch (_) {
      if (!mounted ||
          request != _summaryRequest ||
          session != _session ||
          scope != session.scopeKey) {
        return;
      }
      setState(() => _dutySummary = null);
    }
  }

  Future<void> _refreshWorkspace() async {
    await Future.wait([
      if (_controller != null) _controller!.refreshFromSignal(),
      _loadDutySummary(),
    ]);
  }

  EventController _buildController(WearSession session) => EventController(
    gateway: ApiEventGateway(session.api),
    store: _store(session),
    scopeKey: session.scopeKey,
    actor: _actor(session),
    initialEventId: widget.eventId,
    initialPersonId: widget.personId,
    initialTaskId: widget.taskId,
    initialClaimantUserId: widget.initialClaimantUserId,
    initialEscalated: widget.initialEscalated,
    initialStatus: widget.initialStatus,
    initialType: widget.initialType,
  );

  SharedPreferencesEventStateStore _store(WearSession session) =>
      SharedPreferencesEventStateStore(
        userId: session.userId,
        siteId: session.siteId ?? '',
      );

  EventActor _actor(WearSession session) => EventActor(
    userId: session.userId,
    roles: {...session.roles, if (session.me?['admin'] == true) 'admin'},
    permissions: session.permissions,
    userName: idOf(session.me?['userName']),
  );

  Future<void> _initializeAndRestoreScroll() async {
    await _controller!.initialize();
    _restoreScroll();
  }

  void _restoreScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final offset = _controller!.scrollOffset.clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.jumpTo(offset);
    });
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNearBottom());
  }

  void _loadNearBottom() {
    if (!mounted || !_scroll.hasClients || widget.eventId?.isNotEmpty == true) {
      return;
    }
    final controller = _controller;
    if (controller == null || controller.loadMoreError != null) return;
    if (_scroll.position.extentAfter < 240) {
      unawaited(controller.loadMore());
    }
  }

  void _serverSignaled() {
    final controller = _controller;
    if (controller != null && !controller.writing) {
      unawaited(_refreshWorkspace());
    }
  }

  void _saveScroll() {
    _loadNearBottom();
    _scrollSave?.cancel();
    _scrollSave = Timer(const Duration(milliseconds: 250), () {
      if (_scroll.hasClients) {
        unawaited(_controller?.updateScroll(_scroll.offset));
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_saveScroll);
  }

  @override
  void dispose() {
    _scrollSave?.cancel();
    if (_scroll.hasClients && _controller != null) {
      unawaited(_controller!.updateScroll(_scroll.offset));
    }
    _session?.refreshTick.removeListener(_serverSignaled);
    _controller?.removeListener(_changed);
    _controller?.dispose();
    for (final editor in _handleEditors.values) {
      editor.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.eventId?.isNotEmpty == true) {
      final event = controller.selected;
      if (event != null && event.id == widget.eventId) {
        return EventReferenceView(
          key: ValueKey('${controller.scopeKey}:${event.id}'),
          controller: controller,
          onBack: _backToEvents,
          onSubmit: () => _execute(controller, EventCommand.handle),
          onConfirm: () => _execute(controller, EventCommand.confirm),
          onReview: () => _editReason(controller, EventCommand.close),
          onCommunication: () => _openCommunication(event),
          legacyDetail: _detail(controller, event, includeHandle: false),
        );
      }
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _backToEvents),
          title: const Text('事件详情'),
        ),
        body: controller.detailLoading || controller.loading
            ? const Center(child: CircularProgressIndicator())
            : WearEmpty(
                title: '事件详情暂不可用',
                detail: controller.errorMessage,
                onRetry: () => controller.select(widget.eventId!),
              ),
      );
    }
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: !controller.writing,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || controller.writing) return;
        if (keyboardOpen) {
          FocusScope.of(context).unfocus();
        } else if (controller.selected != null) {
          unawaited(controller.closeDetail());
        }
      },
      child: Scaffold(
        backgroundColor: WearColors.background,
        body: SafeArea(
          child: WearScrollToTop(
            controller: _scroll,
            child: RefreshIndicator(
              onRefresh: _refreshWorkspace,
              child: ListView(
                key: const ValueKey('wear-events-workspace'),
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
                children: [
                  WearBrandHero(
                    key: const ValueKey('wear-page-hero-events'),
                    title: '消息',
                    subtitle: controller.actor.isAdmin
                        ? '异常上报与管理员复核'
                        : '进行中组内告警 · 本人设备提醒',
                    background: WearArt.eventsHero,
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            for (final level in const [
                              ('emergency', '紧急', WearColors.danger),
                              ('abnormal', '异常', WearColors.warning),
                              ('warning', '警告', WearColors.online),
                            ])
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                  ),
                                  child: ChoiceChip(
                                    key: ValueKey('event-level-${level.$1}'),
                                    label: Center(child: Text(level.$2)),
                                    selected:
                                        controller.filters.severity == level.$1,
                                    selectedColor: level.$3.withValues(
                                      alpha: .14,
                                    ),
                                    labelStyle: TextStyle(
                                      color: level.$3,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    onSelected: controller.writing
                                        ? null
                                        : (selected) => controller.setFilters(
                                            controller.filters.copyWith(
                                              severity: selected
                                                  ? level.$1
                                                  : '',
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _filters(controller),
                      ],
                    ),
                  ),
                  if (controller.loading) ...[
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: LinearProgressIndicator(minHeight: 3),
                    ),
                  ],
                  if (controller.errorMessage case final message?)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _notice(message, danger: true),
                    ),
                  if (controller.selected == null &&
                      controller.conflictMessage != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _notice(
                        '${controller.conflictMessage!}；已重新读取服务器状态，未提交草稿仍保留。',
                        danger: true,
                      ),
                    ),
                  if (controller.selected == null &&
                      controller.successMessage != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _notice(controller.successMessage!),
                    ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _resultHeader(controller),
                  ),
                  const SizedBox(height: 10),
                  if (!controller.loading && controller.records.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: WearEmpty(
                        title: '当前筛选没有事件',
                        detail: '当前条件下没有待处理事项，可调整筛选或刷新。',
                        onRetry: controller.reload,
                      ),
                    )
                  else
                    ...controller.records.map(
                      (event) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _eventRow(controller, event),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _listEnd(controller),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openCommunication(WearEvent event) {
    context.go(
      Uri(
        path: '/communications',
        queryParameters: {
          'eventId': event.id,
          'filterRequest': DateTime.now().microsecondsSinceEpoch.toString(),
          if (event.personId.isNotEmpty) 'personId': event.personId,
          if (event.personId.isEmpty && event.deviceId.isNotEmpty)
            'deviceId': event.deviceId,
        },
      ).toString(),
    );
  }

  void _backToEvents() {
    if (_controller?.writing == true) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/events');
    }
  }

  Future<void> _openEvent(EventController controller, String id) async {
    await context.push(
      Uri(path: '/events', queryParameters: {'eventId': id}).toString(),
    );
    if (!mounted || !identical(controller, _controller)) return;
    // Read persisted child drafts before refreshing the underlying list.
    final session = _session!;
    await controller.replaceScope(
      scopeKey: session.scopeKey,
      actor: _actor(session),
      store: _store(session),
    );
    _restoreScroll();
  }

  Widget _filters(EventController controller) {
    final filters = controller.filters;
    final statuses = filters.selectedStatuses.toSet();
    final active =
        statuses.length == 4 &&
        statuses.containsAll({'open', 'claimed', 'handling', 'pending_review'});
    return WearCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: InlineFilters(
        key: ValueKey('event-filters-${_session?.scopeKey}'),
        title: '事件筛选',
        enabled: !controller.writing,
        groups: [
          InlineFilterGroup(
            'status',
            '状态',
            {
              for (final e in _statuses.entries)
                if (e.key != 'active')
                  e.key: !controller.actor.isAdmin && e.key == 'pending_review'
                      ? '已上报'
                      : e.value,
              'active': '待处理 ${controller.inboxCount}',
            },
            presets: const {'active'},
          ),
          InlineFilterGroup('type', '类型', {
            if (_filterOptionsScope == _session?.scopeKey)
              for (final e in _filterOptions)
                'alarm:${idOf(e['code'])}':
                    '${textOf(e['label'])} · ${_deviceTypes[idOf(e['code']).split('.').first] ?? idOf(e['code'])}',
            for (final e in _types.entries)
              if (e.key.isNotEmpty) 'type:${e.key}': e.value,
            for (final code in filters.selectedAlarmCodes)
              if (!_filterOptions.any((e) => idOf(e['code']) == code))
                'alarm:$code':
                    filters.alarmLabels[code] ??
                    (filters.alarmLabel.isEmpty ? code : filters.alarmLabel),
          }),
          const InlineFilterGroup('device', '设备', _deviceTypes),
          InlineFilterGroup('flags', '其他', {
            if (controller.actor.isAdmin)
              'mine': _quickFilterLabel('我负责', 'mine'),
            'escalated': _quickFilterLabel('已升级', 'overdue'),
          }),
        ],
        value: {
          'status': active ? {'active'} : statuses,
          'type': {
            for (final t in filters.selectedTypes) 'type:$t',
            for (final c in filters.selectedAlarmCodes) 'alarm:$c',
          },
          'device': filters.deviceTypes.toSet(),
          'flags': {
            if (filters.escalated) 'escalated',
            if (filters.claimantUserId.isNotEmpty &&
                filters.claimantUserId == _session?.userId)
              'mine',
          },
        },
        fields: const {'person': '人员 ID（可选）', 'task': '任务 ID（可选）'},
        fieldValues: {
          'person': filters.personId,
          'task': filters.taskId,
          'claimant': filters.claimantUserId == _session?.userId
              ? ''
              : filters.claimantUserId,
        },
        loading: _openingFilters,
        error: _filterOptionsError,
        onOpen: _loadFilterOptions,
        onApply: (selected, fields) {
          final kinds = selected['type'] ?? {};
          final codes = kinds
              .where((v) => v.startsWith('alarm:'))
              .map((v) => v.substring(6))
              .toList();
          final chosenStates = selected['status'] ?? {};
          controller.setFilters(
            EventFilters(
              status: chosenStates.contains('active') ? 'active' : 'all',
              statuses: chosenStates.contains('active')
                  ? const []
                  : chosenStates.toList(),
              types: kinds
                  .where((v) => v.startsWith('type:'))
                  .map((v) => v.substring(5))
                  .toList(),
              alarmCodes: codes,
              alarmLabels: {
                for (final code in codes)
                  code:
                      _filterOptions
                          .where((e) => idOf(e['code']) == code)
                          .map((e) => textOf(e['label']))
                          .firstOrNull ??
                      filters.alarmLabels[code] ??
                      code,
              },
              deviceTypes: (selected['device'] ?? {}).toList(),
              escalated: selected['flags']?.contains('escalated') ?? false,
              personId: fields['person'] ?? '',
              taskId: fields['task'] ?? '',
              claimantUserId: selected['flags']?.contains('mine') == true
                  ? _session!.userId
                  : fields['claimant'] ?? '',
            ),
            preserveViewport: true,
          );
        },
      ),
    );
  }

  String _quickFilterLabel(String label, String? countField) {
    final count = countField == null ? null : _dutySummary?[countField];
    return count == null ? label : '$label ${intOf(count)}';
  }

  Widget _resultHeader(EventController controller) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '事件列表',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: WearColors.ink,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        '共 ${controller.total} 条 · ${controller.actor.isAdmin ? '全站未关闭' : '我的待办'} ${controller.inboxCount}',
        style: const TextStyle(color: WearColors.muted),
      ),
    ],
  );

  Widget _eventRow(EventController controller, WearEvent event) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: event.isEmergency ? const Color(0xFFFFF1F2) : Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: event.isEmergency
              ? WearColors.danger.withValues(alpha: .65)
              : WearColors.line,
          width: event.isEmergency ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        key: ValueKey('wear-event-${event.id}'),
        borderRadius: BorderRadius.circular(22),
        onTap: controller.writing
            ? null
            : () => _openEvent(controller, event.id),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: _eventColor(event),
                width: event.isEmergency ? 6 : 0,
              ),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: event.isEmergency
                      ? WearColors.danger.withValues(alpha: .10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  event.isEmergency
                      ? Icons.sos_rounded
                      : event.isWarning
                      ? Icons.info_outline_rounded
                      : Icons.warning_amber_rounded,
                  color: _eventColor(event),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            event.alarmLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: event.isEmergency
                                  ? WearColors.danger
                                  : WearColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          key: ValueKey('event-grade-${event.id}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: event.isEmergency
                                ? WearColors.danger
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            event.severityLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: event.isEmergency
                                  ? Colors.white
                                  : _eventColor(event),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (event.isEmergency && !event.isClosed)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          event.status == 'pending_review'
                              ? '现场已上报 · 等待管理员审批'
                              : '请优先处理 · 需管理员审批',
                          style: const TextStyle(
                            color: WearColors.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(height: 5),
                    Text(
                      '${event.personName.isEmpty ? '人员未知' : event.personName} · ${event.deviceTypeLabel} ${event.sn.isEmpty ? '未知' : event.sn}',
                      style: const TextStyle(color: WearColors.muted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        WearBadge(
                          text: event.statusFor(
                            admin: controller.actor.isAdmin,
                          ),
                          color: _eventColor(event),
                        ),
                        if (event.escalated)
                          WearBadge(text: '已升级', color: _eventColor(event)),
                        if (event.repeatCount > 0)
                          WearBadge(
                            text: '重复 ${event.repeatCount} 次',
                            color: _eventColor(event),
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      formatTime(event.occurredAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: WearColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: WearColors.muted),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _detail(
    EventController controller,
    WearEvent event, {
    bool includeHandle = true,
  }) => WearCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${event.alarmLabel} · #${event.id}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: WearColors.ink,
                ),
              ),
            ),
            IconButton(
              tooltip: '收起详情',
              onPressed: controller.writing ? null : _backToEvents,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            WearBadge(
              text: event.statusFor(admin: controller.actor.isAdmin),
              color: _statusColor(event.status),
            ),
            WearBadge(
              text: event.isHighRisk ? '高风险' : '低风险',
              color: event.isHighRisk ? WearColors.danger : WearColors.warning,
            ),
            if (event.demo)
              const WearBadge(text: '演示事件', color: WearColors.warning),
          ],
        ),
        const Divider(height: 26),
        const Text(
          '事件发生时快照',
          style: TextStyle(fontWeight: FontWeight.w700, color: WearColors.ink),
        ),
        const SizedBox(height: 9),
        _line(
          Icons.person_outline,
          '人员',
          '${_known(event.personName)} · ${_known(event.personCode)}',
        ),
        _line(
          Icons.health_and_safety_outlined,
          '设备',
          '${_known(event.sn)} · ID ${_known(event.deviceId)}',
        ),
        _line(Icons.schedule_outlined, '发生时间', formatTime(event.occurredAt)),
        if (event.alarmCode.isNotEmpty)
          _line(Icons.info_outline, '告警编码', event.alarmCode),
        if (event.sourceEventId.isNotEmpty)
          _line(Icons.link, '来源编号', event.sourceEventId),
        _line(
          Icons.location_on_outlined,
          '位置',
          event.locationLat.isEmpty || event.locationLng.isEmpty
              ? '位置未知（不阻断处置）'
              : '${event.locationLat}, ${event.locationLng} · ${_locationLabel(event.locationQuality)}',
        ),
        if (event.type == 'sos') ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                const WearAssetImage(
                  WearArt.plantMap,
                  width: double.infinity,
                  height: 168,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: WearBadge(
                    text: event.demo ? 'SOS 演示 · 厂区示意 · 非实测' : '厂区示意 · 非实测',
                    color: WearColors.warning,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (event.taskId.isNotEmpty)
          _line(
            Icons.assignment_outlined,
            '关联任务',
            '${event.taskId} · ${_known(event.taskMatch)}',
          ),
        if (event.claimantUserId.isNotEmpty)
          _line(Icons.badge_outlined, '历史处置人', '用户 ${event.claimantUserId}'),
        if (event.deviceId.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: controller.writing
                ? null
                : () => _openCommunication(event),
            icon: const Icon(Icons.call_outlined),
            label: const Text('打开可用通信能力'),
          ),
        ],
        const Divider(height: 28),
        _actions(controller, includeHandle: includeHandle),
        const Divider(height: 28),
        const Text(
          '处置时间线',
          style: TextStyle(fontWeight: FontWeight.w700, color: WearColors.ink),
        ),
        const SizedBox(height: 8),
        if (controller.detailLoading)
          const LinearProgressIndicator(minHeight: 3)
        else if (controller.actions.isEmpty)
          const Text('暂无动作记录', style: TextStyle(color: WearColors.muted))
        else
          ...controller.actions.map(_actionRow),
      ],
    ),
  );

  Widget _actions(EventController controller, {bool includeHandle = true}) {
    final canHandle = controller.can(EventCommand.handle);
    final buttons = <Widget>[
      if (controller.can(EventCommand.ack))
        OutlinedButton.icon(
          key: const ValueKey('event-ack'),
          onPressed: controller.writing
              ? null
              : () => _execute(controller, EventCommand.ack),
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('确认看见'),
        ),
      if (controller.can(EventCommand.confirm))
        FilledButton.icon(
          key: const ValueKey('event-confirm'),
          onPressed: controller.writing
              ? null
              : () => _execute(controller, EventCommand.confirm),
          icon: const Icon(Icons.pan_tool_alt_outlined),
          label: const Text('收到'),
        ),
      if (controller.can(EventCommand.transfer))
        OutlinedButton.icon(
          onPressed: controller.writing ? null : () => _transfer(controller),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('转交'),
        ),
      if (controller.can(EventCommand.close))
        FilledButton.icon(
          onPressed: controller.writing
              ? null
              : () => _editReason(controller, EventCommand.close),
          icon: const Icon(Icons.task_alt),
          label: const Text('审批通过并结束'),
        ),
      if (controller.can(EventCommand.reopen))
        OutlinedButton.icon(
          onPressed: controller.writing
              ? null
              : () => _editReason(controller, EventCommand.reopen),
          icon: const Icon(Icons.restart_alt),
          label: const Text('重开'),
        ),
      if (controller.can(EventCommand.assignTask))
        OutlinedButton.icon(
          key: const ValueKey('event-assign-task'),
          onPressed: controller.writing ? null : () => _assignTask(controller),
          icon: const Icon(Icons.assignment_turned_in_outlined),
          label: const Text('确认关联任务'),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '可执行操作',
          style: TextStyle(fontWeight: FontWeight.w700, color: WearColors.ink),
        ),
        const SizedBox(height: 10),
        if (controller.conflictMessage case final message?
            when widget.eventId == null) ...[
          _actionNotice('$message；已重新读取服务器状态，未提交草稿仍保留。', danger: true),
          const SizedBox(height: 10),
        ],
        if (controller.successMessage case final message?
            when widget.eventId == null) ...[
          _actionNotice(message),
          const SizedBox(height: 10),
        ],
        if (controller.writing) const LinearProgressIndicator(minHeight: 3),
        if (canHandle && includeHandle) ...[
          _handleForm(controller),
          const SizedBox(height: 12),
        ],
        Wrap(spacing: 8, runSpacing: 8, children: buttons),
        if (!canHandle && buttons.isEmpty)
          const Text(
            '当前角色、责任人与事件状态下没有可执行操作。',
            style: TextStyle(color: WearColors.muted),
          ),
      ],
    );
  }

  Widget _actionNotice(String message, {bool danger = false}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: (danger ? WearColors.danger : WearColors.primary).withValues(
        alpha: .08,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      message,
      style: TextStyle(color: danger ? WearColors.danger : WearColors.primary),
    ),
  );

  Widget _handleForm(EventController controller) {
    final event = controller.selected!;
    final draft = controller.draftFor(event.id);
    final editor = _handleEditors.putIfAbsent(
      event.id,
      () => TextEditingController(text: draft.handleComment),
    );
    if (editor.text != draft.handleComment) {
      editor.value = TextEditingValue(
        text: draft.handleComment,
        selection: TextSelection.collapsed(offset: draft.handleComment.length),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: ValueKey('event-handle-input-${event.id}'),
          controller: editor,
          enabled: !controller.writing,
          minLines: 2,
          maxLines: 5,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            labelText: '异常原因（选填）',
            hintText: '记录现场核实情况和已采取的措施',
            alignLabelWithHint: true,
          ),
          onChanged: (value) => unawaited(
            controller.updateDraft(
              event.id,
              controller.draftFor(event.id).copyWith(handleComment: value),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: controller.writing
                    ? null
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('草稿已保存在本机')),
                        );
                      },
                child: const Text('保存草稿'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: ValueKey('event-handle-submit-${event.id}'),
                onPressed: controller.writing
                    ? null
                    : () => _execute(controller, EventCommand.handle),
                icon: const Icon(Icons.build_outlined),
                label: const Text('上报原因'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _actionRow(EventAction action) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.radio_button_checked,
          size: 16,
          color: WearColors.primary,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_actionLabel(action.action)} · ${_known(action.actor)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: WearColors.ink,
                ),
              ),
              if (action.fromStatus.isNotEmpty || action.toStatus.isNotEmpty)
                Text(
                  '${_statusLabel(action.fromStatus)} → ${_statusLabel(action.toStatus)}',
                  style: const TextStyle(fontSize: 12, color: WearColors.muted),
                ),
              if (action.reason.isNotEmpty)
                Text(
                  action.reason,
                  style: const TextStyle(color: WearColors.muted),
                ),
              Text(
                formatTime(action.createTime),
                style: const TextStyle(fontSize: 12, color: WearColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _listEnd(EventController controller) {
    if (controller.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text(
              '正在加载更多事件',
              style: TextStyle(fontSize: 12, color: WearColors.muted),
            ),
          ],
        ),
      );
    }
    if (controller.loadMoreError != null) {
      return Center(
        child: TextButton.icon(
          onPressed: controller.loading || controller.writing
              ? null
              : controller.loadMore,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('加载失败，点击重试'),
        ),
      );
    }
    if (controller.loading || controller.records.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        controller.hasMore ? '继续向下浏览' : '没有更多事件了',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: WearColors.muted),
      ),
    );
  }

  Widget _line(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: WearColors.primary),
        const SizedBox(width: 9),
        SizedBox(
          width: 72,
          child: Text(label, style: const TextStyle(color: WearColors.muted)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(color: WearColors.ink)),
        ),
      ],
    ),
  );

  Widget _notice(String message, {bool danger = false}) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: WearCard(
      padding: const EdgeInsets.all(12),
      child: Text(
        message,
        style: TextStyle(
          color: danger ? WearColors.danger : WearColors.primary,
        ),
      ),
    ),
  );

  Future<void> _execute(
    EventController controller,
    EventCommand command,
  ) async {
    FocusScope.of(context).unfocus();
    final eventId = controller.selected?.id;
    final success = await controller.execute(command);
    if (!mounted ||
        command != EventCommand.handle ||
        controller.selected?.id != eventId) {
      return;
    }
    final message = success
        ? (controller.successMessage ?? '现场记录已提交')
        : controller.conflictMessage ??
              controller.errorMessage ??
              '当前状态不可提交，请刷新后核对';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editReason(
    EventController controller,
    EventCommand command,
  ) async {
    FocusScope.of(context).unfocus();
    final event = controller.selected!;
    final draft = controller.draftFor(event.id);
    final initial = switch (command) {
      EventCommand.close => draft.closeReason,
      EventCommand.reopen => draft.reopenReason,
      _ => '',
    };
    var reason = initial;
    String? error;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: !controller.writing,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => PopScope(
          canPop: !controller.writing,
          child: AlertDialog(
            title: Text(switch (command) {
              EventCommand.close => '关闭事件',
              EventCommand.reopen => '重开事件',
              _ => '填写说明',
            }),
            // The field owns its controller until the dialog exit animation
            // finishes; showDialog completes as soon as the route is popped.
            content: TextFormField(
              initialValue: initial,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: '原因',
                errorText: error,
                alignLabelWithHint: true,
              ),
              onChanged: (value) {
                reason = value;
                final next = switch (command) {
                  EventCommand.close => draft.copyWith(closeReason: value),
                  EventCommand.reopen => draft.copyWith(reopenReason: value),
                  _ => draft,
                };
                unawaited(controller.updateDraft(event.id, next));
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (reason.trim().isEmpty) {
                    setDialog(() => error = '请填写原因');
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('确认提交'),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true && mounted) await _execute(controller, command);
  }

  Future<void> _transfer(EventController controller) async {
    FocusScope.of(context).unfocus();
    await controller.loadOperators();
    if (!mounted || controller.selected == null) return;
    final event = controller.selected!;
    var draft = controller.draftFor(event.id);
    final reason = TextEditingController(text: draft.transferReason);
    String? userId = draft.transferUserId.isEmpty ? null : draft.transferUserId;
    String? error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('转交事件'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue:
                    controller.operators.any((item) => item.userId == userId)
                    ? userId
                    : null,
                decoration: const InputDecoration(labelText: '同站值班人员'),
                items: controller.operators
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.userId,
                        child: Text(item.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  userId = value;
                  draft = draft.copyWith(transferUserId: value ?? '');
                  unawaited(controller.updateDraft(event.id, draft));
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: '转交原因',
                  errorText: error,
                ),
                onChanged: (value) {
                  draft = draft.copyWith(transferReason: value);
                  unawaited(controller.updateDraft(event.id, draft));
                },
              ),
              if (controller.operators.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    '当前厂站没有其他可转交值班人员。',
                    style: TextStyle(color: WearColors.muted),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: controller.operators.isEmpty
                  ? null
                  : () {
                      if (userId == null || reason.text.trim().isEmpty) {
                        setDialog(() => error = '请选择人员并填写转交原因');
                        return;
                      }
                      Navigator.pop(dialogContext, true);
                    },
              child: const Text('确认转交'),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    if (confirmed == true && mounted) {
      await _execute(controller, EventCommand.transfer);
    }
  }

  Future<void> _assignTask(EventController controller) async {
    FocusScope.of(context).unfocus();
    await controller.loadTaskCandidates();
    if (!mounted || controller.selected == null) return;
    final event = controller.selected!;
    var selectedTaskId = controller.draftFor(event.id).taskId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) {
          final pageCount = controller.taskCandidateTotal == 0
              ? 1
              : ((controller.taskCandidateTotal - 1) ~/ 10) + 1;
          return PopScope(
            canPop: !controller.writing && !controller.taskCandidatesLoading,
            child: AlertDialog(
              title: const Text('确认事件关联任务'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '当前事件存在多个候选任务，请人工核对后选择。系统不会自动指定。',
                      style: TextStyle(color: WearColors.muted),
                    ),
                    const SizedBox(height: 10),
                    if (controller.taskCandidatesLoading)
                      const LinearProgressIndicator(minHeight: 3)
                    else if (controller.taskCandidates.isEmpty)
                      const WearEmpty(title: '当前页没有可选任务')
                    else
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: controller.taskCandidates
                              .map(
                                (task) => ListTile(
                                  selected: selectedTaskId == task.id,
                                  leading: Icon(
                                    selectedTaskId == task.id
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    color: selectedTaskId == task.id
                                        ? WearColors.primary
                                        : WearColors.muted,
                                  ),
                                  title: Text(
                                    task.title.isEmpty
                                        ? '任务 #${task.id}'
                                        : task.title,
                                  ),
                                  subtitle: Text(
                                    '${_taskStatusLabel(task.status)}${task.spaceName.isEmpty ? '' : ' · ${task.spaceName}'}${task.demo ? ' · 演示' : ''}',
                                  ),
                                  onTap: () {
                                    setDialog(() => selectedTaskId = task.id);
                                    unawaited(
                                      controller.updateDraft(
                                        event.id,
                                        controller
                                            .draftFor(event.id)
                                            .copyWith(taskId: task.id),
                                      ),
                                    );
                                  },
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: '上一页任务',
                          onPressed:
                              controller.taskCandidateCurrent > 1 &&
                                  !controller.taskCandidatesLoading
                              ? () async {
                                  await controller.loadTaskCandidates(
                                    current:
                                        controller.taskCandidateCurrent - 1,
                                  );
                                  if (dialogContext.mounted) setDialog(() {});
                                }
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text('${controller.taskCandidateCurrent} / $pageCount'),
                        IconButton(
                          tooltip: '下一页任务',
                          onPressed:
                              controller.taskCandidateCurrent < pageCount &&
                                  !controller.taskCandidatesLoading
                              ? () async {
                                  await controller.loadTaskCandidates(
                                    current:
                                        controller.taskCandidateCurrent + 1,
                                  );
                                  if (dialogContext.mounted) setDialog(() {});
                                }
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: selectedTaskId.isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, true),
                  child: const Text('确认关联'),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (confirmed == true && mounted) {
      await _execute(controller, EventCommand.assignTask);
    }
  }

  Future<void> _loadFilterOptions() async {
    if (_openingFilters) return;
    final session = _session!;
    final scope = session.scopeKey;
    setState(() {
      _openingFilters = true;
      _filterOptionsError = null;
    });
    try {
      final options = jsonList(
        await session.api.get('/api/v1/events/filter-options'),
      );
      if (mounted && session.scopeKey == scope) {
        setState(() {
          _filterOptions = options;
          _filterOptionsScope = scope;
        });
      }
    } catch (_) {
      if (mounted && session.scopeKey == scope) {
        setState(() => _filterOptionsError = '具体告警类型加载失败');
      }
    } finally {
      if (mounted) setState(() => _openingFilters = false);
    }
  }
}

const _statuses = {
  'active': '未关闭',
  'open': '待处理',
  'claimed': '待处理',
  'handling': '处置中',
  'pending_review': '待管理员审批',
  'closed': '已关闭',
};

const _types = {
  '': '全部类型',
  'fall': '跌落（设备告警）',
  'impact': '撞击',
  'geofence': '围栏',
  'realtime': '实时告警',
};

const _deviceTypes = {'helmet': '安全帽', 'belt': '安全带', 'watch': '手表'};

String _known(String value) => value.isEmpty ? '未知' : value;
String _statusLabel(String value) =>
    _statuses[value] ?? (value.isEmpty ? '未知状态' : value);
String _actionLabel(String value) =>
    const {
      'ack': '确认看见',
      'claim': '认领',
      'handle': '处置',
      'manual_sos': '手动 SOS 报警',
      'transfer': '转交',
      'review': '复核',
      'close': '关闭',
      'reopen': '重开',
      'escalate': '升级',
    }[value] ??
    value;
String _locationLabel(String value) =>
    const {'ok': '定位正常', 'stale': '定位已过期', 'unknown': '定位质量未知'}[value] ??
    '定位质量未知';
String _taskStatusLabel(String value) =>
    const {
      'draft': '草稿',
      'ready': '待开始',
      'in_progress': '进行中',
      'paused': '已暂停',
      'ended': '已结束',
    }[value] ??
    (value.isEmpty ? '状态未知' : value);

Color _eventColor(WearEvent event) => event.isEmergency
    ? WearColors.danger
    : event.isWarning
    ? WearColors.online
    : WearColors.warning;
Color _statusColor(String status) => switch (status) {
  'closed' => WearColors.muted,
  'pending_review' => WearColors.warning,
  'open' => WearColors.danger,
  _ => WearColors.primary,
};
