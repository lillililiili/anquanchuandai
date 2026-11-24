import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core.dart';
import 'phone_audio.dart';

String _phoneId() {
  final random = Random.secure();
  String hex(int n) =>
      List.generate(n, (_) => random.nextInt(16).toRadixString(16)).join();
  return [
    hex(8),
    hex(4),
    '4${hex(3)}',
    (8 + random.nextInt(4)).toRadixString(16) + hex(3),
    hex(12),
  ].join('-');
}

class PhoneCallsModel extends ChangeNotifier {
  PhoneCallsModel(this.session) {
    audio = PhoneAudio(_changed);
  }
  final WearSession session;
  late final PhoneAudio audio;
  String _scope = '', _client = _phoneId();
  Set<String> contacts = {};
  JsonMap? call;
  String? error;
  bool busy = false, fresh = false, foreground = true;
  bool _polling = false, _disposed = false, _uncertainStart = false;
  String? _pendingLeave;
  DateTime? _lastReply;
  int _generation = 0, _action = 0;
  bool get enabled =>
      session.me?['phoneCallsEnabled'] == true &&
      session.siteId != null &&
      !session.api.isMock;
  bool get canDial =>
      enabled &&
      foreground &&
      fresh &&
      !busy &&
      call == null &&
      !session.callActive.value &&
      session.can('wear:call:start');
  bool canSelect(String personId) => canDial && contacts.contains(personId);
  bool get incoming =>
      call != null &&
      jsonList(
        call!['members'],
      ).any((m) => m['id'] == call!['self'] && m['state'] == 'ringing');
  bool _current(int gen) =>
      !_disposed && gen == _generation && session.scopeKey == _scope;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void updateSession() {
    if (_scope == session.scopeKey) return;
    _generation++;
    _action++;
    _scope = session.scopeKey;
    _pendingLeave = null;
    _client = _phoneId();
    call = null;
    busy = false;
    fresh = false;
    _uncertainStart = false;
    _lastReply = null;
    contacts = {};
    error = null;
    session.setPhoneCallActive(false);
    unawaited(audio.close().catchError((_) {}));
    if (enabled && foreground) unawaited(poll());
  }

  Future<JsonMap> _request(String action, [JsonMap args = const {}]) async =>
      jsonMap(
        await session.api.post(
          '/api/guardian/v1/mobile/phone/$action',
          data: {'siteId': session.siteId, 'clientId': _client, ...args},
        ),
      );

  Future<void> poll() async {
    if (_disposed || !enabled || !foreground || _polling || busy) return;
    _polling = true;
    final gen = _generation, seq = _action;
    try {
      final state = await _request('presence', {
        'busy': session.helmetCallActive,
      });
      if (_current(gen) && seq == _action && foreground && !busy) _apply(state);
    } catch (e) {
      if (_current(gen) && seq == _action) {
        if (e is WearApiException && (e.code == 401 || e.code == 403)) _clear();
        fresh = false;
        contacts = {};
        if (call != null || _uncertainStart) {
          error = '网络中断，正在核实通话状态';
          if (_lastReply == null ||
              DateTime.now().difference(_lastReply!).inSeconds >= 25) {
            _clear();
          }
        }
        _changed();
      }
    } finally {
      _polling = false;
    }
  }

  void _clear() {
    _pendingLeave = null;
    call = null;
    _uncertainStart = false;
    session.setPhoneCallActive(false);
    unawaited(audio.close().catchError((_) {}));
  }

  void _apply(JsonMap state) {
    final oldId = call?['id'];
    fresh = state['ready'] == true;
    _lastReply = DateTime.now();
    contacts = (state['contacts'] as List? ?? []).map(idOf).toSet();
    final next = state['call'] is Map ? jsonMap(state['call']) : null;
    error = null;
    if (next == null) {
      if (call != null || _uncertainStart || audio.prepared) _clear();
    } else {
      call = next;
      if (_pendingLeave == next['id']) error = '麦克风已关闭，请重试挂断';
      _uncertainStart = false;
      session.setPhoneCallActive(true);
      if (incoming && oldId != next['id']) {
        unawaited(SystemSound.play(SystemSoundType.alert));
      }
      if (!incoming && audio.prepared && _pendingLeave == null) {
        final id = idOf(next['id']);
        audio.sync(next, (to, type, sdp) async {
          if (call?['id'] != id || _disposed) return;
          await _request('signal', {
            'callId': id,
            'to': to,
            'type': type,
            'sdp': sdp,
          });
        });
      }
    }
    _changed();
  }

  Future<void> start(Set<String> people) async {
    if (!canDial || people.isEmpty || !contacts.containsAll(people)) return;
    if (people.length > 8) throw const WearApiException(400, '每次最多呼叫 8 部手机');
    await _join('start', {
      'personIds': people.toList(),
      'requestId': _phoneId(),
    });
  }

  Future<void> accept() async {
    if (!incoming || busy || session.helmetCallActive) return;
    await _join('accept', {'callId': call!['id']});
  }

  Future<void> _join(String action, JsonMap args) async {
    final gen = _generation;
    ++_action;
    bool submitted = false;
    busy = true;
    error = null;
    session.setPhoneCallActive(true);
    _changed();
    try {
      await audio.prepare();
      if (!_current(gen) || !foreground || session.helmetCallActive) return;
      submitted = true;
      final reply = await _request(action, args);
      if (_current(gen)) {
        if (foreground) {
          _apply(reply);
        }
      }
    } catch (e) {
      if (_current(gen)) {
        _uncertainStart =
            submitted &&
            (e is! WearApiException || e.code >= 500 || e.code < 100);
        if (!_uncertainStart) await audio.close();
        error = _uncertainStart ? '呼叫结果待确认，正在查询' : e.toString();
        if (call == null && !_uncertainStart) session.setPhoneCallActive(false);
      }
      rethrow;
    } finally {
      if (_current(gen)) {
        busy = false;
        if (!foreground && enabled) {
          await _retireBackgroundClient();
        } else if (!submitted && call == null) {
          session.setPhoneCallActive(false);
          await audio.close();
        }
        _changed();
      }
    }
  }

