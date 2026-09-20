import 'dart:async';

import 'package:flutter/material.dart';

import '../core.dart';
import '../scroll_to_top.dart';
import 'api_gateway.dart';
import 'controller.dart';
import 'contact_filters.dart';
import 'lab_calls.dart';
import 'models.dart' hide JsonMap;
import 'rtc_engine.dart';

class CommunicationsPage extends StatefulWidget {
  const CommunicationsPage({
    super.key,
    this.deviceId,
    this.personId,
    this.eventId,
    this.action,
    this.video = false,
  });

  final String? deviceId;
  final String? personId;
  final String? eventId;
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
  bool _multiSelect = false;
  ContactFilters _filters = const ContactFilters();
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
        oldWidget.eventId != widget.eventId) {
      _loading = true;
      _selectedKeys.clear();
      _controller?.selectDevice(null);
      unawaited(_load());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
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

  void _onRefreshRequested() {
    if (mounted) unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _controller?.setForeground(_foreground);
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller != null && !callLabEnabled) {
      _session?.callActive.value = controller.hasActiveOwnedSession;
    }
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final session = _session;
    final gateway = _gateway;
    final controller = _controller;
    if (session == null || gateway == null || controller == null) return;
    final generation = ++_loadGeneration;
    final scope = session.scopeKey;
    final blocking = _people.isEmpty && _devices.isEmpty;
    setState(() {
      if (blocking) _loading = true;
      _loadError = null;
    });
    try {
      final roster = await ContactRoster.load(session.api, lab: callLabEnabled);
      final people = roster.people;
      final devices = roster.devices;
      PersonOption? person;
      List<CommunicationDevice> equipment = const [];
      CommunicationDevice? selected;
      String eventType = '';
      String? resolvedDeviceId = _clean(widget.deviceId);
      final eventId = _clean(widget.eventId);

      if (eventId != null) {
        final event = await gateway.event(eventId);
        eventType = idOf(event['type']);
        resolvedDeviceId ??= _clean(idOf(event['deviceId']));
      }
      final personId = _clean(widget.personId);
      if (personId != null) {
        person =
            people.where((item) => item.id == personId).firstOrNull ??
            await gateway.person(personId);
        equipment = callLabEnabled
            ? devices.where((d) => d.personId == personId).toList()
            : await gateway.equipmentForPerson(personId);
        selected = resolvedDeviceId == null
            ? equipment.firstOrNull
            : equipment
                  .where((item) => item.id == resolvedDeviceId)
                  .firstOrNull;
      }
      if (resolvedDeviceId != null && selected == null) {
        selected = await gateway.device(resolvedDeviceId);
        final assignedPersonId = selected.personId;
        if (person == null && assignedPersonId != null) {
          person = people
              .where((item) => item.id == assignedPersonId)
              .firstOrNull;
        }
      }
      if (selected != null &&
          equipment.every((item) => item.id != selected!.id)) {
        equipment = [...equipment, selected];
      }
      final history = await gateway.calls(
        eventId: eventId,
        deviceId: selected?.id,
      );
      if (!mounted ||
          generation != _loadGeneration ||
          scope != session.scopeKey) {
        return;
      }
      setState(() {
        _tasks = roster.tasks;
        _equipmentByPerson.clear();
        for (final p in people) {
          _equipmentByPerson[p.id] = devices
              .where((d) => d.personId == p.id)
              .toList();
        }
        _people = people;
        _devices = devices;
        _equipment = equipment;
        _history = history;
        _eventType = eventType;
        _loading = false;
        if (selected != null && resolvedDeviceId != null) {
          _selectedKeys
            ..clear()
            ..add('d:${selected.id}');
        } else if (person != null) {
          _selectedKeys
            ..clear()
            ..add('p:${person.id}');
          _equipmentByPerson[person.id] = equipment;
        } else if (selected != null) {
          _selectedKeys
            ..clear()
            ..add('d:${selected.id}');
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
        _loadError = error;
        _loading = false;
      });
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
      final history = await gateway.calls(deviceId: selected?.id);
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
      setState(() => _loadError = error);
    }
  }

  Future<void> _selectDevice(CommunicationDevice device) async {
    _controller?.selectDevice(device);
    final session = _session;
    final gateway = _gateway;
    if (session == null || gateway == null) return;
    final generation = ++_loadGeneration;
    final scope = session.scopeKey;
    try {
      final history = await gateway.calls(
        eventId: _clean(widget.eventId),
        deviceId: device.id,
      );
      if (!mounted ||
          generation != _loadGeneration ||
          scope != session.scopeKey) {
        return;
      }
      setState(() => _history = history);
    } catch (error) {
      if (error is StaleSessionException) return;
      if (mounted &&
          generation == _loadGeneration &&
          scope == session.scopeKey) {
        setState(() => _loadError = error);
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
                                  if (_multiSelect ||
                                      _selectedKeys.isNotEmpty ||
                                      controller?.selectedDevice != null) ...[
                                    KeyedSubtree(
                                      key: _targetActionsKey,
                                      child: _targetActions(controller),
                                    ),
                                    const SizedBox(height: 18),
                                  ],
                                  _filterBar(),
                                  const SizedBox(height: 10),
                                  _selectionBar(),
                                  const SizedBox(height: 10),
                                  ..._visibleContacts.map(_contactTile),
                                  if (_visibleContacts.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                      child: Text(
                                        '没有匹配的人员或设备',
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
          ],
        ),
      ),
    );
  }

  Widget _targetActions(CommunicationsController? controller) {
    final device = controller?.selectedDevice;
    final targets = _action == 'tts'
        ? _batchDevices()
        : callContactDevices(_batchDevices());
    final targetTitle = targets.length > 1
        ? '已选择 ${targets.length} 台设备 · 群组通讯'
        : targets.length == 1
        ? '当前目标 · ${_deviceCaption(targets.single)}'
        : _selectedKeys.isNotEmpty
        ? '已选择 ${_selectedKeys.length} 项 · 暂无匹配设备'
        : device == null
        ? '请选择联系对象'
        : '当前目标 · ${_deviceCaption(device)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          targetTitle,
          maxLines: _multiSelect ? 1 : null,
          overflow: _multiSelect ? TextOverflow.ellipsis : null,
          strutStyle: _multiSelect
              ? const StrutStyle(
                  fontSize: 16,
                  height: 1.5,
                  forceStrutHeight: true,
                )
              : null,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: WearColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in const {'call': '呼叫', 'tts': '文字播报'}.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _action == entry.key,
                onSelected: (_) => setState(() => _action = entry.key),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_action == 'tts')
          if (_multiSelect || _selectedKeys.isNotEmpty)
            _batchTtsCard()
          else
            const WearCard(child: Text('选择人员或设备后，可输入文字并提交播报。'))
        else
          _originateCard(controller),
      ],
    );
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
                hintText: '搜索人员或设备',
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
    if (_presenceBusy || !_foreground) return;
    _presenceBusy = true;
    final session = _session;
    if (session == null) {
      _presenceBusy = false;
      return;
    }
    final scope = session.scopeKey;
    final generation = _loadGeneration;
    try {
      final devices = await ContactRoster.loadDevices(session.api);
      // Lab state is used only for command receipts, never device presence or
      // assignment. Device ownership and status are main-backend records.
      final state = callLabEnabled && _broadcastId != null
          ? jsonMap(await session.api.get('/api/v1/lab/state'))
          : <String, dynamic>{};
      if (!mounted ||
          scope != session.scopeKey ||
          generation != _loadGeneration) {
        return;
      }
      setState(() {
        if (_broadcastId != null) {
          final message = jsonList(
            state['messages'],
          ).where((m) => idOf(m['id']) == _broadcastId).firstOrNull;
          if (message != null) {
            _broadcastReceipts = jsonList(message['receipts']);
          }
        }
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
    } catch (_) {
      /* Pull-to-refresh exposes connection errors without wiping selections. */
    } finally {
      _presenceBusy = false;
    }
  }

  Widget _filterBar() => WearCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.filter_alt_outlined,
              color: WearColors.brand,
              size: 20,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '联系对象筛选 · ${_visibleContacts.length} 项',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: _showFilters,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [Text('筛选'), Icon(Icons.expand_more, size: 18)],
              ),
            ),
          ],
        ),
        if (!_filters.isEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (_filters.teams.isNotEmpty)
                Text(
                  '班组 ${_filters.teams.length}',
                  style: const TextStyle(color: WearColors.brand, fontSize: 12),
                ),
              if (_filters.presence.isNotEmpty)
                Text(
                  _filters.presence == 'online' ? '在线' : '离线',
                  style: const TextStyle(color: WearColors.brand, fontSize: 12),
                ),
              if (_filters.types.isNotEmpty)
                Text(
                  _filters.types.map(_deviceTypeLabel).join(' / '),
                  style: const TextStyle(color: WearColors.brand, fontSize: 12),
                ),
              if (_filters.tasks.isNotEmpty)
                Text(
                  '作业 ${_filters.tasks.length}',
                  style: const TextStyle(color: WearColors.brand, fontSize: 12),
                ),
            ],
          ),
        const Text(
          '状态同步主平台 · 下拉可同步人员与作业变更',
          style: TextStyle(fontSize: 11, color: WearColors.muted),
        ),
      ],
    ),
  );

  Future<void> _showFilters() async {
    var teams = {..._filters.teams};
    var types = {..._filters.types};
    var tasks = {..._filters.tasks};
    var presence = _filters.presence;
    final teamOptions = <String, String>{
      for (final p in _people)
        if (p.teamId.isNotEmpty)
          p.teamId: p.teamName.isEmpty ? '班组 ${p.teamId}' : p.teamName,
    };
    final taskOptions = <String, String>{
      for (final t in _tasks)
        idOf(t['id']): textOf(t['title'], '作业 ${idOf(t['id'])}'),
    };
    final scope = _session!.scopeKey;
    final result = await showModalBottomSheet<ContactFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WearColors.background,
      builder: (sheet) => StatefulBuilder(
        builder: (context, update) {
          Widget choices(
            String title,
            Map<String, String> options,
            Set<String> selected,
          ) => ExpansionTile(
            title: Text(
              '$title${selected.isEmpty ? '' : ' · 已选 ${selected.length}'}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            children: options.isEmpty
                ? [
                    const ListTile(
                      title: Text(
                        '暂无可选项',
                        style: TextStyle(fontSize: 13, color: WearColors.muted),
                      ),
                    ),
                  ]
                : options.entries
                      .map(
                        (e) => CheckboxListTile(
                          dense: true,
                          title: Text(
                            e.value,
                            style: const TextStyle(fontSize: 13),
                          ),
                          value: selected.contains(e.key),
                          onChanged: (value) => update(() {
                            value == true
                                ? selected.add(e.key)
                                : selected.remove(e.key);
                          }),
                        ),
                      )
                      .toList(),
          );
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .72,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
                    child: Text(
                      '筛选联系对象',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Text(
                    '不同条件同时满足 · 同类多选满足任一项',
                    style: TextStyle(fontSize: 12, color: WearColors.muted),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        choices('班组（多选）', teamOptions, teams),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                '设备在线状态',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                '未选设备类型时，按安全帽状态筛选人员',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: WearColors.muted,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE5EEFC),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    for (final entry in const {
                                      '': '全部',
                                      'online': '在线',
                                      'offline': '离线',
                                    }.entries)
                                      Expanded(
                                        child: Semantics(
                                          selected: presence == entry.key,
                                          child: TextButton(
                                            style: TextButton.styleFrom(
                                              minimumSize: const Size(0, 48),
                                              padding: EdgeInsets.zero,
                                              foregroundColor:
                                                  presence == entry.key
                                                  ? WearColors.brand
                                                  : WearColors.muted,
                                              backgroundColor:
                                                  presence == entry.key
                                                  ? Colors.white
                                                  : Colors.transparent,
                                              textStyle: TextStyle(
                                                fontSize: 13,
                                                fontWeight:
                                                    presence == entry.key
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(9),
                                              ),
                                            ),
                                            onPressed: () => update(
                                              () => presence = entry.key,
                                            ),
                                            child: Text(entry.value),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        choices('设备类型（多选）', const {
                          'helmet': '安全帽',
                          'belt': '腰带 / 安全带',
                          'watch': '手表',
                        }, types),
                        choices('作业组（多选）', taskOptions, tasks),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => update(() {
                            teams = {};
                            types = {};
                            tasks = {};
                            presence = '';
                          }),
                          child: const Text('清除'),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(
                              sheet,
                              ContactFilters(
                                teams: teams,
                                types: types,
                                tasks: tasks,
                                presence: presence,
                              ),
                            ),
                            child: const Text('应用筛选'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result == null || !mounted || scope != _session!.scopeKey) return;
    setState(() {
      _filters = result;
      _pruneSelection();
    });
  }

  List<CommunicationDevice> _batchDevices() => selectedContactDevices(
    selectedKeys: _selectedKeys,
    visibleKeys: _visibleContacts.map((c) => c.key).toSet(),
    devices: <String, CommunicationDevice>{
      for (final d in [..._devices, ..._equipment]) d.id: d,
    }.values.toList(),
    filters: _filters,
  );

  Widget _batchTtsCard() => WearCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '文字播报 · ${_batchDevices().length} 台设备',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
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
        const Spacer(),
        OutlinedButton(
          onPressed: () => setState(() => _multiSelect = !_multiSelect),
          style: OutlinedButton.styleFrom(
            backgroundColor: _multiSelect ? WearColors.brand : Colors.white,
            foregroundColor: _multiSelect ? Colors.white : WearColors.brand,
            side: const BorderSide(color: WearColors.brand),
            minimumSize: const Size(72, 36),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('多选'),
        ),
      ],
    );
  }

  Widget _contactTile(_CommsContact contact) {
    final selected = _selectedKeys.contains(contact.key);
    final helmet = contact.person == null
        ? null
        : PersonHelmetStatus(contact.person!.id, _devices);
    final statusLabel = helmet?.label ?? contact.device?.stateLabel ?? '';
    final isOnline =
        helmet?.isOnline ?? contact.device?.isNormalOnline ?? false;
    final statusColor = isOnline
        ? const Color(0xFF0AA56C)
        : (helmet?.device?.isAbnormal ?? contact.device?.isAbnormal ?? false)
        ? WearColors.warning
        : WearColors.muted;
    return Padding(
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
                const SizedBox(width: 10),
                CircleAvatar(
                  backgroundColor: const Color(0xFFF3F6FB),
                  child: Icon(contact.icon, color: WearColors.brand, size: 22),
                ),
                const SizedBox(width: 10),
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
                                  '$statusLabel${(helmet?.device?.simulatedPresence ?? contact.device?.simulatedPresence ?? false) ? ' · 联调' : ''}',
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

  Widget _originateCard(CommunicationsController? controller) {
    if (callLabEnabled) {
      return WearCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '联调模式 · 通过主平台联系安全帽',
              style: TextStyle(fontSize: 12, color: WearColors.muted),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _batchBusy || _session!.callActive.value
                  ? null
                  : () => _startCallForSelection(),
              icon: const Icon(Icons.call_outlined),
              label: Text(
                callContactDevices(_batchDevices()).length > 1
                    ? '发起群呼'
                    : '发起呼叫',
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _originateButton(
          filled: true,
          icon: Icons.call_outlined,
          title: '发起呼叫',
          subtitle: '通过平台联系所选安全帽',
          enabled: controller != null && !controller.busy,
          onTap: () => unawaited(_startCallForSelection()),
        ),
      ],
    );
  }

  Widget _originateButton({
    required bool filled,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final fg = filled ? Colors.white : WearColors.ink;
    final sub = filled
        ? Colors.white.withValues(alpha: 0.86)
        : WearColors.muted;
    return Material(
      color: enabled
          ? (filled ? WearColors.brand : Colors.white)
          : (filled
                ? WearColors.brand.withValues(alpha: 0.4)
                : const Color(0xFFF7FAFF)),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: filled
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: WearColors.line),
                ),
          child: Row(
            children: [
              Icon(icon, color: enabled ? fg : WearColors.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: enabled ? fg : WearColors.muted,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: enabled ? sub : WearColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: enabled ? fg : WearColors.muted),
            ],
          ),
        ),
      ),
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
    final seenDevices = <String>{};
    final items = <_CommsContact>[
      for (final person in _people) _CommsContact.person(person),
    ];
    for (final device in _devices) {
      seenDevices.add(device.id);
      items.add(
        _CommsContact.device(
          device,
          ownerName: _people
              .where((p) => p.id == device.personId)
              .firstOrNull
              ?.name,
        ),
      );
    }
    for (final device in _equipment) {
      if (seenDevices.add(device.id)) {
        items.add(
          _CommsContact.device(
            device,
            ownerName: _people
                .where((p) => p.id == device.personId)
                .firstOrNull
                ?.name,
          ),
        );
      }
    }
    return items;
  }

  List<_CommsContact> get _visibleContacts {
    final query = _search.text.trim().toLowerCase();
    return _allContacts.where((item) {
      if (query.isNotEmpty && !item.matches(query)) return false;
      final person =
          item.person ??
          _people.where((p) => p.id == item.device?.personId).firstOrNull;
      if (item.device != null && !_filters.matchesDevice(item.device!)) {
        return false;
      }
      if (person == null) {
        return _filters.teams.isEmpty && _filters.tasks.isEmpty;
      }
      return _filters.matchesPerson(person, _devices, _tasks);
    }).toList();
  }

  void _pruneSelection() {
    final visible = _visibleContacts.map((c) => c.key).toSet();
    _selectedKeys.retainAll(visible);
    if (_selectedKeys.isEmpty) _controller?.selectDevice(null);
  }

  Future<void> _toggleContact(_CommsContact contact) async {
    final revealActions = !_multiSelect;
    var selecting = true;
    setState(() {
      if (_multiSelect) {
        if (_selectedKeys.contains(contact.key)) {
          _selectedKeys.remove(contact.key);
          selecting = false;
        } else {
          _selectedKeys.add(contact.key);
        }
      } else {
        _selectedKeys
          ..clear()
          ..add(contact.key);
      }
    });
    if (selecting) {
      await _activateContact(contact);
      if (!mounted || !revealActions) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _multiSelect) return;
        final targetContext = _targetActionsKey.currentContext;
        if (targetContext != null) {
          unawaited(
            Scrollable.ensureVisible(
              targetContext,
              duration: const Duration(milliseconds: 200),
            ),
          );
        }
      });
    }
  }

  Future<void> _callContact(_CommsContact contact) async {
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
    final person = contact.person;
    final device = contact.device;
    if (person != null) {
      await _selectPerson(person);
      return;
    }
    if (device != null) {
      await _selectDevice(device);
    }
  }

  Future<CommunicationDevice?> _deviceOf(_CommsContact contact) async {
    if (contact.device != null) return contact.device;
    final person = contact.person;
    if (person == null) return null;
    final cached = _equipmentByPerson[person.id];
    if (cached != null) {
      final matching = cached.where(_filters.matchesDevice);
      return matching.where((item) => item.supports('intercom')).firstOrNull ??
          matching.firstOrNull;
    }
    final gateway = _gateway;
    if (gateway == null) return null;
    try {
      final equipment = await gateway.equipmentForPerson(person.id);
      if (mounted) {
        setState(() => _equipmentByPerson[person.id] = equipment);
      }
      return equipment.where((item) => item.supports('intercom')).firstOrNull ??
          equipment.firstOrNull;
    } catch (_) {
      return null;
    }
  }

  Future<void> _startCallForSelection() async {
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
        await startLabCall(
          context,
          targets.map((d) => d.id).toList(),
          video: false,
        );
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
      final allowed = controller.policy.canStartVoice(device);
      if (!allowed) continue;
      if (resolved.any((d) => d.id == device.id)) continue;
      resolved.add(device);
    }
    if (resolved.isEmpty) {
      _snack('所选对象暂无可用通话装备');
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
    await controller.startCall(video: false, eventId: eventId, kind: kind);
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
  const _CommsContact._({
    required this.key,
    this.person,
    this.device,
    this.ownerName,
  });

  factory _CommsContact.person(PersonOption person) =>
      _CommsContact._(key: 'p:${person.id}', person: person);

  factory _CommsContact.device(
    CommunicationDevice device, {
    String? ownerName,
  }) => _CommsContact._(
    ownerName: ownerName,
    key: 'd:${device.id}',
    device: device,
  );

  final String key;
  final String? ownerName;
  final PersonOption? person;
  final CommunicationDevice? device;

  IconData get icon {
    if (person != null) return Icons.person_outline;
    return switch (device?.typeCode) {
      'helmet' => Icons.engineering_outlined,
      'belt' => Icons.safety_check_outlined,
      _ => Icons.devices_other_outlined,
    };
  }

  String get title {
    if (person != null) return person!.name;
    final item = device!;
    final type = _deviceTypeLabel(item.typeCode);
    final owner = ownerName?.trim() ?? item.personName?.trim() ?? '';
    if (owner.isNotEmpty) return '$owner的$type';
    return item.sn.isEmpty ? '设备 ${item.id}' : item.sn;
  }

  String get subtitle {
    if (person != null) {
      return person!.personCode.isEmpty ? '现场人员' : person!.personCode;
    }
    final item = device!;
    final sn = item.sn.isEmpty ? item.id : item.sn;
    return '$sn · ${_deviceTypeLabel(item.typeCode)}';
  }

  bool matches(String query) =>
      title.toLowerCase().contains(query) ||
      subtitle.toLowerCase().contains(query);
}

String _deviceTypeLabel(String typeCode) => switch (typeCode) {
  'helmet' => '安全帽',
  'belt' => '安全带',
  'watch' => '手表',
  _ => '设备',
};
