import '../../field/field_home.dart';
import 'package:flutter/material.dart';
import 'package:rolling_intelligence_headband/api/alarm.dart';
import 'package:rolling_intelligence_headband/api/hat.dart';
import 'package:rolling_intelligence_headband/components/skeleton_view.dart';
import 'package:rolling_intelligence_headband/models/alarm.dart' as api;
import 'package:rolling_intelligence_headband/models/hat.dart' as hat;
import 'package:rolling_intelligence_headband/models/user.dart';
import 'package:rolling_intelligence_headband/router/route_tree.dart';
import 'package:rolling_intelligence_headband/store/user_store.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../hooks/use_skeleton.dart';

import '../../hooks/use_theme.dart';
import '../../models/home_models.dart';
import '../../theme/theme.dart';
import '../../theme/theme_signal.dart';

/// 首页组件
class HomeTabPage extends StatelessWidget {
  const HomeTabPage({super.key});
  @override
  Widget build(BuildContext context) => const FieldHomePage();
}

class LegacyHomeTabPage extends HookWidget {
  const LegacyHomeTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();
    final scrollController = useScrollController();

    final userInfo = useUserInfo();

    // 告警数据请求
    final alarmSkeleton = useSkeleton<List<api.Alarm>>(
      emptyMsg: '暂无告警',
      isEmpty: (data) => data.isEmpty,
      request: () async {
        final res = await AlarmApi.getAlarmPage(current: 1, size: 5);
        return res.records ?? [];
      },
    );

    // 设备数据请求
    final deviceSkeleton = useSkeleton<List<hat.Hat>>(
      emptyMsg: '暂无设备',
      isEmpty: (data) => data.isEmpty,
      request: () async {
        final res = await HatApi.getHatPage(current: 1, size: 10);
        return res.records ?? [];
      },
    );

