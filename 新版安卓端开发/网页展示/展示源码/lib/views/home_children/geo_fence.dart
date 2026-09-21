import '../../components/field_brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:rolling_intelligence_headband/hooks/use_agent_page.dart';
import 'package:rolling_intelligence_headband/hooks/use_page_agent.dart';
import 'package:rolling_intelligence_headband/hooks/use_page_agent_get_data.dart';
import 'package:rolling_intelligence_headband/router/route_tree.dart';
import 'package:rolling_intelligence_headband/utils/summarizable.dart';
import '../../hooks/use_theme.dart';
import '../../theme/theme.dart';
import '../../hooks/use_skeleton.dart';
import '../../components/skeleton_view.dart';
import '../../api/fence.dart' as api;
import '../../models/fence.dart';

/// 电子围栏页面
class GeoFencePage extends HookWidget {
  const GeoFencePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();
    final refreshKey = useState(0);

    // 页面总控中心
    final pageController = useAgentPage(
      meta: RouteNode.geoFence,
      greetingMessage: '已进入电子围栏页面，我可以帮您查询围栏列表、添加、编辑或删除围栏',
      expectedComponents: {'statCard', 'fenceList'},
    );

    // 监听 refreshKey 变化，触发刷新
    useEffect(() {
      refreshKey.value; // 触发依赖
      return null;
    }, [refreshKey.value]);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: _buildAppBar(context, theme, refreshKey),
      body: RefreshIndicator(
        onRefresh: () async {
          refreshKey.value++;
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.lg),
              // 统计卡片
              _StatCard(
                theme: theme,
                pageController: pageController,
                refreshKey: refreshKey,
              ),
              const SizedBox(height: AppSpacing.lg),
              // 围栏列表
              _FenceListCard(
                theme: theme,
                pageController: pageController,
                refreshKey: refreshKey,
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
    ValueNotifier<int> refreshKey,
  ) {
    return AppBar(
      backgroundColor: theme.background,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        tooltip: '返回',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back),
      ),
      title: Text(
        '电子围栏',
        style: AppTypography.headlineMedium.copyWith(color: theme.textPrimary),
      ),
      centerTitle: true,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: FilledButton.icon(
            onPressed: () async {
              await context.goto(RouteNode.geoFenceEdit);
              if (context.mounted) refreshKey.value++;
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加'),
          ),
        ),
      ],
    );
  }
}

// ==================== 统计卡片 ====================
class _StatCard extends HookWidget {
  final ThemeColors theme;
  final PageAgentController pageController;
  final ValueNotifier<int> refreshKey;

  const _StatCard({
    required this.theme,
    required this.pageController,
    required this.refreshKey,
  });

