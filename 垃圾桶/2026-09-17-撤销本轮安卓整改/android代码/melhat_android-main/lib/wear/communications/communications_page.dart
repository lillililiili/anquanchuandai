import 'dart:async';
import 'dart:math';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core.dart';
import 'api_gateway.dart';
import 'controller.dart';
import 'models.dart' hide JsonMap;
import 'rtc_engine.dart';

enum _View { contacts, prepare, broadcast, history, call }

class CommunicationsPage extends StatefulWidget {
  const CommunicationsPage({
    super.key,
    this.deviceId,
    this.personId,
    this.eventId,
    this.video = false,
    this.actionIntent,
  });
  final String? deviceId;
  final String? personId;
  final String? eventId;
  final bool video;
  final String? actionIntent;
  @override
  State<CommunicationsPage> createState() => _CommunicationsPageState();
}

class _CommunicationsPageState extends State<CommunicationsPage>
    with WidgetsBindingObserver {
  WearSession? _session;
  String? _scopeKey;
  WearCommunicationsGateway? _gateway;
  CommunicationsController? _controller;
  final _search = TextEditingController();
  final _tts = TextEditingController();
  final _scroll = ScrollController();
  List<PersonOption> _people = [];
  List<CommunicationDevice> _devices = [];
  List<JsonMap> _myEquipment = [];
  final _equipment = <String, List<CommunicationDevice>>{};
  final _equipmentErrors = <String, String>{};
  final _equipmentLoading = <String>{};
  final _selectedPeople = <String>{};
  final _chosenDevices = <String, CommunicationDevice>{};
  final _standaloneDevices = <String, CommunicationDevice>{};
  final _callHistory = <String, CallSession>{};
  List<TtsCommand> _ttsResults = [];
  List<CommunicationDevice> _submittedTargets = [];
  String _submittedText = '';
  _View _view = _View.contacts;
  bool _deviceSearch = false;
  bool _multiSelect = false;
  bool _video = false;
  bool _fromHelmet = false;
  bool _loading = true;
  bool _historyBusy = false;
  bool _ttsBusy = false;
  String _broadcastScope = 'selected';
  String? _error;
  String? _deviceError;
  String? _historyError;
  String? _ttsError;
  String _eventType = '';
  int _generation = 0;
  int _selectionRequest = 0;
  bool _resolvingDevice = false;
  bool _contextApplied = false;
  ColorScheme get _colors => Theme.of(context).colorScheme;
  List<CommunicationDevice> get _targets => {
    for (final id in _selectedPeople)
      if (_chosenDevices[id] != null)
        _chosenDevices[id]!.id: _chosenDevices[id]!,
    ..._standaloneDevices,
  }.values.toList();
  int get _selectionCount => _selectedPeople.length + _standaloneDevices.length;
  String get _selectionLabel =>
      '已选 ${_selectedPeople.length} 人 · ${_targets.length} 台终端'
      '${_standaloneDevices.isEmpty ? '' : '（${_standaloneDevices.length} 台持有人未确认）'}';
  _View get _intentView => switch (widget.actionIntent) {
    'tts' => _View.broadcast,
    'history' => _View.history,
    'call' => _View.call,
    'voice' || 'video' => _View.prepare,
    _ =>
      widget.personId != null ||
              widget.deviceId != null ||
              widget.eventId != null
          ? _View.prepare
          : _View.contacts,
  };
  @override
  void initState() {
    super.initState();
    _video = widget.video || widget.actionIntent == 'video';
    _view = _intentView;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant CommunicationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId ||
        oldWidget.personId != widget.personId ||
        oldWidget.eventId != widget.eventId ||
        oldWidget.actionIntent != widget.actionIntent ||
        oldWidget.video != widget.video) {
      if (widget.actionIntent == 'call' ||
          _controller?.hasActiveOwnedSession == true) {
        _view = _View.call;
        return;
      }
      _video = widget.video || widget.actionIntent == 'video';
      _view = _intentView;
      _selectedPeople.clear();
      _standaloneDevices.clear();
      _contextApplied = false;
      unawaited(_load());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (identical(session, _session) && _scopeKey == session.scopeKey) return;
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    _session = session;
    _scopeKey = session.scopeKey;
    _generation++;
    _selectionRequest++;
    _resolvingDevice = false;
    _contextApplied = false;
    _people = [];
    _devices = [];
    _myEquipment = [];
    _equipment.clear();
    _equipmentErrors.clear();
    _equipmentLoading.clear();
    _selectedPeople.clear();
    _chosenDevices.clear();
    _standaloneDevices.clear();
    _callHistory.clear();
    _ttsResults = [];
    _submittedTargets = [];
    _submittedText = '';
    _tts.clear();
    _search.clear();
    _ttsBusy = false;
    _historyBusy = false;
    _ttsError = null;
    _historyError = null;
    _deviceError = null;
    _view = _intentView;
    _gateway = WearCommunicationsGateway(session.api);
    _controller = CommunicationsController(
      gateway: _gateway!,
      rtc: AgoraWearRtcEngine(),
      userId: session.userId,
      permissions: session.permissions,
    )..addListener(_onControllerChanged);
    session.terminateCall = _controller!.terminate;
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _controller?.setForeground(state == AppLifecycleState.resumed);
  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    _session?.callActive.value = controller.hasActiveOwnedSession;
    setState(() {
      final call = controller.activeCall;
      if (call != null) _callHistory[call.id] = call;
    });
  }

  bool _current(int generation, String scope) =>
      mounted && generation == _generation && scope == _session?.scopeKey;
  Future<void> _load() async {
    final session = _session;
    final gateway = _gateway;
    if (session == null || gateway == null) return;
    final generation = ++_generation;
    final scope = session.scopeKey;
    setState(() {
      _loading = _people.isEmpty;
      _error = null;
    });
    try {
      final people = await gateway.peopleOptions();
      if (!_current(generation, scope)) return;
      setState(() {
        _people = people;
        _loading = false;
      });
      await _loadDevices();
      try {
        final equipment = jsonList(
          await session.api.get('/api/v1/me/equipment'),
        );
        if (_current(generation, scope)) {
          setState(() => _myEquipment = equipment);
        }
      } catch (_) {
        /* Binding remains unconfirmed; helmet origin stays unavailable. */
      }
      if (!_current(generation, scope)) return;
      if (_contextApplied) {
        await Future.wait(_selectedPeople.toList().map(_loadEquipment));
        return;
      }
      String? personId = _clean(widget.personId);
      final deviceId = _clean(widget.deviceId);
      final eventId = _clean(widget.eventId);
      if (eventId != null) {
        final event = await gateway.event(eventId);
        if (!_current(generation, scope)) return;
        _eventType = idOf(event['type']);
        personId ??= _clean(idOf(event['personId']));
        if (personId == null && deviceId == null) {
          _error = '告警未提供可解析人员，请确认联系对象；未自动呼叫来源设备。';
        }
      }
      if (!_current(generation, scope)) return;
      if (personId != null) {
        if (!_people.any((p) => p.id == personId)) {
          final person = await gateway.person(personId);
          if (!_current(generation, scope)) return;
          _people = [..._people, person];
        }
        _selectedPeople.add(personId);
        await _loadEquipment(personId);
        if (!_current(generation, scope)) return;
        if (deviceId != null) {
          final match = _equipment[personId]
              ?.where((d) => d.id == deviceId)
              .firstOrNull;
          if (match != null) {
            _chosenDevices[personId] = match;
          } else {
            _error = '来源设备不在该人员当前装备中，请确认可用终端。';
          }
        }
      } else if (deviceId != null) {
        final raw = jsonMap(await session.api.get('/api/v1/devices/$deviceId'));
        if (!_current(generation, scope)) return;
        await _selectDevice(
          CommunicationDevice.fromJson(
            raw,
            assignment: jsonMap(raw['currentAssignment']),
          ),
        );
      }
      if (!_current(generation, scope)) return;
      _contextApplied = true;
      setState(() {});
      if (_view == _View.history) await _loadHistory();
    } catch (error) {
      if (error is StaleSessionException || !_current(generation, scope)) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _errorText(error);
      });
    }
  }

  Future<void> _loadDevices() async {
    final session = _session!;
    final scope = session.scopeKey;
    try {
      final page = await session.api.page(
        '/api/v1/devices',
        size: 50,
        query: {
          if (_deviceSearch && _search.text.trim().isNotEmpty)
            'sn': _search.text.trim(),
        },
      );
      if (!mounted || scope != session.scopeKey) return;
      setState(() {
        _devices = page.records
            .map(
              (raw) => CommunicationDevice.fromJson(
                raw,
                assignment: jsonMap(raw['currentAssignment']),
              ),
            )
            .toList();
        _deviceError = null;
      });
    } catch (error) {
      if (error is StaleSessionException ||
          !mounted ||
          scope != session.scopeKey) {
        return;
      }
      setState(() => _deviceError = _errorText(error));
    }
  }

  Future<void> _loadEquipment(String personId) async {
    if (_equipmentLoading.contains(personId)) return;
    final scope = _session!.scopeKey;
    setState(() {
      _equipmentLoading.add(personId);
      _equipmentErrors.remove(personId);
    });
    try {
      final items = await _gateway!.equipmentForPerson(personId);
      if (!mounted || scope != _session?.scopeKey) return;
      setState(() {
        _equipment[personId] = items;
        _equipmentLoading.remove(personId);
        // An initially unassigned search result can later be resolved through
        // authoritative equipment data. Keep it as one person's terminal.
        for (final item in items) {
          if (_standaloneDevices.remove(item.id) != null) {
            _selectedPeople.add(personId);
            _chosenDevices[personId] = item;
          }
        }
        final candidates = items
            .where(
              (d) =>
                  !d.demo &&
                  (_view == _View.broadcast
                      ? d.supports('tts')
                      : d.supports('intercom')),
            )
            .toList();
        if (candidates.length == 1 && !_chosenDevices.containsKey(personId)) {
          _chosenDevices[personId] = candidates.single;
        }
        if (_chosenDevices[personId] != null &&
            !items.any((d) => d.id == _chosenDevices[personId]!.id)) {
          _chosenDevices.remove(personId);
        }
      });
    } catch (error) {
      if (error is StaleSessionException ||
          !mounted ||
          scope != _session?.scopeKey) {
        return;
      }
      setState(() {
        _equipmentLoading.remove(personId);
        _equipmentErrors[personId] = _errorText(error);
      });
    }
  }

  Future<void> _togglePerson(PersonOption person) async {
    if (_ttsBusy) return;
    _selectionRequest++;
    _resolvingDevice = false;
    setState(() {
      if (_selectedPeople.contains(person.id)) {
        _selectedPeople.remove(person.id);
      } else {
        if (!_multiSelect) {
          _selectedPeople.clear();
          _standaloneDevices.clear();
        }
        _selectedPeople.add(person.id);
      }
    });
    if (_selectedPeople.contains(person.id) &&
        !_equipment.containsKey(person.id)) {
      await _loadEquipment(person.id);
    }
  }

  Future<void> _selectDevice(CommunicationDevice device) async {
    if (_ttsBusy) return;
    final personId =
        device.personId ??
        _equipment.entries
            .where((entry) => entry.value.any((item) => item.id == device.id))
            .map((entry) => entry.key)
            .firstOrNull;
    setState(() {
      if (!_multiSelect) {
        _selectedPeople.clear();
        _standaloneDevices.clear();
      }
      if (personId != null) {
        _selectedPeople.add(personId);
        _chosenDevices[personId] = device;
        _standaloneDevices.remove(device.id);
      } else {
        _standaloneDevices[device.id] = device;
      }
    });
    if (personId != null && !_equipment.containsKey(personId)) {
      await _loadEquipment(personId);
    }
  }

  Future<void> _selectSearchedDevice(CommunicationDevice device) async {
    if (_ttsBusy) return;
    final request = ++_selectionRequest;
    final scope = _session!.scopeKey;
    setState(() {
      _resolvingDevice = true;
      _deviceError = null;
    });
    try {
      final raw = jsonMap(
        await _session!.api.get('/api/v1/devices/${device.id}'),
      );
      if (!mounted ||
          scope != _session?.scopeKey ||
          request != _selectionRequest) {
        return;
      }
      final resolved = CommunicationDevice.fromJson(
        raw,
        assignment: jsonMap(raw['currentAssignment']),
      );
      setState(() {
        _devices = _devices
            .map((item) => item.id == resolved.id ? resolved : item)
            .toList();
      });
      await _selectDevice(resolved);
    } catch (error) {
      if (error is StaleSessionException ||
          !mounted ||
          scope != _session?.scopeKey ||
          request != _selectionRequest) {
        return;
      }
      setState(() => _deviceError = _errorText(error));
    } finally {
      if (mounted &&
          scope == _session?.scopeKey &&
          request == _selectionRequest) {
        setState(() => _resolvingDevice = false);
      }
    }
  }

  Future<void> _loadHistory() async {
    if (_historyBusy) return;
    final scope = _session!.scopeKey;
    setState(() {
      _historyBusy = true;
      _historyError = null;
    });
    try {
      final eventId = _clean(widget.eventId);
      final results = eventId != null
          ? await _gateway!.calls(eventId: eventId)
          : (await Future.wait(
              _targets.map((d) => _gateway!.calls(deviceId: d.id)),
            )).expand((v) => v).toList();
      if (!mounted || scope != _session?.scopeKey) return;
      setState(() {
        for (final call in results) {
          _callHistory[call.id] = call;
        }
      });
    } catch (error) {
      if (error is StaleSessionException ||
          !mounted ||
          scope != _session?.scopeKey) {
        return;
      }
      setState(() => _historyError = _errorText(error));
    } finally {
      if (mounted && scope == _session?.scopeKey) {
        setState(() => _historyBusy = false);
      }
    }
  }

  void _open(_View view) {
    setState(() => _view = view);
    if (view == _View.history) unawaited(_loadHistory());
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    _search.dispose();
    _tts.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _view == _View.contacts,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _open(_View.contacts);
    },
    child: ColoredBox(
      color: _colors.surface,
      child: SafeArea(
        child: Column(
          children: [
            if (_view != _View.contacts)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '返回通讯',
                      onPressed: () => _open(_View.contacts),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Expanded(
                      child: Text(switch (_view) {
                        _View.prepare => '呼叫准备',
                        _View.broadcast => '文字播报',
                        _View.history => '通话记录',
                        _View.call => '当前通话',
                        _ => '通讯',
                      }, style: Theme.of(context).textTheme.titleLarge),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _view == _View.contacts
                  ? _contactsView()
                  : _taskView(),
            ),
            if (_view == _View.contacts && _selectionCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _open(_View.prepare),
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('呼叫准备'),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  Widget _contactsView() {
    final query = _search.text.trim().toLowerCase();
    final people = _people.where(
      (p) => '${p.name} ${p.personCode}'.toLowerCase().contains(query),
    );
    final devices = _devices.where(
      (d) => '${d.sn} ${d.personName ?? ''}'.toLowerCase().contains(query),
    );
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const PageStorageKey('communications-contacts'),
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const WearBrandHero(
            title: '通讯',
            subtitle: '找到现场人员，选择设备发起联系',
            background: '',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _open(_View.broadcast),
                  icon: const Icon(Icons.campaign_outlined),
                  label: const Text('文字播报'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _open(_View.history),
                  icon: const Icon(Icons.history),
                  label: const Text('通话记录'),
                ),
              ),
            ],
          ),
          if (_controller?.activeCall != null) ...[
            const SizedBox(height: 8),
            ListTile(
              tileColor: _colors.surfaceContainerHighest,
              leading: Icon(Icons.call, color: _colors.primary),
              title: Text(_callLabel(_controller!)),
              subtitle: const Text('返回当前会话'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(_View.call),
            ),
          ],
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('按人员'),
                icon: Icon(Icons.people_outline),
              ),
              ButtonSegment(
                value: true,
                label: Text('按设备查找'),
                icon: Icon(Icons.devices_outlined),
              ),
            ],
            selected: {_deviceSearch},
            onSelectionChanged: (value) =>
                setState(() => _deviceSearch = value.single),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (_deviceSearch) unawaited(_loadDevices());
            },
            decoration: InputDecoration(
              labelText: _deviceSearch ? '设备编号 / 持有人' : '姓名 / 人员编号',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: '清除搜索',
                onPressed: () {
                  _search.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.close),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _selectionLabel,
                  style: TextStyle(color: _colors.onSurfaceVariant),
                ),
              ),
              FilterChip(
                label: const Text('多选'),
                selected: _multiSelect,
                onSelected: (value) => setState(() => _multiSelect = value),
              ),
            ],
          ),
          if (_error != null) _notice(_error!, retry: _load),
          if (_deviceSearch && _deviceError != null)
            _notice(_deviceError!, retry: _loadDevices),
          if (_deviceSearch && _resolvingDevice)
            const LinearProgressIndicator(),
          if (!_deviceSearch) ...[
            ...people.map(_personTile),
            if (people.isEmpty) _empty(query.isEmpty ? '暂无可联系人员' : '没有匹配人员'),
          ] else ...[
            _hint('设备辅助查找；同一持有人的装备不会重复计为人员。'),
            const SizedBox(height: 8),
            ...devices.map(_deviceTile),
            if (devices.isEmpty && _deviceError == null) _empty('没有匹配设备'),
            if (_devices.length == 50) _hint('当前显示前 50 台，可输入完整编号继续查询。'),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _personTile(PersonOption person) {
    final selected = _selectedPeople.contains(person.id);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: selected
            ? _colors.secondaryContainer
            : _colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
          leading: Checkbox(
            value: selected,
            onChanged: (_) => unawaited(_togglePerson(person)),
          ),
          title: Text(
            person.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            person.personCode.isEmpty ? '人员编号未提供' : person.personCode,
          ),
          onTap: () => unawaited(_togglePerson(person)),
          trailing: IconButton(
            tooltip: '查看${person.name}的人员详情',
            onPressed: () =>
                context.push('/people/${Uri.encodeComponent(person.id)}'),
            icon: const Icon(Icons.chevron_right),
          ),
        ),
      ),
    );
  }

  Widget _deviceTile(CommunicationDevice device) {
    final selected = _targets.any((d) => d.id == device.id);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: selected
            ? _colors.secondaryContainer
            : _colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
          leading: Icon(_deviceIcon(device), color: _colors.primary),
          title: Text(device.sn.isEmpty ? device.id : device.sn),
          subtitle: Text(
            '${device.personName ?? '持有人未确认'} · ${_capabilityText(device)}',
          ),
          onTap: () async {
            if (selected) {
              setState(() {
                _standaloneDevices.remove(device.id);
                for (final entry in _chosenDevices.entries.toList()) {
                  if (entry.value.id == device.id) {
                    _selectedPeople.remove(entry.key);
                  }
                }
              });
            } else {
              await _selectSearchedDevice(device);
            }
          },
          trailing: IconButton(
            tooltip: '查看装备详情',
            onPressed: () =>
                context.push('/devices/${Uri.encodeComponent(device.id)}'),
            icon: Icon(selected ? Icons.check_circle : Icons.chevron_right),
          ),
        ),
      ),
    );
  }

  Widget _taskView() => ListView(
    key: ValueKey(_view),
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    children: switch (_view) {
      _View.prepare => _prepareContents(),
      _View.broadcast => _broadcastContents(),
      _View.history => _historyContents(),
      _View.call => _callContents(),
      _ => [],
    },
  );
  List<Widget> _targetContents() => [
    Text('联系对象', style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: 6),
    _hint(_selectionLabel),
    if (_selectionCount == 0) ...[
      _empty('尚未选择联系对象'),
      OutlinedButton.icon(
        onPressed: () => _open(_View.contacts),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('选择人员或设备'),
      ),
    ],
    if (_error != null) _notice(_error!, retry: _load),
    for (final personId in _selectedPeople) _personTerminals(personId),
    for (final device in _standaloneDevices.values)
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: WearCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                device.sn.isEmpty ? device.id : device.sn,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              _hint('持有人未确认 · ${_capabilityText(device)}'),
              _hint('仅联系此明确选择的设备，不计入人员数。'),
            ],
          ),
        ),
      ),
    const SizedBox(height: 16),
  ];
  Widget _personTerminals(String personId) {
    final person = _people.where((p) => p.id == personId).firstOrNull;
    final items = _equipment[personId] ?? <CommunicationDevice>[];
    final loading = _equipmentLoading.contains(personId);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: WearCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    person?.name ?? '人员 $personId',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      context.push('/people/${Uri.encodeComponent(personId)}'),
                  child: const Text('人员详情'),
                ),
              ],
            ),
            if (loading) const LinearProgressIndicator(),
            if (_equipmentErrors[personId] != null)
              _notice(
                _equipmentErrors[personId]!,
                retry: () => _loadEquipment(personId),
              ),
            if (!loading &&
                items.isEmpty &&
                !_equipmentErrors.containsKey(personId))
              _hint('未查到当前装备，暂不可联系。'),
            if (items.length > 1) _hint('请选择本次终端；未选择时不会自动呼叫首台设备。'),
            for (final device in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _chosenDevices[personId]?.id == device.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: _chosenDevices[personId]?.id == device.id
                      ? _colors.primary
                      : _colors.onSurfaceVariant,
                ),
                title: Text(device.sn.isEmpty ? device.id : device.sn),
                subtitle: Text(_capabilityText(device)),
                onTap: _ttsBusy
                    ? null
                    : () => setState(() => _chosenDevices[personId] = device),
                trailing: IconButton(
                  tooltip: '终端详情',
                  onPressed: () => context.push(
                    '/devices/${Uri.encodeComponent(device.id)}',
                  ),
                  icon: const Icon(Icons.info_outline),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _prepareContents() {
    final reason = _callUnavailable;
    final helmet = _myEquipment
        .where((d) => d['typeCode'] == 'helmet')
        .firstOrNull;
    return [
      ..._targetContents(),
      Text('发起端', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: false,
            label: Text('本机手机'),
            icon: Icon(Icons.phone_android),
          ),
          ButtonSegment(
            value: true,
            label: Text('本人安全帽'),
            icon: Icon(Icons.engineering_outlined),
          ),
        ],
        selected: {_fromHelmet},
        onSelectionChanged: (value) =>
            setState(() => _fromHelmet = value.single),
      ),
      const SizedBox(height: 8),
      _hint(
        _fromHelmet
            ? helmet == null
                  ? '未确认本人安全帽绑定；帽端发起暂不可用。'
                  : '本人安全帽 ${textOf(helmet['sn'])}；帽端发起暂未开通。'
            : '使用本机麦克风与扬声器。确认发起后才申请媒体权限。',
      ),
      const SizedBox(height: 20),
      Text('通话方式', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: false,
            label: Text('语音'),
            icon: Icon(Icons.call_outlined),
          ),
          ButtonSegment(
            value: true,
            label: Text('视频'),
            icon: Icon(Icons.videocam_outlined),
          ),
        ],
        selected: {_video},
        onSelectionChanged: (value) => setState(() => _video = value.single),
      ),
      const SizedBox(height: 12),
      _hint(_selectionCount > 1 ? '多人组呼 · 将保留全部已选对象' : '单人 / 单终端联系'),
      if (reason != null) _notice(reason),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: reason != null ? null : _startCall,
        icon: Icon(_video ? Icons.videocam_outlined : Icons.call_outlined),
        label: const Text('发起通话'),
      ),
      if (_controller?.statusMessage.isNotEmpty == true)
        _notice(_controller!.statusMessage),
    ];
  }

  String? get _callUnavailable {
    final controller = _controller;
    if (controller == null) return '通讯服务正在准备';
    if (_fromHelmet) return '帽端发起暂未开通，可切换为本机手机联系。';
    if (_selectionCount > 1) return '多人组呼暂未开通，已保留所选人员。';
    if (_selectionCount == 0) return '请先选择联系对象';
    if (_targets.length != 1) return '请确认该人员本次使用的通信终端';
    if (controller.busy || controller.hasActiveOwnedSession) {
      return '请先返回并结束当前通话';
    }
    if (!controller.policy.canStartCalls) return '当前账号没有发起通话权限';
    if (_targets.single.demo) return '示例设备不发送真实通话请求';
    if (!controller.policy.canStartVoice(_targets.single)) {
      return '所选终端未声明语音能力，请选择可用终端';
    }
    if (_video && !controller.policy.canStartVideo(_targets.single)) {
      return '所选终端未声明视频能力，可选择语音或更换终端';
    }
    return null;
  }

  Future<void> _startCall() async {
    if (_callUnavailable != null) return;
    final controller = _controller!;
    controller.selectDevice(_targets.single);
    final future = controller.startCall(
      video: _video,
      eventId: _clean(widget.eventId),
      kind: widget.eventId != null && _eventType == 'sos' ? 'sos' : 'single',
    );
    _open(_View.call);
    await future;
  }

  List<Widget> _broadcastContents() => [
    ..._targetContents(),
    Text('播报范围', style: Theme.of(context).textTheme.titleMedium),
    Wrap(
      spacing: 8,
      children: [
        for (final entry in const {
          'selected': '已选对象',
          'group': '按分组',
          'unit': '按机组',
        }.entries)
          ChoiceChip(
            label: Text(entry.value),
            selected: _broadcastScope == entry.key,
            onSelected: _ttsBusy
                ? null
                : (_) => setState(() => _broadcastScope = entry.key),
          ),
      ],
    ),
    if (_broadcastScope != 'selected') _notice('暂无可用的分组或机组范围，可返回已选对象进行播报。'),
    const SizedBox(height: 12),
    TextField(
      controller: _tts,
      minLines: 4,
      maxLines: 8,
      maxLength: 300,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        labelText: '播报正文',
        hintText: '输入现场需要听到的内容',
        alignLabelWithHint: true,
      ),
    ),
    const SizedBox(height: 8),
    _hint('提交仅表示指令受理，不代表现场已经听到。每台设备的结果分别展示。'),
    if (_ttsUnavailable != null) _notice(_ttsUnavailable!),
    const SizedBox(height: 16),
    FilledButton.icon(
      onPressed: _ttsUnavailable == null && !_ttsBusy ? _sendTts : null,
      icon: const Icon(Icons.campaign_outlined),
      label: Text(_ttsBusy ? '提交中…' : '确认目标并提交播报'),
    ),
    if (_ttsError != null) _notice(_ttsError!),
    if (_submittedTargets.isNotEmpty) ...[
      const SizedBox(height: 20),
      Text('上次提交的逐设备结果', style: Theme.of(context).textTheme.titleMedium),
      _hint('提交内容：$_submittedText'),
      for (final device in _submittedTargets) _ttsResultTile(device),
    ],
  ];
  String? get _ttsUnavailable {
    if (_broadcastScope != 'selected') return '该范围暂不可提交';
    if (_selectionCount == 0) return '请先选择播报对象';
    if (_selectedPeople.any((id) => _chosenDevices[id] == null)) {
      return '请为每位人员确认一个播报终端';
    }
    if (_targets.any((d) => d.demo)) return '示例设备不发送真实播报指令';
    if (_controller?.policy.canSubmitTts != true) return '当前账号没有文字播报权限';
    if (_targets.any((d) => !d.supports('tts'))) return '部分所选终端未声明播报能力，请更换终端';
    if (_tts.text.trim().isEmpty) return '请输入播报内容';
    return null;
  }

  Future<void> _sendTts() async {
    if (_ttsBusy || _ttsUnavailable != null) return;
    final scope = _session!.scopeKey;
    final targets = List<CommunicationDevice>.of(_targets);
    final text = _tts.text.trim();
    setState(() {
      _ttsBusy = true;
      _ttsError = null;
      _ttsResults = [];
      _submittedTargets = targets;
      _submittedText = text;
    });
    try {
      final results = await _gateway!.sendTts(
        deviceIds: targets.map((d) => d.id).toSet().toList(),
        text: text,
        eventId: _clean(widget.eventId),
        idempotencyKey:
            'tts-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
      );
      if (!mounted || scope != _session?.scopeKey) return;
      setState(() => _ttsResults = results);
    } catch (error) {
      if (error is StaleSessionException ||
          !mounted ||
          scope != _session?.scopeKey) {
        return;
      }
      setState(() => _ttsError = _errorText(error));
    } finally {
      if (mounted && scope == _session?.scopeKey) {
        setState(() => _ttsBusy = false);
      }
    }
  }

  Widget _ttsResultTile(CommunicationDevice device) {
    final result = _ttsResults
        .where((r) => r.deviceId == device.id)
        .firstOrNull;
    final label = _ttsBusy
        ? '正在提交'
        : switch (result?.status) {
            TtsCommandStatus.accepted => '服务端已受理（未确认现场播放）',
            TtsCommandStatus.sent => '已下发（未确认现场播放）',
            TtsCommandStatus.failed => '下发失败',
            _ => '结果未确认，请查询后再决定是否重试',
          };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        result?.status == TtsCommandStatus.failed
            ? Icons.error_outline
            : Icons.info_outline,
        color: _colors.onSurfaceVariant,
      ),
      title: Text(device.sn.isEmpty ? device.id : device.sn),
      subtitle: Text(label),
    );
  }

  List<Widget> _historyContents() {
    final calls = _callHistory.values.toList()
      ..sort(
        (a, b) => (b.startedAt ?? DateTime(1970)).compareTo(
          a.startedAt ?? DateTime(1970),
        ),
      );
    return [
      _hint(
        widget.eventId != null
            ? '显示关联告警的通话及本次会话。'
            : '显示已查询终端的通话记录，以及本次登录期间的通话。',
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _historyBusy ? null : _loadHistory,
        icon: const Icon(Icons.refresh),
        label: const Text('刷新记录'),
      ),
      if (_historyBusy) const LinearProgressIndicator(),
      if (_historyError != null) _notice(_historyError!, retry: _loadHistory),
      if (calls.isEmpty && !_historyBusy) _empty('暂无相关通话记录'),
      for (final call in calls)
        WearCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              call.video ? Icons.videocam_outlined : Icons.call_outlined,
              color: _colors.primary,
            ),
            title: Text(
              '${switch (call.kind) {
                'sos' => 'SOS',
                'group' => '组呼',
                'single' => '单呼',
                _ => '通话',
              }} · ${call.sn.isEmpty ? call.deviceId : call.sn}',
            ),
            subtitle: Text(
              '${call.statusLabel}\n${formatTime(call.startedAt)}\n发起账号 ${call.requesterUserId.isEmpty ? '未提供' : call.requesterUserId} · 发起端未提供${call.eventId == null ? '' : '\n关联告警 ${call.eventId}'}',
            ),
            trailing:
                _controller!.policy.canJoin(call) &&
                    !_controller!.hasActiveOwnedSession
                ? IconButton(
                    tooltip: '加入此会话',
                    icon: const Icon(Icons.login),
                    onPressed: () {
                      _open(_View.call);
                      unawaited(_controller!.resumeCall(call));
                    },
                  )
                : null,
          ),
        ),
    ];
  }

  String _callLabel(CommunicationsController controller) {
    final call = controller.activeCall;
    if (call == null) return controller.busy ? '正在创建会话' : '尚未建立会话';
    if (call.demo) return '演示状态（未连接真实设备）';
    if (call.status == WearCallStatus.connected && !controller.isConnected) {
      return '正在确认媒体连接';
    }
    return call.statusLabel;
  }

  List<Widget> _callContents() {
    final controller = _controller!;
    final call = controller.activeCall;
    return [
      WearCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              call == null
                  ? '准备连接'
                  : '终端 ${call.sn.isEmpty ? call.deviceId : call.sn}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _hint('发起端：本机手机'),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                _callLabel(controller),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (controller.statusMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(controller.statusMessage),
              ),
            const SizedBox(height: 20),
            if (call?.video == true)
              _videoPanel(controller)
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(36),
                  child: Icon(
                    Icons.call_outlined,
                    size: 56,
                    color: _colors.onSurfaceVariant,
                  ),
                ),
              ),
            if (call != null) _hint('会话 ${call.id}'),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: controller.isConnected
                ? controller.toggleMicrophone
                : null,
            icon: Icon(
              controller.microphoneMuted
                  ? Icons.mic_off_outlined
                  : Icons.mic_outlined,
            ),
            label: Text(controller.microphoneMuted ? '取消静音' : '静音'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _colors.error,
              foregroundColor: _colors.onError,
            ),
            onPressed: call != null && controller.policy.canEnd(call)
                ? controller.hangUp
                : null,
            icon: const Icon(Icons.call_end),
            label: const Text('结束通话'),
          ),
        ],
      ),
      if (call == null || call.isTerminal)
        TextButton(
          onPressed: () => _open(_View.prepare),
          child: const Text('返回呼叫准备'),
        ),
      if (call != null && !controller.policy.owns(call))
        _notice('仅会话发起人可加入、读取凭证或结束通话。'),
    ];
  }

  Widget _videoPanel(CommunicationsController controller) {
    final call = controller.activeCall;
    final rtc = controller.rtc;
    final engine = rtc is AgoraWearRtcEngine ? rtc.nativeEngine : null;
    if (call == null ||
        engine == null ||
        call.demo ||
        !controller.isConnected ||
        controller.remoteUid == null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: _colors.surfaceContainerHighest,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.videocam_off_outlined,
                  color: _colors.onSurfaceVariant,
                  size: 36,
                ),
                const SizedBox(height: 8),
                Text(call?.demo == true ? '演示会话 · 无真实视频' : '等待真实远端视频'),
              ],
            ),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: AgoraVideoView(
          controller: VideoViewController.remote(
            rtcEngine: engine,
            canvas: VideoCanvas(uid: controller.remoteUid),
            connection: RtcConnection(channelId: call.channelName),
          ),
        ),
      ),
    );
  }

  Widget _hint(String text) => Text(
    text,
    style: TextStyle(color: _colors.onSurfaceVariant, fontSize: 14),
  );
  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(child: _hint(text)),
  );
  Widget _notice(String text, {Future<void> Function()? retry}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: _colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: _colors.onSurface)),
          ),
          if (retry != null)
            TextButton(onPressed: retry, child: const Text('重试')),
        ],
      ),
    ),
  );
  IconData _deviceIcon(CommunicationDevice device) =>
      device.typeCode == 'helmet'
      ? Icons.engineering_outlined
      : Icons.devices_other_outlined;
  String _capabilityText(CommunicationDevice device) => device.demo
      ? '示例设备 · 非真实终端'
      : [
          if (device.supports('intercom')) '语音',
          if (device.supports('video')) '视频',
          if (device.supports('tts')) '播报',
          '在线状态未确认',
          if (!device.supports('intercom') &&
              !device.supports('tts') &&
              !device.supports('video'))
            '未声明通信能力',
        ].join(' / ');
  String _errorText(Object error) =>
      error is WearApiException ? error.message : '操作未完成，请稍后重试';
  String? _clean(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
