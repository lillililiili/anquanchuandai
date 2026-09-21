import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../api/hat.dart';
import '../../api/intercom.dart';
import '../../components/app_map.dart';
import '../../components/field_brand.dart';
import '../../components/field_motion.dart';
import '../../components/skeleton_view.dart';
import '../../hooks/use_skeleton.dart';
import '../../hooks/use_theme.dart';
import '../../hooks/useAgoraRtcEngine.dart';
import '../../models/hat.dart';
import '../../models/hat_location_record.dart';
import '../../models/agora_credentials.dart';
import '../../theme/theme.dart';
import '../../utils/app_logger.dart';

/// 设备详情和位置数据组合
typedef DeviceDetailData = ({Hat? hat, HatLocationRecord? location});

/// 监控详情页面
class MonitorDetailPage extends HookWidget {
  final String? deviceId;
  final String? credentialsJson;
  final String? hatNumber;
  const MonitorDetailPage({
    super.key,
    this.deviceId,
    this.credentialsJson,
    this.hatNumber,
  });
  @override
  Widget build(BuildContext context) {
    final theme = useTheme();
    final rtcState = useAgoraRtcEngine();
    final credentials = useState<AgoraCredentials?>(null);
    final isConnecting = useState(false);
    final connectionError = useState<String?>(null);
    final retryVersion = useState(0);
    final skeleton = useSkeleton<DeviceDetailData>(
      request: () async {
        if (deviceId == null) return (hat: null, location: null);
        final results = await Future.wait([
          HatApi.getHatByNumber(hatNumber ?? ''),
          HatApi.getSingleHatHistory(hatId: deviceId!),
        ]);
        final hat = results[0] as Hat?;
        final records = results[1] as List<HatLocationRecord>;
        return (hat: hat, location: records.isNotEmpty ? records.first : null);
      },
      isEmpty: (data) => data.hat == null,
    );
    final hasProvidedCredentials = credentialsJson?.isNotEmpty == true;
    useEffect(
      () {
        var cancelled = false;
        Future<void> connectToDevice() async {
          isConnecting.value = true;
          connectionError.value = null;
          try {
            AgoraCredentials creds;
            if (hasProvidedCredentials) {
              creds = AgoraCredentials.fromJson(
                jsonDecode(credentialsJson!) as Map<String, dynamic>,
              );
            } else {
              final hat = skeleton.data.value?.hat;
              if (hat?.hatNumber == null) return;
              creds = await IntercomApi.singleCall(
                hatNumber: hat!.hatNumber!,
                clientId: 'app_123',
                participant: hat.bindUserName,
              );
            }
            if (!context.mounted || cancelled) return;
            credentials.value = creds;
            await rtcState.joinChannel(creds);
          } catch (error) {
            AppLogger.e('monitor_detail connectToDevice error', error);
            if (context.mounted && !cancelled)
              connectionError.value = '设备连接失败，请检查网络后重试';
          } finally {
            if (context.mounted && !cancelled) isConnecting.value = false;
          }
        }

        if (hasProvidedCredentials ||
            skeleton.data.value?.hat?.hatNumber != null)
          connectToDevice();
        return () {
          cancelled = true;
          unawaited(rtcState.leaveChannel());
        };
      },
      [
        credentialsJson,
        hasProvidedCredentials ? null : skeleton.data.value?.hat?.hatNumber,
        retryVersion.value,
      ],
    );

    final sdkFailed =
        rtcState.status.contains('失败') || rtcState.status.contains('错误');
    final error = connectionError.value ?? (sdkFailed ? '连接中断，请重试' : null);
    final hasVideo = rtcState.remoteUsers.values.any((user) => user.hasVideo);
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('监控详情'),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SkeletonView.fromHook(
        skeleton,
        (data) => SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.hat?.bindUserName ?? '未绑定人员',
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    MotionSwap(
                      value: '${isConnecting.value}:$error:$hasVideo',
                      child: Text(
                        '${data.hat?.hatNumber ?? '未知设备'} · ${isConnecting.value
                            ? '正在连接'
                            : error != null
                            ? '连接失败'
                            : hasVideo
                            ? '画面已连接'
                            : '等待设备推流'}',
                        style: TextStyle(
                          color: error != null
                              ? Theme.of(context).colorScheme.error
                              : theme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _VideoPlayerSection(
                  rtcState: rtcState,
                  credentials: credentials.value,
                  isConnecting: isConnecting.value,
                  error: error,
                  onRetry: () => retryVersion.value++,
                ),
              ),
              const SizedBox(height: 16),
              _DeviceStatusCard(theme: theme, hat: data.hat),
              const SizedBox(height: 16),
              _DeviceInfoCard(theme: theme, hat: data.hat),
              const SizedBox(height: 16),
              _LocationCard(theme: theme, hat: data.hat),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoPlayerSection extends StatelessWidget {
  final AgoraRtcState rtcState;
  final AgoraCredentials? credentials;
  final bool isConnecting;
  final String? error;
  final VoidCallback onRetry;
  const _VideoPlayerSection({
    required this.rtcState,
    required this.credentials,
    required this.isConnecting,
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
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: ColoredBox(
          color: const Color(0xFF202B46),
          child: canRender
              ? AgoraVideoView(
                  controller: VideoViewController.remote(
                    rtcEngine: rtcState.engine!,
                    canvas: VideoCanvas(uid: remoteUser.uid),
                    connection: RtcConnection(
                      channelId: credentials?.channelName ?? '',
                    ),
                  ),
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isConnecting)
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
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
                          isConnecting ? '正在连接设备…' : error ?? '等待设备推流',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        if (!isConnecting) ...[
                          const SizedBox(height: 6),
                          const Text(
                            '请确认设备在线并已开启推流',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 14),
                          MotionEntrance(
                            child: MotionPress(
                              child: FilledButton.icon(
                                onPressed: onRetry,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('重新连接'),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

// ==================== 设备状态卡片 ====================
class _DeviceStatusCard extends StatelessWidget {
  final ThemeColors theme;
  final Hat? hat;

  const _DeviceStatusCard({required this.theme, this.hat});

  @override
  Widget build(BuildContext context) {
    final electricity = hat?.electricityUsage;
    final storage = hat?.storageUsage;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 卡片标题
          Text(
            '设备状态',
            style: AppTypography.title.copyWith(
              color: theme.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // 状态项列表
          Row(
            children: [
              // 电量
              Expanded(
                child: _StatusItem(
                  icon: Icons.battery_full,
                  label: '剩余电量',
                  value: electricity != null ? '${electricity.toInt()}%' : '--',
                  progressValue: electricity != null
                      ? electricity.toDouble() / 100
                      : 0,
                  progressColor: SpringColors.mintGreen,
                  theme: theme,
                ),
              ),
              const SizedBox(width: AppSpacing.xl),
              // 存储空间
              Expanded(
                child: _StatusItem(
                  icon: Icons.storage,
                  label: '存储空间',
                  value: storage != null ? '${storage.toInt()}%' : '--',
                  progressValue: storage != null ? storage.toDouble() / 100 : 0,
                  progressColor: SpringColors.mintGreen,
                  theme: theme,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double progressValue;
  final Color progressColor;
  final ThemeColors theme;

  const _StatusItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.progressValue,
    required this.progressColor,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: progressColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: progressColor, size: 18),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: theme.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          value,
          style: AppTypography.title.copyWith(
            color: theme.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progressValue.clamp(0.0, 1.0),
            backgroundColor: theme.isDark
                ? const Color(0xFF2A2A2A)
                : const Color(0xFFE8E8E8),
            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

// ==================== 设备信息卡片 ====================
class _DeviceInfoCard extends StatelessWidget {
  final ThemeColors theme;
  final Hat? hat;

  const _DeviceInfoCard({required this.theme, this.hat});

  @override
  Widget build(BuildContext context) {
    final isOnline = hat?.status == '1' || hat?.status == 'online';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: FieldArtworkSurface(
        scene: 'device-card',
        opacity: 0.35,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 卡片标题
            Text(
              '设备信息',
              style: AppTypography.title.copyWith(
                color: theme.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // 设备内容
            Row(
              children: [
                // 设备图标
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: SpringColors.skyBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.construction,
                    color: theme.textPrimary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                // 设备信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hat?.hatNumber ?? '安全帽',
                        style: AppTypography.title.copyWith(
                          color: theme.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '绑定用户：${hat?.bindUserName ?? '未绑定'}',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.textTertiary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '所属分组：${hat?.bindGroup ?? '未分组'}',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                // 在线状态
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isOnline
                        ? theme.background
                        : SpringColors.cherryRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isOnline ? theme.divider : SpringColors.cherryRed,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    isOnline ? '在线' : '离线',
                    style: AppTypography.button.copyWith(
                      color: isOnline
                          ? theme.textPrimary
                          : SpringColors.cherryRed,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 当前位置卡片 ====================
class _LocationCard extends HookWidget {
  final ThemeColors theme;
  final Hat? hat;

  const _LocationCard({required this.theme, this.hat});

  @override
  Widget build(BuildContext context) {
    // 解析经纬度
    LatLng? position;
    if (hat?.latitude != null && hat?.longitude != null) {
      final lat = double.tryParse(hat!.latitude!);
      final lng = double.tryParse(hat!.longitude!);
      if (lat != null && lng != null) {
        position = LatLng(lat, lng);
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '当前位置',
                style: AppTypography.title.copyWith(
                  color: theme.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // 分割线
          Divider(
            height: 1,
            color: theme.isDark
                ? const Color(0x1FFFFFFF)
                : const Color(0x14000000),
          ),
          const SizedBox(height: AppSpacing.lg),
          // 地图区域
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
            child: Container(
              width: double.infinity,
              height: 180,
              child: position != null
                  ? AppMap(
                      initialCenter: position,
                      initialZoom: 16,
                      interactionFlags: InteractiveFlag.none,
                      children: [
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: position,
                              width: 40,
                              height: 40,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: SpringColors.cherryRed.withValues(
                                    alpha: 0.2,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.location_on,
                                  color: SpringColors.cherryRed,
                                  size: 28,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Container(
                      color: theme.isDark
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFFF5F5F5),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.location_off,
                              color: theme.textTertiary,
                              size: 48,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              '暂无位置信息',
                              style: AppTypography.body.copyWith(
                                color: theme.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
          if (position != null) ...[
            const SizedBox(height: AppSpacing.lg),
            // 坐标信息
            Row(
              children: [
                // 左侧：图标
                Icon(Icons.gps_fixed, size: 16, color: theme.textPrimary),

                // 间距
                const SizedBox(width: AppSpacing.sm),

                // 右侧：经度和纬度（使用 Expanded 包裹 Column）
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, // 让文字左对齐
                    children: [
                      Text(
                        '经度：${hat!.longitude}',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.textSecondary,
                        ),
                      ),
                      Text(
                        '纬度：${hat!.latitude}',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
