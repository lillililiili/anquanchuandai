import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

  ColorScheme get _colors => Theme.of(context).colorScheme;

  Future<void> _openDetail(EventController controller, String eventId) async {
    FocusScope.of(context).unfocus();
    _scrollSave?.cancel();
    if (_scroll.hasClients) await controller.updateScroll(_scroll.offset);
    await controller.select(eventId);
    if (!mounted || controller.selected?.id != eventId) return;
    if (GoRouter.maybeOf(context) != null) {
      final uri = GoRouterState.of(context).uri;
      context.replace(
        uri
            .replace(
              queryParameters: {...uri.queryParameters, 'eventId': eventId},
            )
            .toString(),
      );
    }
  }

  Future<void> _closeDetail(EventController controller) async {
    FocusScope.of(context).unfocus();
    await controller.closeDetail();
    if (!mounted) return;
    final router = GoRouter.maybeOf(context);
    if (router != null && widget.eventId != null) {
      final uri = GoRouterState.of(context).uri;
      final query = Map<String, String>.from(uri.queryParameters)
        ..remove('eventId');
      context.replace(uri.replace(queryParameters: query).toString());
    }
    _restoreScroll();
  }

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
        if (controller.selected?.id != eventId) {
          await controller.select(eventId);
        }
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
      return Center(child: CircularProgressIndicator());
    }
    final event = controller.selected;
    return PopScope(
      canPop: !controller.writing && event == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || controller.writing) return;
        if (MediaQuery.viewInsetsOf(context).bottom > 0) {
          FocusScope.of(context).unfocus();
        } else if (event != null) {
          unawaited(_closeDetail(controller));
        }
      },
      child: Scaffold(
        backgroundColor: _colors.surface,
        body: SafeArea(
          child: IndexedStack(
            index: event == null ? 0 : 1,
            children: [
              RefreshIndicator(
                onRefresh: controller.refreshFromSignal,
                child: ListView(
                  key: ValueKey('wear-events-workspace'),
                  controller: _scroll,
                  physics: AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.only(bottom: 32),
                  children: [
                    WearBrandHero(
                      title: '告警',
                      subtitle: '统一告警流水',
                      background: WearArt.eventsHero,
                      trailing: IconButton(
                        tooltip: '刷新最新状态',
                        onPressed: controller.loading || controller.writing
                            ? null
                            : controller.refreshFromSignal,
                        icon: Icon(Icons.refresh),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _filters(controller),
                          if (controller.loading || controller.detailLoading)
                            LinearProgressIndicator(minHeight: 3),
                          if (controller.errorMessage case final message?)
                            _notice(message, danger: true),
                          if (event == null &&
                              controller.conflictMessage != null)
                            _notice(controller.conflictMessage!, danger: true),
                          SizedBox(height: 16),
                          _resultHeader(controller),
                          SizedBox(height: 12),
                          if (!controller.loading && controller.records.isEmpty)
                            WearEmpty(
                              title: '当前筛选没有告警',
                              detail: '可调整筛选或刷新查看。',
                              onRetry: controller.reload,
                            )
                          else
                            ...controller.records.map(
                              (item) => _eventRow(controller, item),
                            ),
                          _paging(controller),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (event == null)
                SizedBox.shrink()
              else
                Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          IconButton(
                            key: ValueKey('event-back'),
                            tooltip: '返回告警列表',
                            onPressed: controller.writing
                                ? null
                                : () => _closeDetail(controller),
                            icon: Icon(Icons.arrow_back),
                          ),
                          Expanded(
                            child: Text(
                              '告警详情',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: '刷新告警详情',
                            onPressed:
                                controller.writing || controller.detailLoading
                                ? null
                                : controller.refreshFromSignal,
                            icon: Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: controller.refreshFromSignal,
                        child: SingleChildScrollView(
                          key: ValueKey('event-detail-${event.id}'),
                          physics: AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
                          child: Column(
                            children: [
                              if (controller.errorMessage case final message?)
                                _notice(message, danger: true),
                              _detail(controller, event),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filters(EventController controller) => WearCard(
    padding: EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '处理状态',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _colors.onSurface,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: controller.writing
                  ? null
                  : () => _showFilters(controller),
              icon: Icon(Icons.tune, size: 19),
              label: Text('筛选'),
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
              WearBadge(text: '仅已升级', color: WearColors.danger),
          ],
        ),
      ],
    ),
  );

  Widget _resultHeader(EventController controller) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '告警列表',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: _colors.onSurface,
        ),
      ),
      SizedBox(height: 4),
      Text(
        controller.loading
            ? '正在读取告警…'
            : controller.errorMessage != null && controller.records.isEmpty
            ? '告警数量暂不可用'
            : '第 ${controller.current} 页 · 共 ${controller.total} 条',
        style: TextStyle(color: _colors.onSurfaceVariant),
      ),
    ],
  );

  Widget _eventRow(EventController controller, WearEvent event) => Padding(
    padding: EdgeInsets.only(bottom: 10),
    child: WearCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        key: ValueKey('wear-event-${event.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: controller.writing
            ? null
            : () => _openDetail(controller, event.id),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _eventColor(event).withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: _eventColor(event),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.typeLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _colors.onSurface,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      '${event.personName.isEmpty ? '人员未知' : event.personName} · 区域／楼层未知',
                      style: TextStyle(color: _colors.onSurfaceVariant),
                    ),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        WearBadge(
                          text: event.statusLabel,
                          color: event.isClosed
                              ? _colors.onSurfaceVariant
                              : _statusColor(event.status),
                        ),
                        WearBadge(
                          text: _severityLabel(event.severity),
                          color: _eventColor(event),
                        ),
                        if (event.escalated)
                          WearBadge(text: '已升级', color: WearColors.danger),
                        if (event.demo)
                          WearBadge(text: '演示', color: WearColors.warning),
                        if (event.repeatCount > 0)
                          WearBadge(text: '重复 ${event.repeatCount} 次'),
                      ],
                    ),
                    SizedBox(height: 7),
                    Text(
                      _eventTime(event.occurredAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: _colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: _colors.onSurfaceVariant),
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
        Text(
          event.typeLabel,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            WearBadge(
              text: event.statusLabel,
              color: event.isClosed
                  ? _colors.onSurfaceVariant
                  : _statusColor(event.status),
            ),
            WearBadge(
              text: _severityLabel(event.severity),
              color: _eventColor(event),
            ),
            if (event.demo) WearBadge(text: '演示事件', color: WearColors.warning),
          ],
        ),
        SizedBox(height: 12),
        _summary(
          Icons.person_outline,
          event.personName.isEmpty ? '人员未知' : event.personName,
          emphasized: true,
        ),
        _summary(Icons.schedule_outlined, _eventTime(event.occurredAt)),
        _summary(Icons.location_on_outlined, '区域未知 · 楼层未知'),
        SizedBox(height: 12),
        if (event.personId.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: ValueKey('event-contact-voice'),
                onPressed: controller.writing
                    ? null
                    : () => _contact(event, 'voice'),
                icon: Icon(Icons.call_outlined),
                label: Text('语音联系'),
              ),
              OutlinedButton.icon(
                key: ValueKey('event-contact-video'),
                onPressed: controller.writing
                    ? null
                    : () => _contact(event, 'video'),
                icon: Icon(Icons.videocam_outlined),
                label: Text('视频联系'),
              ),
            ],
          )
        else
          Text(
            '暂无关联人员，无法发起联系。',
            style: TextStyle(color: _colors.onSurfaceVariant),
          ),
        SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (event.personId.isNotEmpty)
              TextButton.icon(
                key: ValueKey('event-contact-tts'),
                onPressed: controller.writing
                    ? null
                    : () => _contact(event, 'tts'),
                icon: Icon(Icons.campaign_outlined),
                label: Text('语音播报'),
              ),
            if (controller.can(EventCommand.ack))
              OutlinedButton.icon(
                key: ValueKey('event-ack'),
                onPressed: controller.writing
                    ? null
                    : () => _execute(controller, EventCommand.ack),
                icon: Icon(Icons.visibility_outlined),
                label: Text('确认看见'),
              ),
          ],
        ),
        if (event.personId.isNotEmpty)
          Text(
            '联系前可确认当前可用设备。',
            style: TextStyle(color: _colors.onSurfaceVariant, fontSize: 13),
          ),
        Divider(height: 24),
        _actions(controller),
        ExpansionTile(
          key: PageStorageKey('event-more-info-${event.id}'),
          tilePadding: EdgeInsets.zero,
          title: Text('更多资料'),
          subtitle: Text('来源设备、位置记录与关联作业'),
          children: [
            _line(Icons.tag_outlined, '告警编号', event.id),
            _line(Icons.person_outline, '人员编号', _known(event.personCode)),
            _line(
              Icons.health_and_safety_outlined,
              '来源设备',
              '${_known(event.sn)} · ID ${_known(event.deviceId)}',
            ),
            _line(
              Icons.location_on_outlined,
              '发生时位置',
              event.locationLat.isEmpty || event.locationLng.isEmpty
                  ? '位置未知'
                  : '${event.locationLat}, ${event.locationLng} · ${_locationLabel(event.locationQuality)}',
            ),
            _line(Icons.radar_outlined, '位置来源与精度', '尚无记录'),
            _line(Icons.sensors_outlined, '事件来源', _sourceLabel(event.source)),
            _line(Icons.timer_outlined, '接收时间', _eventTime(event.receivedAt)),
            if (event.taskId.isNotEmpty)
              _line(
                Icons.assignment_outlined,
                '关联作业',
                '作业 ${event.taskId} · ${_taskMatchLabel(event.taskMatch)}',
              ),
            if (event.claimantUserId.isNotEmpty)
              _line(
                Icons.badge_outlined,
                '当前认领人',
                '用户 ${event.claimantUserId}',
              ),
          ],
        ),
        Divider(height: 24),
        Text('处置时间线', style: Theme.of(context).textTheme.titleMedium),
        SizedBox(height: 8),
        if (controller.detailLoading)
          LinearProgressIndicator(minHeight: 3)
        else if (controller.actions.isEmpty)
          Text('暂无动作记录', style: TextStyle(color: _colors.onSurfaceVariant))
        else
          ...controller.actions.map(_actionRow),
      ],
    ),
  );

  Widget _summary(IconData icon, String text, {bool emphasized = false}) =>
      Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: _colors.onSurfaceVariant),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: emphasized
                      ? _colors.onSurface
                      : _colors.onSurfaceVariant,
                  fontSize: emphasized ? 17 : 14,
                  fontWeight: emphasized ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _actions(EventController controller) {
    final canHandle = controller.can(EventCommand.handle);
    final buttons = <Widget>[
      if (controller.can(EventCommand.claim))
        FilledButton.icon(
          key: ValueKey('event-claim'),
          onPressed: controller.writing
              ? null
              : () => _execute(controller, EventCommand.claim),
          icon: Icon(Icons.pan_tool_alt_outlined),
          label: Text('认领'),
        ),
      if (controller.can(EventCommand.transfer))
        OutlinedButton.icon(
          onPressed: controller.writing ? null : () => _transfer(controller),
          icon: Icon(Icons.swap_horiz),
          label: Text('转交'),
        ),
      if (controller.can(EventCommand.close))
        FilledButton.icon(
          onPressed: controller.writing
              ? null
              : () => _editReason(controller, EventCommand.close),
          icon: Icon(Icons.task_alt),
          label: Text(controller.selected!.isHighRisk ? '复核并关闭' : '关闭'),
        ),
      if (controller.can(EventCommand.reopen))
        OutlinedButton.icon(
          onPressed: controller.writing
              ? null
              : () => _editReason(controller, EventCommand.reopen),
          icon: Icon(Icons.restart_alt),
          label: Text('重开'),
        ),
      if (controller.can(EventCommand.assignTask))
        OutlinedButton.icon(
          key: ValueKey('event-assign-task'),
          onPressed: controller.writing ? null : () => _assignTask(controller),
          icon: Icon(Icons.assignment_turned_in_outlined),
          label: Text('确认关联任务'),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '确认与处置说明',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: _colors.onSurface,
          ),
        ),
        SizedBox(height: 10),
        if (controller.conflictMessage case final message?) ...[
          _actionNotice('$message；已重新读取服务器状态，未提交草稿仍保留。', danger: true),
          SizedBox(height: 10),
        ],
        if (controller.successMessage case final message?) ...[
          _actionNotice(message),
          SizedBox(height: 10),
        ],
        if (controller.writing) LinearProgressIndicator(minHeight: 3),
        if (canHandle) ...[_handleForm(controller), SizedBox(height: 12)],
        if (buttons.isNotEmpty)
          ExpansionTile(
            key: PageStorageKey('event-more-actions'),
            tilePadding: EdgeInsets.zero,
            title: Text('更多处理'),
            subtitle: Text('认领、转交与其他处置'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 8, runSpacing: 8, children: buttons),
              ),
              SizedBox(height: 12),
            ],
          ),
        if (!canHandle && buttons.isEmpty && !controller.can(EventCommand.ack))
          Text(
            '此告警当前没有可用的处置操作。',
            style: TextStyle(color: _colors.onSurfaceVariant),
          ),
      ],
    );
  }

  Widget _actionNotice(String message, {bool danger = false}) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: (danger ? WearColors.danger : WearColors.primary).withValues(
        alpha: .08,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      message,
      style: TextStyle(color: danger ? _colors.error : _colors.onSurface),
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
          decoration: InputDecoration(
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
        SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: ValueKey('event-handle-submit-${event.id}'),
            onPressed: controller.writing
                ? null
                : () => _execute(controller, EventCommand.handle),
            icon: Icon(Icons.check),
            label: Text('提交处置'),
          ),
        ),
        SizedBox(height: 8),
        Text(
          '未提交说明会随页面草稿保留。',
          style: TextStyle(color: _colors.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _actionRow(EventAction action) => Padding(
    padding: EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.radio_button_checked, size: 16, color: WearColors.primary),
        SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_actionLabel(action.action)} · ${_known(action.actor)}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _colors.onSurface,
                ),
              ),
              if (action.fromStatus.isNotEmpty || action.toStatus.isNotEmpty)
                Text(
                  '${_statusLabel(action.fromStatus)} → ${_statusLabel(action.toStatus)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: _colors.onSurfaceVariant,
                  ),
                ),
              if (action.reason.isNotEmpty)
                Text(
                  action.reason,
                  style: TextStyle(color: _colors.onSurfaceVariant),
                ),
              Text(
                formatTime(action.createTime),
                style: TextStyle(fontSize: 12, color: _colors.onSurfaceVariant),
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
        child: Text('上一页'),
      ),
      SizedBox(width: 10),
      OutlinedButton(
        onPressed:
            controller.hasMore && !controller.loading && !controller.writing
            ? controller.nextPage
            : null,
        child: Text('下一页'),
      ),
    ],
  );

  Widget _line(IconData icon, String label, String value) => Padding(
    padding: EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: _colors.secondary),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: _colors.onSurfaceVariant, fontSize: 13),
              ),
              SizedBox(height: 3),
              Text(value, style: TextStyle(color: _colors.onSurface)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _notice(String message, {bool danger = false}) => Padding(
    padding: EdgeInsets.only(top: 12),
    child: WearCard(
      padding: EdgeInsets.all(12),
      child: Text(
        message,
        style: TextStyle(color: danger ? _colors.error : _colors.onSurface),
      ),
    ),
  );

  void _contact(WearEvent event, String intent) {
    context.push(
      Uri(
        path: '/communications',
        queryParameters: {
          'eventId': event.id,
          'personId': event.personId,
          'intent': intent,
        },
      ).toString(),
    );
  }

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
                child: Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (text.text.trim().isEmpty) {
                    setDialog(() => error = '请填写原因');
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: Text('确认提交'),
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
          title: Text('转交事件'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue:
                    controller.operators.any((item) => item.userId == userId)
                    ? userId
                    : null,
                decoration: InputDecoration(labelText: '同站值班人员'),
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
              SizedBox(height: 12),
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
                Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    '当前厂站没有其他可转交值班人员。',
                    style: TextStyle(color: _colors.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('取消'),
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
              child: Text('确认转交'),
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
              title: Text('确认事件关联任务'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '当前事件存在多个候选任务，请人工核对后选择。系统不会自动指定。',
                      style: TextStyle(color: _colors.onSurfaceVariant),
                    ),
                    SizedBox(height: 10),
                    if (controller.taskCandidatesLoading)
                      LinearProgressIndicator(minHeight: 3)
                    else if (controller.taskCandidates.isEmpty)
                      WearEmpty(title: '当前页没有可选任务')
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
                                        : _colors.onSurfaceVariant,
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
                          icon: Icon(Icons.chevron_left),
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
                          icon: Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text('取消'),
                ),
                FilledButton(
                  onPressed: selectedTaskId.isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, true),
                  child: Text('确认关联'),
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
                  Text(
                    '筛选事件',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: InputDecoration(labelText: '状态'),
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
                  SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: InputDecoration(labelText: '类型'),
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
                  SizedBox(height: 12),
                  TextField(
                    controller: person,
                    decoration: InputDecoration(labelText: '人员 ID（可选）'),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: task,
                    decoration: InputDecoration(labelText: '任务 ID（可选）'),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: claimant,
                    decoration: InputDecoration(labelText: '认领人用户 ID（可选）'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: escalated,
                    title: Text('仅看已升级事件'),
                    onChanged: (value) => setSheet(() => escalated = value),
                  ),
                  SizedBox(height: 18),
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
                    child: Text('应用筛选'),
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
  'active': '未关闭（含待复核）',
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

String _eventTime(String value) =>
    value.trim().isEmpty ? '时间未知' : formatTime(value);
String _severityLabel(String value) =>
    const {
      'critical': '紧急',
      'high': '高等级',
      'medium': '中等级',
      'low': '低等级',
    }[value] ??
    (value.isEmpty ? '等级未知' : value);

String _sourceLabel(String value) =>
    const {
      'simulator': '演示数据',
      'device': '设备上报',
      'manual': '人工上报',
      'rule': '规则触发',
      'platform': '平台监测',
    }[value] ??
    (value.isEmpty ? '来源未知' : '其他来源');
String _taskMatchLabel(String value) =>
    const {
      'matched': '已关联',
      'pending': '待确认关联',
      'unmatched': '未匹配作业',
      'none': '未关联作业',
      'manual': '人工关联',
    }[value] ??
    '关联状态未知';
