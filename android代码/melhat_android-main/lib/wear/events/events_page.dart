import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../components/field_brand.dart';
import '../core.dart';
import 'event_controller.dart';
import 'event_models.dart';
import 'event_repository.dart';
import 'event_state_store.dart';

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
    if (mounted) setState(() {});
  }

  void _serverSignaled() {
    final controller = _controller;
    if (controller != null && !controller.writing) {
      unawaited(controller.refreshFromSignal());
    }
  }

  void _saveScroll() {
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
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: !controller.writing && controller.selected == null,
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
          child: RefreshIndicator(
            onRefresh: controller.refreshFromSignal,
            child: ListView(
              key: const ValueKey('wear-events-workspace'),
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              children: [
                FieldArtworkSurface(
                  scene: 'workbench-card',
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 14, 2),
                    child: WearPageHeader(
                      title: '安全事件',
                      subtitle: '统一接警、认领、处置与复核',
                      trailing: IconButton(
                        tooltip: '刷新最新状态',
                        onPressed: controller.loading || controller.writing
                            ? null
                            : controller.refreshFromSignal,
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _filters(controller),
                if (controller.loading) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 3),
                ],
                if (controller.errorMessage case final message?)
                  _notice(message, danger: true),
                if (controller.selected == null &&
                    controller.conflictMessage != null)
                  _notice(
                    '${controller.conflictMessage!}；已重新读取服务器状态，未提交草稿仍保留。',
                    danger: true,
                  ),
                if (controller.selected == null &&
                    controller.successMessage != null)
                  _notice(controller.successMessage!),
                if (controller.selected case final event?) ...[
                  const SizedBox(height: 14),
                  _detail(controller, event),
                ],
                const SizedBox(height: 14),
                _resultHeader(controller),
                const SizedBox(height: 10),
                if (!controller.loading && controller.records.isEmpty)
                  WearEmpty(
                    title: '当前筛选没有事件',
                    detail: '当前条件下没有待处理事项，可调整筛选或刷新。',
                    onRetry: controller.reload,
                  )
                else
                  ...controller.records.map(
                    (event) => _eventRow(controller, event),
                  ),
                const SizedBox(height: 10),
                _paging(controller),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filters(EventController controller) => WearCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '查询条件',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: WearColors.ink,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: controller.writing
                  ? null
                  : () => _showFilters(controller),
              icon: const Icon(Icons.tune, size: 19),
              label: const Text('筛选'),
            ),
          ],
        ),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            WearBadge(text: _statusLabel(controller.filters.status)),
            if (controller.filters.type.isNotEmpty)
              WearBadge(text: _typeLabel(controller.filters.type)),
            if (controller.filters.personId.isNotEmpty)
              WearBadge(text: '人员 ${controller.filters.personId}'),
            if (controller.filters.taskId.isNotEmpty)
              WearBadge(text: '任务 ${controller.filters.taskId}'),
            if (controller.filters.claimantUserId.isNotEmpty)
              WearBadge(text: '认领人 ${controller.filters.claimantUserId}'),
            if (controller.filters.escalated)
              const WearBadge(text: '仅已升级', color: WearColors.danger),
          ],
        ),
      ],
    ),
  );

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
        '第 ${controller.current} 页 · 共 ${controller.total} 条 · 未关闭 ${controller.inboxCount}',
        style: const TextStyle(color: WearColors.muted),
      ),
    ],
  );

  Widget _eventRow(EventController controller, WearEvent event) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: WearCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        key: ValueKey('wear-event-${event.id}'),
        borderRadius: BorderRadius.circular(22),
        onTap: controller.writing ? null : () => controller.select(event.id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _eventColor(event).withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: _eventColor(event),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.typeLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: WearColors.ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${event.personName.isEmpty ? '人员未知' : event.personName} · ${event.sn.isEmpty ? '设备未知' : event.sn}',
                      style: const TextStyle(color: WearColors.muted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        WearBadge(
                          text: event.statusLabel,
                          color: _statusColor(event.status),
                        ),
                        if (event.escalated)
                          const WearBadge(
                            text: '已升级',
                            color: WearColors.danger,
                          ),
                        if (event.demo)
                          const WearBadge(
                            text: '演示',
                            color: WearColors.warning,
                          ),
                        if (event.repeatCount > 0)
                          WearBadge(text: '重复 ${event.repeatCount} 次'),
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

  Widget _detail(EventController controller, WearEvent event) => WearCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${event.typeLabel} · #${event.id}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: WearColors.ink,
                ),
              ),
            ),
            IconButton(
              tooltip: '收起详情',
              onPressed: controller.writing ? null : controller.closeDetail,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            WearBadge(
              text: event.statusLabel,
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
        _line(
          Icons.location_on_outlined,
          '位置',
          event.locationLat.isEmpty || event.locationLng.isEmpty
              ? '位置未知（不阻断处置）'
              : '${event.locationLat}, ${event.locationLng} · ${_locationLabel(event.locationQuality)}',
        ),
        if (event.taskId.isNotEmpty)
          _line(
            Icons.assignment_outlined,
            '关联任务',
            '${event.taskId} · ${_known(event.taskMatch)}',
          ),
        if (event.claimantUserId.isNotEmpty)
          _line(Icons.badge_outlined, '当前认领人', '用户 ${event.claimantUserId}'),
        if (event.deviceId.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: controller.writing
                ? null
                : () => context.push(
                    '/communications?eventId=${Uri.encodeQueryComponent(event.id)}&deviceId=${Uri.encodeQueryComponent(event.deviceId)}',
                  ),
            icon: const Icon(Icons.call_outlined),
            label: const Text('打开可用通信能力'),
          ),
        ],
        const Divider(height: 28),
        _actions(controller),
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

  Widget _actions(EventController controller) {
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
      if (controller.can(EventCommand.claim))
        FilledButton.icon(
          key: const ValueKey('event-claim'),
          onPressed: controller.writing
              ? null
              : () => _execute(controller, EventCommand.claim),
          icon: const Icon(Icons.pan_tool_alt_outlined),
          label: const Text('认领'),
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
          label: const Text('关闭'),
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
        if (controller.conflictMessage case final message?) ...[
          _actionNotice('$message；已重新读取服务器状态，未提交草稿仍保留。', danger: true),
          const SizedBox(height: 10),
        ],
        if (controller.successMessage case final message?) ...[
          _actionNotice(message),
          const SizedBox(height: 10),
        ],
        if (controller.writing) const LinearProgressIndicator(minHeight: 3),
        if (canHandle) ...[_handleForm(controller), const SizedBox(height: 12)],
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
            labelText: '处置说明（可选）',
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
        FilledButton.icon(
          key: ValueKey('event-handle-submit-${event.id}'),
          onPressed: controller.writing
              ? null
              : () => _execute(controller, EventCommand.handle),
          icon: const Icon(Icons.build_outlined),
          label: const Text('提交处置'),
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

  Widget _paging(EventController controller) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      OutlinedButton(
        onPressed:
            controller.current > 1 && !controller.loading && !controller.writing
            ? controller.previousPage
            : null,
        child: const Text('上一页'),
      ),
      const SizedBox(width: 10),
      OutlinedButton(
        onPressed:
            controller.hasMore && !controller.loading && !controller.writing
            ? controller.nextPage
            : null,
        child: const Text('下一页'),
      ),
    ],
  );

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
    await controller.execute(command);
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
    final text = TextEditingController(text: initial);
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
            content: TextField(
              controller: text,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: '原因',
                errorText: error,
                alignLabelWithHint: true,
              ),
              onChanged: (value) {
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
                  if (text.text.trim().isEmpty) {
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
    text.dispose();
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

  Future<void> _showFilters(EventController controller) async {
    FocusScope.of(context).unfocus();
    var status = controller.filters.status;
    var type = controller.filters.type;
    final person = TextEditingController(text: controller.filters.personId);
    final task = TextEditingController(text: controller.filters.taskId);
    final claimant = TextEditingController(
      text: controller.filters.claimantUserId,
    );
    var escalated = controller.filters.escalated;
    final result = await showModalBottomSheet<EventFilters>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              18,
              18,
              18 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '筛选事件',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: '状态'),
                    items: _statuses.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setSheet(() => status = value ?? 'active'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: '类型'),
                    items: _types.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setSheet(() => type = value ?? ''),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: person,
                    decoration: const InputDecoration(labelText: '人员 ID（可选）'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: task,
                    decoration: const InputDecoration(labelText: '任务 ID（可选）'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: claimant,
                    decoration: const InputDecoration(
                      labelText: '认领人用户 ID（可选）',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: escalated,
                    title: const Text('仅看已升级事件'),
                    onChanged: (value) => setSheet(() => escalated = value),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      sheetContext,
                      EventFilters(
                        status: status,
                        type: type,
                        personId: person.text.trim(),
                        taskId: task.text.trim(),
                        claimantUserId: claimant.text.trim(),
                        escalated: escalated,
                      ),
                    ),
                    child: const Text('应用筛选'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    person.dispose();
    task.dispose();
    claimant.dispose();
    if (result != null && mounted) await controller.setFilters(result);
  }
}

const _statuses = {
  'active': '未关闭',
  'open': '待认领',
  'claimed': '已认领',
  'handling': '处置中',
  'pending_review': '待复核',
  'closed': '已关闭',
};

const _types = {
  '': '全部类型',
  'sos': 'SOS 求助',
  'fall': '跌倒',
  'impact': '撞击',
  'geofence': '围栏',
  'realtime': '实时告警',
};

String _known(String value) => value.isEmpty ? '未知' : value;
String _statusLabel(String value) =>
    _statuses[value] ?? (value.isEmpty ? '未知状态' : value);
String _typeLabel(String value) =>
    _types[value] ?? (value.isEmpty ? '全部类型' : value);
String _actionLabel(String value) =>
    const {
      'ack': '确认看见',
      'claim': '认领',
      'handle': '处置',
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

Color _eventColor(WearEvent event) =>
    event.isHighRisk ? WearColors.danger : WearColors.warning;
Color _statusColor(String status) => switch (status) {
  'closed' => WearColors.muted,
  'pending_review' => WearColors.warning,
  'open' => WearColors.danger,
  _ => WearColors.primary,
};
