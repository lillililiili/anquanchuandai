import 'dart:async';

import 'package:flutter/material.dart';

import '../core.dart';
import '../scroll_to_top.dart';
import 'api_gateway.dart';
import 'controller.dart';
import 'contact_filters.dart';
import 'contact_action_bar.dart';
import 'phone_calls.dart';
import 'device_voice_messages.dart';
import 'lab_calls.dart';
import 'models.dart' hide JsonMap;
import 'rtc_engine.dart';
import 'sip_rtc_engine.dart';
import 'zlm_rtc_engine.dart';

class CommunicationsPage extends StatefulWidget {
  const CommunicationsPage({
    super.key,
    this.deviceId,
    this.personId,
    this.eventId,
    this.filterRequest,
    this.action,
    this.video = false,
  });

  final String? deviceId;
  final String? personId;
  final String? eventId;
  final String? filterRequest;
  final String? action;
  final bool video;

  @override
  State<CommunicationsPage> createState() => _CommunicationsPageState();
}

class _CommunicationsPageState extends State<CommunicationsPage>
    with WidgetsBindingObserver {
  WearSession? _session;
  WearCommunicationsGateway? _gateway;
  CommunicationsController? _controller;
  final _tts = TextEditingController();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _targetActionsKey = GlobalKey();
  List<PersonOption> _people = const [];
  List<CommunicationDevice> _devices = const [];
  List<CommunicationDevice> _equipment = const [];
  final Set<String> _phones = {};
  final Map<String, CommunicationDevice> _hats = {};
  final Map<String, CommunicationDevice> _broadcastTargets = {};
  PhoneCallsModel? _phoneCalls;
  String? _personFilter;
  bool _applyRouteTarget = true;
  bool _batchBusy = false;
  bool _preparingCall = false;
  List<JsonMap> _broadcastReceipts = const [];
  String? _broadcastId;
  Timer? _presenceTimer;
  bool _presenceBusy = false;
  bool _foreground = true;
  late String _action;
  bool _loading = true;
  Object? _loadError;
  String? _refreshWarning;
  String? _rosterScope;
  String? _activeLoadScope;
  int? _activeLoadGeneration;
  String _eventType = '';
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _action = _initialAction;
    WidgetsBinding.instance.addObserver(this);
  }

  String get _initialAction => widget.action == 'tts' ? 'tts' : 'call';

  @override
  void didUpdateWidget(CommunicationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.action != widget.action || oldWidget.video != widget.video) {
      _action = _initialAction;
    }
    if (oldWidget.deviceId != widget.deviceId ||
        oldWidget.personId != widget.personId ||
        oldWidget.eventId != widget.eventId ||
        oldWidget.filterRequest != widget.filterRequest) {
      _loading = true;
      _applyRouteTarget = true;
      _clearTargets();
      _controller?.selectDevice(null);
      unawaited(_load());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    _phoneCalls = PhoneCallScope.maybeOf(context);
    _phones.retainAll(_phoneCalls?.contacts ?? const <String>{});
    if (!identical(session, _session)) {
      _controller?.removeListener(_onControllerChanged);
      _controller?.dispose();
      _session?.refreshTick.removeListener(_onRefreshRequested);
      _session = session;
      session.refreshTick.addListener(_onRefreshRequested);
      _gateway = WearCommunicationsGateway(session.api);
      _controller = CommunicationsController(
        gateway: _gateway!,
        rtc: session.api.isMock
            ? OfflineWearRtcEngine()
            : ProtocolWearRtcEngine(api: session.api),
        userId: session.userId,
        permissions: session.permissions,
      )..addListener(_onControllerChanged);
      if (!callLabEnabled) session.terminateCall = _controller!.terminate;
      unawaited(_load());
      _presenceTimer?.cancel();
      _presenceTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (!_loading && !_batchBusy) unawaited(_refreshPresence());
      });
    }
  }

  void _onRefreshRequested() {
    if (mounted && _foreground) unawaited(_load(background: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _controller?.setForeground(_foreground);
    if (_foreground && !_loading && !_batchBusy) unawaited(_refreshPresence());
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller != null && !callLabEnabled) {
      _session?.setHelmetCallActive(controller.hasLocalSession);
    }
    if (mounted) setState(() {});
  }

  Future<void> _load({bool background = false}) async {
    final session = _session;
    final gateway = _gateway;
    final controller = _controller;
    if (session == null || gateway == null || controller == null) return;
    final scope = session.scopeKey;
    if (background && _activeLoadScope == scope) return;
    final generation = ++_loadGeneration;
    _activeLoadScope = scope;
    _activeLoadGeneration = generation;
    final blocking = _rosterScope != scope;
    setState(() {
      if (_rosterScope != null && _rosterScope != scope) {
        _people = const [];
        _devices = const [];
        _equipment = const [];
        _clearTargets();
        _personFilter = null;
        _applyRouteTarget = true;
        _rosterScope = null;
        _refreshWarning = null;
      }
      if (blocking && (!background || _loadError == null)) _loading = true;
      if (!background) _loadError = null;
    });
    try {
      final roster = await ContactRoster.load(
        session.api,
        lab: callLabEnabled,
        includeTasks: false,
      );
      final people = roster.people;
      final devices = roster.devices;
      PersonOption? person;
      List<CommunicationDevice> equipment = const [];
      CommunicationDevice? selected;
      String eventType = '';
      String? resolvedDeviceId = _clean(widget.deviceId);
      String? personId = _clean(widget.personId);
      final eventId = _clean(widget.eventId);

      if (eventId != null) {
        final event = await gateway.event(eventId);
        eventType = idOf(event['type']);
        resolvedDeviceId ??= _clean(idOf(event['deviceId']));
        personId ??= _clean(idOf(event['personId']));
      }
      if (personId != null) {
        person =
            people.where((item) => item.id == personId).firstOrNull ??
            await gateway.person(personId);
        equipment = devices.where((d) => d.personId == personId).toList();
        selected = resolvedDeviceId == null
            ? equipment.firstOrNull
            : equipment
                  .where((item) => item.id == resolvedDeviceId)
                  .firstOrNull;
      }
      // An event's person takes priority over a device that may now be reassigned.
      if (resolvedDeviceId != null && selected == null && person == null) {
        selected = await gateway.device(resolvedDeviceId);
        final assignedPersonId = selected.personId;
        if (person == null && assignedPersonId != null) {
          person =
              people.where((item) => item.id == assignedPersonId).firstOrNull ??
              await gateway.person(assignedPersonId);
        }
      }
      if (selected != null &&
          equipment.every((item) => item.id != selected!.id)) {
        equipment = [...equipment, selected];
      }
      if (!mounted ||
          generation != _loadGeneration ||
          scope != session.scopeKey) {
        return;
      }
      setState(() {
        _rosterScope = scope;
        _loadError = null;
        _refreshWarning = null;
        _people = [
          ...people,
          if (person != null && people.every((p) => p.id != person!.id)) person,
        ];
        _devices = devices;
        _equipment = equipment;
        _eventType = eventType;
        _loading = false;
        if (_applyRouteTarget) {
          _search.clear();
          _personFilter = person?.id;
          _clearTargets();
          if (person != null) {
            final hat = _hatOf(person.id);
            if (hat != null && _canCallHat(hat)) _hats[person.id] = hat;
            if (_action == 'tts') {
              for (final device in _broadcastOptions.where(
                (d) => d.personId == person!.id,
              )) {
                _broadcastTargets[device.id] = device;
              }
            }
          }
          _applyRouteTarget = false;
        }
      });
      _pruneSelection();
      controller.selectDevice(selected);
      await controller.recoverOwnedCalls();
    } catch (error) {
      if (error is StaleSessionException) return;
      if (!mounted ||
          generation != _loadGeneration ||
          scope != session.scopeKey) {
        return;
      }
      setState(() {
        if (blocking) {
          _loadError = error;
        } else {
          _markPresenceUnknown();
          _refreshWarning = '通讯刷新失败，在线状态暂不可用，请下拉重试';
          _loadError = null;
        }
        _loading = false;
      });
    } finally {
      if (_activeLoadGeneration == generation) {
        _activeLoadGeneration = null;
        _activeLoadScope = null;
      }
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _presenceTimer?.cancel();
    _session?.refreshTick.removeListener(_onRefreshRequested);
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerChanged);
    // Do not clear callActive during synchronous teardown. The session owns
    // forced expiry and the controller invalidates late RTC continuations.
    _controller?.dispose();
    _tts.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final capabilityNotice = _loading || _loadError != null
        ? null
        : _capabilityNotice;
    return ColoredBox(
      color: WearColors.background,
      child: SafeArea(
        child: Column(
          children: [
            if (controller?.activeCall != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: WearCard(child: _callControls(controller!)),
              ),
            Expanded(
              child: _loading
                  ? const Column(
                      children: [
                        _CommsHero(),
                        Expanded(
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ],
                    )
                  : _loadError != null
                  ? Column(
                      children: [
                        const _CommsHero(),
                        Expanded(
                          child: WearEmpty(
                            title: '通讯数据加载失败',
                            detail: _errorText(_loadError!),
                            onRetry: _load,
                          ),
                        ),
                      ],
                    )
                  : WearScrollToTop(
                      controller: _scroll,
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          key: const ValueKey('wear-communications-list'),
                          controller: _scroll,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          children: [
                            if (controller?.recoveryError.isNotEmpty == true)
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  controller!.recoveryError,
                                  style: const TextStyle(
                                    color: WearColors.danger,
                                  ),
                                ),
                              ),
                            if (controller?.activeCall != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  8,
                                ),
                                child: _activeCallCard(controller!),
                              ),
                            _headerWithSearch(),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                28,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_action == 'tts') ...[
                                    KeyedSubtree(
                                      key: _targetActionsKey,
                                      child: _batchTtsCard(),
                                    ),
                                    const SizedBox(height: 18),
                                  ],
                                  if (_personFilter != null)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: InputChip(
                                        label: Text(
                                          '联系人：${_people.where((p) => p.id == _personFilter).firstOrNull?.name ?? _personFilter}',
                                        ),
                                        deleteButtonTooltipMessage: '清除联系人筛选',
                                        onDeleted: () => setState(() {
                                          _personFilter = null;
                                          _pruneSelection();
                                        }),
                                      ),
                                    ),
                                  if (_refreshWarning != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        _refreshWarning!,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: WearColors.muted,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  _selectionBar(),
                                  if (controller != null &&
                                      controller.activeCall == null &&
                                      controller.statusMessage.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: WearCard(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(controller.statusMessage),
                                            if (controller.rtcPhase ==
                                                WearRtcPhase.preparing)
                                              TextButton(
                                                onPressed: controller
                                                    .cancelPreparation,
                                                child: const Text('取消准备'),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  ..._visibleContacts.map(_contactTile),
                                  if (_visibleContacts.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                      child: Text(
                                        '没有匹配的联系人',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: WearColors.muted,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 14),
                                  const DeviceVoiceMessages(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            if (capabilityNotice != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  capabilityNotice,
                  key: const ValueKey('communications-capability-notice'),
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: WearColors.muted,
                  ),
                ),
              ),
            if (!_loading &&
                _loadError == null &&
                controller?.activeCall == null)
              ContactActionBar(
                onPhone:
                    _canUseActions &&
                        _phones.isNotEmpty &&
                        _phoneCalls?.canDial == true
                    ? () => unawaited(_startPhoneCall())
                    : null,
                onHelmet:
                    _canUseActions &&
                        _hats.isNotEmpty &&
                        _hats.values.every(_canCallHat)
                    ? () => unawaited(_startHelmetCall())
                    : null,
                showBroadcast: _controller?.policy.canSubmitTts == true,
                onBroadcast: _canUseActions && _broadcastOptions.isNotEmpty
                    ? _showBroadcast
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  bool get _canUseActions =>
      _refreshWarning == null &&
      !_batchBusy &&
      !_preparingCall &&
      _controller?.busy == false &&
      _session?.callActive.value == false;

  Iterable<CommunicationDevice> get _currentDevices => {
    for (final d in [..._equipment, ..._devices]) d.id: d,
  }.values;

  CommunicationDevice? _hatOf(String personId) {
    final hats = _currentDevices.where(
      (d) => d.typeCode == 'helmet' && d.personId == personId,
    );
    if (widget.deviceId != null && personId == _personFilter) {
      return hats.where((d) => d.id == widget.deviceId).firstOrNull;
    }
    return hats.where(_canCallHat).firstOrNull ?? hats.firstOrNull;
  }

  bool _canCallHat(CommunicationDevice d) =>
      d.typeCode == 'helmet' &&
      d.personId != null &&
      d.isNormalOnline &&
      _controller?.policy.canStartVideo(d) == true;

  Iterable<CommunicationDevice> get _broadcastOptions => _currentDevices.where(
    (d) =>
        d.personId != null &&
        _controller?.policy.canSendTts(d) == true &&
        (_personFilter == null || d.personId == _personFilter) &&
        (widget.deviceId == null ||
            _personFilter == null ||
            widget.deviceId == d.id),
  );

  String? get _capabilityNotice {
    final policy = _controller?.policy;
    if (policy != null && !policy.canStartCalls && !policy.canSubmitTts) {
      return '当前账号未获设备语音或广播权限，可查看通讯录和事件记录。';
    }
    return null;
  }

  void _showBroadcast() {
    setState(() {
      _action = 'tts';
      for (final device in _broadcastOptions) {
        if (_hats.containsKey(device.personId)) {
          _broadcastTargets[device.id] = device;
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _targetActionsKey.currentContext;
      if (target != null) {
        unawaited(
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 200),
          ),
        );
      }
    });
  }

  Widget _headerWithSearch() {
    return Column(
      children: [
        const _CommsHero(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Material(
            color: Colors.white,
            elevation: 0,
            borderRadius: BorderRadius.circular(16),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(_pruneSelection),
              onSubmitted: (_) => unawaited(_load()),
              decoration: InputDecoration(
                hintText: '搜索联系人',
                hintStyle: const TextStyle(color: WearColors.muted),
                prefixIcon: const Icon(Icons.search, color: WearColors.muted),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: WearColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: WearColors.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: WearColors.brand),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _refreshPresence() async {
    if (_presenceBusy || !_foreground || _activeLoadScope != null) return;
    _presenceBusy = true;
    final session = _session;
    if (session == null) {
      _presenceBusy = false;
      return;
    }
    final scope = session.scopeKey;
    final generation = _loadGeneration;
    var devicesUpdated = false;
    try {
      final devices = await ContactRoster.loadDevices(
        session.api,
        previous: _devices,
      );
      if (!mounted ||
          scope != session.scopeKey ||
          generation != _loadGeneration) {
        return;
      }
      setState(() {
        devicesUpdated = true;
        _refreshWarning = null;
        _devices = devices;
        final priorIds = _equipment.map((d) => d.id).toSet();
        _equipment = _devices.where((d) => priorIds.contains(d.id)).toList();
        _pruneSelection();
      });
      // Optional broadcast receipts cannot hold up or discard authoritative
      // device updates already returned by the main backend.
      final broadcastId = _broadcastId;
      if (callLabEnabled && broadcastId != null) {
        final state = jsonMap(await session.api.get('/api/v1/lab/state'));
        if (!mounted ||
            scope != session.scopeKey ||
            generation != _loadGeneration ||
            broadcastId != _broadcastId) {
          return;
        }
        final message = jsonList(
          state['messages'],
        ).where((m) => idOf(m['id']) == broadcastId).firstOrNull;
        if (message != null) {
          setState(() {
            _broadcastReceipts = jsonList(message['receipts']);
          });
        }
      }
    } catch (error) {
      if (!devicesUpdated &&
          error is! StaleSessionException &&
          mounted &&
          scope == session.scopeKey &&
          generation == _loadGeneration) {
        setState(() {
          _markPresenceUnknown();
          _refreshWarning = '通讯刷新失败，在线状态暂不可用，请下拉重试';
        });
      }
    } finally {
      _presenceBusy = false;
    }
  }

  void _markPresenceUnknown() {
    _devices = ContactRoster.unavailableDevices(_devices);
    _equipment = ContactRoster.unavailableDevices(_equipment);
    _hats.clear();
    _broadcastTargets.clear();
  }

  List<CommunicationDevice> _batchDevices() =>
      _broadcastTargets.values.toList();

  Widget _batchTtsCard() => WearCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '文字播报 · ${_batchDevices().length} 台设备',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            IconButton(
              tooltip: '收起文字播报',
              onPressed: () => setState(() => _action = 'call'),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          '逐台返回发送状态；受理或设备确认不代表现场已听到。',
          style: TextStyle(fontSize: 12, color: WearColors.muted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final device in _broadcastOptions)
              FilterChip(
                label: Text(_deviceCaption(device)),
                selected: _broadcastTargets.containsKey(device.id),
                onSelected: _batchBusy
                    ? null
                    : (selected) => setState(() {
                        if (selected) {
                          _broadcastTargets[device.id] = device;
                        } else {
                          _broadcastTargets.remove(device.id);
                        }
                      }),
              ),
          ],
        ),
        TextField(
          controller: _tts,
          minLines: 2,
          maxLines: 4,
          maxLength: 200,
          decoration: const InputDecoration(
            hintText: '输入要播报的内容',
            border: OutlineInputBorder(),
          ),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            textStyle: Theme.of(context).textTheme.labelLarge,
          ),
          onPressed:
              _batchBusy ||
                  (!callLabEnabled &&
                      !_batchDevices().any(
                        (d) => _controller!.policy.canSendTts(d),
                      ))
              ? null
              : _sendBroadcast,
          icon: const Icon(Icons.campaign_outlined),
          label: Text(_batchBusy ? '提交中…' : '提交播报指令'),
        ),
        ..._broadcastReceipts.map(
          (r) => Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${_receiptCaption(r)} · ${switch (idOf(r['state'])) {
                'sent' => '已发送',
                'acknowledged' => '模拟设备已确认',
                'offline' => '离线未发送',
                'accepted' => '已受理',
                'failed' => '发送失败',
                'unsupported' => '不支持播报',
                _ => '状态待确认',
              }}',
              style: const TextStyle(fontSize: 12, color: WearColors.muted),
            ),
          ),
        ),
      ],
    ),
  );

  String _deviceCaption(CommunicationDevice device) {
    final personName =
        _people.where((p) => p.id == device.personId).firstOrNull?.name ??
        device.personName ??
        '';
    final sn = device.sn.isEmpty ? device.id : device.sn;
    return personName.isEmpty ? sn : '$personName · $sn';
  }

  String _receiptCaption(JsonMap receipt) {
    final id = idOf(receipt['deviceId']);
    final device = [
      ..._devices,
      ..._equipment,
    ].where((d) => d.id == id).firstOrNull;
    if (device != null) return _deviceCaption(device);
    final sn = textOf(receipt['sn'], id);
    final name = textOf(receipt['personName'], '');
    return name.isEmpty ? sn : '$name · $sn';
  }

  Future<void> _sendBroadcast() async {
    if (_batchBusy) return;
    if (_refreshWarning != null) {
      _snack('请先刷新联系人在线状态');
      return;
    }
    final text = _tts.text.trim();
    final devices = _batchDevices();
    final session = _session!;
    final scope = session.scopeKey;
    if (text.isEmpty || devices.isEmpty) {
      _snack('请选择设备并输入播报内容');
      return;
    }
    setState(() {
      _batchBusy = true;
      _broadcastReceipts = [];
      _broadcastId = null;
    });
    try {
      List<JsonMap> receipts;
      if (callLabEnabled) {
        final response = jsonMap(
          await session.api.post(
            '/api/v1/lab/tts',
            data: {
              'deviceIds': devices.map((d) => d.id).toList(),
              'text': text,
            },
          ),
        );
        if (mounted && scope == session.scopeKey) {
          _broadcastId = idOf(response['id']);
        }
        receipts = jsonList(response['receipts']);
      } else {
        final supported = devices
            .where((d) => _controller!.policy.canSendTts(d))
            .toList();
        receipts = [
          for (final d in devices.where((d) => !supported.contains(d)))
            {'deviceId': d.id, 'state': 'unsupported'},
        ];
        if (supported.isNotEmpty) {
          final results = await _gateway!.sendTts(
            deviceIds: supported.map((d) => d.id).toList(),
            recipients: supported
                .map((d) => {...d.equipmentContext, 'deviceId': d.id})
                .toList(),
            text: text,
            idempotencyKey: 'tts-${DateTime.now().microsecondsSinceEpoch}',
            eventId: _clean(widget.eventId),
          );
          receipts.addAll(
            results.map(
              (r) => {'deviceId': r.deviceId, 'state': r.status.name},
            ),
          );
        }
      }
      if (!mounted || scope != session.scopeKey) return;
      setState(() => _broadcastReceipts = receipts);
    } catch (e) {
      if (mounted && scope == session.scopeKey) _snack(_errorText(e));
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  Widget _selectionBar() {
    return Row(
      key: const ValueKey('contact-selection-bar'),
      children: [
        Expanded(
          child: Row(
            children: [
              const Text(
                '已选 ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: WearColors.ink,
                ),
              ),
              Text(
                '${_phones.length + _hats.length} 项',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: WearColors.brand,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed:
              (_phones.isEmpty && _hats.isEmpty && _broadcastTargets.isEmpty) ||
                  _batchBusy
              ? null
              : () {
                  setState(_clearTargets);
                  _controller?.selectDevice(null);
                },
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: WearColors.brand,
            side: const BorderSide(color: WearColors.brand),
            minimumSize: const Size(72, 36),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('清空'),
        ),
      ],
    );
  }

  Widget _contactTile(_CommsContact contact) {
    final id = contact.person.id;
    final helmet = PersonHelmetStatus(id, _devices);
    final hat = _hatOf(id);
    final statusColor = helmet.isOnline
        ? WearColors.online
        : (helmet.device?.isAbnormal ?? false)
        ? WearColors.warning
        : WearColors.muted;
    final canPhone =
        _canUseActions &&
        _phoneCalls?.canSelect(id) == true &&
        (_phones.contains(id) || _phones.length < 8);
    final compatible =
        _hats.containsKey(id) ||
        _hats.isEmpty ||
        (_hats.length < 8 &&
            hat?.source == 'SPLIT_HELMET' &&
            _hats.values.every((d) => d.source == 'SPLIT_HELMET'));
    final canHat =
        hat != null && _canUseActions && _canCallHat(hat) && compatible;
    return Padding(
      key: ValueKey('contact-${contact.key}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFF3F6FB),
                child: Icon(contact.icon, color: WearColors.brand, size: 22),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: WearColors.ink,
                      ),
                    ),
                    Text(
                      contact.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: WearColors.muted,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.circle, size: 6, color: statusColor),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '${helmet.label}${helmet.device?.simulatedPresence == true ? ' · 模拟状态' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: statusColor),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _targetIcon(
                contact,
                phone: true,
                enabled: canPhone,
                selected: _phones.contains(id),
                hint: canPhone ? '选择手机' : '手机当前不可呼叫',
                toggle: () => setState(() {
                  if (!_phones.remove(id)) {
                    if (_phones.length >= 8) {
                      _snack('每次最多呼叫 8 部手机');
                      return;
                    }
                    _phones.add(id);
                  }
                }),
              ),
              _targetIcon(
                contact,
                phone: false,
                enabled: canHat,
                selected: _hats.containsKey(id),
                hint: canHat
                    ? '选择安全帽'
                    : hat == null
                    ? '安全帽未关联'
                    : !hat.isNormalOnline
                    ? '安全帽${hat.stateLabel}'
                    : '安全帽视频对讲不可用',
                toggle: () {
                  if (hat == null) return;
                  setState(() {
                    if (_hats.remove(id) != null) return;
                    _hats[id] = hat;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _targetIcon(
    _CommsContact contact, {
    required bool phone,
    required bool enabled,
    required bool selected,
    required String hint,
    required VoidCallback toggle,
  }) {
    final color = !enabled
        ? const Color(0xFFA4ADBC)
        : selected
        ? const Color(0xFF087D49)
        : WearColors.brand;
    final label = phone ? '手机' : '安全帽';
    return IconButton(
      key: ValueKey('contact-${phone ? 'call' : 'helmet'}-${contact.key}'),
      tooltip: selected && enabled ? '取消选择$label' : hint,
      isSelected: selected && enabled,
      onPressed: enabled ? toggle : null,
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: selected && enabled
            ? const Color(0xFFE0F4E9)
            : Colors.transparent,
      ),
      icon: phone
          ? Icon(
              selected ? Icons.phone_in_talk : Icons.call_outlined,
              color: color,
            )
          : CustomPaint(
              size: const Size.square(24),
              painter: _SafetyHelmetPainter(color),
            ),
    );
  }

  Widget _activeCallCard(CommunicationsController controller) {
    final call = controller.activeCall!;
    final statusColor = call.demo
        ? WearColors.warning
        : controller.isConnected
        ? WearColors.primary
        : call.status == WearCallStatus.failed ||
              call.status == WearCallStatus.timedOut
        ? WearColors.danger
        : WearColors.muted;
    return WearCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '当前会话',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: WearColors.ink,
                  ),
                ),
              ),
              Flexible(
                child: WearBadge(
                  text: controller.activeStatusLabel,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '会话 ${call.id} · 设备 ${call.sn.isEmpty ? call.deviceId : call.sn}',
            style: const TextStyle(color: WearColors.muted),
          ),
          if (call.connectedDeviceIds.isNotEmpty)
            Text(
              '媒体已连接：${call.connectedDeviceIds.join('、')}',
              style: const TextStyle(color: WearColors.muted),
            ),
          for (final skipped in call.skipped)
            Text(
              '${textOf(skipped['deviceId'] ?? skipped['helmetSn'] ?? skipped['sn'], '设备')} · 未接通：${textOf(skipped['reason'] ?? skipped['message'], '设备未受理')}',
              style: const TextStyle(color: WearColors.warning),
            ),
          if (controller.statusMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                controller.statusMessage,
                style: TextStyle(
                  color: controller.rtcPhase == WearRtcPhase.failed
                      ? WearColors.danger
                      : WearColors.ink,
                ),
              ),
            ),
          if (call.video &&
              !controller.isRecoveredSession &&
              controller.rtc is ProtocolWearRtcEngine)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: controller.rtcProtocol == 'ZLM_WEBRTC'
                  ? ValueListenableBuilder(
                      valueListenable: (controller.rtc as ProtocolWearRtcEngine)
                          .splitStreams,
                      builder: (context, streams, _) => Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: streams.entries
                            .map(
                              (entry) => SizedBox(
                                width: streams.length == 1
                                    ? MediaQuery.sizeOf(context).width - 80
                                    : (MediaQuery.sizeOf(context).width - 88) /
                                          2,
                                child: ZlmStreamView(
                                  key: ValueKey(entry.key),
                                  stream: entry.value,
                                  label: entry.key,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    )
                  : SipRemoteVideo(
                      engine: controller.rtc as ProtocolWearRtcEngine,
                    ),
            ),
          if (!controller.policy.owns(call))
            const Padding(
              padding: EdgeInsets.only(top: 9),
              child: Text(
                '仅会话发起人可加入、读取凭证或结束通话。',
                style: TextStyle(color: WearColors.muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _callControls(CommunicationsController controller) {
    if (controller.isRecoveredSession) {
      return Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: controller.busy ? null : controller.refreshActiveCall,
            icon: const Icon(Icons.refresh),
            label: const Text('刷新原通话状态'),
          ),
          FilledButton.icon(
            onPressed:
                !controller.busy &&
                    controller.policy.canEnd(controller.activeCall!)
                ? controller.hangUp
                : null,
            icon: const Icon(Icons.call_end),
            label: const Text('结束原通话'),
          ),
        ],
      );
    }
    Widget action(IconData icon, String label, VoidCallback? onTap) => SizedBox(
      width: 66,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: label,
            onPressed: onTap,
            icon: Icon(
              icon,
              color: onTap == null ? WearColors.muted : WearColors.brand,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: WearColors.ink),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceEvenly,
          spacing: 4,
          runSpacing: 6,
          children: [
            action(
              controller.microphoneMuted
                  ? Icons.mic_off_outlined
                  : Icons.mic_outlined,
              '麦克风',
              controller.isConnected
                  ? () => unawaited(controller.toggleMicrophone())
                  : null,
            ),
            action(
              controller.speakerphoneEnabled
                  ? Icons.volume_up_outlined
                  : Icons.volume_off_outlined,
              '扬声器',
              controller.isConnected
                  ? () => unawaited(controller.toggleSpeakerphone())
                  : null,
            ),
            action(
              Icons.people_outline,
              '参与人员',
              () => _showCallParticipants(controller),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: WearColors.danger),
          onPressed: controller.policy.canEnd(controller.activeCall!)
              ? controller.hangUp
              : null,
          icon: const Icon(Icons.call_end),
          label: const Text('结束通话'),
        ),
      ],
    );
  }

  Future<void> _showCallParticipants(
    CommunicationsController controller,
  ) async {
    final call = controller.activeCall;
    if (call == null) return;
    final target = _devices.where((d) => d.id == call.deviceId).firstOrNull;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '参与人员',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const ListTile(
                leading: Icon(Icons.phone_android),
                title: Text('本机 · 值班端'),
              ),
              ListTile(
                leading: const Icon(Icons.engineering_outlined),
                title: Text(
                  target == null
                      ? (call.sn.isEmpty ? call.deviceId : call.sn)
                      : _deviceCaption(target),
                ),
                subtitle: Text(
                  call.demo
                      ? '演示会话 · 模拟数据'
                      : controller.remotePresent
                      ? '远端已加入'
                      : '等待远端加入',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_CommsContact> get _allContacts {
    final items = <_CommsContact>[
      for (final person in _people) _CommsContact.person(person),
    ];
    return items;
  }

  List<_CommsContact> get _visibleContacts {
    final query = _search.text.trim().toLowerCase();
    return _allContacts.where((item) {
      if (_personFilter != null && item.person.id != _personFilter) {
        return false;
      }
      return query.isEmpty || item.matches(query);
    }).toList();
  }

  void _clearTargets() {
    _phones.clear();
    _hats.clear();
    _broadcastTargets.clear();
  }

  bool _sameAssignment(
    CommunicationDevice current,
    CommunicationDevice saved,
  ) =>
      current.id == saved.id &&
      current.personId == saved.personId &&
      current.equipmentContext['assignmentId'] ==
          saved.equipmentContext['assignmentId'] &&
      current.equipmentContext['assignmentVersion'] ==
          saved.equipmentContext['assignmentVersion'];

  void _pruneSelection() {
    final roster = _people.map((p) => p.id).toSet();
    _phones.retainAll(roster);
    _hats.removeWhere(
      (id, saved) =>
          !roster.contains(id) ||
          !_currentDevices.any(
            (d) => _sameAssignment(d, saved) && _canCallHat(d),
          ),
    );
    _broadcastTargets.removeWhere(
      (id, saved) => !_broadcastOptions.any((d) => _sameAssignment(d, saved)),
    );
  }

  Future<void> _startPhoneCall() async {
    try {
      await _phoneCalls?.start({..._phones});
    } catch (error) {
      if (mounted) _snack(error.toString());
    }
  }

  Future<void> _startHelmetCall() async {
    final controller = _controller;
    if (!_canUseActions || controller == null || _hats.isEmpty) return;
    final scope = _session!.scopeKey;
    final selected = _hats.values.toList();
    setState(() => _preparingCall = true);
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('安全帽呼叫'),
          content: Text(
            selected.first.source == 'SPLIT_HELMET'
                ? '将接收安全帽画面，并开启麦克风进行对讲。'
                : '将开启麦克风和摄像头，与安全帽进行视频通话。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('开始呼叫'),
            ),
          ],
        ),
      );
      if (!mounted ||
          accepted != true ||
          scope != _session?.scopeKey ||
          _session?.callActive.value == true) {
        return;
      }
      if (selected.any(
        (saved) => !_currentDevices.any(
          (d) => _sameAssignment(d, saved) && _canCallHat(d),
        ),
      )) {
        _snack('安全帽状态或领用关系已变化，请重新选择');
        return;
      }
      final event = _clean(widget.eventId);
      controller.selectDevice(selected.first);
      await controller.startCall(
        video: true,
        eventId: event,
        kind: selected.length > 1
            ? 'group'
            : event != null && _eventType == 'sos'
            ? 'sos'
            : 'single',
        targets: selected.length > 1 ? selected : const [],
      );
    } finally {
      if (mounted) setState(() => _preparingCall = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _errorText(Object error) =>
      error is WearApiException ? error.message : '操作未完成，请稍后重试';

  String? _clean(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

class _SafetyHelmetPainter extends CustomPainter {
  const _SafetyHelmetPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final shell = Path()
      ..moveTo(3.5, 16)
      ..cubicTo(3.5, 11.5, 5.7, 8, 9.5, 6.6)
      ..moveTo(14.5, 6.6)
      ..cubicTo(18.3, 8, 20.5, 11.5, 20.5, 16)
      ..moveTo(10.2, 11.5)
      ..lineTo(9.5, 5.5)
      ..quadraticBezierTo(12, 4.4, 14.5, 5.5)
      ..lineTo(13.8, 11.5);
    canvas.drawPath(shell, stroke);
    canvas.drawRRect(
      RRect.fromLTRBR(2, 16, 22, 19.5, const Radius.circular(1.4)),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_SafetyHelmetPainter oldDelegate) =>
      color != oldDelegate.color;
}

class _CommsHero extends StatelessWidget {
  const _CommsHero();

  @override
  Widget build(BuildContext context) {
    return const WearBrandHero(
      key: ValueKey('wear-page-hero-comms'),
      title: '通讯',
      subtitle: '高效协同，守护安全',
      background: WearArt.commsHero,
    );
  }
}

class _CommsContact {
  const _CommsContact.person(this.person);
  final PersonOption person;
  String get key => 'p:${person.id}';
  IconData get icon => Icons.person_outline;
  String get title => person.name;
  String get subtitle => person.personCode.isEmpty ? '现场人员' : person.personCode;
  bool matches(String query) =>
      title.toLowerCase().contains(query) ||
      subtitle.toLowerCase().contains(query);
}
