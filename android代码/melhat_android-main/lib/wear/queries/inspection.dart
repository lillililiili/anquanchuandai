import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../core.dart';

String inspectionStatus(Object? status) => switch (status) {
  'completed' => '已完成',
  'abnormal' => '有异常',
  _ => '进行中',
};

Color inspectionColor(Object? status) => switch (status) {
  'completed' => const Color(0xFF168447),
  'abnormal' => const Color(0xFFB96300),
  _ => WearColors.brand,
};

String inspectionRequestId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

/// A single shared group snapshot; writes are never optimistically marked successful.
class InspectionController extends ChangeNotifier with WidgetsBindingObserver {
  InspectionController(this.session, this.taskId) : scope = session.scopeKey {
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_resumed && !busy) unawaited(refresh());
    });
    unawaited(refresh());
  }
  final WearSession session;
  final String taskId;
  final String scope;
  JsonMap? data;
  Object? error;
  bool busy = false;
  bool loading = true;
  bool _disposed = false;
  bool _resumed = true;
  int _generation = 0;
  late final Timer _timer;
  final Map<String, String> _requests = {};
  String get path => '/api/v1/work-tasks/$taskId/inspection';
  List<JsonMap> get items => jsonList(data?['items']);
  JsonMap? get current => items
      .where((i) => idOf(i['id']) == idOf(data?['currentItemId']))
      .firstOrNull;
  int get completed => intOf(data?['completed']);
  int get total => intOf(data?['total']);
  JsonMap? get accountProgress => data?['accountProgress'] is Map
      ? jsonMap(data!['accountProgress'])
      : null;
  int get accountCompleted => intOf(accountProgress?['completed']);
  int get accountTotal => intOf(accountProgress?['total']);
  bool get active => !_disposed && scope == session.scopeKey;
  bool get canWrite => active && data != null && error == null && !busy;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed && !busy) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (!active || busy) return;
    final generation = ++_generation;
    try {
      final result = jsonMap(await session.api.get(path));
      if (!active || generation != _generation) return;
      data = result;
      error = null;
    } catch (e) {
      if (!active || generation != _generation) return;
      error = e;
      if (e is WearApiException && [401, 403, 404].contains(e.code)) {
        data = null;
      }
    }
    if (active && generation == _generation) {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> mutate(String suffix, Object body) async {
    if (!active || busy) return false;
    ++_generation;
    busy = true;
    error = null;
    notifyListeners();
    var success = false;
    try {
      final result = jsonMap(
        await session.api.post('$path/$suffix', data: body),
      );
      if (!active) return false;
      data = result;
      success = true;
    } catch (e) {
      if (active) {
        error = e;
        if (e is WearApiException && [401, 403, 404].contains(e.code)) {
          data = null;
        }
      }
    } finally {
      busy = false;
      if (active) notifyListeners();
    }
    if (success) session.requestRefresh();
    return success;
  }

  Future<bool> record(String itemId) async {
    final request = _requests.putIfAbsent(itemId, inspectionRequestId);
    final ok = await mutate('records', {
      'itemId': itemId,
      'requestId': request,
    });
    if (ok) _requests.remove(itemId);
    return ok;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
