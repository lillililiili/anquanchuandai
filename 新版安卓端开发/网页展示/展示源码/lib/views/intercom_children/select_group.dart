import '../../components/field_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:rolling_intelligence_headband/utils/app_logger.dart';
import '../../api/hat_group.dart';
import '../../components/pagination_list_view.dart';
import '../../hooks/use_pagination.dart';
import '../../hooks/use_theme.dart';
import '../../models/hat_group.dart';
import '../../theme/theme.dart';
import '../../theme/theme_signal.dart';

/// 选择群组页面 - 用于对讲调度
class SelectGroupPage extends HookWidget {
  final String? groupName;
  final bool? autoSelect;

  const SelectGroupPage({super.key, this.groupName, this.autoSelect});

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();
    final selectedGroupId = useState<int?>(null);
    final searchText = useState('');

    // 分页 hook
    final pagination = usePaginationTable<HatGroup>(
      apiFun: (params) => HatGroupApi.getGroupPage(
        current: params['pageNum'],
        size: params['pageSize'],
        groupName: searchText.value.isEmpty ? null : searchText.value,
      ),
      immediate: true,
      pageSize: 20,
      onComplete:
          ({
            required currentPage,
            required data,
            required isInitialLoad,
            required pageSize,
            required total,
          }) {
            if (!isInitialLoad || autoSelect != true || groupName == null) {
              return;
            }
            final matched = data
                .where((g) => g.groupName == groupName)
                .firstOrNull;
            AppLogger.i(
              'SelectGroupPage: autoSelect, matched: ${matched?.groupName}',
            );
            if (matched != null) {
              Navigator.of(context).pop({
                'groupId': matched.id.toString(),
                'groupName': matched.groupName ?? '',
              });
            } else {
              Navigator.of(context).pop(null);
            }
          },
    );

    // 根据 id 获取分组名称
    String? getSelectedGroupName() {
      if (selectedGroupId.value == null) return null;
      final selectedGroup = pagination.dataSource.value.firstWhere(
        (g) => g.id == selectedGroupId.value,
        orElse: () => HatGroup(),
      );
      return selectedGroup.groupName;
    }

