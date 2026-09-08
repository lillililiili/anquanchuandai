import '../../store/chat_store.dart';
import '../../components/field_brand.dart';
import '../../components/field_motion.dart';
import '../../field/field_alarms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:rolling_intelligence_headband/hooks/use_agent_page.dart';
import 'package:rolling_intelligence_headband/hooks/use_page_agent.dart';
import 'package:rolling_intelligence_headband/hooks/use_page_agent_get_data.dart';
import 'package:rolling_intelligence_headband/router/route_tree.dart';
import 'package:rolling_intelligence_headband/utils/summarizable.dart';
import '../../api/alarm.dart';
import '../../components/pagination_view.dart';
import '../../components/skeleton_view.dart';
import '../../hooks/use_pagination.dart';
import '../../hooks/use_skeleton.dart';
import '../../hooks/use_theme.dart';
import '../../models/alarm.dart';
import '../../models/chat_models.dart';
import '../../theme/theme.dart';

/// 告警记录页面
///
/// 使用新的页面总控中心架构：
/// 1. useAgentPage - 页面总控，管理多组件初始化聚合
/// 2. 子组件各自调用 completeInit 通知就绪
/// 3. usePaginationTable 封装保留在子组件中
/// 4. usePageAgent 只封装操作，不复用 API 调用
class AlarmRecordPage extends HookWidget {
  const AlarmRecordPage({super.key});
  @override
  Widget build(BuildContext context) {
    final legacy = useState(false);
    return legacy.value
        ? LegacyAlarmRecordPage(onBack: () => legacy.value = false)
        : FieldAlarmWorkspace(onAdvanced: () => legacy.value = true);
  }
}

