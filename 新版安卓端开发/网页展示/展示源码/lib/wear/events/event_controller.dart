import 'dart:async';

import 'package:flutter/foundation.dart';

import 'event_models.dart';
import 'event_policy.dart';

export 'event_policy.dart' show EventActor;

abstract interface class EventGateway {
  Future<EventPageData> fetchPage(EventFilters filters, int current, int size);
  Future<int> fetchInboxCount();
  Future<TaskCandidatePage> fetchTaskCandidates(int current, int size);
  Future<WearEvent> fetchDetail(String eventId);
  Future<List<EventAction>> fetchActions(String eventId);
  Future<List<DutyOperator>> fetchOperators();
  Future<WearEvent> execute(
    EventCommand command,
    WearEvent event,
    EventDraft draft,
  );
}

abstract interface class EventStateStore {
  Future<EventWorkspaceState?> read();
  Future<void> write(EventWorkspaceState value);
}

class EventController extends ChangeNotifier {
  EventController({
    required this.gateway,
    required EventStateStore store,
    required String scopeKey,
    required EventActor actor,
    this.pageSize = 20,
    this.initialEventId,
    this.initialPersonId,
    this.initialTaskId,
    this.initialClaimantUserId,
    this.initialEscalated,
    this.initialStatus,
    this.initialType,
  }) : _store = store,
       _scopeKey = scopeKey,
       _actor = actor;

  final EventGateway gateway;
  final int pageSize;
  final String? initialEventId;
  final String? initialPersonId;
  final String? initialTaskId;
  final String? initialClaimantUserId;
  final bool? initialEscalated;
  final String? initialStatus;
  final String? initialType;

  EventStateStore _store;
  String _scopeKey;
  EventActor _actor;
  int _scopeGeneration = 0;
  int _pageGeneration = 0;
  int _detailGeneration = 0;
  int _refreshGeneration = 0;
  int _countGeneration = 0;
  bool _disposed = false;
  Future<void> _persistChain = Future.value();

  EventFilters filters = const EventFilters();
  List<WearEvent> records = const [];
  List<EventAction> actions = const [];
  List<DutyOperator> operators = const [];
  List<WorkTaskCandidate> taskCandidates = const [];
  WearEvent? selected;
  int total = 0;
  int inboxCount = 0;
  int taskCandidateTotal = 0;
  int taskCandidateCurrent = 1;
  int current = 1;
  double scrollOffset = 0;
  bool loading = false;
  bool loadingMore = false;
  bool _endReached = false;
  String? loadMoreError;
  bool detailLoading = false;
  bool writing = false;
  bool taskCandidatesLoading = false;
  String? errorMessage;
  String? conflictMessage;
  String? successMessage;
  final Map<String, EventDraft> _drafts = {};
  final Set<String> _ackedLocally = {};
  final Map<String, String> _submittedHandleComments = {};

  String get scopeKey => _scopeKey;
  EventActor get actor => _actor;
  bool get hasMore => !_endReached && current * pageSize < total;

  EventDraft draftFor(String eventId) => _drafts[eventId] ?? const EventDraft();

  String? submittedHandleCommentFor(String eventId) {
    final confirmed = _submittedHandleComments[eventId];
    if (confirmed != null) return confirmed;
    if (selected?.id == eventId) {
      // The API returns the action timeline newest first.
      for (final action in actions) {
        if (action.action == 'reopen') break;
        if (action.action == 'handle') return action.reason.trim();
      }
    }
    return null;
  }

  bool isHandleCommentSubmitted(String eventId) {
    final text = draftFor(eventId).handleComment.trim();
    final submitted = submittedHandleCommentFor(eventId);
    return submitted != null && text == submitted;
  }

