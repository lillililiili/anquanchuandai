import '../../components/field_brand.dart';
import '../../components/field_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../api/alarm.dart';
import '../../components/app_map.dart';
import '../../components/skeleton_view.dart';
import '../../hooks/auto_loading.dart';
import '../../hooks/use_skeleton.dart';
import '../../hooks/use_theme.dart';
import '../../models/alarm.dart';
import '../../theme/theme.dart';

/// 告警详情页面
class AlarmDetailPage extends HookWidget {
  final String? alarmId;

  const AlarmDetailPage({super.key, this.alarmId});

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();

    final skeleton = useSkeleton<Alarm>(
      request: () => AlarmApi.getById(alarmId!),
      immediate: alarmId != null,
    );

    return Scaffold(
      backgroundColor: theme.background,
      appBar: _buildAppBar(context, theme),
      body: SkeletonView.fromHook(
        skeleton,
        (alarm) => SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 6),
              // 告警信息卡片
              _AlarmInfoCard(
                alarm: alarm,
                theme: theme,
                onRefresh: skeleton.execute,
              ),
              const SizedBox(height: 6),
              // 设备信息卡片
              _DeviceInfoCard(alarm: alarm, theme: theme),
              const SizedBox(height: 6),
              // 位置信息卡片
              _LocationInfoCard(alarm: alarm, theme: theme),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
      floatingActionButton: skeleton.data.value != null
          ? _HandleFloatingButton(
              alarm: skeleton.data.value!,
              theme: theme,
              onRefresh: skeleton.execute,
            )
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, ThemeColors theme) {
    return AppBar(
      backgroundColor: theme.background,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: SpringColors.mintGreen.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new,
            size: 18,
            color: SpringColors.mintGreen,
          ),
        ),
      ),
      title: Text(
        '告警详情',
        style: AppTypography.headlineMedium.copyWith(color: theme.textPrimary),
      ),
      centerTitle: true,
    );
  }
}

// ==================== 告警信息卡片 ====================
class _AlarmInfoCard extends HookWidget {
  final Alarm alarm;
  final ThemeColors theme;
  final VoidCallback onRefresh;

  const _AlarmInfoCard({
    required this.alarm,
    required this.theme,
    required this.onRefresh,
  });

  // 根据 alarmType 获取中文标题
  String _getAlarmTitle(String? type) {
    final map = {
      'sos': 'SOS 告警',
      'fall': '跌落告警',
      'removal': '脱帽告警',
      'silent': '静默告警',
      'proximity': '近电感应',
    };
    return map[type] ?? '未知告警';
  }

  @override
  Widget build(BuildContext context) {
    final loadingState = useAutoLoading();
    final isHandled = alarm.isHandled == 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            theme.cardBackground,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '告警信息',
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getAlarmTitle(alarm.alarmType),
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const FieldSceneAccent(scene: 'device-card', size: 60),
            ],
          ),
          const SizedBox(height: 16),
          // 分割线
          Divider(
            height: 1,
            color: theme.isDark
                ? const Color(0x1FFFFFFF)
                : const Color(0x14000000),
          ),
          const SizedBox(height: AppSpacing.lg),
          // 告警详情列表
          _InfoRow(
            label: '告警类型',
            value: _getAlarmTitle(alarm.alarmType),
            theme: theme,
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoRow(
            label: '告警级别',
            value: alarm.alarmLevel ?? '普通',
            valueColor: SpringColors.cherryRed,
            theme: theme,
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoRow(
            label: '发生时间',
            value: alarm.alarmStartTime ?? '',
            theme: theme,
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoRow(
            label: '处理状态',
            value: isHandled ? '已处理' : '未处理',
            valueColor: isHandled
                ? SpringColors.mintGreen
                : SpringColors.cherryRed,
            theme: theme,
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoRow(
            label: '告警描述',
            value: alarm.description?.trim().isNotEmpty == true
                ? alarm.description!
                : '暂无描述',
            theme: theme,
            isMultiline: true,
          ),
          // 操作按钮（仅未处理时显示）
          if (!isHandled) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: loadingState.loading
                        ? null
                        : () async {
                            try {
                              await loadingState.run(
                                AlarmApi.answer(alarm.id!),
                              );
                              onRefresh();
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('操作失败: $e')),
                                );
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SpringColors.skyBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMedium,
                        ),
                      ),
                    ),
                    child: Text(loadingState.loading ? '处理中...' : '接听'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _showHandleDialog(context, alarm),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SpringColors.mintGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMedium,
                        ),
                      ),
                    ),
                    child: const Text('标记处理'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showHandleDialog(BuildContext context, Alarm alarm) {
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('处理告警'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请输入处理描述：'),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '请输入处理详情...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final updatedAlarm = Alarm(
                  id: alarm.id,
                  description: descriptionController.text,
                  isHandled: 1,
                );
                await AlarmApi.handle(updatedAlarm);
                onRefresh();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('处理失败: $e')));
                }
              }
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }
}

