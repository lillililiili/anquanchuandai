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
  List<PersonOption> _people = const [];
  List<CommunicationDevice> _equipment = const [];
  List<CallSession> _history = const [];
  PersonOption? _person;
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
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final people = await gateway.peopleOptions();
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
        _person = person;
        _equipment = equipment;
        _history = history;
        _eventType = eventType;
        _loading = false;
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
      _person = person;
      _equipment = const [];
      _history = const [];
      _loading = true;
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
        _history = history;
        _loading = false;
      });
      _controller?.selectDevice(selected);
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
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: WearPageHeader(
                title: '通讯',
                subtitle: '按人员当前装备发起通话或播报；接通状态以服务器为准。',
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                  ? WearEmpty(
                      title: '通讯数据加载失败',
                      detail: _errorText(_loadError!),
                      onRetry: _load,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                        children: [
                          _targetCard(controller),
                          const SizedBox(height: 14),
                          if (controller != null &&
                              controller.selectedDevice != null)
                            _actionCard(controller),
                          if (controller != null &&
                              controller.selectedDevice != null)
                            const SizedBox(height: 14),
                          if (controller?.activeCall != null)
                            _activeCallCard(controller!),
                          if (controller?.activeCall != null)
                            const SizedBox(height: 14),
                          if (controller != null &&
                              controller.selectedDevice != null)
                            _ttsCard(controller),
                          const SizedBox(height: 14),
                          _historyCard(controller),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _targetCard(CommunicationsController? controller) {
    return WearCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '联系对象',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: WearColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<PersonOption>(
            initialValue: _people
                .where((item) => item.id == _person?.id)
                .firstOrNull,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '人员（非登录账号）',
              border: OutlineInputBorder(),
            ),
            items: _people
                .map(
                  (person) => DropdownMenuItem(
                    value: person,
                    child: Text('${person.name} · ${person.personCode}'),
                  ),
                )
                .toList(),
            onChanged: _selectPerson,
          ),
          const SizedBox(height: 14),
          if (_equipment.isEmpty)
            const Text('该人员暂无当前装备', style: TextStyle(color: WearColors.muted))
          else
            ..._equipment.map((device) {
              final selected = controller?.selectedDevice?.id == device.id;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => _selectDevice(device),
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? WearColors.primary : WearColors.muted,
                ),
                title: Text(device.sn.isEmpty ? '设备 ${device.id}' : device.sn),
                subtitle: Text(_capabilityText(device)),
                trailing: device.demo ? const WearBadge(text: '演示') : null,
              );
            }),
        ],
      ),
    );
  }

  Widget _actionCard(CommunicationsController controller) {
    final device = controller.selectedDevice!;
    final canVoice = controller.policy.canStartVoice(device);
    final canVideo = controller.policy.canStartVideo(device);
    final eventId = _clean(widget.eventId);
    final kind = eventId != null && _eventType == 'sos' ? 'sos' : 'single';
    return WearCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '发起通话',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: WearColors.ink,
                  ),
                ),
              ),
              WearBadge(text: kind == 'sos' ? 'SOS 会话' : '单呼'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: canVoice && !controller.busy
                      ? () => controller.startCall(eventId: eventId, kind: kind)
                      : null,
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('语音呼叫'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canVideo && !controller.busy
                      ? () => controller.startCall(
                          video: true,
                          eventId: eventId,
                          kind: kind,
                        )
                      : null,
                  icon: const Icon(Icons.videocam_outlined),
                  label: const Text('视频呼叫'),
                ),
              ),
            ],
          ),
          if (!device.supports('intercom'))
            const Padding(
              padding: EdgeInsets.only(top: 9),
              child: Text(
                '型号能力未包含 intercom，不能呼叫。',
                style: TextStyle(color: WearColors.muted),
              ),
            ),
          if (widget.video && !device.supports('video'))
            const Padding(
              padding: EdgeInsets.only(top: 9),
              child: Text(
                '该设备不支持视频，已保留语音入口。',
                style: TextStyle(color: WearColors.warning),
              ),
            ),
        ],
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
          if (call.video && !call.demo) ...[
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
    final rtc = controller.rtc;
    final engine = rtc is AgoraWearRtcEngine ? rtc.nativeEngine : null;
    if (engine == null) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Color(0xFFE7EEF0),
          child: Center(
            child: Text('等待视频初始化', style: TextStyle(color: WearColors.muted)),
          ),
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

  String _capabilityText(CommunicationDevice device) {
    final labels = <String>[
      if (device.supports('intercom')) '语音',
      if (device.supports('video')) '视频',
      if (device.supports('tts')) '播报',
    ];
    return labels.isEmpty ? '无通讯能力' : labels.join(' · ');
  }

  String _errorText(Object error) =>
      error is WearApiException ? error.message : '操作未完成，请稍后重试';

  String? _clean(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