  Future<void> initialize({bool applyInitial = true}) async {
    final scope = _scopeGeneration;
    final restored = await _store.read();
    if (!_acceptScope(scope)) return;
    if (restored != null) {
      filters = restored.filters;
      current = restored.current;
      scrollOffset = restored.scrollOffset;
      _drafts
        ..clear()
        ..addAll(restored.drafts);
    }
    if (applyInitial) {
      filters = filters.copyWith(
        personId: initialPersonId ?? filters.personId,
        taskId: initialTaskId ?? filters.taskId,
        claimantUserId: initialClaimantUserId ?? filters.claimantUserId,
        escalated: initialEscalated ?? filters.escalated,
        status: initialStatus,
        type: initialType,
      );
    }
    // Older home-detail links persisted a hidden SOS-only list filter.
    // Emergency filtering now uses the existing escalated control instead.
    if (filters.type == 'sos') {
      filters = filters.copyWith(type: '');
      current = 1;
      scrollOffset = 0;
    }
    final target = applyInitial
        ? initialEventId ?? restored?.selectedEventId ?? ''
        : restored?.selectedEventId ?? '';
    await reload(current: current);
    if (target.isNotEmpty && _acceptScope(scope)) await select(target);
  }

  Future<void> replaceScope({
    required String scopeKey,
    required EventActor actor,
    required EventStateStore store,
  }) async {
    _scopeGeneration++;
    _pageGeneration++;
    _detailGeneration++;
    _refreshGeneration++;
    _countGeneration++;
    _scopeKey = scopeKey;
    _actor = actor;
    _store = store;
    filters = const EventFilters();
    records = const [];
    loadingMore = false;
    loadMoreError = null;
    _endReached = false;
    actions = const [];
    operators = const [];
    taskCandidates = const [];
    selected = null;
    total = 0;
    inboxCount = 0;
    taskCandidateTotal = 0;
    taskCandidateCurrent = 1;
    current = 1;
    scrollOffset = 0;
    _drafts.clear();
    _ackedLocally.clear();
    _submittedHandleComments.clear();
    notifyListeners();
    await initialize(applyInitial: false);
  }

  Future<void> reload({int? current}) async {
    final request = ++_pageGeneration;
    final scope = _scopeGeneration;
    final targetPage = current ?? this.current;
    final requestedFilters = filters;
    loadingMore = false;
    loadMoreError = null;
    loading = true;
    errorMessage = null;
    notifyListeners();
    unawaited(_reloadInboxCount(scope));
    try {
      // Rebuild all previously loaded batches so refreshing/returning never
      // replaces a continuous list with only its final batch.
      final rows = <String, WearEvent>{};
      var reachedEnd = false;
      var loadedPage = 1;
      var latestTotal = 0;
      for (var number = 1; number <= targetPage; number++) {
        final page = await gateway.fetchPage(
          requestedFilters,
          number,
          pageSize,
        );
        if (!_acceptPage(scope, request)) return;
        for (final event in page.records) {
          rows[event.id] = event;
        }
        loadedPage = page.current;
        latestTotal = page.total;
        reachedEnd =
            page.records.isEmpty ||
            page.current < number ||
            page.current * pageSize >= page.total;
        if (reachedEnd) break;
      }
      records = rows.values.toList();
      total = latestTotal;
      this.current = loadedPage;
      _endReached = reachedEnd;
    } catch (error) {
      if (!_acceptPage(scope, request)) return;
      if (error is! EventStaleScope) errorMessage = error.toString();
    } finally {
      if (_acceptPage(scope, request)) {
        loading = false;
        notifyListeners();
        _persist();
      }
    }
  }

  Future<void> setFilters(
    EventFilters value, {
    bool preserveViewport = false,
  }) async {
    conflictMessage = null;
    successMessage = null;
    // Invalidate a pending append before persistence yields to its response.
    _pageGeneration++;
    loadingMore = false;
    loadMoreError = null;
    _endReached = false;
    if (!preserveViewport) {
      records = const [];
      total = 0;
      scrollOffset = 0;
    }
    filters = value;
    current = 1;
    await _persist();
    await reload(current: 1);
  }

  Future<void> loadMore() async {
    if (loading || loadingMore || writing || !hasMore) return;
    final request = ++_pageGeneration;
    final scope = _scopeGeneration;
    final targetPage = current + 1;
    loadingMore = true;
    loadMoreError = null;
    notifyListeners();
    try {
      final page = await gateway.fetchPage(filters, targetPage, pageSize);
      if (!_acceptPage(scope, request)) return;
      final rows = {for (final event in records) event.id: event};
      for (final event in page.records) {
        rows[event.id] = event;
      }
      records = rows.values.toList();
      total = page.total;
      _endReached =
          page.records.isEmpty ||
          page.current < targetPage ||
          page.current * pageSize >= page.total;
      current = page.current;
    } catch (error) {
      if (_acceptPage(scope, request) && error is! EventStaleScope) {
        loadMoreError = '后续事件加载失败';
      }
    } finally {
      if (_acceptPage(scope, request)) {
        loadingMore = false;
        notifyListeners();
        unawaited(_persist());
      }
    }
  }