    return Scaffold(
      backgroundColor: theme.background,
      appBar: _buildAppBar(context, theme),
      body: Column(
        children: [
          const SizedBox(height: AppSpacing.lg),
          // 搜索栏
          _buildSearchBar(
            theme: theme,
            searchText: searchText,
            onSearch: () => pagination.reload(),
          ),
          const SizedBox(height: AppSpacing.lg),
          // 群组列表 - 使用 PaginationListView
          Expanded(
            child: PaginationListView<HatGroup>(
              bind: pagination,
              itemBuilder: (context, group, index) => _GroupListItem(
                group: group,
                theme: theme,
                isSelected: selectedGroupId.value == group.id,
                onSelected: (selected) {
                  selectedGroupId.value = selected ? group.id : null;
                },
              ),
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppSpacing.sm),
              onRefresh: () => pagination.reload(),
              emptyMsg: '暂无分组数据',
            ),
          ),
          // 底部下一步按钮
          _buildBottomButton(
            context,
            theme,
            selectedGroupId.value,
            getSelectedGroupName(),
          ),
        ],
      ),
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
            color: SpringColors.mintGreen.withValues(alpha: 0.15),
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
        '选择群组',
        style: AppTypography.headlineMedium.copyWith(
          color: theme.textPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _buildSearchBar({
    required ThemeColors theme,
    required ValueNotifier<String> searchText,
    required VoidCallback onSearch,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        boxShadow: AppShadows.light,
      ),
      child: Row(
        children: [
          // 搜索图标
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Icon(Icons.search, size: 20, color: SpringColors.mintGreen),
          ),
          const SizedBox(width: AppSpacing.sm),
          // 搜索输入框
          Expanded(
            child: TextField(
              onChanged: (value) => searchText.value = value,
              onSubmitted: (_) => onSearch(),
              style: TextStyle(fontSize: 14, color: theme.textPrimary),
              decoration: InputDecoration(
                hintText: '搜索群组',
                hintStyle: TextStyle(fontSize: 14, color: theme.textTertiary),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                isDense: true,
                filled: false,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // 搜索按钮
          GestureDetector(
            onTap: onSearch,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: SpringColors.skyBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              ),
              child: const Icon(
                Icons.arrow_forward,
                size: 20,
                color: SpringColors.skyBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButton(
    BuildContext context,
    ThemeColors theme,
    int? selectedGroupId,
    String? selectedGroupName,
  ) {
    final isEnabled = selectedGroupId != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: GestureDetector(
        onTap: isEnabled
            ? () {
                // 返回选中的组信息
                Navigator.of(context).pop({
                  'groupId': selectedGroupId.toString(),
                  'groupName': selectedGroupName ?? '',
                });
              }
            : null,
        child: AnimatedScale(
          scale: isEnabled ? 1 : 0.98,
          duration: AppSpacing.pressDuration,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              gradient: isEnabled
                  ? const LinearGradient(
                      colors: [SpringColors.skyBlue, Color(0xFF2563EB)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              color: isEnabled
                  ? null
                  : (theme.isDark ? Colors.grey[700] : Colors.grey[300]),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              boxShadow: isEnabled
                  ? [
                      BoxShadow(
                        color: SpringColors.skyBlue.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isEnabled)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '1',
                        style: AppTypography.button.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  Text(
                    '确认',
                    style: AppTypography.button.copyWith(
                      color: isEnabled ? Colors.white : Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== 群组列表项 ====================
class _GroupListItem extends HookWidget {
  final HatGroup group;
  final ThemeColors theme;
  final bool isSelected;
  final Function(bool) onSelected;

  const _GroupListItem({
    required this.group,
    required this.theme,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = SpringColors.skyBlue;

    return AnimatedContainer(
      duration: MotionPolicy.duration(context, MotionPolicy.contentMs),
      curve: MotionPolicy.effectsCurve,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: isSelected
            ? Color.alphaBlend(
                primaryColor.withValues(alpha: .09),
                theme.cardBackground,
              )
            : theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.3)
              : (theme.isDark
                    ? const Color(0x0DFFFFFF)
                    : const Color(0x0A000000)),
          width: 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: primaryColor.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : AppShadows.light,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
          onTap: () => onSelected(!isSelected),
          child: MotionPress(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 第一行：复选框、群组图标、群组名称、设备数量
                  Row(
                    children: [
                      // 单选按钮（圆形）
                      AnimatedSwitcher(
                        duration: MotionPolicy.duration(
                          context,
                          MotionPolicy.contentMs,
                        ),
                        switchInCurve: MotionPolicy.effectsCurve,
                        switchOutCurve: Curves.easeIn,
                        child: isSelected
                            ? Container(
                                key: const ValueKey('selected'),
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: SpringColors.skyBlue,
                                  border: Border.all(
                                    color: SpringColors.skyBlue,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              )
                            : Container(
                                key: const ValueKey('unselected'),
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: theme.isDark
                                        ? Colors.white38
                                        : Colors.black38,
                                    width: 2,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      // 群组图标
                      AnimatedContainer(
                        duration: MotionPolicy.duration(
                          context,
                          MotionPolicy.contentMs,
                        ),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primaryColor.withValues(alpha: 0.15)
                              : primaryColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMedium,
                          ),
                        ),
                        child: Icon(
                          Icons.groups,
                          size: 20,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      // 群组名称
                      Expanded(
                        child: Text(
                          group.groupName ?? '未命名群组',
                          style: AppTypography.body.copyWith(
                            color: theme.textPrimary,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      // 设备数量
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusSmall,
                          ),
                        ),
                        child: Text(
                          '${group.safetyCount ?? 0}',
                          style: TextStyle(
                            fontSize: 12,
                            color: primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 第二行：分组描述
                  if (group.groupDesc != null &&
                      group.groupDesc!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      group.groupDesc!,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