  @override
  Widget build(BuildContext context) {
    final skeleton = useSkeleton<List<Fence>>(
      request: () async {
        final page = await api.FenceApi.getFencePage(current: 1, size: 100);
        return page.records ?? [];
      },
      immediate: false,
      isEmpty: (data) => data.isEmpty,
      emptyMsg: '暂无围栏数据',
      onComplete: (data, {required isInitialLoad}) {
        if (isInitialLoad) {
          pageController.completeInit(componentId: 'statCard');
        } else {
          pageController.completeAction(
            result: {
              'total': data.length,
              'active': data.where((f) => f.status == 1).length,
              'inactive': data.where((f) => f.status != 1).length,
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

    // 监听刷新
    useEffect(() {
      skeleton.execute();
      return null;
    }, [refreshKey.value]);

    usePageAgentGetData(pageController, "statCard", () {
      final fences = skeleton.data.value ?? [];
      return {
        'total': fences.length,
        'active': fences.where((f) => f.status == 1).length,
        'inactive': fences.where((f) => f.status != 1).length,
      };
    }, deps: [refreshKey.value]);

    final fences = skeleton.data.value ?? [];
    final totalCount = fences.length;
    final activeCount = fences.where((f) => f.status == 1).length;
    final inactiveCount = fences.where((f) => f.status != 1).length;

    return Container(
      margin: AppSpacing.cardMargin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          FieldSceneAccent(scene: 'fence-card', size: 48),
          _StatItem(
            value: '$totalCount',
            label: '已加载围栏',
            valueColor: theme.textPrimary,
          ),
          _StatItem(
            value: '$activeCount',
            label: '启用中',
            valueColor: theme.textPrimary,
          ),
          _StatItem(
            value: '$inactiveCount',
            label: '已作废',
            valueColor: theme.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final Color valueColor;

  const _StatItem({
    required this.value,
    required this.label,
    required this.valueColor,
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
        Text(
          label,
          style: TextStyle(fontSize: 13, color: const Color(0xFF6B7280)),
        ),
      ],
    );
  }
}

// ==================== 围栏列表卡片 ====================
class _FenceListCard extends HookWidget {
  final ThemeColors theme;
  final PageAgentController pageController;
  final ValueNotifier<int> refreshKey;

  const _FenceListCard({
    required this.theme,
    required this.pageController,
    required this.refreshKey,
  });

  @override
  Widget build(BuildContext context) {
    final searchText = useState('');
    final activeFilter = useState<int?>(null);
    final skeleton = useSkeleton<List<Fence>>(
      request: () async {
        final page = await api.FenceApi.getFencePage(current: 1, size: 100);
        return page.records ?? [];
      },
      immediate: false,
      isEmpty: (data) => data.isEmpty,
      emptyMsg: '暂无围栏数据',
      onComplete: (data, {required isInitialLoad}) {
        if (isInitialLoad) {
          pageController.completeInit(componentId: 'fenceList');
        } else {
          pageController.completeAction(
            result: {
              'total': data.length,
              'active': data.where((f) => f.status == 1).length,
              'inactive': data.where((f) => f.status != 1).length,
            },
          );
        }
      },
      onError: (error, stackTrace, {required isInitialLoad}) {
        if (isInitialLoad) {
          pageController.failInit('围栏列表加载失败: $error', componentId: 'fenceList');
        } else {
          pageController.failAction('围栏列表加载失败: $error');
        }
      },
    );

    // 绑定 AI 工具：查询围栏列表
    usePageAgent(
      controller: pageController,
      toolName: 'queryFenceList',
      executeFn: (params) async {
        return skeleton.execute();
      },
    );

    // 绑定 AI 工具：添加围栏
    usePageAgent(
      controller: pageController,
      toolName: 'addFence',
      executeFn: (params) async {
        await context.goto(RouteNode.geoFenceEdit);
        refreshKey.value++;
        return {'success': true, 'message': '已跳转到添加围栏页面'};
      },
    );

    // 绑定 AI 工具：编辑围栏
    usePageAgent(
      controller: pageController,
      toolName: 'editFence',
      executeFn: (params) async {
        final fenceId = params?['fenceId'] as String?;
        if (fenceId == null || fenceId.isEmpty) {
          throw Exception('缺少围栏ID参数');
        }
        await context.goto(
          RouteNode.geoFenceEdit,
          params: {'fenceId': fenceId},
        );
        refreshKey.value++;
        return {'success': true, 'message': '已跳转到编辑围栏页面'};
      },
    );

    // 绑定 AI 工具：删除围栏
    usePageAgent(
      controller: pageController,
      toolName: 'deleteFence',
      executeFn: (params) async {
        final fenceId = params?['fenceId'] as String?;
        if (fenceId == null || fenceId.isEmpty) {
          throw Exception('缺少围栏ID参数');
        }
        await api.FenceApi.deleteFence(fenceId);
        refreshKey.value++;
        return {'success': true, 'message': '围栏已删除'};
      },
    );

    // 监听刷新
    useEffect(() {
      skeleton.execute();
      return null;
    }, [refreshKey.value]);

    usePageAgentGetData(pageController, "fenceList", () {
      final fences = skeleton.data.value ?? [];
      return {
        'total': fences.length,
        'active': fences.where((f) => f.status == 1).length,
        'inactive': fences.where((f) => f.status != 1).length,
        'summary': SummaryHelper.list(fences, title: '围栏列表', maxItems: 10),
      };
    }, deps: [refreshKey.value]);

    return Container(
      margin: AppSpacing.cardMargin,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.divider),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜索已加载的围栏',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => searchText.value = value.trim(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final option in <int?, String>{
                  null: '全部',
                  1: '启用中',
                  0: '已作废',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(option.value),
                      selected: activeFilter.value == option.key,
                      onSelected: (_) => activeFilter.value = option.key,
                    ),
                  ),
              ],
            ),
          ),
          SkeletonView.fromHook(skeleton, (fences) {
            final visible = fences
                .where(
                  (fence) =>
                      (fence.fenceName ?? '').contains(searchText.value) &&
                      (activeFilter.value == null ||
                          (activeFilter.value == 1
                              ? fence.status == 1
                              : fence.status != 1)),
                )
                .toList();
            if (visible.isEmpty)
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Text('当前条件下没有围栏，请调整搜索或状态'),
              );
            return Column(
              children: visible.asMap().entries.map((entry) {
                final index = entry.key;
                final fence = entry.value;
                return Column(
                  children: [
                    if (index > 0)
                      Divider(
                        height: 1,
                        indent: 60,
                        endIndent: 60,
                        color: theme.isDark
                            ? const Color(0x1FFFFFFF)
                            : const Color(0x14000000),
                      ),
                    _FenceListItem(
                      fence: fence,
                      theme: theme,
                      onRefresh: () => refreshKey.value++,
                      refreshKey: refreshKey,
                    ),
                  ],
                );
              }).toList(),
            );
          }),
        ],
      ),
    );
  }
}

