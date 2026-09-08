import '../../components/tech_surface.dart';
import '../../components/field_motion.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:rolling_intelligence_headband/hooks/use_agent_page.dart';
import 'package:rolling_intelligence_headband/hooks/use_page_agent.dart';
import 'package:rolling_intelligence_headband/hooks/use_page_agent_get_data.dart';
import 'package:rolling_intelligence_headband/router/route_tree.dart';
import 'package:rolling_intelligence_headband/utils/app_logger.dart';
import '../../api/hat.dart';
import '../../api/intercom.dart';
import '../../components/field_brand.dart';
import '../../components/field_assistant_action.dart';
import '../../components/skeleton_view.dart';
import '../../hooks/use_skeleton.dart';
import '../../hooks/use_theme.dart';
import '../../hooks/useAgoraRtcEngine.dart';
import '../../models/hat.dart';
import '../../models/agora_credentials.dart';
import '../../http/response/page.dart';
import '../../theme/theme.dart';

class MonitorTab extends HookWidget {
  const MonitorTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();
    final selectedHat = useState<Hat?>(null);
    final rtcState = useAgoraRtcEngine();
    final credentials = useState<AgoraCredentials?>(null);
    final isConnecting = useState(false);
    final connectionError = useState<String?>(null);
    final retryVersion = useState(0);
    final deviceSearch = useState('');
    final skeleton = useSkeleton<DataPage<Hat>>(
      request: () => HatApi.getHatPage(current: 1, size: 20),
      isEmpty: (data) => data.isEmpty,
      onComplete: (data, {required isInitialLoad}) {
        final list = data.records ?? [];
        if (list.isEmpty) {
          selectedHat.value = null;
          credentials.value = null;
          return;
        }
        if (!isInitialLoad) return;
        selectedHat.value = list.firstWhere(
          (hat) => hat.status == '1' || hat.status == 'online',
          orElse: () => list.first,
        );
      },
    );

    useEffect(() {
      final hat = selectedHat.value;
      if (hat?.hatNumber == null) return null;
      var cancelled = false;
      Future<void> connectToDevice() async {
        isConnecting.value = true;
        connectionError.value = null;
        credentials.value = null;
        try {
          final creds = await IntercomApi.singleCall(
            hatNumber: hat!.hatNumber,
            clientId: 'app_123',
            participant: hat.bindUserName,
          );
          if (!context.mounted || cancelled) return;
          credentials.value = creds;
          await rtcState.joinChannel(creds);
        } catch (error) {
          AppLogger.e('monitor_tab connectToDevice error', error);
          if (context.mounted && !cancelled) {
            connectionError.value = '设备连接失败，请检查网络后重试';
          }
        } finally {
          if (context.mounted && !cancelled) isConnecting.value = false;
        }
      }

      connectToDevice();
      return () {
        cancelled = true;
        unawaited(rtcState.leaveChannel());
      };
    }, [selectedHat.value, retryVersion.value]);