    return Scaffold(
      body: NestedScrollView(
        controller: scrollController,
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            if (userInfo != null)
              SliverPersistentHeader(
                pinned: true, // 必须钉住，否则滚动后就消失了
                delegate: _UserInfoHeaderDelegate(
                  userInfo: userInfo,
                  isDark: theme.isDark,
                  min: 90.0, // 收缩后的高度 (只保留用户名+按钮)
                  max: 140.0, // 完全展开的高度 (包含头像、装饰、问候语)
                ),
              ),
          ];
        },
        body: ListView(
          children: [
            // 2. 快捷操作金刚区
            _QuickActionsSection(
              actions: _mockQuickActions(context),
              theme: theme,
            ),
            // 3. 最近告警
            _AlarmSection(skeleton: alarmSkeleton, theme: theme),
            // 4. 设备状态
            _DeviceSection(skeleton: deviceSkeleton, theme: theme),
            // 底部间距（避免被悬浮导航栏遮挡）
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}

// ==================== 2. 自定义 Delegate (核心逻辑) ====================
class _UserInfoHeaderDelegate extends SliverPersistentHeaderDelegate {
  final UserInfo userInfo;
  final bool isDark;
  final double min;
  final double max;

  _UserInfoHeaderDelegate({
    required this.userInfo,
    required this.isDark,
    required this.min,
    required this.max,
  });

  @override
  double get minExtent => min;

  @override
  double get maxExtent => max;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // 计算滚动进度 (0.0 -> 1.0)
    // 0.0 = 完全展开，1.0 = 完全收缩
    final totalScrollRange = maxExtent - minExtent;
    final progress = (shrinkOffset / totalScrollRange).clamp(0.0, 1.0);

    final theme = ThemeModeSignal.themeColorsSignal.value;
    final primaryColor = SpringColors.getMintColor(isDark);

    // 2. 透明度控制
    final fadeOutOpacity = (1.0 - progress * 1.5).clamp(0.0, 1.0); // 快速消失

    // 3. 位移控制 (用户名从下往上移，或者从左往右)
    // 这里我们让用户名在收缩时向左移动一点点，以腾出空间给按钮或居左
    final nameTranslationX = -20.0 * progress;

    // 4. 尺寸控制
    final avatarSize = 56.0 * (1.0 - progress); // 56 -> 0
    final buttonScale = 1.0 - (progress * 0.2); // 1.0 -> 0.7

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryColor.withValues(alpha: 0.15),
            primaryColor.withValues(alpha: 0.08),
            Colors.transparent,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          // --- 主体内容 ---
          Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top:
                  MediaQuery.of(context).padding.top +
                  (12 * (1 - progress)), // 顶部间距也收缩
              bottom: 12,
            ),
            child: Row(
              children: [
                // 1. 头像区域 (逐渐缩小至消失)
                SizedBox(
                  width: avatarSize + 20, // 保持外圈比例
                  height: avatarSize + 20,
                  child: Opacity(
                    opacity: fadeOutOpacity,
                    child: Transform.scale(
                      scale: 1.0 - progress,
                      child: _buildAvatar(userInfo.avatar, size: 56),
                    ),
                  ),
                ),

                // 间距 (头像消失后，间距也应该动态调整，这里简化处理)
                if (progress < 0.9) SizedBox(width: 12 * (1 - progress)),

                // 2. 用户信息列
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center, // 始终垂直居中
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 问候语 (快速消失)
                      if (progress < 0.3)
                        Opacity(
                          opacity: fadeOutOpacity,
                          child: Text(
                            _getGreeting(DateTime.now().hour),
                            style: TextStyle(
                              color: theme.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),

                      // 用户名 (始终存在，但位置微调)
                      Transform.translate(
                        offset: Offset(nameTranslationX, 0),
                        child: Text(
                          userInfo.nickName,
                          style: TextStyle(
                            color: theme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      // 角色标签 (快速消失)
                      if (progress < 0.4)
                        Opacity(
                          opacity: fadeOutOpacity,
                          child: _buildRoleTag(theme),
                        ),
                    ],
                  ),
                ),

                // 3. 扫一扫按钮 (固定大小，不随滚动缩放)
                _ScanButton(scale: buttonScale),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return oldDelegate is _UserInfoHeaderDelegate &&
        (oldDelegate.userInfo != userInfo || oldDelegate.isDark != isDark);
  }

  // --- 以下复用你原有的辅助 Widget (略作修改以适应无状态) ---

  Widget _buildRoleTag(ThemeColors theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.primary.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: SpringColors.mintGreen,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            userInfo.userName,
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String avatarUrl, {double size = 64}) {
    final outerSize = size + 20;
    final borderWidth = size * 0.04;

    return Container(
      width: outerSize,
      height: outerSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 外圈光环
          Container(
            width: outerSize,
            height: outerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.4),
                  Colors.white.withValues(alpha: 0.2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          // 内圈头像
          Positioned.fill(
            left: borderWidth * 2,
            top: borderWidth * 2,
            right: borderWidth * 2,
            bottom: borderWidth * 2,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.8),
                  width: borderWidth,
                ),
              ),
              child: ClipOval(
                child: Image.network(
                  avatarUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.white,
                    child: Icon(
                      Icons.person,
                      size: size * 0.5,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 在线状态
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              width: size * 0.25,
              height: size * 0.25,
              decoration: BoxDecoration(
                color: SpringColors.mintGreen,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: size * 0.04),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getGreeting(int hour) {
    if (hour < 6) return '夜深了 🌙';
    if (hour < 9) return '早上好 ☀️';
    if (hour < 12) return '上午好 🌤️';
    if (hour < 14) return '中午好 🍽️';
    if (hour < 18) return '下午好 🌅';
    if (hour < 22) return '晚上好 🌆';
    return '夜深了 🌙';
  }
}

class _ScanButton extends HookWidget {
  final double scale;

  const _ScanButton({this.scale = 1.0});

  // double get scaleSize => 1;

  @override
  Widget build(BuildContext context) {
    final isScanning = useState(false);

    final baseSize = 52.0 * scale;
    final innerSize = 40.0 * scale;
    final iconSize = 24.0 * scale;
    final strokeWidth = 3.0 * scale;
    // 阴影缩放倍率比图标小 (0.8)
    final shadowScale = scale * 0.2;

    return GestureDetector(
      onTap: () {
        isScanning.value = true;
        Future.delayed(const Duration(seconds: 2), () {
          isScanning.value = false;
        });
      },
      child: Container(
        width: baseSize,
        height: baseSize,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.45),
            width: 1.5 * scale,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10 * shadowScale,
              offset: Offset(0, 4 * shadowScale),
            ),
          ],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            child: isScanning.value
                ? SizedBox(
                    key: const ValueKey('scanning'),
                    width: innerSize,
                    height: innerSize,
                    child: CircularProgressIndicator(
                      strokeWidth: strokeWidth,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        const Color(0xFF10B981),
                      ),
                    ),
                  )
                : Container(
                    key: const ValueKey('icon'),
                    width: innerSize,
                    height: innerSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 6 * shadowScale,
                          offset: Offset(0, 2 * shadowScale),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.qr_code_scanner,
                      color: const Color(0xFF10B981),
                      size: iconSize,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ==================== 快捷操作金刚区 ====================
class _QuickActionsSection extends StatelessWidget {
  final List<QuickAction> actions;
  final ThemeColors theme;

  const _QuickActionsSection({required this.actions, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: AppSpacing.cardMargin,
      padding: AppSpacing.cardPaddingLarge,
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '快捷操作',
            style: AppTypography.title.copyWith(color: theme.textPrimary),
          ),
          const SizedBox(height: AppSpacing.md),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: AppSpacing.lg,
              mainAxisSpacing: AppSpacing.lg,
              childAspectRatio: 0.85,
            ),
            itemCount: actions.length,
            itemBuilder: (context, index) {
              final action = actions[index];
              return _QuickActionItem(action: action, theme: theme);
            },
          ),
        ],
      ),
    );
  }
}

class _QuickActionItem extends HookWidget {
  final QuickAction action;
  final ThemeColors theme;

  const _QuickActionItem({required this.action, required this.theme});

  @override
  Widget build(BuildContext context) {
    final isPressed = useState(false);
    final actionColor = _getActionColor(action.label);

    return GestureDetector(
      onTapDown: (_) => isPressed.value = true,
      onTapUp: (_) {
        isPressed.value = false;
        action.onTap?.call();
      },
      onTapCancel: () => isPressed.value = false,
      child: AnimatedScale(
        scale: isPressed.value ? AppSpacing.pressScale : 1,
        duration: AppSpacing.pressDuration,
        child: Container(
          decoration: BoxDecoration(
            color: actionColor.withValues(
              alpha: SpringColors.iconBackgroundAlpha,
            ),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: AppSpacing.quickActionIconSize,
                height: AppSpacing.quickActionIconSize,
                decoration: BoxDecoration(
                  color: actionColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  action.icon,
                  color: Colors.white,
                  size: AppSpacing.quickActionIconIconSize,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                action.label,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getActionColor(String label) {
    return SpringColors.getActionColor(label);
  }
}

// ==================== 最近告警 ====================
class _AlarmSection extends StatelessWidget {
  final SkeletonBind<List<api.Alarm>> skeleton;
  final ThemeColors theme;

  const _AlarmSection({required this.skeleton, required this.theme});

  @override
  Widget build(BuildContext context) {
    final primaryColor = SpringColors.getMintColor(theme.isDark);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        boxShadow: AppShadows.card,
      ),
      child: SkeletonView.fromHook(
        skeleton,
        (alarms) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Padding(
              padding: AppSpacing.cardPaddingLarge,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '最近告警',
                    style: AppTypography.title.copyWith(
                      color: theme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            // 告警列表
            ...alarms.asMap().entries.map(
              (entry) => _AlarmItem(
                alarm: entry.value,
                theme: theme,
                isLast: entry.key == alarms.length - 1,
              ),
            ),
            // 无告警提示
            if (alarms.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 48,
                        color: theme.textTertiary,
                      ),
                      const SizedBox(height: 12),
                      Text('暂无告警', style: TextStyle(color: theme.textTertiary)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AlarmItem extends StatelessWidget {
  final api.Alarm alarm;
  final ThemeColors theme;
  final bool isLast;

  const _AlarmItem({
    required this.alarm,
    required this.theme,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final alarmType = _getAlarmType(alarm.alarmType);

    return GestureDetector(
      onTap: () {
        context.goto(
          RouteNode.alarmDetail,
          params: {'alarmId': alarm.id ?? ''},
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(bottom: BorderSide(color: theme.divider, width: 1)),
        ),
        child: Row(
          children: [
            // 告警类型图标
            Container(
              width: AppSpacing.alarmIconSize,
              height: AppSpacing.alarmIconSize,
              decoration: BoxDecoration(
                color: alarmType.color.withValues(
                  alpha: SpringColors.iconBackgroundAlpha,
                ),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              ),
              child: Icon(
                alarmType.icon,
                color: alarmType.color,
                size: AppSpacing.alarmIconIconSize,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            // 告警信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alarmType.label,
                    style: AppTypography.body.copyWith(
                      color: theme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    alarm.description ?? '',
                    style: TextStyle(fontSize: 13, color: theme.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    alarm.alarmStartTime ?? '',
                    style: TextStyle(fontSize: 12, color: theme.textTertiary),
                  ),
                ],
              ),
            ),
            // 状态指示（未处理时显示红点）
            if (alarm.isHandled == 0)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: alarmType.color,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  AlarmType _getAlarmType(String? type) {
    switch (type) {
      case 'sos':
        return AlarmType.sos;
      case 'fall':
        return AlarmType.fall;
      case 'heartRate':
        return AlarmType.heartRate;
      case 'geoFence':
        return AlarmType.geoFence;
      case 'lowBattery':
        return AlarmType.lowBattery;
      case 'offline':
        return AlarmType.offline;
      default:
        return AlarmType.sos;
    }
  }
}

// ==================== 设备状态 ====================
class _DeviceSection extends StatelessWidget {
  final SkeletonBind<List<hat.Hat>> skeleton;
  final ThemeColors theme;

  const _DeviceSection({required this.skeleton, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: AppSpacing.cardMargin,
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        boxShadow: AppShadows.card,
      ),
      child: SkeletonView.fromHook(
        skeleton,
        (devices) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Padding(
              padding: AppSpacing.cardPaddingLarge,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '设备状态',
                    style: AppTypography.title.copyWith(
                      color: theme.textPrimary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: SpringColors.mintGreen.withValues(
                        alpha: SpringColors.iconBackgroundAlpha,
                      ),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: SpringColors.mintGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '在线 ${devices.where((d) => d.status == '1').length}/${devices.length}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: SpringColors.mintGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 设备列表
            ...devices.asMap().entries.map(
              (entry) => _DeviceItem(
                device: entry.value,
                theme: theme,
                isLast: entry.key == devices.length - 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceItem extends StatelessWidget {
  final hat.Hat device;
  final ThemeColors theme;
  final bool isLast;

  const _DeviceItem({
    required this.device,
    required this.theme,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final onlineColor = SpringColors.skyBlue;
    final isOnline = device.status == '1';

    return GestureDetector(
      onTap: () {
        if (device.id != null) {
          context.goto(
            RouteNode.monitorDetail,
            params: {'deviceId': device.id ?? ''},
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(bottom: BorderSide(color: theme.divider, width: 1)),
        ),
        child: Row(
          children: [
            // 设备图标
            Container(
              width: AppSpacing.alarmIconSize,
              height: AppSpacing.alarmIconSize,
              decoration: BoxDecoration(
                color: (isOnline ? onlineColor : Colors.grey).withValues(
                  alpha: SpringColors.iconBackgroundAlpha,
                ),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              ),
              child: Icon(
                Icons.bluetooth,
                color: isOnline ? onlineColor : Colors.grey,
                size: AppSpacing.alarmIconIconSize,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            // 设备信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        device.hatNumber ?? '',
                        style: AppTypography.body.copyWith(
                          color: theme.textPrimary,
                        ),
                      ),
                      if (isOnline) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: SpringColors.mintGreen.withValues(
                              alpha: SpringColors.iconBackgroundAlpha,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSmall,
                            ),
                          ),
                          child: const Text(
                            '在线',
                            style: TextStyle(
                              fontSize: 11,
                              color: SpringColors.mintGreen,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 14,
                        color: theme.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        device.bindUserName ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 更多操作
            Icon(Icons.chevron_right, color: theme.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }
}

List<QuickAction> _mockQuickActions(BuildContext context) => [
  // QuickAction(
  //   icon: Icons.check_circle_outline,
  //   label: '打卡签到',
  //   onTap: () => context.push(AppRoutes.checkIn),
  // ),
  // QuickAction(icon: Icons.videocam, label: '实时监控', onTap: () => {}),
  // QuickAction(icon: Icons.mic, label: '集群对讲'),
  QuickAction(
    icon: Icons.history,
    label: '轨迹回放',
    onTap: () => context.goto(RouteNode.playbackOfTrajectory),
  ),
  QuickAction(
    icon: Icons.location_on,
    label: '电子围栏',
    onTap: () => context.goto(RouteNode.geoFence),
  ),
  QuickAction(
    icon: Icons.warning,
    label: '告警记录',
    onTap: () => context.goto(RouteNode.alarmRecord),
  ),
];