// ==================== 围栏列表项 ====================
class _FenceListItem extends HookWidget {
  final Fence fence;
  final ThemeColors theme;
  final VoidCallback onRefresh;
  final ValueNotifier<int> refreshKey;

  const _FenceListItem({
    required this.fence,
    required this.theme,
    required this.onRefresh,
    required this.refreshKey,
  });

  IconData _getFenceIcon() {
    switch (fence.fenceShape) {
      case 'circle':
        return Icons.center_focus_strong;
      case 'polygon':
        return Icons.dashboard_outlined;
      case 'rectangle':
        return Icons.crop_square;
      default:
        return Icons.add_location_outlined;
    }
  }

  String _getFenceTypeText() {
    switch (fence.fenceShape) {
      case 'circle':
        return '圆形围栏';
      case 'polygon':
        return '多边形围栏';
      case 'rectangle':
        return '矩形围栏';
      default:
        return fence.fenceType ?? '围栏';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPressed = useState(false);
    final isActive = fence.status == 1;

    return GestureDetector(
      onTapDown: (_) => isPressed.value = true,
      onTapUp: (_) => isPressed.value = false,
      onTapCancel: () => isPressed.value = false,
      child: AnimatedScale(
        scale: isPressed.value ? AppSpacing.pressScale : 1,
        duration: AppSpacing.pressDuration,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              // 图标
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: SpringColors.skyBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                ),
                child: Icon(
                  _getFenceIcon(),
                  size: 22,
                  color: isActive ? theme.textPrimary : const Color(0xFF6B7280),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              // 围栏信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            fence.fenceName ?? '未命名',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.body.copyWith(
                              color: theme.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        // 状态标签
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFF16744A).withValues(alpha: 0.1)
                                : const Color(0xFFE5E5E5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isActive ? '启用中' : '已作废',
                            style: TextStyle(
                              fontSize: 12,
                              color: isActive
                                  ? const Color(0xFF16744A)
                                  : const Color(0xFF6B7280),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '类型：${_getFenceTypeText()}',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Icon(
                          Icons.notifications_none,
                          size: 14,
                          color: theme.textTertiary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '告警：${fence.alertCount ?? 0}次',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // 操作按钮
              Column(
                children: [
                  GestureDetector(
                    onTap: () async {
                      await context.goto(
                        RouteNode.geoFenceEdit,
                        params: {'fenceId': fence.id ?? ''},
                      );
                      // 从编辑页面返回后自动刷新
                      refreshKey.value++;
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: SpringColors.skyBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSmall,
                        ),
                      ),
                      child: const Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: const Color(0xFF202B46),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  GestureDetector(
                    onTap: () => _showDeleteConfirmDialog(context, fence),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSmall,
                        ),
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmDialog(BuildContext context, Fence fence) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除围栏'),
        content: Text('删除“${fence.fenceName ?? "未命名围栏"}”后将移除该区域配置，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await api.FenceApi.deleteFence(fence.id!);
                onRefresh();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('删除失败：$e')));
                }
              }
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
