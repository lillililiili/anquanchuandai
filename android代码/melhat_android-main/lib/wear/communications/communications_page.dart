import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';

import '../core.dart';
import 'api_gateway.dart';
import 'controller.dart';
import 'models.dart' hide JsonMap;
import 'rtc_engine.dart';

class CommunicationsPage extends StatefulWidget {
  const CommunicationsPage({
    super.key,
    this.deviceId,
    this.personId,
    this.eventId,
    this.video = false,
  });

  final String? deviceId;
  final String? personId;
  final String? eventId;
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
  List<PersonOption> _people = const [];
  List<CommunicationDevice> _devices = const [];
  List<CommunicationDevice> _equipment = const [];
  List<CallSession> _history = const [];
  List<JsonMap> _myEquipment = const [];
  final Map<String, List<CommunicationDevice>> _equipmentByPerson = {};
  final Set<String> _selectedKeys = {};
  bool _multiSelect = false;
  bool _loading = true;
  Object? _loadError;
  String _eventType = '';
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (!identical(session, _session)) {
      _controller?.removeListener(_onControllerChanged);
      _controller?.dispose();
      _session = session;
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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller?.setForeground(state == AppLifecycleState.resumed);
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller != null) {
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
      final people = await gateway.peopleOptions(
        name: _search.text.trim().isEmpty ? null : _search.text.trim(),
      );
      final devices = await gateway.listDevices(
        sn: _search.text.trim().isEmpty ? null : _search.text.trim(),
      );
      final myEquipment = await gateway.meEquipment();
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
        equipment = await gateway.equipmentForPerson(personId);
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
        _people = people;
        _devices = devices;
        _myEquipment = myEquipment;
        _equipment = equipment;
        _history = history;
        _eventType = eventType;
        _loading = false;
        if (person != null) {
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
      final equipment = await gateway.equipmentForPerson(person.id);
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
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerChanged);
    // Do not clear callActive during synchronous teardown. The session owns
    // forced expiry and the controller invalidates late RTC continuations.
    _controller?.dispose();
    _tts.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ColoredBox(
      color: WearColors.background,
      child: SafeArea(
        child: _loading
            ? const Column(
                children: [
                  _CommsHero(),
                  Expanded(child: Center(child: CircularProgressIndicator())),
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
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [
                    _headerWithSearch(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _selectionBar(),
                          const SizedBox(height: 10),
                          ..._visibleContacts.map(_contactTile),
                          if (_visibleContacts.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 18),
                              child: Text(
                                '没有匹配的人员或设备',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: WearColors.muted),
                              ),
                            ),
                          const SizedBox(height: 14),
                          _originateCard(controller),
                          if (controller?.activeCall != null) ...[
                            const SizedBox(height: 14),
                            _activeCallCard(controller!),
                          ],
                          if (controller != null &&
                              controller.selectedDevice != null) ...[
                            const SizedBox(height: 14),
                            _ttsCard(controller),
                          ],
                          const SizedBox(height: 14),
                          _historyCard(controller),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _headerWithSearch() {
    return SizedBox(
      height: 210,
      width: double.infinity,
      child: Stack(
        children: [
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 188,
            child: _CommsHero(),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 166,
            child: Material(
              color: Colors.white,
              elevation: 0,
              borderRadius: BorderRadius.circular(16),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => unawaited(_load()),
                decoration: InputDecoration(
                  hintText: '搜索人员或设备',
                  hintStyle: const TextStyle(color: WearColors.muted),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: WearColors.muted,
                  ),
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
      ),
    );
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
          '${_selectedKeys.length} 人',
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
            backgroundColor: _multiSelect
                ? WearColors.brand
                : Colors.white,
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
    final helmet = _boundHelmet;
    final helmetSn = textOf(helmet?['sn'], '');
    final canVideo = controller?.selectedDevice != null &&
        controller!.policy.canStartVideo(controller.selectedDevice!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '选择发起设备',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: WearColors.ink,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _snack('组呼与安全帽侧发起正在对接。当前可由本机向所选装备发起单呼。'),
              child: const Row(
                children: [
                  Text(
                    '通讯服务待联调',
                    style: TextStyle(fontSize: 12, color: WearColors.muted),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.info_outline, size: 16, color: WearColors.muted),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.engineering_outlined, size: 16, color: WearColors.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                helmet == null
                    ? '未绑定安全帽'
                    : '本人已绑定安全帽 ${helmetSn.isEmpty ? textOf(helmet['deviceId']) : helmetSn}',
                style: const TextStyle(fontSize: 13, color: WearColors.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _originateButton(
          filled: true,
          icon: Icons.call_outlined,
          title: '手机呼叫',
          subtitle: '使用本机麦克风与扬声器',
          enabled: controller != null && !controller.busy,
          onTap: () => unawaited(
            _startCallForSelection(video: false, fromHelmet: false),
          ),
        ),
        const SizedBox(height: 10),
        _originateButton(
          filled: false,
          icon: Icons.engineering_outlined,
          title: '安全帽呼叫',
          subtitle: '使用本人绑定安全帽发起',
          enabled: controller != null && !controller.busy && helmet != null,
          onTap: () => unawaited(
            _startCallForSelection(video: false, fromHelmet: true),
          ),
        ),
        if (canVideo) ...[
          const SizedBox(height: 10),
          _originateButton(
            filled: false,
            icon: Icons.videocam_outlined,
            title: '视频呼叫',
            subtitle: '向所选装备发起视频',
            enabled: !controller.busy,
            onTap: () => unawaited(
              _startCallForSelection(video: true, fromHelmet: false),
            ),
          ),
        ],
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
            '未绑定安全帽时，安全帽呼叫不可用',
            style: TextStyle(fontSize: 12, color: WearColors.muted),
          ),
        ),
        if (widget.video &&
            controller?.selectedDevice != null &&
            !controller!.selectedDevice!.supports('video'))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '该设备不支持视频，已保留语音入口。',
              style: TextStyle(color: WearColors.warning),
            ),
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
    final sub = filled ? Colors.white.withValues(alpha: 0.86) : WearColors.muted;
    return Material(
      color: enabled
          ? (filled ? WearColors.brand : Colors.white)
          : (filled ? WearColors.brand.withValues(alpha: 0.4) : const Color(0xFFF7FAFF)),
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
              Icon(
                Icons.chevron_right,
                color: enabled ? fg : WearColors.muted,
              ),
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
          if (call.video) ...[
            const SizedBox(height: 12),
            _videoPanel(controller),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: controller.isConnected
                      ? controller.toggleMicrophone
                      : null,
                  icon: Icon(
                    controller.microphoneMuted
                        ? Icons.mic_off_outlined
                        : Icons.mic_outlined,
                  ),
                  label: Text(controller.microphoneMuted ? '取消静音' : '麦克风'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: WearColors.danger,
                  ),
                  onPressed: controller.policy.canEnd(call)
                      ? controller.hangUp
                      : null,
                  icon: const Icon(Icons.call_end),
                  label: const Text('结束通话'),
                ),
              ),
            ],
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

  Widget _videoPanel(CommunicationsController controller) {
    final call = controller.activeCall;
    final rtc = controller.rtc;
    final engine = rtc is AgoraWearRtcEngine ? rtc.nativeEngine : null;
    if (call == null ||
        engine == null ||
        call.demo ||
        !controller.isConnected) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            const WearAssetImage(
              WearArt.videoPlaceholder,
              width: double.infinity,
              height: 180,
              fit: BoxFit.cover,
            ),
            Positioned(
              left: 10,
              top: 10,
              child: WearBadge(
                text: call?.demo == true ? '示例画面 · 非实时' : '等待远端视频',
                color: WearColors.warning,
              ),
            ),
          ],
        ),
      );
    }
    final remoteUid = controller.remoteUid;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: remoteUid == null
            ? Stack(
                children: [
                  AgoraVideoView(
                    controller: VideoViewController(
                      rtcEngine: engine,
                      canvas: const VideoCanvas(uid: 0),
                    ),
                  ),
                  const Positioned.fill(
                    child: Center(child: WearBadge(text: '等待远端视频')),
                  ),
                ],
              )
            : AgoraVideoView(
                controller: VideoViewController.remote(
                  rtcEngine: engine,
                  canvas: VideoCanvas(uid: remoteUid),
                  connection: RtcConnection(
                    channelId: controller.activeCall!.channelName,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _ttsCard(CommunicationsController controller) {
    final device = controller.selectedDevice!;
    final enabled = controller.policy.canSendTts(device);
    return WearCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '文字播报',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: WearColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '提交成功仅表示指令已受理，不代表现场已经听到。',
            style: TextStyle(color: WearColors.muted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tts,
            minLines: 2,
            maxLines: 4,
            maxLength: 300,
            onChanged: (value) => controller.ttsText = value,
            decoration: const InputDecoration(
              hintText: '输入要播报的内容',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: enabled && !controller.ttsBusy
                  ? () => controller.sendTts(eventId: _clean(widget.eventId))
                  : null,
              icon: const Icon(Icons.campaign_outlined),
              label: Text(controller.ttsBusy ? '提交中…' : '提交播报指令'),
            ),
          ),
          if (controller.ttsMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                controller.ttsMessage,
                style: TextStyle(
                  color: controller.ttsMessage.contains('失败')
                      ? WearColors.danger
                      : WearColors.ink,
                ),
              ),
            ),
        ],
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
      items.add(_CommsContact.device(device));
    }
    for (final device in _equipment) {
      if (seenDevices.add(device.id)) {
        items.add(_CommsContact.device(device));
      }
    }
    return items;
  }

  List<_CommsContact> get _visibleContacts {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _allContacts;
    return _allContacts.where((item) => item.matches(query)).toList();
  }

  JsonMap? get _boundHelmet {
    for (final item in _myEquipment) {
      if (item['typeCode']?.toString() == 'helmet') return item;
    }
    return null;
  }

  Future<void> _toggleContact(_CommsContact contact) async {
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
    if (selecting) await _activateContact(contact);
  }

  Future<void> _callContact(_CommsContact contact) async {
    setState(() {
      _selectedKeys
        ..clear()
        ..add(contact.key);
    });
    await _activateContact(contact);
    await _startCallForSelection(video: false, fromHelmet: false);
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
      return cached.where((item) => item.supports('intercom')).firstOrNull ??
          cached.firstOrNull;
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

  Future<void> _startCallForSelection({
    required bool video,
    required bool fromHelmet,
  }) async {
    final controller = _controller;
    if (controller == null) return;
    if (fromHelmet && _boundHelmet == null) {
      _snack('未绑定安全帽时，安全帽呼叫不可用');
      return;
    }
    if (_selectedKeys.isEmpty) {
      _snack('请先选择联系人');
      return;
    }
    final resolved = <CommunicationDevice>[];
    final labels = <String>[];
    for (final contact in _allContacts) {
      if (!_selectedKeys.contains(contact.key)) continue;
      final device = await _deviceOf(contact);
      if (device == null) continue;
      final allowed = video
          ? controller.policy.canStartVideo(device)
          : controller.policy.canStartVoice(device);
      if (!allowed) continue;
      resolved.add(device);
      labels.add(contact.title);
    }
    if (resolved.isEmpty) {
      _snack(video ? '所选对象不支持视频通话' : '所选对象暂无可用通话装备');
      return;
    }
    controller.selectDevice(resolved.first);
    if (resolved.length > 1) {
      _snack('群体通话待服务端开通，已向「${labels.first}」发起单呼');
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
      title: '通讯',
      subtitle: '高效协同，守护安全',
      background: WearArt.commsHero,
    );
  }
}

class _CommsContact {
  const _CommsContact._({required this.key, this.person, this.device});

  factory _CommsContact.person(PersonOption person) =>
      _CommsContact._(key: 'p:${person.id}', person: person);

  factory _CommsContact.device(CommunicationDevice device) =>
      _CommsContact._(key: 'd:${device.id}', device: device);

  final String key;
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
    final owner = item.personName?.trim() ?? '';
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