  Future<void> leave() async {
    final current = call;
    if (current == null || busy) return;
    ++_action;
    busy = true;
    final gen = _generation;
    _pendingLeave = idOf(current['id']);
    try {
      await audio.close();
      final reply = await _request('leave', {'callId': current['id']});
      if (_current(gen)) _apply(reply);
    } catch (e) {
      if (_current(gen)) {
        if (e is WearApiException && e.code == 404) {
          _clear();
          error = null;
        } else {
          error = '麦克风已关闭，挂断结果待确认，可重试';
        }
      }
    } finally {
      if (_current(gen)) {
        busy = false;
        _changed();
      }
    }
  }

  Future<void> _retireBackgroundClient() async {
    final offline = _request('offline').then<void>((_) {}).catchError((_) {});
    ++_action;
    _client = _phoneId();
    _clear();
    await offline;
  }

  void setForeground(bool value) {
    if (_disposed || foreground == value) return;
    foreground = value;
    if (value) {
      unawaited(poll());
      return;
    }
    fresh = false;
    contacts = {};
    // Permission prompts temporarily obscure the app. Keep the in-progress preparation intact.
    if (enabled && !busy) {
      unawaited(_retireBackgroundClient());
    }
    _changed();
  }

  @override
  void dispose() {
    if (enabled && foreground) {
      unawaited(_request('offline').then<void>((_) {}).catchError((_) {}));
    }
    _disposed = true;
    _generation++;
    unawaited(audio.close().catchError((_) {}));
    super.dispose();
  }
}

class PhoneCallScope extends InheritedNotifier<PhoneCallsModel> {
  const PhoneCallScope({
    super.key,
    required PhoneCallsModel model,
    required super.child,
  }) : super(notifier: model);
  static PhoneCallsModel? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PhoneCallScope>()?.notifier;
}

class PhoneCallHost extends StatefulWidget {
  const PhoneCallHost({super.key, required this.session, required this.child});
  final WearSession session;
  final Widget child;
  @override
  State<PhoneCallHost> createState() => _PhoneCallHostState();
}

class _PhoneCallHostState extends State<PhoneCallHost>
    with WidgetsBindingObserver {
  late final model = PhoneCallsModel(widget.session);
  Timer? timer;
  int tick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(model.updateSession);
    model.updateSession();
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (model.call != null || model._uncertainStart || ++tick % 3 == 0) {
        unawaited(model.poll());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) model.setForeground(true);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      model.setForeground(false);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(model.updateSession);
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PhoneCallScope(
    model: model,
    child: ListenableBuilder(
      listenable: model,
      child: widget.child,
      builder: (context, child) {
        final call = model.call;
        if (call == null) return Stack(children: [child!]);
        final members = jsonList(
          call['members'],
        ).where((m) => m['id'] != call['self']).toList();
        final incoming = model.incoming;
        return Stack(
          children: [
            child!,
            const ModalBarrier(dismissible: false, color: Colors.black38),
            Center(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Material(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.white,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              incoming ? '手机来电' : '手机通话',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            for (final m in members)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.person_outline),
                                title: Text(idOf(m['name'])),
                                subtitle: Text(
                                  incoming && m['id'] == call['caller']
                                      ? '正在呼叫你'
                                      : switch (m['state']) {
                                          'ringing' => '等待接听',
                                          'declined' => '已拒接',
                                          'left' => '已离开',
                                          'missed' => '无人接听',
                                          'offline' => '已离线',
                                          _ =>
                                            model.audio.connected(idOf(m['id']))
                                                ? '语音已连接'
                                                : model.audio.failure(
                                                        idOf(m['id']),
                                                      ) ??
                                                      '正在连接语音',
                                        },
                                ),
                              ),
                            if (model.error != null)
                              Text(
                                model.error!,
                                style: const TextStyle(
                                  color: WearColors.danger,
                                ),
                              ),
                            const SizedBox(height: 12),
                            if (!incoming)
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => model.audio.setMuted(
                                      !model.audio.muted,
                                    ),
                                    icon: Icon(
                                      model.audio.muted
                                          ? Icons.mic_off
                                          : Icons.mic,
                                    ),
                                    label: Text(
                                      model.audio.muted ? '开启麦克风' : '静音',
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () async {
                                      try {
                                        await model.audio.setSpeaker(
                                          !model.audio.speaker,
                                        );
                                      } catch (_) {
                                        if (mounted) {
                                          setState(
                                            () => model.error = '音频输出切换失败',
                                          );
                                        }
                                      }
                                    },
                                    icon: Icon(
                                      model.audio.speaker
                                          ? Icons.volume_up
                                          : Icons.hearing,
                                    ),
                                    label: Text(
                                      model.audio.speaker ? '切换听筒' : '切换扬声器',
                                    ),
                                  ),
                                ],
                              ),
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: model.busy ? null : model.leave,
                                  child: Text(incoming ? '拒接' : '挂断'),
                                ),
                                if (incoming)
                                  FilledButton(
                                    onPressed: model.busy
                                        ? null
                                        : () async {
                                            try {
                                              await model.accept();
                                            } catch (_) {
                                              /* The call panel shows the reason. */
                                            }
                                          },
                                    child: const Text('接听'),
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
            ),
          ],
        );
      },
    ),
  );
}
