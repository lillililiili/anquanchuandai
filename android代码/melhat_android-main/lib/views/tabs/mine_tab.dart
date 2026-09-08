import '../../components/field_motion.dart';
import 'package:flutter/material.dart';
import 'package:rolling_intelligence_headband/api/user.dart';
import 'package:rolling_intelligence_headband/models/app_statistics.dart';
import 'package:rolling_intelligence_headband/models/user.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:rolling_intelligence_headband/router/route_tree.dart';
import '../../hooks/use_agent_page.dart';
import '../../hooks/use_page_agent.dart';
import '../../hooks/use_theme.dart';
import '../../hooks/auto_loading.dart';
import '../../store/user_store.dart';
import '../../theme/theme.dart';
import '../../field/field_session.dart';
import '../../components/field_brand.dart';
import '../../components/field_assistant_action.dart';
import '../../utils/app_logger.dart';
import 'package:voice_recognizer/voice_recognizer.dart';

/// 我的页面
class MineTabPage extends HookWidget {
  const MineTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();
    final userStore = useUserStore();

    // 1. 页面总控中心
    final pageController = useAgentPage(
      meta: RouteNode.homeTab4,
      greetingMessage: '已进入我的页面，我可以帮您查看个人信息或退出登录',
      expectedComponents: {'statistics'},
    );

    // 使用 useAutoLoading 管理退出登录的 loading 状态
    final logoutState = useAutoLoading();

    // 统计数据
    final statistics = useState<AppStatistics?>(null);
    final isLoading = useState(true);
    final statisticsError = useState(false);
    final refreshKey = useState(0);

    // 注册 getUserInfo 工具
    usePageAgent(
      controller: pageController,
      toolName: 'getUserInfo',
      executeFn: (params) async {
        return userStore.userInfo?.toJson() ?? {};
      },
    );

    // 注册 getStatistics 工具
    usePageAgent(
      controller: pageController,
      toolName: 'getStatistics',
      executeFn: (params) async {
        return {
          'hatCount': statistics.value?.hatCount,
          'alarmCount': statistics.value?.alarmCount,
        };
      },
    );

    // 注册 logout 工具
    usePageAgent(
      controller: pageController,
      toolName: 'logout',
      executeFn: (params) async {
        await userStore.logout();
        return {'success': true};
      },
    );

    // 获取统计数据
    final mineContext = useContext();
    useEffect(() {
      Future<void> fetchStatistics() async {
        isLoading.value = true;
        statisticsError.value = false;
        try {
          final data = await UserApi.getAppStatistics();
          if (!mineContext.mounted) return;
          statistics.value = data;
          pageController.completeInit(componentId: 'statistics');
        } catch (e) {
          if (!mineContext.mounted) return;
          statisticsError.value = true;
          AppLogger.e('getAppStatistics error', e);
          pageController.completeInit(componentId: 'statistics');
        } finally {
          if (mineContext.mounted) {
            isLoading.value = false;
          }
        }
      }

      fetchStatistics();

      return null;
    }, [refreshKey.value]);

    Future<void> handleLogout() async {
      await logoutState.run(userStore.logout());
      // 退出成功后跳转到登录页
      // if (context.mounted) {
      //   context.replace(RouteNode.login);
      // }
    }