class LegacyAlarmRecordPage extends HookWidget {
  final VoidCallback? onBack;
  const LegacyAlarmRecordPage({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();
    final scrollController = useScrollController();

    // 1. 页面总控中心
    final pageController = useAgentPage(
      meta: RouteNode.alarmRecord,
      greetingMessage: '已进入告警记录页面，我可以帮您查询特定条件的告警记录',
      // 可选：明确指定预期组件，全部就绪后才算完全就绪
      expectedComponents: {'statCard', 'AlarmRecordListSection'},
    );

    // 用于存储刷新回调
    final refreshCallbacks = <Future<void> Function()>[];

    // 注册刷新回调
    void registerRefreshCallback(Future<void> Function() callback) {
      refreshCallbacks.add(callback);
    }

    return Scaffold(
      backgroundColor: theme.background,
      appBar: _buildAppBar(context, theme, pageController),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait(refreshCallbacks.map((cb) => cb()));
        },
        child: SingleChildScrollView(
          controller: scrollController,
          child: Column(
            children: [
              const SizedBox(height: 6),
              // 统计卡片 - 独立初始化
              _StatCard(
                theme: theme,
                onRegisterRefresh: registerRefreshCallback,
                pageController: pageController,
              ),
              const SizedBox(height: 6),
              // 筛选表单和告警列表 - 独立初始化
              _AlarmListSection(
                theme: theme,
                scrollController: scrollController,
                onRegisterRefresh: registerRefreshCallback,
                pageController: pageController,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ThemeColors theme,
    PageAgentController pageController,
  ) {
    return AppBar(
      backgroundColor: theme.background,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: GestureDetector(
        onTap: onBack ?? () => Navigator.of(context).pop(),
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
        '告警记录',
        style: AppTypography.headlineMedium.copyWith(color: theme.textPrimary),
      ),
      centerTitle: true,
      // 显示页面总控状态
      actions: [
        IconButton(
          tooltip: '打开 AI 助手',
          onPressed: () => ChatStore.instance.setChatPanelOpen(true),
          icon: const Icon(Icons.smart_toy_outlined),
        ),
        ValueListenableBuilder(
          valueListenable: pageController.statusNotifier,
          builder: (context, status, child) {
            if (status == AgentStatus.loading) {
              return Container(
                margin: const EdgeInsets.only(right: AppSpacing.md),
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    SpringColors.mintGreen,
                  ),
                ),
              );
            }
            if (status == AgentStatus.error) {
              return Container(
                margin: const EdgeInsets.only(right: AppSpacing.md),
                child: Icon(
                  Icons.error_outline,
                  color: SpringColors.cherryRed,
                  size: 24,
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}

// ==================== 统计卡片 ====================
class _StatCard extends HookWidget {
  final ThemeColors theme;
  final void Function(Future<void> Function()) onRegisterRefresh;
  final PageAgentController pageController;

  const _StatCard({
    required this.theme,
    required this.onRegisterRefresh,
    required this.pageController,
  });

  @override
  Widget build(BuildContext context) {
    final skeleton = useSkeleton<Map<String, dynamic>>(
      request: () => AlarmApi.getUnhandledCount(),
      onComplete: (data, {required isInitialLoad}) {
        if (isInitialLoad) {
          pageController.completeInit(componentId: 'statCard');
        } else {
          pageController.completeAction(
            result: {
              'today': data['today'] ?? 0,
              'unhandled': data['unhandled'] ?? 0,
              'week': data['week'] ?? 0,
            },
          );
        }
      },
      onError: (error, stackTrace, {required isInitialLoad}) {
        if (isInitialLoad) {
          pageController.failInit('统计卡片加载失败: $error', componentId: 'statCard');
        } else {
          pageController.failAction('统计卡片加载失败: $error');
        }
      },
    );

    // 注册刷新回调
    useEffect(() {
      onRegisterRefresh(skeleton.execute);
      return null;
    }, []);

    usePageAgentGetData(pageController, "statCard", () {
      return skeleton.data.value ?? {};
    });

    return SkeletonView.fromHook(
      skeleton,
      (data) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              theme.cardBackground,
            ],
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.shield_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '设备告警概览',
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const FieldSceneAccent(scene: 'device-card', size: 42),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(
                  value: '${data['today'] ?? 0}',
                  label: '今日告警',
                  valueColor: SpringColors.cherryRed,
                  theme: theme,
                ),
                _StatItem(
                  value: '${data['unhandled'] ?? 0}',
                  label: '未处理',
                  valueColor: SpringColors.sproutYellow,
                  theme: theme,
                ),
                _StatItem(
                  value: '${data['week'] ?? 0}',
                  label: '本周告警',
                  valueColor: SpringColors.mintGreen,
                  theme: theme,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final Color valueColor;
  final ThemeColors theme;

  const _StatItem({
    required this.value,
    required this.label,
    required this.valueColor,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(label, style: TextStyle(fontSize: 13, color: theme.textTertiary)),
      ],
    );
  }
}

// ==================== 筛选表单和告警列表整合 ====================
class _AlarmListSection extends HookWidget {
  final ThemeColors theme;
  final ScrollController scrollController;
  final void Function(Future<void> Function()) onRegisterRefresh;
  final PageAgentController pageController;

  const _AlarmListSection({
    required this.theme,
    required this.scrollController,
    required this.onRegisterRefresh,
    required this.pageController,
  });

  @override
  Widget build(BuildContext context) {
    // 筛选状态
    final alarmType = useState<String?>(null);
    final status = useState<String?>(null);
    final startDate = useState<String?>(null);
    final endDate = useState<String?>(null);

    // 1. 保留 usePaginationTable 封装，使用 onComplete 回调通知页面总控
    final pagination = usePaginationTable<Alarm>(
      apiFun: (params) => AlarmApi.getAlarmPage(
        current: params['pageNum'],
        size: params['pageSize'],
        alarmType: _mapAlarmType(alarmType.value),
        isHandled: _mapStatus(status.value),
        startTimeFrom: startDate.value,
        startTimeTo: endDate.value,
      ),
      immediate: true,
      currentPage: 1,
      pageSize: 10,
      onComplete:
          ({
            required data,
            required total,
            required currentPage,
            required pageSize,
            required isInitialLoad,
          }) {
            if (isInitialLoad) {
              pageController.completeInit(
                componentId: 'AlarmRecordListSection',
              );
            } else {
              pageController.completeAction(
                result: {
                  'total': total,
                  'currentPage': currentPage,
                  'pageSize': pageSize,
                  'dataCount': data.length,
                },
              );
            }
          },
      onError: (error, stackTrace, {required isInitialLoad}) {
        if (isInitialLoad) {
          pageController.failInit(
            '告警列表加载失败: $error',
            componentId: 'AlarmRecordListSection',
          );
        } else {
          pageController.failAction('告警列表加载失败: $error');
        }
      },
    );

    // 2. usePageAgent 只封装操作，不复用 API 调用
    // 人机一致性：AI 调用工具 = 用户点击筛选按钮，都走 pagination.reload()
    usePageAgent(
      controller: pageController,
      toolName: 'queryAlarmRecord',
      executeFn: (params) async {
        final pageNum = int.tryParse('${params?['pageNum'] ?? 1}') ?? 1;
        final pageSize = int.tryParse('${params?['pageSize'] ?? 10}') ?? 10;
        return pagination.execute(page: pageNum, size: pageSize);
      },
    );

    // 注册刷新回调
    useEffect(() {
      onRegisterRefresh(pagination.reload);
      return null;
    }, []);

    usePageAgentGetData(pageController, "AlarmRecordListSection", () {
      final alarms = pagination.dataSource.value;
      return {
        'total': pagination.total.value,
        'summary': SummaryHelper.list(alarms, title: '告警记录', maxItems: 10),
      };
    });

    // 筛选后重新加载
    void onFilter() {
      pagination.reload();
    }

    return Column(
      children: [
        // 筛选表单
        _buildFilterCard(
          context: context,
          alarmType: alarmType,
          status: status,
          startDate: startDate,
          endDate: endDate,
          onFilter: onFilter,
        ),
        const SizedBox(height: AppSpacing.lg),
        // 告警列表 - 使用 PaginationView
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: theme.cardBackground,
            borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
            boxShadow: AppShadows.card,
          ),
          child: PaginationView.fromHook<Alarm>(
            bind: pagination,
            scrollController: scrollController,
            slot: (data, status) => Column(
              children: data.asMap().entries.map((entry) {
                final index = entry.key;
                final alarm = entry.value;
                return Column(
                  children: [
                    if (index > 0)
                      Divider(
                        height: 1,
                        indent: 72,
                        endIndent: AppSpacing.lg,
                        color: theme.isDark
                            ? const Color(0x1FFFFFFF)
                            : const Color(0x14000000),
                      ),
                    _AlarmListItem(alarm: alarm, theme: theme),
                  ],
                );
              }).toList(),
            ),
            emptyMsg: '暂无告警记录',
          ),
        ),
      ],
    );
  }

  Widget _buildFilterCard({
    required BuildContext context,
    required ValueNotifier<String?> alarmType,
    required ValueNotifier<String?> status,
    required ValueNotifier<String?> startDate,
    required ValueNotifier<String?> endDate,
    required VoidCallback onFilter,
  }) {
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
          // 第一行：告警类型、处理状态
          Row(
            children: [
              Expanded(
                child: _buildFormField(
                  label: '告警类型',
                  child: _buildDropdown(
                    hint: '全部',
                    value: alarmType.value,
                    items: const ['全部', 'SOS 告警', '跌倒告警', '越界告警', '静止告警'],
                    onChanged: (v) => alarmType.value = v,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: _buildFormField(
                  label: '处理状态',
                  child: _buildDropdown(
                    hint: '全部',
                    value: status.value,
                    items: const ['全部', '已处理', '未处理'],
                    onChanged: (v) => status.value = v,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // 第二行：开始日期、结束日期
          Row(
            children: [
              Expanded(
                child: _buildFormField(
                  label: '开始日期',
                  child: _buildDatePicker(
                    hint: '开始日期',
                    value: startDate.value,
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        startDate.value = date.toIso8601String().split('T')[0];
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: _buildFormField(
                  label: '结束日期',
                  child: _buildDatePicker(
                    hint: '结束日期',
                    value: endDate.value,
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        endDate.value = date.toIso8601String().split('T')[0];
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // 筛选按钮
          GestureDetector(
            onTap: onFilter,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: SpringColors.skyBlue,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              ),
              child: Center(
                child: Text(
                  '筛选告警',
                  style: AppTypography.button.copyWith(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.body.copyWith(
            color: theme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    );
  }

  Widget _buildDropdown({
    required String hint,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(
          color: theme.isDark
              ? const Color(0xFF3A3A3A)
              : const Color(0xFFE0E0E0),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        child: Container(
          color: theme.isDark ? const Color(0xFF2A2A2A) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                hint: Text(
                  hint,
                  style: TextStyle(fontSize: 14, color: theme.textTertiary),
                ),
                items: items.map((item) {
                  return DropdownMenuItem(
                    value: item,
                    child: Text(
                      item,
                      style: TextStyle(fontSize: 14, color: theme.textPrimary),
                    ),
                  );
                }).toList(),
                onChanged: onChanged,
                icon: Icon(
                  Icons.keyboard_arrow_down,
                  size: 20,
                  color: theme.textSecondary,
                ),
                dropdownColor: theme.cardBackground,
                style: TextStyle(fontSize: 14, color: theme.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDatePicker({
    required String hint,
    required String? value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          border: Border.all(
            color: theme.isDark
                ? const Color(0xFF3A3A3A)
                : const Color(0xFFE0E0E0),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          child: Container(
            color: theme.isDark ? const Color(0xFF2A2A2A) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      value ?? hint,
                      style: TextStyle(
                        fontSize: 14,
                        color: value != null
                            ? theme.textPrimary
                            : theme.textTertiary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                    color: theme.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _mapAlarmType(String? value) {
    if (value == null || value == '全部') return null;
    final map = {
      'SOS 告警': 'sos',
      '跌倒告警': 'fall',
      '越界告警': 'removal',
      '静止告警': 'silent',
    };
    return map[value];
  }

  int? _mapStatus(String? value) {
    if (value == null || value == '全部') return null;
    return value == '已处理' ? 1 : 0;
  }
}

// ==================== 告警列表项 ====================
class _AlarmListItem extends HookWidget {
  final Alarm alarm;
  final ThemeColors theme;

  const _AlarmListItem({required this.alarm, required this.theme});

  (IconData, Color) _getAlarmStyle(String? type) {
    switch (type) {
      case 'sos':
        return (Icons.warning, SpringColors.cherryRed);
      case 'fall':
        return (Icons.arrow_downward, SpringColors.cherryRed);
      case 'removal':
        return (Icons.logout, SpringColors.sproutYellow);
      case 'silent':
        return (Icons.access_time, SpringColors.cherryRed);
      case 'proximity':
        return (Icons.bolt, SpringColors.sproutYellow);
      default:
        return (Icons.warning, SpringColors.cherryRed);
    }
  }

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
    final isPressed = useState(false);
    final (icon, iconColor) = _getAlarmStyle(alarm.alarmType);
    final title = _getAlarmTitle(alarm.alarmType);
    final isProcessed = alarm.isHandled == 1;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.goto(
        RouteNode.alarmDetail,
        params: {'alarmId': alarm.id ?? ''},
      ),
      onTapDown: (_) => isPressed.value = true,
      onTapUp: (_) => isPressed.value = false,
      onTapCancel: () => isPressed.value = false,
      child: AnimatedScale(
        scale: isPressed.value ? AppSpacing.pressScale : 1,
        duration: AppSpacing.pressDuration,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 24, color: iconColor),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: AppTypography.title.copyWith(
                            color: theme.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isProcessed
                                ? SpringColors.mintGreen.withValues(alpha: 0.1)
                                : SpringColors.cherryRed.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSmall,
                            ),
                          ),
                          child: Text(
                            isProcessed ? '已处理' : '未处理',
                            style: TextStyle(
                              fontSize: 12,
                              color: isProcessed
                                  ? SpringColors.mintGreen
                                  : SpringColors.cherryRed,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      alarm.description ?? '暂无描述',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Icon(
                          Icons.construction,
                          size: 14,
                          color: theme.textTertiary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            '安全帽 ${alarm.hatNumber ?? ''}',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.textTertiary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Icon(
                          Icons.person_outline,
                          size: 14,
                          color: theme.textTertiary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            alarm.userName ?? '',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.textTertiary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: theme.textTertiary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          alarm.alarmStartTime ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