    final scrollController = useScrollController();
    Future<void> handleSwitchDevice(Hat hat) async {
      if (isConnecting.value) {
        throw StateError('设备正在连接，请稍后切换');
      }
      if (hat.hatNumber == selectedHat.value?.hatNumber) return;
      selectedHat.value = hat;
      if (scrollController.hasClients) {
        await scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    }

    Future<void> handleEnterDetail() async {
      final hat = selectedHat.value;
      if (hat == null || isConnecting.value) return;
      final savedCreds = credentials.value;
      await rtcState.leaveChannel();
      if (!context.mounted) return;
      await context.goto(
        RouteNode.monitorDetail,
        params: {
          'deviceId': hat.id ?? '',
          'hatNumber': hat.hatNumber ?? '',
          if (savedCreds != null)
            'credentialsJson': jsonEncode(savedCreds.toJson()),
        },
      );
      if (context.mounted && savedCreds != null) {
        isConnecting.value = true;
        try {
          await rtcState.joinChannel(savedCreds);
        } finally {
          if (context.mounted) isConnecting.value = false;
        }
      }
    }

    final hasVideo = rtcState.remoteUsers.values.any((user) => user.hasVideo);
    final sdkFailed =
        rtcState.status.contains('失败') || rtcState.status.contains('错误');
    final error = connectionError.value ?? (sdkFailed ? '连接中断，请重试' : null);
    final status = selectedHat.value == null
        ? '尚未选择设备'
        : isConnecting.value
        ? '正在连接'
        : error != null
        ? '连接失败'
        : hasVideo
        ? '画面已连接'
        : rtcState.joined
        ? '等待设备推流'
        : '等待设备接入';

    return _AgentScope(
      selectedHat: selectedHat,
      isConnecting: isConnecting,
      skeleton: skeleton,
      handleSwitchDevice: handleSwitchDevice,
      handleEnterDetail: handleEnterDetail,
      child: MotionActivity(
        child: Scaffold(
          backgroundColor: theme.background,
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: () async {
                await skeleton.execute();
              },
              child: SingleChildScrollView(
                controller: scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const FieldBrandMark(size: 30),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '现场监控',
                            style: TextStyle(
                              color: theme.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const FieldAssistantAction(),
                        IconButton(
                          tooltip: '刷新设备',
                          onPressed:
                              skeleton.status.value == SkeletonStatus.loading
                              ? null
                              : () {
                                  skeleton.execute();
                                },
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedHat.value?.bindUserName ?? '选择监控设备',
                                style: TextStyle(
                                  color: theme.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                selectedHat.value?.hatNumber ??
                                    '从下方列表选择，查看现场画面',
                                style: TextStyle(
                                  color: theme.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        MotionSwap(
                          value: status,
                          child: _ConnectionLabel(
                            text: status,
                            isLive: hasVideo,
                            hasError: error != null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _VideoPlayerSection(
                      rtcState: rtcState,
                      credentials: credentials.value,
                      isConnecting: isConnecting.value,
                      error: error,
                      hasDevice: selectedHat.value != null,
                      onRetry: () => retryVersion.value++,
                    ),
                    const SizedBox(height: 16),
                    MotionEntrance(
                      index: 1,
                      child: _DeviceInfoCard(
                        theme: theme,
                        hat: selectedHat.value,
                        onDetail:
                            selectedHat.value == null || isConnecting.value
                            ? null
                            : handleEnterDetail,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '监控设备',
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (value) => deviceSearch.value = value.trim(),
                      decoration: const InputDecoration(
                        hintText: '在已加载设备中搜索姓名或帽号',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SkeletonView.fromHook(
                      skeleton,
                      (data) => _DeviceList(
                        theme: theme,
                        hats: (data.records ?? [])
                            .where(
                              (hat) =>
                                  deviceSearch.value.isEmpty ||
                                  (hat.bindUserName ?? '').contains(
                                    deviceSearch.value,
                                  ) ||
                                  (hat.hatNumber ?? '').contains(
                                    deviceSearch.value,
                                  ),
                            )
                            .toList(),
                        selectedHat: selectedHat.value,
                        busy: isConnecting.value,
                        onSelect: handleSwitchDevice,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Agent 适配层
class _AgentScope extends HookWidget {
  final Widget child;
  final ValueNotifier<Hat?> selectedHat;
  final ValueNotifier<bool> isConnecting;
  final SkeletonBind<DataPage<Hat>> skeleton;
  final Future<void> Function(Hat) handleSwitchDevice;
  final Future<void> Function() handleEnterDetail;

  const _AgentScope({
    required this.child,
    required this.selectedHat,
    required this.isConnecting,
    required this.skeleton,
    required this.handleSwitchDevice,
    required this.handleEnterDetail,
  });

  @override
  Widget build(BuildContext context) {
    final pageController = useAgentPage(meta: RouteNode.homeTab3);

    // 工具1：查询监控设备列表
    usePageAgent(
      controller: pageController,
      toolName: 'queryMonitorDevices',
      executeFn: (params) async {
        final records = skeleton.data.value?.records ?? [];
        return {
          'devices': records
              .map(
                (h) => {
                  'hatNumber': h.hatNumber,
                  'bindUserName': h.bindUserName,
                  'bindGroup': h.bindGroup,
                  'status': h.status,
                },
              )
              .toList(),
          'total': records.length,
          'selectedHatNumber': selectedHat.value?.hatNumber,
        };
      },
    );

    // 工具2：切换到指定监控设备
    usePageAgent(
      controller: pageController,
      toolName: 'selectMonitorDevice',
      executeFn: (params) async {
        final hatNumber = params?['hatNumber'] as String?;
        final bindUserName = params?['bindUserName'] as String?;
        if (hatNumber == null && bindUserName == null) {
          return {'success': false, 'message': '请提供设备编号或绑定人员姓名'};
        }
        final records = skeleton.data.value?.records ?? [];
        final target = records.firstWhere(
          (h) =>
              (hatNumber != null && h.hatNumber == hatNumber) ||
              (bindUserName != null && h.bindUserName == bindUserName),
          orElse: () => Hat(),
        );
        if (target.hatNumber == null) {
          return {'success': false, 'message': '未找到匹配的设备'};
        }
        await handleSwitchDevice(target);
        return {
          'success': true,
          'message':
              '已切换到设备：${target.hatNumber}（${target.bindUserName ?? '未绑定'}）',
        };
      },
    );

    // 工具3：进入当前设备的监控详情
    usePageAgent(
      controller: pageController,
      toolName: 'enterMonitorDetail',
      executeFn: (params) async {
        if (selectedHat.value == null) {
          return {'success': false, 'message': '当前没有选中设备'};
        }
        await handleEnterDetail();
        return {
          'success': true,
          'message': '已进入设备 ${selectedHat.value!.hatNumber} 的监控详情',
        };
      },
    );

    // 暴露页面状态给 AI
    usePageAgentGetData(pageController, 'monitorState', () {
      final hat = selectedHat.value;
      final records = skeleton.data.value?.records ?? [];
      return {
        'selectedHat': hat != null
            ? {
                'hatNumber': hat.hatNumber,
                'bindUserName': hat.bindUserName,
                'status': hat.status,
                'electricityUsage': hat.electricityUsage,
              }
            : null,
        'deviceCount': records.length,
        'isConnecting': isConnecting.value,
        'onlineCount': records.where((h) => h.status == '1').length,
      };
    });

    // 通知 AI 页面就绪
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          pageController.completeEmptyInit();
        }
      });
      return null;
    }, []);

    return child;
  }
}

class _ConnectionLabel extends StatelessWidget {
  final String text;
  final bool isLive;
  final bool hasError;
  const _ConnectionLabel({
    required this.text,
    this.isLive = false,
    this.hasError = false,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = hasError ? const Color(0xFF991B1B) : colors.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: hasError
            ? const Color(0xFFFEE2E2)
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLive
                ? Icons.videocam_outlined
                : hasError
                ? Icons.error_outline
                : Icons.circle_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoPlayerSection extends StatelessWidget {
  final AgoraRtcState rtcState;
  final AgoraCredentials? credentials;
  final bool isConnecting;
  final bool hasDevice;
  final String? error;
  final VoidCallback onRetry;
  const _VideoPlayerSection({
    required this.rtcState,
    required this.credentials,
    required this.isConnecting,
    required this.hasDevice,
    required this.onRetry,
    this.error,
  });
  @override
  Widget build(BuildContext context) {
    final remoteUser = rtcState.remoteUsers.values
        .where((user) => user.hasVideo)
        .firstOrNull;
    final canRender =
        !isConnecting &&
        error == null &&
        remoteUser != null &&
        rtcState.engine != null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 210),
        child: ColoredBox(
          color: const Color(0xFF202B46),
          child: canRender
              ? AspectRatio(
                  aspectRatio: 4 / 3,
                  child: AgoraVideoView(
                    controller: VideoViewController.remote(
                      rtcEngine: rtcState.engine!,
                      canvas: VideoCanvas(uid: remoteUser.uid),
                      connection: RtcConnection(
                        channelId: credentials?.channelName ?? '',
                      ),
                    ),
                  ),
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: MotionSwap(
                      value: '$isConnecting:$error:$hasDevice',
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isConnecting)
                            const SizedBox(
                              width: 64,
                              height: 64,
                              child: TechAura(orb: true),
                            )
                          else
                            Icon(
                              error != null
                                  ? Icons.wifi_off
                                  : Icons.videocam_outlined,
                              color: Colors.white70,
                              size: 40,
                            ),
                          const SizedBox(height: 12),
                          Text(
                            isConnecting
                                ? '正在连接设备…'
                                : error ?? (hasDevice ? '等待设备接入' : '尚未选择设备'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            hasDevice ? '请确认设备在线并已开启推流' : '选择下方设备后显示现场画面',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                          if (hasDevice && !isConnecting) ...[
                            const SizedBox(height: 14),
                            MotionPress(
                              child: FilledButton.icon(
                                onPressed: onRetry,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('重新连接'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _DeviceInfoCard extends StatelessWidget {
  final ThemeColors theme;
  final Hat? hat;
  final VoidCallback? onDetail;
  const _DeviceInfoCard({required this.theme, this.hat, this.onDetail});
  @override
  Widget build(BuildContext context) {
    return MotionReveal(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: FieldArtworkSurface(
          scene: 'device-card',
          opacity: 0.45,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.construction_outlined,
                    color: theme.textPrimary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '设备摘要',
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  MotionSwap(
                    value: '${hat?.hatNumber}:${onDetail != null}',
                    child: MotionPress(
                      enabled: onDetail != null,
                      child: TextButton(
                        onPressed: onDetail,
                        child: const Text('进入详情'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _InfoItem(label: '所属分组', value: hat?.bindGroup ?? '未分组'),
                  _InfoItem(
                    label: '剩余电量',
                    value: hat?.electricityUsage == null
                        ? '—'
                        : '${hat!.electricityUsage!.toInt()}%',
                  ),
                  _InfoItem(
                    label: '设备状态',
                    value: hat == null
                        ? '未选择'
                        : (hat!.status == '1' || hat!.status == 'online')
                        ? '在线'
                        : '离线',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  const _InfoItem({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DeviceList extends StatelessWidget {
  final ThemeColors theme;
  final List<Hat> hats;
  final Hat? selectedHat;
  final bool busy;
  final Function(Hat) onSelect;
  const _DeviceList({
    required this.theme,
    required this.hats,
    required this.selectedHat,
    required this.busy,
    required this.onSelect,
  });
  @override
  Widget build(BuildContext context) {
    if (hats.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('没有匹配的设备', style: TextStyle(color: theme.textSecondary)),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: hats.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, indent: 16, endIndent: 16, color: theme.divider),
        itemBuilder: (context, index) {
          final hat = hats[index];
          final selected = selectedHat?.hatNumber == hat.hatNumber;
          final online = hat.status == '1' || hat.status == 'online';
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.videocam_outlined,
                    color: theme.textPrimary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hat.bindUserName ?? '未绑定人员',
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${hat.hatNumber ?? '未知帽号'} · ${online ? '在线' : '离线'}',
                        style: TextStyle(
                          color: theme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (selected)
                  const _ConnectionLabel(text: '当前')
                else
                  OutlinedButton(
                    onPressed: busy ? null : () => onSelect(hat),
                    child: const Text('切换'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
