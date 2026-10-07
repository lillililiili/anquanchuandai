import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'event_controller.dart';
import 'event_models.dart';

class SharedPreferencesEventStateStore implements EventStateStore {
  SharedPreferencesEventStateStore({required this.userId, required this.siteId})
    : _writeGeneration = _writeGenerations[userId] ?? 0;

  static final Map<String, int> _writeGenerations = {};
  static final Map<String, Future<void>> _writeTails = {};

  final String userId;
  final String siteId;
  final int _writeGeneration;

  /// Invalidates existing writers and drains writes that reached preferences.
  /// Call this before deleting keys with the `wear.<userId>.` prefix.
  static Future<void> revokeUser(String userId) async {
    _writeGenerations[userId] = (_writeGenerations[userId] ?? 0) + 1;
    await (_writeTails[userId] ?? Future<void>.value()).catchError((_) {});
  }

  String get _base => 'wear.$userId.events.${siteId.isEmpty ? 'all' : siteId}';
  String get _stateKey => '$_base.state';
  String get _draftPrefix => '$_base.draft.';

  @override
  Future<EventWorkspaceState?> read() async {
    final prefs = await SharedPreferences.getInstance();
    EventWorkspaceState state;
    try {
      final raw = prefs.getString(_stateKey);
      state = raw == null
          ? const EventWorkspaceState()
          : EventWorkspaceState.fromJson(jsonDecode(raw));
    } catch (_) {
      state = const EventWorkspaceState();
    }
    final drafts = <String, EventDraft>{};
    for (final key in prefs.getKeys().where(
      (key) => key.startsWith(_draftPrefix),
    )) {
      try {
        final raw = prefs.getString(key);
        if (raw == null) continue;
        final draft = EventDraft.fromJson(jsonDecode(raw));
        if (!draft.isEmpty) drafts[key.substring(_draftPrefix.length)] = draft;
      } catch (_) {
        // One corrupt event draft must not block recovery of the remaining workspace.
      }
    }
    return EventWorkspaceState(
      filters: state.filters,
      current: state.current,
      selectedEventId: state.selectedEventId,
      scrollOffset: state.scrollOffset,
      drafts: drafts,
    );
  }

  @override
  Future<void> write(EventWorkspaceState value) async {
    if ((_writeGenerations[userId] ?? 0) != _writeGeneration) return;
    final previous = _writeTails[userId] ?? Future<void>.value();
    final operation = previous.catchError((_) {}).then((_) async {
      if ((_writeGenerations[userId] ?? 0) != _writeGeneration) return;
      await _writeNow(value);
    });
    _writeTails[userId] = operation.catchError((_) {});
    await operation;
  }

  Future<void> _writeNow(EventWorkspaceState value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _stateKey,
      jsonEncode(
        EventWorkspaceState(
          filters: value.filters,
          current: value.current,
          selectedEventId: value.selectedEventId,
          scrollOffset: value.scrollOffset,
        ).toJson(),
      ),
    );
    final desired = value.drafts.keys.map((id) => '$_draftPrefix$id').toSet();
    final stale = prefs
        .getKeys()
        .where((key) => key.startsWith(_draftPrefix) && !desired.contains(key))
        .toList();
    for (final key in stale) {
      await prefs.remove(key);
    }
    for (final entry in value.drafts.entries) {
      await prefs.setString(
        '$_draftPrefix${entry.key}',
        jsonEncode(entry.value.toJson()),
      );
    }
  }
}