// ==================== 设备信息卡片 ====================
class _DeviceInfoCard extends StatelessWidget {
  final Alarm alarm;
  final ThemeColors theme;

  const _DeviceInfoCard({required this.alarm, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: SpringColors.skyBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.construction,
                  size: 14,
                  color: SpringColors.skyBlue,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '设备信息',
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
          // 设备详情列表
          _InfoRow(label: '设备编号', value: alarm.hatNumber ?? '未知', theme: theme),
          const SizedBox(height: AppSpacing.md),
          _InfoRow(label: '绑定人员', value: alarm.userName ?? '未知', theme: theme),
        ],
      ),
    );
  }
}

// ==================== 位置信息卡片 ====================
class _LocationInfoCard extends StatelessWidget {
  final Alarm alarm;
  final ThemeColors theme;

  const _LocationInfoCard({required this.alarm, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: SpringColors.cherryRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.location_on,
                  size: 14,
                  color: SpringColors.cherryRed,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '位置信息',
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
          // 位置详情
          _InfoRow(label: '告警ID', value: alarm.id ?? '', theme: theme),
          const SizedBox(height: AppSpacing.md),
          _InfoRow(
            label: '处理时间',
            value: alarm.handleTime ?? '未处理',
            theme: theme,
          ),
          const SizedBox(height: AppSpacing.lg),
          // 地图区域
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
            child: SizedBox(height: 200, child: _buildAlarmMap()),
          ),
        ],
      ),
    );
  }

  Widget _buildAlarmMap() {
    // 获取告警位置，如果没有则使用默认位置
    final lat = alarm.latitude ?? 37.2408718814842;
    final lng = alarm.longitude ?? 118.81377768291111;
    final position = LatLng(lat, lng);

    return AppMap(
      initialCenter: position,
      initialZoom: 15,
      children: [
        MarkerLayer(
          markers: [
            Marker(
              point: position,
              width: 40,
              height: 40,
              child: Container(
                decoration: BoxDecoration(
                  color: SpringColors.cherryRed,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: SpringColors.cherryRed.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.warning, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ==================== 通用信息行组件 ====================
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeColors theme;
  final Color? valueColor;
  final bool isMultiline;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.theme,
    this.valueColor,
    this.isMultiline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: theme.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: valueColor ?? theme.textPrimary,
              height: isMultiline ? 1.5 : 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

// ==================== 处理悬浮按钮 ====================
class _HandleFloatingButton extends HookWidget {
  final Alarm alarm;
  final ThemeColors theme;
  final VoidCallback onRefresh;

  const _HandleFloatingButton({
    required this.alarm,
    required this.theme,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final isHandled = alarm.isHandled == 1;

    return FloatingActionButton.extended(
      onPressed: isHandled ? null : () => _showHandleDialog(context),
      backgroundColor: isHandled
          ? (theme.isDark ? Colors.grey[700] : Colors.grey[300])
          : SpringColors.mintGreen,
      icon: Icon(
        isHandled ? Icons.check_circle : Icons.check_circle_outline,
        color: isHandled
            ? (theme.isDark ? Colors.grey[500] : Colors.grey[600])
            : Colors.white,
      ),
      label: Text(
        isHandled ? '已处理' : '处理告警',
        style: TextStyle(
          color: isHandled
              ? (theme.isDark ? Colors.grey[500] : Colors.grey[600])
              : Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _showHandleDialog(BuildContext context) {
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        ),
        title: Text(
          '处理告警',
          style: AppTypography.title.copyWith(color: theme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '请输入处理描述：',
              style: TextStyle(fontSize: 14, color: theme.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: descriptionController,
              maxLines: 3,
              style: TextStyle(color: theme.textPrimary),
              decoration: InputDecoration(
                hintText: '请输入处理详情...',
                hintStyle: TextStyle(color: theme.textTertiary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                  borderSide: BorderSide(color: theme.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                  borderSide: BorderSide(color: theme.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                  borderSide: BorderSide(color: SpringColors.skyBlue),
                ),
                filled: true,
                fillColor: theme.background,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: theme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final updatedAlarm = Alarm(
                  id: alarm.id,
                  description: descriptionController.text,
                  isHandled: 1,
                );
                await AlarmApi.handle(updatedAlarm);
                onRefresh();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('处理失败: $e')));
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: SpringColors.mintGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              ),
            ),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }
}
