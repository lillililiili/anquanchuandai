import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core.dart';
import 'contact_filters.dart';
import 'models.dart' show CommunicationDevice, PersonOption;
import 'lab_video_stream.dart';
import '../queries/query_utils.dart' show deviceTypeLabel;

/// Opt-in signalling lab. Production RTC remains on its existing controller.
const bool callLabEnabled = bool.fromEnvironment('CALL_LAB_ENABLED');

bool labCallActive(JsonMap call) =>
    const ['ringing', 'connected'].contains(call['state']);

String labCallStatus(String? state) => switch (state) {
  'ringing' => '等待接听',
  'connected' => '已接通（状态联调）',
  'ended' => '通话已结束',
  'rejected' => '已拒接',
  'timed_out' => '呼叫超时',
  'offline' => '设备已离线',
  _ => '状态待确认',
};

Future<void> startLabCall(
  BuildContext context,
  List<String> deviceIds, {
  bool video = false,
}) async {
  final model = LabCallScope.of(context);
  try {
    final id = await model.start(deviceIds, video: video);
    if (context.mounted && id != null) context.push('/lab-call/$id');
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

/// Single owner for lab polling and the session's active-call lock. A failed
/// poll invalidates presentation, but retains the lock until the server has
/// confirmed a terminal state, so a network error cannot enable station swap.
class LabCallsModel extends ChangeNotifier {
  LabCallsModel(this.session) : _scope = session.scopeKey;
  final WearSession session;
  String _scope;
  bool _disposed = false, _polling = false, foreground = true;
  int _revision = 0;
  bool fresh = false, busy = false;
  String? error;
  List<JsonMap> calls = [], devices = [];
  Future<void> Function()? _previousTerminate;
  late final Future<void> Function() _terminate = endAll;
  bool _ownsLock = false;
  bool _pendingStart = false;

  bool get eligible => session.me != null && session.siteId != null;
  bool get canViewHelmetVideo =>
      (session.me?['admin'] == true || session.can('wear:call:start')) &&
      (session.me?['admin'] == true ||
          session.isDuty ||
          session.hasRole('wear_platform_admin'));
  JsonMap? get active => calls.where(labCallActive).firstOrNull;
  JsonMap? get incoming => fresh && foreground && session.isDuty
      ? calls
            .where(
              (c) => c['direction'] == 'incoming' && c['state'] == 'ringing',
            )
            .firstOrNull
      : null;
  JsonMap? call(String id) =>
      calls.where((c) => idOf(c['id']) == id).firstOrNull;
  bool _current(String scope) => !_disposed && scope == session.scopeKey;

  void sessionChanged() {
    if (_scope == session.scopeKey) return;
    _scope = session.scopeKey;
    _revision++;
    busy = false;
    _pendingStart = false;
    calls = [];
    devices = [];
    fresh = false;
    error = null;
    _release();
    _notify();
  }

  void _acquire() {
    if (_ownsLock) return;
    // Do not steal an active native RTC session.
    if (session.callActive.value) return;
    _ownsLock = true;
    _previousTerminate = session.terminateCall;
    session.terminateCall = _terminate;
    session.callActive.value = true;
  }

  void _release() {
    if (!_ownsLock) return;
    _ownsLock = false;
    if (identical(session.terminateCall, _terminate)) {
      session.terminateCall = _previousTerminate;
      session.callActive.value = false;
    }
    _previousTerminate = null;
  }

  Future<void> poll() async {
    sessionChanged();
    if (_disposed || _polling || !foreground || !eligible) return;
    final scope = session.scopeKey;
    final revision = _revision;
    _polling = true;
    try {
      final data = jsonMap(await session.api.get('/api/v1/lab/state'));
      if (!_current(scope) || !foreground || revision != _revision) return;
      calls = jsonList(data['calls'])
          .where(
            (c) =>
                idOf(c['siteId']) == session.siteId &&
                idOf(c['userId']) == session.userId,
          )
          .toList();
      devices = jsonList(data['devices']);
      fresh = true;
      error = null;
      if (active != null) {
        _acquire();
      } else if (!_pendingStart) {
        _release();
      }
    } catch (e) {
      if (!_current(scope) || revision != _revision) return;
      fresh = false;
      error = '联调连接中断，通话状态待确认';
    } finally {
      _polling = false;
      if (_current(scope)) _notify();
    }
  }

  Future<String?> start(List<String> ids, {bool video = false}) async {
    if (busy || session.busy || session.callActive.value) {
      throw const WearApiException(409, '请先结束当前通话');
    }
    if (!eligible || ids.isEmpty) throw const WearApiException(400, '请选择在线设备');
    final scope = session.scopeKey;
    _revision++;
    busy = true;
    // Reserve the session before the request: switching station while a slow
    // POST is being accepted would otherwise orphan a live server call.
    _pendingStart = true;
    _acquire();
    _notify();
    try {
      final data = jsonMap(
        await session.api.post(
          '/api/v1/lab/calls',
          // Legacy callers may still pass video=true. Every invitation is now
          // voice; helmet video is a separate one-way view on this same call.
          data: {'deviceIds': ids.toSet().toList(), 'video': false},
        ),
      );
      if (!_current(scope)) return null;
      _revision++;
      final row = data['call'] is Map ? jsonMap(data['call']) : data;
      final id = idOf(row['id']);
      if (id.isEmpty) throw const WearApiException(502, '联调服务未返回通话编号');
      calls = [row, ...calls.where((c) => idOf(c['id']) != id)];
      _pendingStart = false;
      _acquire();
      fresh = true;
      error = null;
      unawaited(poll());
      return _current(scope) ? id : null;
    } catch (_) {
      if (_current(scope)) {
        _pendingStart = false;
        _revision++;
        // A transport error is ambiguous: the server may have created the
        // call. Release only after a fresh poll proves there is no active call.
        // If offline, the normal foreground timer retries on reconnection.
        await poll();
      }
      rethrow;
    } finally {
      if (_current(scope)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> action(String id, String action) async {
    if (busy || !eligible) return;
    if (!const ['accept', 'reject', 'end'].contains(action)) return;
    final scope = session.scopeKey;
    _revision++;
    busy = true;
    _notify();
    try {
      final result = jsonMap(
        await session.api.post('/api/v1/lab/calls/$id/$action', data: {}),
      );
      if (!_current(scope)) return;
      _revision++;
      final row = result['call'] is Map ? jsonMap(result['call']) : result;
      if (idOf(row['id']) == id) {
        calls = [row, ...calls.where((c) => idOf(c['id']) != id)];
        fresh = true;
        error = null;
        if (active == null) _release();
      }
      await poll();
    } finally {
      if (_current(scope)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> setVideo(String id, {required bool enabled}) async {
    if (!canViewHelmetVideo || idOf(call(id)?['userId']) != session.userId) {
      throw const WearApiException(403, '仅当前通话的值班端可查看安全帽画面');
    }
    if (busy ||
        !eligible ||
        !fresh ||
        call(id)?['state'] != 'connected' ||
        !jsonList(
          call(id)?['participants'],
        ).any((p) => p['state'] == 'connected')) {
      throw const WearApiException(409, '请在通话接通且状态同步后查看安全帽画面');
    }
    final scope = session.scopeKey;
    _revision++;
    busy = true;
    _notify();
    try {
      final result = jsonMap(
        await session.api.post(
          '/api/v1/lab/calls/$id/video',
          data: {'enabled': enabled},
        ),
      );
      if (!_current(scope)) return;
      _revision++;
      final row = result['call'] is Map ? jsonMap(result['call']) : result;
      if (idOf(row['id']) != id || row['videoEnabled'] != enabled) {
        throw const WearApiException(502, '现场画面状态未确认，请同步后重试');
      }
      calls = [row, ...calls.where((c) => idOf(c['id']) != id)];
      fresh = true;
      error = null;
      unawaited(poll());
    } catch (_) {
      if (_current(scope)) {
        fresh = false;
        unawaited(poll());
      }
      rethrow;
    } finally {
      if (_current(scope)) {
        busy = false;
        _notify();
      }
    }
  }

  bool canInvite(String id) =>
      eligible &&
      fresh &&
      !busy &&
      (session.me?['admin'] == true || session.can('wear:call:start')) &&
      (session.me?['admin'] == true || session.isDuty) &&
      idOf(call(id)?['userId']) == session.userId &&
      idOf(call(id)?['siteId']) == session.siteId &&
      call(id)?['state'] == 'connected';

  Future<bool> invite(String id, List<String> deviceIds) async {
    if (!canInvite(id)) {
      throw const WearApiException(409, '当前通话暂不可邀请，请确认通话状态');
    }
    final existing = jsonList(
      call(id)?['participants'],
    ).map((p) => idOf(p['deviceId'])).toSet();
    final ids = deviceIds
        .where((id) => id.isNotEmpty && !existing.contains(id))
        .toSet()
        .toList();
    if (ids.isEmpty) throw const WearApiException(400, '请选择尚未参与通话的人员');
    final scope = session.scopeKey;
    _revision++;
    busy = true;
    _notify();
    try {
      final result = jsonMap(
        await session.api.post(
          '/api/v1/lab/calls/$id/invite',
          data: {'deviceIds': ids},
        ),
      );
      if (!_current(scope)) return false;
      if (call(id)?['state'] != 'connected') return false;
      final row = result['call'] is Map ? jsonMap(result['call']) : result;
      if (idOf(row['id']) != id) {
        throw const WearApiException(502, '邀请结果与当前通话不匹配，请刷新状态');
      }
      _revision++;
      calls = [row, ...calls.where((c) => idOf(c['id']) != id)];
      fresh = true;
      error = null;
      if (active == null) _release();
      return true;
    } catch (_) {
      if (_current(scope)) {
        _revision++;
        // A timeout may follow a successful invitation. Reconcile with the
        // server before allowing another attempt; never mark invitees joined.
        fresh = false;
        unawaited(poll());
      }
      rethrow;
    } finally {
      if (_current(scope)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> endAll() async {
    final scope = session.scopeKey;
    final ids = calls.where(labCallActive).map((c) => idOf(c['id'])).toList();
    for (final id in ids) {
      if (!_current(scope)) return;
      await session.api.post('/api/v1/lab/calls/$id/end', data: {});
    }
    if (!_disposed) await poll();
  }

  void setForeground(bool value) {
    foreground = value;
    if (!value) fresh = false;
    _notify();
    if (value) unawaited(poll());
  }

  JsonMap? participantDevice(JsonMap p) => devices
      .where((d) => idOf(d['id'] ?? d['deviceId']) == idOf(p['deviceId']))
      .firstOrNull;

  String _participantValue(List<Object?> values, String fallback) =>
      values
          .map((v) => v?.toString().trim() ?? '')
          .where((v) => v.isNotEmpty)
          .firstOrNull ??
      fallback;

  String participantPersonName(JsonMap p) => _participantValue([
    p['personName'],
    participantDevice(p)?['personName'],
  ], '未关联人员');

  String participantSerial(JsonMap p) => _participantValue([
    p['sn'],
    participantDevice(p)?['sn'],
    p['deviceId'],
  ], '未编号');

  String participantType(JsonMap p) =>
      deviceTypeLabel(p['typeCode'] ?? participantDevice(p)?['typeCode']);

  String participantName(JsonMap p) =>
      '${participantPersonName(p)} · ${participantSerial(p)}';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _release();
    super.dispose();
  }
}

class _InviteCallParticipantsSheet extends StatefulWidget {
  const _InviteCallParticipantsSheet({
    required this.model,
    required this.callId,
  });
  final LabCallsModel model;
  final String callId;
  @override
  State<_InviteCallParticipantsSheet> createState() =>
      _InviteCallParticipantsSheetState();
}

class _InviteCallParticipantsSheetState
    extends State<_InviteCallParticipantsSheet>
    with WidgetsBindingObserver {
  late final String _scope = widget.model.session.scopeKey;
  ContactRoster? _roster;
  final _selected = <String>{};
  String _query = '';
  String? _error;
  bool _loading = true, _submitting = false;
  bool _fetching = false;
  Timer? _refreshTimer;
  bool get _current => mounted && widget.model.session.scopeKey == _scope;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_current &&
          !_submitting &&
          widget.model.foreground &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_load(background: true));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _current && !_submitting) {
      unawaited(_load(background: true));
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load({bool background = false}) async {
    if (!_current || _fetching || _submitting) return;
    _fetching = true;
    setState(() {
      if (!background) _loading = true;
      _error = null;
    });
    try {
      final roster = await ContactRoster.load(
        widget.model.session.api,
        lab: false,
      );
      if (_current) {
        setState(() {
          _roster = roster;
          _selected.retainAll(
            _available().map((d) => d.personId).whereType<String>(),
          );
        });
      }
    } catch (_) {
      if (_current) {
        setState(() {
          _error = '人员加载失败，请重试';
          _roster = null;
        });
      }
    } finally {
      _fetching = false;
      if (_current) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  List<CommunicationDevice> _available() {
    if (!_current) return [];
    final participating = jsonList(
      widget.model.call(widget.callId)?['participants'],
    ).map((p) => idOf(p['deviceId'])).toSet();
    return (_roster?.devices ?? <CommunicationDevice>[])
        .where(
          (d) =>
              d.online == 'online' &&
              d.supports('intercom') &&
              d.personId != null &&
              !participating.contains(d.id),
        )
        .toList();
  }

  Future<void> _invite() async {
    if (!_current || _submitting || !widget.model.canInvite(widget.callId)) {
      return;
    }
    final ids = _available()
        .where((d) => _selected.contains(d.personId))
        .map((d) => d.id)
        .toList();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final invited = await widget.model.invite(widget.callId, ids);
      if (mounted && _current && invited) Navigator.pop(context);
    } catch (error) {
      if (_current) {
        setState(() {
          _error = '$error';
        });
      }
    } finally {
      if (_current) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.model,
    builder: (context, _) {
      final devices = _available();
      final ids = devices.map((d) => d.personId).toSet();
      final people = (_roster?.people ?? <PersonOption>[])
          .where((p) => ids.contains(p.id))
          .toList();
      final query = _query.trim().toLowerCase();
      final visible = people
          .where(
            (p) =>
                query.isEmpty ||
                '${p.name} ${p.personCode} ${devices.where((d) => d.personId == p.id).map((d) => d.sn).join(' ')}'
                    .toLowerCase()
                    .contains(query),
          )
          .toList();
      final count = people.where((p) => _selected.contains(p.id)).length;
      final active = _current && widget.model.canInvite(widget.callId);
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .72,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '邀请人员',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _loading || _submitting
                            ? null
                            : () => _load(),
                        tooltip: '刷新在线人员',
                        icon: const Icon(Icons.refresh),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        tooltip: '关闭邀请',
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Text(
                    '选择在线人员，接听后加入当前通话',
                    style: TextStyle(fontSize: 12, color: WearColors.muted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (value) => setState(() {
                      _query = value;
                    }),
                    decoration: const InputDecoration(
                      hintText: '搜索人员或安全帽',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  if (!_current || (!active && !_submitting))
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        '通话已结束或状态待确认，暂不可邀请',
                        style: TextStyle(color: WearColors.muted),
                      ),
                    ),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _roster == null
                        ? Center(
                            child: TextButton(
                              onPressed: _current ? _load : null,
                              child: const Text('重新加载'),
                            ),
                          )
                        : visible.isEmpty
                        ? Center(
                            child: Text(
                              query.isEmpty ? '暂无可邀请的在线人员' : '没有匹配的人员',
                              style: const TextStyle(color: WearColors.muted),
                            ),
                          )
                        : ListView.builder(
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final p = visible[index];
                              return CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  devices
                                      .where((d) => d.personId == p.id)
                                      .map((d) => '${d.sn} · ${d.stateLabel}')
                                      .join('、'),
                                ),
                                value: _selected.contains(p.id),
                                onChanged: active && !_submitting
                                    ? (checked) => setState(() {
                                        checked == true
                                            ? _selected.add(p.id)
                                            : _selected.remove(p.id);
                                      })
                                    : null,
                              );
                            },
                          ),
                  ),
                  FilledButton.icon(
                    onPressed: active && !_loading && !_submitting && count > 0
                        ? _invite
                        : null,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_call),
                    label: Text(
                      _submitting
                          ? '正在邀请…'
                          : '呼叫并邀请${count > 0 ? '（$count 人）' : ''}',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class LabCallScope extends InheritedNotifier<LabCallsModel> {
  const LabCallScope({
    super.key,
    required LabCallsModel model,
    required super.child,
  }) : super(notifier: model);
  static LabCallsModel of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LabCallScope>()!.notifier!;
}

class LabCallHost extends StatefulWidget {
  const LabCallHost({
    super.key,
    required this.session,
    required this.child,
    required this.openCall,
    this.callPageVisible,
    this.routeChanges,
    this.enabled = callLabEnabled,
  });
  final WearSession session;
  final Widget child;
  final void Function(String id) openCall;
  final bool Function()? callPageVisible;
  final Listenable? routeChanges;
  final bool enabled;
  @override
  State<LabCallHost> createState() => _LabCallHostState();
}

class _LabCallHostState extends State<LabCallHost> with WidgetsBindingObserver {
  late final LabCallsModel model = LabCallsModel(widget.session);
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    widget.routeChanges?.addListener(_routeChanged);
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_sessionChanged);
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(model.poll()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(model.poll());
    });
  }

  void _sessionChanged() {
    // Avoid notifying the widget tree inside router/session rebuilds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        model.sessionChanged();
        unawaited(model.poll());
      }
    });
  }

  void _routeChanged() {
    // GoRouter can notify while its Navigator is building. Refresh the overlay
    // after that frame so push/pop visibility follows the actual top route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      model.setForeground(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    _timer?.cancel();
    widget.routeChanges?.removeListener(_routeChanged);
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_sessionChanged);
    model.dispose();
    super.dispose();
  }

  Future<void> _answer(JsonMap call, bool accept) async {
    final id = idOf(call['id']);
    final scope = widget.session.scopeKey;
    try {
      await model.action(id, accept ? 'accept' : 'reject');
      if (mounted &&
          accept &&
          scope == widget.session.scopeKey &&
          model.call(id)?['state'] == 'connected') {
        widget.openCall(id);
      }
    } catch (_) {
      // Keep the incoming overlay with a retryable error. Never dismiss on a
      // failed answer or tell the operator that the peer accepted.
      model.error = '操作未成功，请检查联调连接后重试';
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return LabCallScope(
      model: model,
      child: AnimatedBuilder(
        animation: model,
        builder: (context, _) {
          final incoming = model.incoming;
          return Stack(
            children: [
              widget.child,
              if (incoming == null &&
                  model.active != null &&
                  !(widget.callPageVisible?.call() ?? false))
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 76,
                  child: SafeArea(
                    child: Material(
                      elevation: 3,
                      color: const Color(0xFFE7F2FF),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => widget.openCall(idOf(model.active!['id'])),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.phone_in_talk,
                                color: WearColors.brand,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  model.fresh
                                      ? '状态联调进行中 · 返回通话'
                                      : '连接中断 · 查看通话状态',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: WearColors.ink,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: WearColors.brand,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (incoming != null) ...[
                const Positioned.fill(
                  child: ModalBarrier(
                    dismissible: false,
                    color: Color(0x660C2340),
                  ),
                ),
                Positioned.fill(
                  child: SafeArea(
                    child: Center(
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          margin: const EdgeInsets.all(24),
                          padding: const EdgeInsets.all(24),
                          constraints: const BoxConstraints(maxWidth: 420),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                incoming['sos'] == true
                                    ? Icons.sos
                                    : Icons.phone_in_talk,
                                color: incoming['sos'] == true
                                    ? const Color(0xFFFF4365)
                                    : WearColors.brand,
                                size: 42,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                incoming['sos'] == true ? '紧急 SOS 来电' : '语音来电',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 12),
                              for (final p in jsonList(
                                incoming['participants'],
                              ))
                                Text(
                                  model.participantName(p),
                                  textAlign: TextAlign.center,
                                ),
                              const SizedBox(height: 12),
                              const Text(
                                '语音状态联调 · 支持测试视频',
                                style: TextStyle(
                                  color: WearColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                              if (model.error != null)
                                Text(
                                  model.error!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: model.busy
                                          ? null
                                          : () => _answer(incoming, false),
                                      child: const Text('拒接'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: model.busy
                                          ? null
                                          : () => _answer(incoming, true),
                                      child: const Text('接听'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class LabCallPage extends StatefulWidget {
  const LabCallPage({super.key, required this.id});
  final String id;
  @override
  State<LabCallPage> createState() => _LabCallPageState();
}

class _LabCallPageState extends State<LabCallPage> {
  Timer? _clock;
  bool _muted = false, _speaker = false;
  bool _closeScheduled = false;

  void _closeFinishedCall(LabCallsModel model) {
    bool finished() =>
        model.fresh &&
        const {
          'ended',
          'rejected',
          'timed_out',
          'offline',
        }.contains(model.call(widget.id)?['state']);
    if (_closeScheduled || !finished()) return;
    _closeScheduled = true;
    final callRoute = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _closeScheduled = false;
      if (!mounted || !finished() || callRoute == null) return;
      final navigator = Navigator.of(context);
      // Dismiss call sheets/dialogs first, but never pop another page above us.
      navigator.popUntil((route) => route == callRoute || route is PageRoute);
      if (!callRoute.isCurrent) return;
      if (navigator.canPop()) {
        navigator.pop();
      } else {
        GoRouter.maybeOf(context)?.go('/communications');
      }
    });
  }

  Widget _participantAvatars(List<JsonMap> people, LabCallsModel model) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
          final columns = constraints.maxWidth < 270 || largeText ? 2 : 3;
          final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final person in people)
                SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFFE8F5FF),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/field-brand/preview/character_avatar.jpg',
                            width: 36,
                            height: 36,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        model.participantPersonName(person),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        model.participantType(person),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: WearColors.muted,
                        ),
                      ),
                      Text(
                        model.participantSerial(person),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          color: WearColors.muted,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        model.fresh
                            ? labCallStatus(
                                person['state']?.toString(),
                              ).replaceAll('（状态联调）', '')
                            : '状态待确认',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: model.fresh && person['state'] == 'connected'
                              ? const Color(0xFF00A985)
                              : WearColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      );
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String _elapsed(JsonMap call, bool fresh) {
    if (!fresh || call['state'] != 'connected') return '--:--';
    final from = intOf(call['connectedAt']);
    if (from <= 0) return '--:--';
    final seconds = ((DateTime.now().millisecondsSinceEpoch - from) ~/ 1000)
        .clamp(0, 86400);
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _end(LabCallsModel model) async {
    try {
      await model.action(widget.id, 'end');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _toggleVideo(LabCallsModel model, bool enabled) async {
    try {
      await model.setVideo(widget.id, enabled: enabled);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showParticipants(LabCallsModel model, bool video) async {
    Widget contents() => AnimatedBuilder(
      animation: model,
      builder: (context, _) {
        final current = model.call(widget.id);
        final people = jsonList(current?['participants'])
            .where(
              (p) =>
                  !video ||
                  (current?['videoEnabled'] == true &&
                      current?['state'] == 'connected' &&
                      p['state'] == 'connected'),
            )
            .toList();
        return ListView(
          padding: const EdgeInsets.all(20),
          shrinkWrap: !video,
          children: [
            const Text(
              '参与设备 · 状态联调',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            if (!video) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: model.canInvite(widget.id)
                    ? () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => _InviteCallParticipantsSheet(
                          model: model,
                          callId: widget.id,
                        ),
                      )
                    : null,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('邀请人员'),
              ),
            ],
            if (video)
              const Text(
                '安全帽单向画面 · 联调视频 · 手机不发布视频',
                style: TextStyle(fontSize: 12, color: WearColors.muted),
              ),
            for (final person in people)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: video
                    ? _scene(person, model, full: true)
                    : ListTile(
                        title: Text(model.participantName(person)),
                        subtitle: Text(
                          '${model.participantType(person)} · ${model.fresh ? labCallStatus(person['state']?.toString()) : '状态待确认'}',
                        ),
                      ),
              ),
          ],
        );
      },
    );
    if (video) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('安全帽画面 · 联调视频'),
              leading: IconButton(
                tooltip: '关闭全屏',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ),
            body: contents(),
          ),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .75,
            ),
            child: contents(),
          ),
        ),
      );
    }
  }

  Widget _control(
    IconData icon,
    String label,
    Color color,
    VoidCallback? tap, {
    bool selected = false,
    String? tooltip,
  }) => SizedBox(
    width: double.infinity,
    child: Column(
      children: [
        IconButton.filledTonal(
          tooltip: tooltip,
          onPressed: tap,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: color.withValues(alpha: selected ? .25 : .10),
            foregroundColor: color,
            fixedSize: const Size(48, 48),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, maxLines: 1, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
  Widget _scene(
    JsonMap p,
    LabCallsModel model, {
    bool full = false,
    bool details = true,
  }) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: AspectRatio(
      aspectRatio: full ? 16 / 9 : 1.2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          LabVideoStream(
            key: ValueKey(
              '${widget.id}:${p['deviceId']}:${model.session.scopeKey}',
            ),
            session: model.session,
            callId: widget.id,
            deviceId: idOf(p['deviceId']),
            active: model.fresh && p['state'] == 'connected',
          ),
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(6),
              color: const Color(0xAA173954),
              child: const Text(
                '联调视频 · 主平台转发',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
          if (details)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: const Color(0xBB173954),
                child: Text(
                  '${model.participantName(p)}\n${model.fresh ? labCallStatus(p['state']?.toString()) : '状态待确认'}',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _videoInfo(
    JsonMap call,
    List<JsonMap> participants,
    LabCallsModel model,
  ) {
    final status = !model.fresh
        ? '状态待确认'
        : call['state'] == 'connected'
        ? '已接通'
        : labCallStatus(call['state']?.toString());
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const CircleAvatar(
          radius: 16,
          backgroundImage: AssetImage(
            'assets/field-brand/preview/character_avatar.jpg',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                participants.length > 1
                    ? '群组通话 · ${participants.length} 台设备'
                    : participants.isEmpty
                    ? '设备通话'
                    : model.participantName(participants.first),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                model.session.siteName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: WearColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          constraints: const BoxConstraints(maxWidth: 86),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: call['sos'] == true
                ? const Color(0xFFFFEDF0)
                : const Color(0xFFE4F8F2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${call['sos'] == true ? 'SOS · ' : ''}$status',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              color: call['sos'] == true
                  ? const Color(0xFFFF4365)
                  : const Color(0xFF00A985),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!callLabEnabled) {
      return const Scaffold(body: Center(child: Text('当前安装包未启用状态联调')));
    }
    final model = LabCallScope.of(context);
    final call = model.call(widget.id);
    _closeFinishedCall(model);
    final video =
        call?['videoEnabled'] == true && call?['state'] == 'connected';
    final participants = jsonList(call?['participants']);
    final videoParticipants = participants
        .where((p) => p['state'] == 'connected')
        .toList();
    final active = call != null && labCallActive(call);
    return Scaffold(
      backgroundColor: WearColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 6),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '返回通讯',
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go('/communications'),
                  icon: const Icon(Icons.chevron_left),
                ),
                const WearRollingWordmark(height: 22),
              ],
            ),
            SizedBox(
              height: video
                  ? WearHeaderLayout.height(context)
                  : (MediaQuery.sizeOf(context).height * .15).clamp(
                      88.0,
                      104.0,
                    ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/field-brand/preview/comms_hero.jpg',
                    fit: BoxFit.cover,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '通讯 / 通话',
                          style: TextStyle(
                            fontSize: 10,
                            color: WearColors.brand,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          video ? '通话与现场画面' : '语音通话',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '语音状态联调 · 支持测试视频',
                          style: TextStyle(
                            fontSize: 12,
                            color: WearColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: WearColors.line),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  children: [
                    if (call == null)
                      const Text('通话记录尚未同步，请稍后重试')
                    else ...[
                      if (!video) ...[
                        if (participants.length > 1)
                          _participantAvatars(participants, model)
                        else
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: const Color(0xFFE8F5FF),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/field-brand/preview/character_avatar.jpg',
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                      ],
                      if (!video) ...[
                        Text(
                          participants.length > 1
                              ? '群组${video ? '视频' : '语音'} · ${participants.length} 台设备'
                              : participants.isEmpty
                              ? '设备通话'
                              : model.participantPersonName(participants.first),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (participants.length == 1) ...[
                          const SizedBox(height: 5),
                          Text(
                            '${model.participantType(participants.first)} · ${model.participantSerial(participants.first)}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: WearColors.muted,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              model.session.siteName,
                              style: const TextStyle(
                                fontSize: 12,
                                color: WearColors.muted,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE4F8F2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                model.fresh
                                    ? labCallStatus(call['state']?.toString())
                                    : '连接中断 · 状态待确认',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: model.fresh
                                      ? const Color(0xFF00A985)
                                      : Colors.orange.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (call['sos'] == true)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'SOS 紧急来电',
                              style: TextStyle(
                                color: Color(0xFFFF4365),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        const SizedBox(height: 2),
                      ] else ...[
                        _videoInfo(call, participants, model),
                        const SizedBox(height: 10),
                        if (participants.length > 1) ...[
                          _participantAvatars(participants, model),
                          const SizedBox(height: 14),
                        ],
                      ],
                      if (video) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: Text(
                            '仅查看安全帽画面 · 手机不发布视频',
                            style: TextStyle(
                              fontSize: 11,
                              color: WearColors.muted,
                            ),
                          ),
                        ),
                        if (videoParticipants.isEmpty)
                          const Text('暂无已接通的安全帽画面'),
                        if (videoParticipants.isNotEmpty)
                          Stack(
                            children: [
                              if (videoParticipants.length == 1)
                                _scene(
                                  videoParticipants.first,
                                  model,
                                  full: true,
                                  details: false,
                                ),
                              if (videoParticipants.length > 1)
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        crossAxisSpacing: 8,
                                        mainAxisSpacing: 8,
                                        childAspectRatio: 1.2,
                                      ),
                                  itemCount: videoParticipants.length,
                                  itemBuilder: (_, i) =>
                                      _scene(videoParticipants[i], model),
                                ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: IconButton(
                                  tooltip: '全屏查看安全帽示意画面',
                                  onPressed: () =>
                                      _showParticipants(model, true),
                                  icon: const Icon(
                                    Icons.fullscreen,
                                    color: Colors.white,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(0x99173954),
                                    fixedSize: const Size(48, 48),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: video ? 10 : 4),
                        child: Text(
                          key: const ValueKey('lab-call-timer'),
                          _elapsed(call, model.fresh),
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0095FF),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: _control(
                              _muted ? Icons.mic_off_outlined : Icons.mic_none,
                              '麦克风',
                              WearColors.brand,
                              active
                                  ? () => setState(() => _muted = !_muted)
                                  : null,
                              selected: _muted,
                              tooltip: _muted
                                  ? '模拟麦克风已关闭，点击开启；不采集音频'
                                  : '模拟麦克风已开启，点击关闭；不采集音频',
                            ),
                          ),
                          Expanded(
                            child: _control(
                              _speaker ? Icons.volume_up : Icons.volume_down,
                              '扬声器',
                              const Color(0xFF00B790),
                              active
                                  ? () => setState(() => _speaker = !_speaker)
                                  : null,
                              selected: _speaker,
                              tooltip: _speaker
                                  ? '模拟扬声器已开启，点击关闭；不播放真实音频'
                                  : '模拟扬声器已关闭，点击开启；不播放真实音频',
                            ),
                          ),
                          Expanded(
                            child: _control(
                              Icons.people_outline,
                              '参与人员',
                              const Color(0xFF8953FF),
                              () => _showParticipants(model, false),
                            ),
                          ),
                          Expanded(
                            child: _control(
                              video
                                  ? Icons.videocam_off_outlined
                                  : Icons.videocam_outlined,
                              video ? '关闭视频' : '开启视频',
                              const Color(0xFF0095FF),
                              model.canViewHelmetVideo &&
                                      call['state'] == 'connected' &&
                                      model.fresh &&
                                      !model.busy
                                  ? () => _toggleVideo(model, !video)
                                  : null,
                              selected: video,
                              tooltip: '查看主平台转发的安全帽单向画面，不发起新呼叫，手机不采集或发布视频',
                            ),
                          ),
                        ],
                      ),
                      if (!model.canViewHelmetVideo)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            '仅当前通话的值班端可查看安全帽画面',
                            style: TextStyle(
                              fontSize: 11,
                              color: WearColors.muted,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            IconButton.filled(
                              onPressed: active && !model.busy
                                  ? () => _end(model)
                                  : null,
                              icon: const Icon(Icons.call_end),
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFFFF4365),
                                foregroundColor: Colors.white,
                                fixedSize: const Size(54, 54),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              child: TextButton(
                                onPressed: () => model.poll(),
                                child: const Text('同步状态'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        active ? '结束通话' : '通话已结束',
                        style: const TextStyle(
                          color: WearColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (model.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          model.error!,
                          style: const TextStyle(color: Colors.orange),
                        ),
                      ),
                    if (call == null)
                      TextButton(
                        onPressed: () => model.poll(),
                        child: const Text('同步状态'),
                      ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 20,
                    color: WearColors.muted,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '仅验证外呼、来电、接听和挂断状态；未采集或传输麦克风、摄像头数据。',
                      style: TextStyle(fontSize: 10, color: WearColors.muted),
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
}