    return MotionActivity(
      child: Scaffold(
        backgroundColor: theme.background,

        appBar: AppBar(
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FieldBrandMark(size: 32),
              SizedBox(width: 10),
              Text('我的'),
            ],
          ),
          actions: [
            const FieldAssistantAction(),
            IconButton(
              tooltip: '刷新个人信息',
              onPressed: isLoading.value ? null : () => refreshKey.value++,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // 1. 信息卡片
                userStore.userInfo != null
                    ? MotionEntrance(
                        child: _UserInfoCard(
                          userInfo: userStore.userInfo!,
                          theme: theme,
                          statistics: statistics.value,
                          isLoading: isLoading.value,
                        ),
                      )
                    : const SizedBox.shrink(),
                if (statisticsError.value)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '统计暂不可用，请点击右上角刷新。',
                      style: TextStyle(color: theme.textSecondary),
                    ),
                  ),
                // 2. 功能列表
                MotionEntrance(
                  index: 1,
                  child: MotionReveal(
                    child: _FunctionListSection(
                      theme: theme,
                      onLogout: () =>
                          _showLogoutDialog(context, logoutState, handleLogout),
                      onClearModel: () => _showClearModelDialog(context),
                      isLoading: logoutState.loading,
                    ),
                  ),
                ),
                // 底部间距（避免被悬浮导航栏遮挡）
                const SizedBox(height: 96),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showClearModelDialog(BuildContext context) {
    var busy = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialog, setDialog) => PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: const Text('清除语音模型？'),
            content: const Text('将删除当前设备已下载的语音识别模型。下次使用语音功能时需要重新下载。'),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialog),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        setDialog(() => busy = true);
                        try {
                          await ModelDownloadService.instance.deleteModel();
                          VoiceRecognizerRegistry.instance.reset();
                          if (dialog.mounted) Navigator.pop(dialog);
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('语音模型已清除')),
                            );
                        } catch (_) {
                          if (dialog.mounted) setDialog(() => busy = false);
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('清除失败，请重试')),
                            );
                        }
                      },
                child: Text(busy ? '正在清除…' : '确认清除'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(
    BuildContext context,
    AutoLoadingState logoutState,
    VoidCallback onConfirm,
  ) {
    var busy = false;
    final drafts = FieldSession.instance.drafts.values
        .where(
          (d) =>
              d.inquiry.trim().isNotEmpty ||
              d.measure.trim().isNotEmpty ||
              d.result.trim().isNotEmpty,
        )
        .length;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialog, setDialog) => PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: const Text('退出当前账号？'),
            content: Text(
              drafts > 0 ? '有 $drafts 条未提交的告警草稿，退出后将清除。' : '退出后需要重新登录才能查看现场数据。',
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialog),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: busy
                    ? null
                    : () {
                        setDialog(() => busy = true);
                        Navigator.pop(dialog);
                        onConfirm();
                      },
                child: const Text('退出登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== 用户信息卡片 ====================
class _UserInfoCard extends StatelessWidget {
  final UserInfo userInfo;
  final ThemeColors theme;
  final AppStatistics? statistics;
  final bool isLoading;

  const _UserInfoCard({
    required this.userInfo,
    required this.theme,
    this.statistics,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final mintGreen = theme.textPrimary;

    return Container(
      margin: AppSpacing.cardMargin,
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        boxShadow: AppShadows.card,
      ),
      child: FieldArtworkSurface(
        scene: 'profile-card',
        opacity: .22,
        child: Padding(
          padding: AppSpacing.cardPaddingLarge,
          child: Column(
            children: [
              // 头像和基本信息
              Row(
                children: [
                  // 头像
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: mintGreen.withValues(
                        alpha: AppSpacing.iconBackgroundAlphaActive,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Image.network(
                        userInfo.avatar,
                        fit: BoxFit.cover,
                        errorBuilder: (context, _, _) =>
                            Icon(Icons.person, size: 28, color: mintGreen),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  // 姓名和部门
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userInfo.nickName,
                          style: TextStyle(
                            color: theme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: SpringColors.skyBlue.withValues(
                              alpha: AppSpacing.iconBackgroundAlpha,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSmall,
                            ),
                          ),
                          child: Text(
                            userInfo.remark,
                            style: const TextStyle(
                              color: SpringColors.mintGreenDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              // 数据统计
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatItem(
                    icon: Icons.devices_outlined,
                    value: isLoading ? "--" : "${statistics?.hatCount ?? "--"}",
                    label: '管理安全帽',
                    color: SpringColors.skyBlue,
                    theme: theme,
                  ),
                  _StatItem(
                    icon: Icons.warning_amber_outlined,
                    value: isLoading
                        ? "--"
                        : "${statistics?.alarmCount ?? "--"}",
                    label: '已处理告警',
                    color: SpringColors.cherryRed,
                    theme: theme,
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

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final ThemeColors theme;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: AppSpacing.statIconSize,
          height: AppSpacing.statIconSize,
          decoration: BoxDecoration(
            color: color.withValues(alpha: AppSpacing.iconBackgroundAlpha),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          ),
          child: Icon(icon, color: color, size: AppSpacing.statIconIconSize),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          value,
          style: TextStyle(
            color: theme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: theme.textSecondary, fontSize: 12)),
      ],
    );
  }
}

// ==================== 功能列表区域 ====================
class _FunctionListSection extends StatelessWidget {
  final ThemeColors theme;
  final VoidCallback? onLogout;
  final VoidCallback? onClearModel;
  final bool isLoading;

  const _FunctionListSection({
    required this.theme,
    this.onLogout,
    this.onClearModel,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: AppSpacing.cardMargin,
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          _FunctionItem(
            icon: Icons.security,
            iconColor: SpringColors.mintGreen,
            title: '我的安全帽',
            subtitle: '查看个人绑定设备',
            theme: theme,
            onTap: () => context.goto(RouteNode.mySafetyHat),
          ),
          _Divider(theme: theme),
          _FunctionItem(
            icon: Icons.smart_toy,
            iconColor: SpringColors.skyBlue,
            title: 'AI 配置',
            subtitle: '配置 AI 服务参数',
            theme: theme,
            onTap: () => context.goto(RouteNode.aiConfig),
          ),
          _Divider(theme: theme),
          _FunctionItem(
            icon: Icons.delete_sweep_outlined,
            iconColor: SpringColors.sproutYellow,
            title: '清除语音模型',
            subtitle: '删除已下载的语音识别模型文件',
            theme: theme,
            onTap: onClearModel,
          ),
          _Divider(theme: theme),
          _FunctionItem(
            icon: Icons.logout,
            iconColor: SpringColors.cherryRed,
            title: '退出登录',
            subtitle: '安全退出账号',
            isDestructive: true,
            theme: theme,
            isLoading: isLoading,
            onTap: onLogout,
          ),
        ],
      ),
    );
  }
}

class _FunctionItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isDestructive;
  final VoidCallback? onTap;
  final ThemeColors theme;
  final bool isLoading;

  const _FunctionItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.isDestructive = false,
    this.onTap,
    required this.theme,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return MotionPress(
      enabled: !isLoading && onTap != null,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              // 图标
              Container(
                width: AppSpacing.listIconSize,
                height: AppSpacing.listIconSize,
                decoration: BoxDecoration(
                  color: iconColor.withValues(
                    alpha: AppSpacing.iconBackgroundAlpha,
                  ),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                ),
                child: isLoading
                    ? const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Icon(
                        icon,
                        color: iconColor,
                        size: AppSpacing.listIconIconSize,
                      ),
              ),
              const SizedBox(width: AppSpacing.md),
              // 标题和副标题
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDestructive
                            ? SpringColors.cherryRed
                            : theme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // 箭头
              Icon(Icons.chevron_right, color: theme.divider, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final ThemeColors theme;

  const _Divider({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: theme.divider,
      indent: AppSpacing.listIconSize + AppSpacing.md,
      endIndent: AppSpacing.lg,
    );
  }
}
