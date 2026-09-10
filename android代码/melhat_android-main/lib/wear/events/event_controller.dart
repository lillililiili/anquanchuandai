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
  bool detailLoading = false;
  bool writing = false;
  bool taskCandidatesLoading = false;
  String? errorMessage;
  String? conflictMessage;
  String? successMessage;
  final Map<String, EventDraft> _drafts = {};
  final Set<String> _ackedLocally = {};

  String get scopeKey => _scopeKey;
  EventActor get actor => _actor;
  bool get hasMore => current * pageSize < total;

  EventDraft draftFor(String eventId) => _drafts[eventId] ?? const EventDraft();

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
        status: initialStatus ?? filters.status,
        type: initialType ?? filters.type,
      );
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
    notifyListeners();
    await initialize(applyInitial: false);
  }

  Future<void> reload({int? current}) async {
    final request = ++_pageGeneration;
    final scope = _scopeGeneration;
    final targetPage = current ?? this.current;
    loading = true;
    errorMessage = null;
    notifyListeners();
    unawaited(_reloadInboxCount(scope));
    try {
      final page = await gateway.fetchPage(filters, targetPage, pageSize);
      if (!_acceptPage(scope, request)) return;
      records = page.records;
      total = page.total;
      this.current = page.current;
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

  Future<void> setFilters(EventFilters value) async {
    conflictMessage = null;
    successMessage = null;
    filters = value;
    current = 1;
    scrollOffset = 0;
    await _persist();
    await reload(current: 1);
  }

  Future<void> nextPage() =>
      hasMore ? reload(current: current + 1) : Future.value();
  Future<void> previousPage() =>
      current > 1 ? reload(current: current - 1) : Future.value();

  Future<void> select(String eventId) async {
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
    writing = true;
    errorMessage = null;
    conflictMessage = null;
    successMessage = null;
    notifyListeners();
    final scope = _scopeGeneration;
    final selectionGeneration = _detailGeneration;
    try {
      final latest = await gateway.execute(command, event, draftFor(event.id));
      if (!_acceptScope(scope)) return false;
      if (command != EventCommand.ack) _drafts.remove(event.id);
      if (command == EventCommand.ack) _ackedLocally.add(event.id);
      successMessage = _successText(command);
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
    EventCommand.claim => '事件已认领',
    EventCommand.handle => '处置记录已提交',
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
