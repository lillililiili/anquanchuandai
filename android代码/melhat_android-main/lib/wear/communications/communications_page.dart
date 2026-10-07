import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core.dart';
import '../scroll_to_top.dart';
import 'api_gateway.dart';
import 'controller.dart';
import 'contact_filters.dart';
import 'contact_action_bar.dart';
import 'contact_favorites.dart';
import 'contact_video_request.dart';
import '../inline_filters.dart';
import 'lab_calls.dart';
import 'models.dart' hide JsonMap;
import 'rtc_engine.dart';

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
  List<CallSession> _history = const [];
  final Map<String, List<CommunicationDevice>> _equipmentByPerson = {};
  final Set<String> _selectedKeys = {};
  ContactFavorites? _favorites;
  bool _favoritesReady = false;
  bool _favoriteBusy = false;
  ContactVideoRequest? _videoRequest;
  ContactFilters _filters = const ContactFilters();
  String? _personFilter;
  bool _applyRouteTarget = true;
  List<JsonMap> _tasks = const [];
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
  bool _tasksUnavailable = false;
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
      _selectedKeys.clear();
      _controller?.selectDevice(null);
      unawaited(_load());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    final favorites = ContactFavorites(
      server: session.api.dio.options.baseUrl,
      userId: session.userId,
      siteId: session.siteId ?? 'none',
    );
    if (_favorites?.storageKey != favorites.storageKey) {
      _favorites = favorites;
      _favoritesReady = false;
      _favoriteBusy = false;
      unawaited(_loadFavorites(favorites));
    }
    if (!identical(session, _session)) {
      _controller?.removeListener(_onControllerChanged);
      _controller?.dispose();
      _session?.refreshTick.removeListener(_onRefreshRequested);
      _session = session;
      session.refreshTick.addListener(_onRefreshRequested);
      _gateway = WearCommunicationsGateway(session.api);
      _controller = CommunicationsController(
        gateway: _gateway!,
        rtc: AgoraWearRtcEngine(),
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

  Future<void> _loadFavorites(ContactFavorites favorites) async {
    try {
      await favorites.load();
      if (mounted && identical(favorites, _favorites)) {
        setState(() => _favoritesReady = true);
      }
    } catch (_) {
      if (mounted && identical(favorites, _favorites)) {
        _snack('常用联系人读取失败，请重新进入通讯页');
      }
    }
  }

  Future<void> _toggleFavorite(_CommsContact contact) async {
    final favorites = _favorites;
    if (!_favoritesReady || _favoriteBusy || favorites == null) return;
    setState(() => _favoriteBusy = true);
    try {
      await favorites.toggle(contact.key);
    } catch (_) {
      if (mounted && identical(favorites, _favorites)) {
        _snack('收藏保存失败，请重试');
      }
    } finally {
      if (mounted && identical(favorites, _favorites)) {
        setState(() => _favoriteBusy = false);
      }
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
      _session?.callActive.value = controller.hasActiveOwnedSession;
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
        _tasks = const [];
        _history = const [];
        _equipmentByPerson.clear();
        _selectedKeys.clear();
        _filters = const ContactFilters();
        _personFilter = null;
        _applyRouteTarget = true;
        _rosterScope = null;
        _refreshWarning = null;
        _tasksUnavailable = false;
      }
      if (blocking && (!background || _loadError == null)) _loading = true;
      if (!background) _loadError = null;
    });
    try {
      final roster = await ContactRoster.load(
        session.api,
        lab: callLabEnabled,
        allTasks: session.isAdmin,
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
      final history = await _readHistory(
        eventId: eventId,
        deviceId: selected?.id,
      );
      if (!mounted ||
          generation != _loadGeneration ||
          scope != session.scopeKey) {
        return;
      }
      setState(() {
        if (!roster.tasksUnavailable || blocking) _tasks = roster.tasks;
        _tasksUnavailable = roster.tasksUnavailable;
        _rosterScope = scope;
        _loadError = null;
        _refreshWarning = null;
        _equipmentByPerson.clear();
        for (final p in people) {
          _equipmentByPerson[p.id] = devices
              .where((d) => d.personId == p.id)
              .toList();
        }
        _people = [
          ...people,
          if (person != null && people.every((p) => p.id != person!.id)) person,
        ];
        _devices = devices;
        _equipment = equipment;
        _history = history;
        _eventType = eventType;
        _loading = false;
        if (_applyRouteTarget) {
          _filters = const ContactFilters();
          _search.clear();
          _personFilter = person?.id;
          _selectedKeys.clear();
          if (person != null) {
            _selectedKeys.add('p:${person.id}');
            _equipmentByPerson[person.id] = equipment;
          }
          _applyRouteTarget = false;
        }
      });
      _pruneSelection();
      controller.selectDevice(selected);
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

  Future<void> _selectPerson(PersonOption? person) async {
    final session = _session;
    final gateway = _gateway;
    if (session == null || gateway == null || person == null) return;
    final generation = ++_loadGeneration;
    final scope = session.scopeKey;
    setState(() {
      _equipment = const [];
      _history = const [];
      _loadError = null;
    });
    _controller?.selectDevice(null);
    try {
      final equipment = _devices
          .where((d) => d.personId == person.id && _filters.matchesDevice(d))
          .toList();
      final selected = equipment.firstOrNull;
      final history = await _readHistory(deviceId: selected?.id);
      if (!mounted ||
          generation != _loadGeneration ||
          scope != session.scopeKey) {
        return;
      }
      setState(() {
        _equipment = equipment;
        _equipmentByPerson[person.id] = equipment;
        _history = history;
      });
      _controller?.selectDevice(selected);
    } catch (error) {
      if (error is StaleSessionException) return;
      if (!mounted ||
          generation != _loadGeneration ||
          scope != session.scopeKey) {
        return;
      }
      _snack(_errorText(error));
    }
  }

  Future<List<CallSession>> _readHistory({
    String? eventId,
    String? deviceId,
  }) async {
    // Targets have already been resolved from this station's authorized
    // roster/detail. History is optional and never grants calling privileges.
    if (_session?.can('wear:call:start') != true) return const [];
    try {
      return await _gateway!.calls(eventId: eventId, deviceId: deviceId);
    } on WearApiException catch (error) {
      if (error.code != 403) rethrow;
      return const [];
    }
  }

  @override
  void dispose() {
    _videoRequest?.dispose();
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
                                  _filterBar(),
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
                                  if (_refreshWarning != null ||
                                      _tasksUnavailable)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        _refreshWarning ?? '作业筛选暂不可用，联系人正常显示',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: WearColors.muted,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  _selectionBar(),
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
                                  _historyCard(controller),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            if (!_loading &&
                _loadError == null &&
                controller?.activeCall == null)
              ContactActionBar(
                onVoice: _canUseActions
                    ? () => unawaited(_startCallForSelection())
                    : null,
                onVideo: _canUseActions
                    ? () => unawaited(_startCallForSelection(video: true))
                    : null,
                onBroadcast: _canUseActions ? _showBroadcast : null,
              ),
          ],
        ),
      ),
    );
  }

  bool get _canUseActions =>
      _selectedKeys.isNotEmpty &&
      _refreshWarning == null &&
      !_batchBusy &&
      !_preparingCall &&
      _controller?.busy == false &&
      _session?.callActive.value == false;

  void _showBroadcast() {
    setState(() => _action = 'tts');
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
        _equipment = _equipment
            .map(
              (d) =>
                  _devices.where((fresh) => fresh.id == d.id).firstOrNull ?? d,
            )
            .toList();
        _equipmentByPerson.clear();
        for (final p in _people) {
          _equipmentByPerson[p.id] = _devices
              .where((d) => d.personId == p.id)
              .toList();
        }
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
    _equipmentByPerson.clear();
    for (final p in _people) {
      _equipmentByPerson[p.id] = _devices
          .where((d) => d.personId == p.id)
          .toList();
    }
  }

  Widget _filterBar() => WearCard(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: InlineFilters(
      key: ValueKey('contact-filters-${_session?.scopeKey}'),
      title: '联系对象筛选 · ${_visibleContacts.length} 项',
      groups: [
        const InlineFilterGroup('presence', '状态', {
          'online': '在线',
          'offline': '离线',
        }),
        InlineFilterGroup('team', '班组', {
          for (final p in _people)
            if (p.teamId.isNotEmpty)
              p.teamId: p.teamName.isEmpty ? '班组 ${p.teamId}' : p.teamName,
        }),
        InlineFilterGroup('task', '作业', {
          for (final t in _tasks)
            idOf(t['id']): textOf(t['title'], '作业 ${idOf(t['id'])}'),
        }),
      ],
      value: {
        'team': _filters.teams,
        'presence': _filters.selectedPresence,
        'device': _filters.types,
        'task': _filters.tasks,
      },
      onApply: (selected, _) => setState(() {
        _filters = ContactFilters(
          teams: selected['team'] ?? {},
          types: selected['device'] ?? {},
          tasks: selected['task'] ?? {},
          presences: selected['presence'] ?? {},
        );
        _pruneSelection();
      }),
      footer: const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          '状态同步主平台 · 按联系人安全帽在线状态筛选',
          style: TextStyle(fontSize: 11, color: WearColors.muted),
        ),
      ),
    ),
  );

  CommunicationDevice? get _explicitDevice => [
    ..._devices,
    ..._equipment,
  ].where((d) => d.id == widget.deviceId && d.personId != null).firstOrNull;

  List<CommunicationDevice> _batchDevices() =>
      selectedContactDevices(
        selectedKeys: _selectedKeys,
        visibleKeys: _visibleContacts.map((c) => c.key).toSet(),
        devices: <String, CommunicationDevice>{
          for (final d in [..._devices, ..._equipment]) d.id: d,
        }.values.toList(),
        filters: _filters,
      ).where((device) {
        final explicit = _explicitDevice;
        return explicit == null ||
            device.personId != explicit.personId ||
            device.id == explicit.id;
      }).toList();

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
        TextField(
          controller: _tts,
          minLines: 2,
          maxLines: 4,
          maxLength: 300,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
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
                    '${_selectedKeys.length} 项',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: WearColors.brand,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                '星标联系人优先显示',
                style: TextStyle(fontSize: 11, color: WearColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: _selectedKeys.isEmpty || _batchBusy
              ? null
              : () {
                  setState(() => _selectedKeys.clear());
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
    final selected = _selectedKeys.contains(contact.key);
    final helmet = PersonHelmetStatus(contact.person.id, _devices);
    final statusLabel = helmet.label;
    final isOnline = helmet.isOnline;
    final statusColor = isOnline
        ? const Color(0xFF0AA56C)
        : (helmet.device?.isAbnormal ?? false)
        ? WearColors.warning
        : WearColors.muted;
    return Padding(
      key: ValueKey('contact-${contact.key}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => unawaited(_toggleContact(contact)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                _checkBox(selected),
                const SizedBox(width: 8),
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
                      if (statusLabel.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Icon(Icons.circle, size: 6, color: statusColor),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  '$statusLabel${(helmet.device?.simulatedPresence ?? false) ? ' · 联调' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('favorite-${contact.key}'),
                  tooltip: _favorites?.contains(contact.key) == true
                      ? '取消收藏'
                      : '收藏并置顶',
                  isSelected: _favorites?.contains(contact.key) == true,
                  onPressed: _favoritesReady && !_favoriteBusy
                      ? () => unawaited(_toggleFavorite(contact))
                      : null,
                  icon: const Icon(
                    Icons.star_border_rounded,
                    color: WearColors.muted,
                  ),
                  selectedIcon: const Icon(
                    Icons.star_rounded,
                    color: WearColors.brand,
                  ),
                ),
                IconButton(
                  tooltip: '呼叫',
                  onPressed: () => unawaited(_callContact(contact)),
                  icon: const Icon(
                    Icons.call_outlined,
                    color: WearColors.brand,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _checkBox(bool selected) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? WearColors.brand : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? WearColors.brand : const Color(0xFFC9D4E5),
          width: 1.5,
        ),
      ),
      child: selected
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : null,
    );
  }

  Widget _activeCallCard(CommunicationsController controller) {
    final call = controller.activeCall!;
    final statusColor = call.demo
        ? WearColors.warning
        : call.status == WearCallStatus.connected
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
              WearBadge(text: call.statusLabel, color: statusColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '会话 ${call.id} · 设备 ${call.sn.isEmpty ? call.deviceId : call.sn}',
            style: const TextStyle(color: WearColors.muted),
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
            action(
              Icons.videocam_outlined,
              '开启视频',
              controller.activeCall?.isTerminal == false
                  ? () => _snack('真实通道尚未接入同一通话内开启安全帽视频；语音通话保持不变，未发起新的呼叫。')
                  : null,
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
                      ? '演示会话 · 未接入真实设备'
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

  Widget _historyCard(CommunicationsController? controller) {
    return WearCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '相关会话',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: WearColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          if (_history.isEmpty)
            const Text('暂无相关通话记录', style: TextStyle(color: WearColors.muted))
          else
            ..._history.map((call) {
              final canResume =
                  !callLabEnabled &&
                  controller != null &&
                  !controller.busy &&
                  !controller.hasActiveOwnedSession &&
                  controller.policy.canJoin(call);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  call.video ? Icons.videocam_outlined : Icons.call_outlined,
                  color: WearColors.primary,
                ),
                title: Text(
                  '${call.kind == 'sos' ? 'SOS' : '单呼'} · ${call.sn.isEmpty ? call.deviceId : call.sn}',
                ),
                subtitle: Text(
                  '${call.statusLabel} · ${formatTime(call.startedAt)}',
                ),
                trailing: canResume ? const Icon(Icons.login) : null,
                onTap: canResume ? () => controller.resumeCall(call) : null,
              );
            }),
        ],
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
    final visible = _allContacts.where((item) {
      if (_personFilter != null && item.person.id != _personFilter) {
        return false;
      }
      if (query.isNotEmpty && !item.matches(query)) return false;
      return _filters.matchesPerson(item.person, _devices, _tasks);
    }).toList();
    return _favorites?.order(visible, (contact) => contact.key) ?? visible;
  }

  void _pruneSelection() {
    final visible = _visibleContacts.map((c) => c.key).toSet();
    _selectedKeys.retainAll(visible);
    if (_selectedKeys.isEmpty) _controller?.selectDevice(null);
  }

  Future<void> _toggleContact(_CommsContact contact) async {
    var selecting = true;
    setState(() {
      if (_selectedKeys.contains(contact.key)) {
        _selectedKeys.remove(contact.key);
        selecting = false;
      } else {
        _selectedKeys.add(contact.key);
      }
    });
    if (selecting) {
      await _activateContact(contact);
    }
  }

  Future<void> _callContact(_CommsContact contact) async {
    if (_refreshWarning != null) {
      _snack('请先刷新联系人在线状态');
      return;
    }
    final session = _session;
    if (!mounted ||
        session == null ||
        _batchBusy ||
        _preparingCall ||
        session.callActive.value ||
        _controller?.busy == true) {
      return;
    }
    final scope = session.scopeKey;
    _preparingCall = true;
    setState(() {
      _selectedKeys
        ..clear()
        ..add(contact.key);
    });
    try {
      await _activateContact(contact);
      if (!mounted ||
          scope != session.scopeKey ||
          _batchBusy ||
          session.callActive.value) {
        return;
      }
      _preparingCall = false;
      await _startCallForSelection();
    } finally {
      _preparingCall = false;
    }
  }

  Future<void> _activateContact(_CommsContact contact) async {
    await _selectPerson(contact.person);
  }

  Future<CommunicationDevice?> _deviceOf(_CommsContact contact) async {
    final person = contact.person;
    final explicit = _explicitDevice;
    if (explicit != null && explicit.personId == person.id) return explicit;
    final cached = _equipmentByPerson[person.id];
    if (cached != null) {
      final matching = cached.where(_filters.matchesDevice);
      return matching.where((item) => item.supports('intercom')).firstOrNull ??
          matching.firstOrNull;
    }
    final equipment = _devices.where(
      (d) => d.personId == person.id && _filters.matchesDevice(d),
    );
    return equipment.where((item) => item.supports('intercom')).firstOrNull ??
        equipment.firstOrNull;
  }

  Future<void> _startCallForSelection({bool video = false}) async {
    if (_refreshWarning != null) {
      _snack('请先刷新联系人在线状态');
      return;
    }
    final controller = _controller;
    if (!mounted ||
        controller == null ||
        _batchBusy ||
        _preparingCall ||
        controller.busy ||
        _session?.callActive.value == true) {
      return;
    }
    if (_selectedKeys.isEmpty) {
      _snack('请先选择联系人');
      return;
    }
    if (callLabEnabled) {
      final targets = callContactDevices(_batchDevices());
      if (targets.isEmpty) {
        _snack('所选对象暂无支持呼叫的设备');
        return;
      }
      setState(() => _batchBusy = true);
      try {
        if (video) {
          final model = LabCallScope.of(context);
          if (!model.canViewHelmetVideo) {
            _snack('当前账号无查看安全帽画面的权限');
            return;
          }
          final id = await model.start(targets.map((d) => d.id).toList());
          if (!mounted || id == null) return;
          _videoRequest?.dispose();
          _videoRequest = ContactVideoRequest(
            model,
            (error) => _snack(_errorText(error)),
          )..watch(id);
          context.push('/lab-call/$id');
        } else {
          await startLabCall(context, targets.map((d) => d.id).toList());
        }
      } catch (error) {
        _snack(_errorText(error));
      } finally {
        if (mounted) setState(() => _batchBusy = false);
      }
      return;
    }
    final scope = _session!.scopeKey;
    final resolved = <CommunicationDevice>[];

    for (final contact in _visibleContacts) {
      if (!_selectedKeys.contains(contact.key)) continue;
      final device = await _deviceOf(contact);
      if (device == null) continue;
      final allowed = video
          ? controller.policy.canStartVideo(device)
          : controller.policy.canStartVoice(device);
      if (!allowed) continue;
      if (resolved.any((d) => d.id == device.id)) continue;
      resolved.add(device);
    }
    if (resolved.isEmpty) {
      _snack(video ? '所选对象暂无支持视频的通话装备或当前账号无权限' : '所选对象暂无可用通话装备');
      return;
    }
    if (!mounted || scope != _session?.scopeKey) return;
    controller.selectDevice(resolved.first);
    if (resolved.length > 1) {
      _snack('当前真实通话接口仅支持单呼，请仅选择一个设备；群呼可在联调模式验证。');
      return;
    }
    final eventId = _clean(widget.eventId);
    final kind = eventId != null && _eventType == 'sos' ? 'sos' : 'single';
    await controller.startCall(video: video, eventId: eventId, kind: kind);
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