  Future<void> select(String eventId) async {
    final entering = selected?.id != eventId;
    final request = ++_detailGeneration;
    final scope = _scopeGeneration;
    detailLoading = true;
    errorMessage = null;
    conflictMessage = null;
    successMessage = null;
    notifyListeners();
    try {
      final result = await Future.wait<Object>([
        gateway.fetchDetail(eventId),
        gateway.fetchActions(eventId),
      ]);
      if (!_acceptDetail(scope, request)) return;
      selected = result[0] as WearEvent;
      actions = result[1] as List<EventAction>;
      _submittedHandleComments.remove(eventId);
      if (entering && !_drafts.containsKey(eventId)) {
        final submitted = submittedHandleCommentFor(eventId);
        if (submitted != null && submitted.isNotEmpty) {
          _drafts[eventId] = EventDraft(handleComment: submitted);
        }
      }
      await _persist();
    } catch (error) {
      if (!_acceptDetail(scope, request)) return;
      if (error is! EventStaleScope) errorMessage = error.toString();
    } finally {
      if (_acceptDetail(scope, request)) {
        detailLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> closeDetail() async {
    _detailGeneration++;
    selected = null;
    actions = const [];
    notifyListeners();
    await _persist();
  }

  Future<void> loadOperators() async {
    final scope = _scopeGeneration;
    try {
      final result = await gateway.fetchOperators();
      if (_acceptScope(scope)) {
        operators = result
            .where((item) => item.userId != actor.userId)
            .toList();
        notifyListeners();
      }
    } catch (error) {
      if (_acceptScope(scope) && error is! EventStaleScope) {
        errorMessage = error.toString();
      }
    }
  }

  Future<void> loadTaskCandidates({int current = 1}) async {
    final scope = _scopeGeneration;
    taskCandidatesLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final page = await gateway.fetchTaskCandidates(current, 10);
      if (!_acceptScope(scope)) return;
      taskCandidates = page.records;
      taskCandidateTotal = page.total;
      taskCandidateCurrent = page.current;
    } catch (error) {
      if (_acceptScope(scope) && error is! EventStaleScope) {
        errorMessage = error.toString();
      }
    } finally {
      if (_acceptScope(scope)) {
        taskCandidatesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> updateDraft(String eventId, EventDraft draft) async {
    if (draft.isEmpty) {
      _drafts.remove(eventId);
    } else {
      _drafts[eventId] = draft;
    }
    notifyListeners();
    await _persist();
  }

  Future<void> updateScroll(double offset) async {
    scrollOffset = offset < 0 ? 0 : offset;
    await _persist();
  }

  bool can(EventCommand command) {
    final event = selected;
    if (event == null || !EventPolicy.can(command, event, actor)) return false;
    if (command == EventCommand.ack &&
        (_ackedLocally.contains(event.id) ||
            (actor.userName.isNotEmpty &&
                actions.any(
                  (action) =>
                      action.action == 'ack' && action.actor == actor.userName,
                )))) {
      return false;
    }
    return true;
  }

  Future<bool> execute(EventCommand command) async {
    final event = selected;
    if (writing || event == null || !can(command)) {
      return false;
    }
    final submittedDraft = draftFor(event.id);
    writing = true;
    errorMessage = null;
    conflictMessage = null;
    successMessage = null;
    notifyListeners();
    final scope = _scopeGeneration;
    final selectionGeneration = _detailGeneration;
    try {
      final latest = await gateway.execute(command, event, submittedDraft);
      if (!_acceptScope(scope)) return false;
      if (command == EventCommand.handle) {
        // Keep the visible note; only a confirmed POST marks it as submitted.
        _submittedHandleComments[event.id] = submittedDraft.handleComment
            .trim();
      } else if (command != EventCommand.ack && command != EventCommand.claim) {
        _drafts.remove(event.id);
      }
      if (command == EventCommand.reopen) {
        _submittedHandleComments.remove(event.id);
      }
      if (command == EventCommand.ack) _ackedLocally.add(event.id);
      successMessage = command == EventCommand.handle
          ? (latest.isClosed ? '现场记录已提交，事件已结束' : '现场记录已提交，等待管理员审批')
          : _successText(command);
      if (selectionGeneration != _detailGeneration ||
          selected?.id != event.id) {
        await reload(current: current);
        return true;
      }
      selected = latest;
      try {
        await _refreshAfterWrite(event.id, scope);
      } on EventStaleScope {
        return true;
      } catch (error) {
        if (_acceptScope(scope)) {
          errorMessage = '操作已成功，但最新列表加载失败：$error';
        }
      }
      return true;
    } on EventConflict catch (conflict) {
      if (!_acceptScope(scope)) return false;
      conflictMessage = conflict.message;
      if (selectionGeneration != _detailGeneration ||
          selected?.id != event.id) {
        await reload(current: current);
        return false;
      }
      try {
        await _refreshAfterWrite(event.id, scope);
      } on EventStaleScope {
        return false;
      } catch (error) {
        if (_acceptScope(scope)) {
          errorMessage = '状态已冲突，重新加载失败：$error';
        }
      }
      return false;
    } catch (error) {
      if (_acceptScope(scope) && error is! EventStaleScope) {
        errorMessage = error.toString();
      }
      return false;
    } finally {
      if (_acceptScope(scope)) {
        writing = false;
        notifyListeners();
        _persist();
      }
    }
  }

  Future<void> refreshFromSignal() async {
    final request = ++_refreshGeneration;
    final scope = _scopeGeneration;
    final id = selected?.id;
    await reload(current: current);
    if (!_acceptScope(scope) || request != _refreshGeneration) return;
    if (id != null && id.isNotEmpty) await select(id);
  }

  Future<void> _refreshAfterWrite(String eventId, int scope) async {
    final detail = await Future.wait<Object>([
      gateway.fetchDetail(eventId),
      gateway.fetchActions(eventId),
    ]);
    if (!_acceptScope(scope)) return;
    selected = detail[0] as WearEvent;
    actions = detail[1] as List<EventAction>;
    await reload(current: current);
  }

  Future<void> _reloadInboxCount(int scope) async {
    final request = ++_countGeneration;
    try {
      final result = await gateway.fetchInboxCount();
      if (_acceptScope(scope) && request == _countGeneration) {
        inboxCount = result;
        notifyListeners();
      }
    } on EventStaleScope {
      // A replacement scope owns the next count.
    } catch (_) {
      // The authoritative page remains usable if this supplementary count fails.
    }
  }

  String _successText(EventCommand command) => switch (command) {
    EventCommand.ack => '已确认看见该事件',
    EventCommand.claim => '异常无需认领',
    EventCommand.confirm => '设备提醒已确认，任务已结束',
    EventCommand.handle => '原因已上报，本次处理已完成，由管理员复核',
    EventCommand.transfer => '事件已转交',
    EventCommand.close => '事件已关闭',
    EventCommand.reopen => '事件已重开',
    EventCommand.assignTask => '事件关联任务已确认',
  };

  bool _acceptScope(int scope) => !_disposed && scope == _scopeGeneration;
  bool _acceptPage(int scope, int request) =>
      _acceptScope(scope) && request == _pageGeneration;
  bool _acceptDetail(int scope, int request) =>
      _acceptScope(scope) && request == _detailGeneration;

  Future<void> _persist() {
    final store = _store;
    final value = EventWorkspaceState(
      filters: filters,
      current: current,
      selectedEventId: selected?.id ?? '',
      scrollOffset: scrollOffset,
      drafts: Map.unmodifiable(_drafts),
    );
    final operation = _persistChain.then((_) => store.write(value));
    _persistChain = operation.catchError((_) {});
    return operation;
  }

  @override
  void dispose() {
    _disposed = true;
    _scopeGeneration++;
    _pageGeneration++;
    _detailGeneration++;
    _refreshGeneration++;
    _countGeneration++;
    super.dispose();
  }
}
